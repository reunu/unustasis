import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'domain/update_planner.dart';
import 'scooter_service.dart';
import 'service/ble_commands.dart';
import 'service/ota_transfer_service.dart';

final log = Logger('LsOtaScreen');

enum _PlanPhase { idle, queryingVersions, fetchingIndex, ready, upToDate, error }

class LsOtaScreen extends StatefulWidget {
  const LsOtaScreen({super.key});

  @override
  State<LsOtaScreen> createState() => _LsOtaScreenState();
}

class _LsOtaScreenState extends State<LsOtaScreen> {
  static const _releasesBase = "https://downloads.librescoot.org/releases";

  final OtaTransferService _transfer = OtaTransferService.shared;

  // Session state is static: the State is disposed when the user navigates
  // away while a transfer/install keeps running on the shared service, and a
  // re-opened screen must show the same plan, versions and progress instead
  // of starting blank.
  static _PlanPhase _phase = _PlanPhase.idle;
  static String _channel = "stable";
  static String? _inferredChannel;
  static bool _channelSwitch = false;
  static String? _mdbVersion;
  static String? _dbcVersion;
  static List<FirmwareRelease> _releases = [];
  static UpdatePlan? _plan;

  bool _downloading = false;
  double _downloadProgress = 0;
  String? _error;
  bool _wasConnected = false;

  UpdateStep? get _activeStep => _transfer.activeStep;

  @override
  void initState() {
    super.initState();
    _transfer.addListener(_onTransferChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only start a fresh planning pass when nothing is going on. When the
      // screen is re-opened during a transfer/install (or on its outcome,
      // e.g. "lock the scooter to reboot"), re-attach to that session
      // instead of wiping it.
      if (_transfer.state == OtaTransferState.idle) _refresh();
    });
  }

  @override
  void dispose() {
    _transfer.removeListener(_onTransferChanged);
    super.dispose();
  }

  void _onTransferChanged() {
    if (mounted) setState(() {});
  }

  bool get _refreshing =>
      _phase == _PlanPhase.queryingVersions || _phase == _PlanPhase.fetchingIndex;

  /// Re-reads the installed versions over BLE, fetches the release index and
  /// rebuilds the update plan.
  Future<void> _refresh({bool channelSwitch = false}) async {
    if (_refreshing || _transfer.busy) return;
    final service = context.read<ScooterService>();

    // A finished transfer's outcome tile is superseded by the fresh plan.
    _transfer.reset();

    setState(() {
      _phase = _PlanPhase.queryingVersions;
      _channelSwitch = channelSwitch;
      _plan = null;
      _error = null;
    });

    // Installed versions via the extended command channel. Null (timeout /
    // old firmware) degrades the plan to the newest full image.
    String? mdb, dbc;
    if (service.connected) {
      final scooter = service.myScooter;
      final repo = service.characteristicRepository;
      try {
        mdb = await getInstalledVersionCommand(scooter, repo, "mdb");
      } catch (e) {
        log.warning("MDB version query failed: $e");
      }
      try {
        dbc = await getInstalledVersionCommand(scooter, repo, "dbc");
      } catch (e) {
        log.warning("DBC version query failed: $e");
      }
    }
    if (!mounted) return;

    setState(() {
      _mdbVersion = mdb;
      _dbcVersion = dbc;
      _inferredChannel = UpdatePlanner.inferChannel(mdb);
      // Follow the installed channel unless the user deliberately switched.
      if (!channelSwitch && _inferredChannel != null) {
        _channel = _inferredChannel!;
      }
      _phase = _PlanPhase.fetchingIndex;
    });

    try {
      final resp = await http
          .get(Uri.parse("$_releasesBase/$_channel.json"))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw "Release index unavailable (HTTP ${resp.statusCode})";
      }
      final releases = [
        for (final r in jsonDecode(resp.body) as List<dynamic>)
          FirmwareRelease.fromJson(r as Map<String, dynamic>)
      ];
      final plan = UpdatePlanner.buildPlan(
        releases: releases,
        channel: _channel,
        mdbVersion: mdb,
        dbcVersion: dbc,
        channelSwitch: channelSwitch,
      );
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _plan = plan;
        _phase = plan.upToDate ? _PlanPhase.upToDate : _PlanPhase.ready;
      });
    } catch (e) {
      log.warning("Update check failed: $e");
      if (!mounted) return;
      setState(() {
        _error = "Update check failed: $e";
        _phase = _PlanPhase.error;
      });
    }
  }

  Future<void> _onChannelSelected(String selected) async {
    if (selected == _channel && !_channelSwitch) return;
    final isSwitch = _inferredChannel != null && selected != _inferredChannel;
    if (isSwitch) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Switch update channel?"),
          content: Text(
              "The scooter is on the ${_inferredChannel!} channel. Switching to "
              "$selected requires downloading and transferring a full firmware "
              "image for both boards, which takes a long time over Bluetooth."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Switch to $selected"),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _channel = selected);
    _refresh(channelSwitch: isSwitch);
  }

  Future<void> _onInstallPressed(UpdateStep step) async {
    if (step.isFullImage) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Install full image?"),
          content: Text(
              "${step.asset.name} is a full firmware image "
              "(${_formatBytes(step.asset.size)}). Transferring it over "
              "Bluetooth can take a long time. Continue?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Install"),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _executeStep(step);
  }

  Future<void> _executeStep(UpdateStep step) async {
    final service = context.read<ScooterService>();
    final scooter = service.myScooter;
    if (scooter == null) return;
    final repo = service.characteristicRepository;

    setState(() => _error = null);
    _transfer.activeStep = step;
    try {
      final bundle = await _downloadBundle(step.asset);
      await _transfer.transfer(
        scooter,
        repo,
        bundle,
        bundleId: step.bundleId,
        component: step.component,
      );
    } catch (e) {
      log.warning("OTA update failed: $e");
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// After a failed delta install (e.g. the scooter has no base image),
  /// offers the same release as a full image.
  Future<void> _tryFullImageInstead(UpdateStep deltaStep) async {
    final variant = UpdatePlanner.variantFor(deltaStep.component);
    var release = deltaStep.release;
    var asset = release.menderAsset(variant);
    if (asset == null) {
      final latest = UpdatePlanner.latestFull(_releases, _channel, variant);
      asset = latest?.menderAsset(variant);
      if (latest == null || asset == null) {
        setState(() => _error = "No full image available on the $_channel channel");
        return;
      }
      release = latest;
    }
    await _onInstallPressed(UpdateStep(
      component: deltaStep.component,
      release: release,
      asset: asset,
      kind: StepKind.full,
    ));
  }

  Future<File> _downloadBundle(FirmwareAsset asset) async {
    final dir = await getApplicationSupportDirectory();
    final file = File("${dir.path}/ota/${asset.name}");
    if (await file.exists() && await file.length() == asset.size) {
      return file; // already downloaded
    }
    await file.parent.create(recursive: true);

    // The download keeps running if the user navigates away (this State gets
    // disposed), so every UI update needs a mounted guard.
    if (mounted) {
      setState(() {
        _downloading = true;
        _downloadProgress = 0;
      });
    }
    try {
      final req = http.Request("GET", Uri.parse(asset.url));
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) {
        throw "Download failed (HTTP ${resp.statusCode})";
      }
      final total = resp.contentLength ?? asset.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      }
      await sink.close();
      return file;
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _formatBytes(num bytes) {
    if (bytes >= 1 << 20) return "${(bytes / (1 << 20)).toStringAsFixed(1)} MB";
    if (bytes >= 1 << 10) return "${(bytes / (1 << 10)).toStringAsFixed(0)} kB";
    return "$bytes B";
  }

  String _formatEta(int? seconds) {
    if (seconds == null) return "";
    if (seconds >= 3600) return " — ~${(seconds / 3600).toStringAsFixed(1)} h left";
    if (seconds >= 90) return " — ~${(seconds / 60).round()} min left";
    return " — ~$seconds s left";
  }

  Widget _versionTile(String label, String? version, IconData icon) {
    final known = UpdatePlanner.isKnownVersion(version);
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(known
          ? version!
          : version == "unknown"
              ? "unknown — switch the scooter on so the dashboard boots"
              : "unavailable (older firmware?)"),
      trailing: known ? null : const Icon(Icons.warning_amber, color: Colors.amber),
    );
  }

  Widget _planList(UpdatePlan plan, {required bool actionable}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final warning in plan.warnings)
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline),
            title: Text(warning, style: const TextStyle(fontSize: 13)),
          ),
        for (var i = 0; i < plan.steps.length; i++)
          ListTile(
            leading: Icon(plan.steps[i].isFullImage
                ? Icons.system_update_alt
                : Icons.compress),
            title: Text(
                "Step ${i + 1}: ${plan.steps[i].componentLabel} → ${plan.steps[i].release.tagName}"),
            subtitle: Text(
                "${plan.steps[i].asset.name} (${_formatBytes(plan.steps[i].asset.size)})"
                " — ${plan.steps[i].kindLabel}"),
            trailing: i == 0
                ? TextButton(
                    onPressed: actionable ? () => _onInstallPressed(plan.steps[i]) : null,
                    child: const Text("Install"),
                  )
                : const Icon(Icons.lock_outline, size: 18),
          ),
        if (plan.steps.length > 1)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "One update at a time — the plan refreshes after each step.",
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _transferStatus() {
    switch (_transfer.state) {
      case OtaTransferState.idle:
        return const SizedBox.shrink();
      case OtaTransferState.hashing:
      case OtaTransferState.handshaking:
        return ListTile(
          leading: const CircularProgressIndicator(),
          title: Text(_transfer.statusMessage),
        );
      case OtaTransferState.transferring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text("Transferring to ${_activeStep?.componentLabel ?? 'scooter'}"),
              subtitle: Text(
                  "${_formatBytes(_transfer.ackedBytes)} of ${_formatBytes(_transfer.totalBytes)}"
                  " — ${_formatBytes(_transfer.throughput)}/s"
                  "${_formatEta(_transfer.etaSeconds)}"),
              trailing: TextButton(
                onPressed: _transfer.abort,
                child: const Text("Cancel"),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: _transfer.progress),
            ),
          ],
        );
      case OtaTransferState.verifying:
        return ListTile(
          leading: const CircularProgressIndicator(),
          title: const Text("Verifying transfer"),
          subtitle: Text(_transfer.statusMessage),
        );
      case OtaTransferState.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: const Text("Installing"),
              subtitle: Text(_transfer.statusMessage),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: _transfer.installPercent / 100),
            ),
          ],
        );
      case OtaTransferState.pendingReboot:
        return Column(
          children: [
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text("Installed"),
              subtitle: Text("Lock the scooter to reboot and finish the update."),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text("Check again"),
              subtitle: const Text("Re-reads the installed versions and plans the next step."),
              onTap: _refreshing ? null : () => _refresh(),
            ),
          ],
        );
      case OtaTransferState.success:
        return Column(
          children: [
            const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text("Update installed"),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text("Check again"),
              onTap: _refreshing ? null : () => _refresh(),
            ),
          ],
        );
      case OtaTransferState.failure:
        final active = _activeStep;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text("Update failed"),
              subtitle: Text(_transfer.statusMessage),
              trailing: _transfer.resumable && active != null
                  ? TextButton(
                      onPressed: () => _executeStep(active),
                      child: const Text("Resume"))
                  : null,
            ),
            if (active != null && !active.isFullImage)
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text("Try full image instead"),
                subtitle: const Text(
                    "Use this when the scooter can't apply the delta "
                    "(e.g. no base image on the scooter)."),
                onTap: () => _tryFullImageInstead(active),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final connected = service.connected;
    // characteristicRepository is late-initialized during connect
    final otaAvailable = connected && service.characteristicRepository.otaAvailable;

    // After the post-install reboot (MDB) the link drops and comes back:
    // re-plan automatically so the user sees the next step.
    if (connected != _wasConnected) {
      _wasConnected = connected;
      if (connected &&
          (_transfer.state == OtaTransferState.pendingReboot ||
              _transfer.state == OtaTransferState.success)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }

    final actionable = connected && otaAvailable && !_transfer.busy && !_downloading;

    return Scaffold(
      appBar: AppBar(title: const Text("Firmware update")),
      body: ListView(
        children: [
          if (!connected)
            const ListTile(
              leading: Icon(Icons.bluetooth_disabled),
              title: Text("Scooter not connected"),
            )
          else if (!otaAvailable)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("Wireless updates not supported"),
              subtitle: Text("The scooter's firmware does not expose the OTA service yet."),
            ),
          _versionTile("Scooter (MDB)", _mdbVersion, Icons.memory),
          _versionTile("Dashboard (DBC)", _dbcVersion, Icons.speed),
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: const Text("Channel"),
            subtitle: _channelSwitch
                ? const Text("Channel switch: full images required",
                    style: TextStyle(color: Colors.amber))
                : null,
            trailing: DropdownButton<String>(
              value: _channel,
              items: [
                for (final c in UpdatePlanner.channels)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (_transfer.busy || _refreshing)
                  ? null
                  : (v) {
                      if (v != null) _onChannelSelected(v);
                    },
            ),
          ),
          if (_phase == _PlanPhase.queryingVersions)
            const ListTile(
              leading: CircularProgressIndicator(),
              title: Text("Reading installed versions..."),
            )
          else if (_phase == _PlanPhase.fetchingIndex)
            const ListTile(
              leading: CircularProgressIndicator(),
              title: Text("Checking for updates..."),
            )
          else if (_phase == _PlanPhase.upToDate)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text("Everything is up to date"),
              trailing: TextButton(
                onPressed: _refreshing ? null : () => _refresh(),
                child: const Text("Check again"),
              ),
            )
          else if (_phase == _PlanPhase.ready && _plan != null)
            _planList(_plan!, actionable: actionable),
          if (_downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(title: Text("Downloading bundle...")),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(value: _downloadProgress),
                ),
              ],
            ),
          _transferStatus(),
          if (_error != null)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(_error!),
              trailing: _phase == _PlanPhase.error
                  ? TextButton(
                      onPressed: _refreshing ? null : () => _refresh(),
                      child: const Text("Retry"),
                    )
                  : null,
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Keep the app in the foreground and the phone near the scooter during "
              "the transfer. An interrupted transfer resumes where it left off.",
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
