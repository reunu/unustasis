import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'domain/ota_protocol.dart';
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
    if (_refreshing || _transfer.active) return;
    final service = context.read<ScooterService>();

    // Recover an installation that outlived the app: after a force-close the
    // shared service is idle, but the scooter retains the session and
    // answers STATUS_REQ with its phase and progress.
    if (_transfer.state == OtaTransferState.idle &&
        service.connected &&
        service.characteristicRepository.otaAvailable) {
      try {
        if (await _transfer.syncFromScooter(
            service.myScooter!, service.characteristicRepository)) {
          if (mounted) setState(() {});
          return;
        }
      } catch (e) {
        log.warning("OTA status sync failed: $e");
      }
    }

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
      if (!mounted) return;
      if (resp.statusCode != 200) {
        throw FlutterI18n.translate(context, "ls_ota_error_index",
            translationParams: {"code": "${resp.statusCode}"});
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
      unawaited(_pruneDownloads(plan));
    } catch (e) {
      log.warning("Update check failed: $e");
      if (!mounted) return;
      setState(() {
        _error = FlutterI18n.translate(context, "ls_ota_error_check_failed",
            translationParams: {"error": "$e"});
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
          title: Text(FlutterI18n.translate(context, "ls_ota_switch_channel_title")),
          content: Text(FlutterI18n.translate(context, "ls_ota_switch_channel_body",
              translationParams: {"current": _inferredChannel!, "selected": selected})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(FlutterI18n.translate(context, "cancel")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(FlutterI18n.translate(context, "ls_ota_switch_channel_confirm",
                  translationParams: {"channel": selected})),
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
          title: Text(FlutterI18n.translate(context, "ls_ota_full_image_title")),
          content: Text(FlutterI18n.translate(context, "ls_ota_full_image_body",
              translationParams: {
                "asset": step.asset.name,
                "size": _formatBytes(step.asset.size),
              })),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(FlutterI18n.translate(context, "cancel")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(FlutterI18n.translate(context, "ls_ota_install")),
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
        setState(() => _error = FlutterI18n.translate(context, "ls_ota_error_no_full_image",
            translationParams: {"channel": _channel}));
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

  /// Deletes downloaded bundles the fresh plan no longer references.
  /// Downloads are only kept as a resume cache ("Resume", "Try full image");
  /// once the plan moves past a release its bundle is dead weight — full
  /// images are hundreds of MB of app storage (backed up on iOS). Runs only
  /// on the fresh-plan path, so nothing is downloading or transferring.
  Future<void> _pruneDownloads(UpdatePlan plan) async {
    try {
      final dir = Directory("${(await getApplicationSupportDirectory()).path}/ota");
      if (!await dir.exists()) return;
      final keep = {for (final step in plan.steps) step.asset.name};
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (keep.contains(name)) continue;
        log.info("Pruning stale bundle: $name");
        await entry.delete();
      }
    } catch (e) {
      log.warning("Bundle cleanup failed: $e");
    }
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
        // the download may outlive the screen; only translate with a live context
        throw !mounted
            ? "Download failed (HTTP ${resp.statusCode})"
            : FlutterI18n.translate(context, "ls_ota_error_download",
                translationParams: {"code": "${resp.statusCode}"});
      }
      final total = resp.contentLength ?? asset.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        }
      } finally {
        await sink.close();
      }
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
    if (seconds >= 3600) {
      return FlutterI18n.translate(context, "ls_ota_eta_hours",
          translationParams: {"hours": (seconds / 3600).toStringAsFixed(1)});
    }
    if (seconds >= 90) {
      return FlutterI18n.translate(context, "ls_ota_eta_minutes",
          translationParams: {"minutes": "${(seconds / 60).round()}"});
    }
    return FlutterI18n.translate(context, "ls_ota_eta_seconds",
        translationParams: {"seconds": "$seconds"});
  }

  String _boardLabel(int component) => FlutterI18n.translate(
      context, component == OtaProtocol.componentDbc ? "ls_ota_board_dbc" : "ls_ota_board_mdb");

  String _kindLabel(StepKind kind) {
    switch (kind) {
      case StepKind.delta:
        return FlutterI18n.translate(context, "ls_ota_kind_delta");
      case StepKind.full:
        return FlutterI18n.translate(context, "ls_ota_kind_full");
      case StepKind.convergeDelta:
        return FlutterI18n.translate(context, "ls_ota_kind_converge_delta");
      case StepKind.convergeFull:
        return FlutterI18n.translate(context, "ls_ota_kind_converge_full");
      case StepKind.channelSwitchFull:
        return FlutterI18n.translate(context, "ls_ota_kind_channel_switch");
    }
  }

  /// Progress bar in the app's house style (see driving_screen/home_screen) —
  /// the M3 default derives its track color from `secondary`, which is green
  /// like `primary` here, making the bar green-on-green.
  Widget _progressBar(double? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        color: Theme.of(context).colorScheme.primary,
        minHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _versionTile(String labelKey, String? version, IconData icon) {
    final known = UpdatePlanner.isKnownVersion(version);
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(FlutterI18n.translate(context, labelKey)),
      subtitle: Text(known
          ? version!
          : FlutterI18n.translate(
              context,
              version == "unknown" ? "ls_ota_version_unknown" : "ls_ota_version_unavailable")),
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
            title: Text(
                FlutterI18n.translate(context, warning.key, translationParams: warning.params),
                style: const TextStyle(fontSize: 13)),
          ),
        for (var i = 0; i < plan.steps.length; i++)
          ListTile(
            leading: Icon(plan.steps[i].isFullImage
                ? Icons.system_update_alt
                : Icons.compress),
            title: Text(FlutterI18n.translate(context, "ls_ota_step_title", translationParams: {
              "number": "${i + 1}",
              "board": _boardLabel(plan.steps[i].component),
              "version": plan.steps[i].release.tagName,
            })),
            subtitle: Text(FlutterI18n.translate(context, "ls_ota_step_subtitle",
                translationParams: {
                  "asset": plan.steps[i].asset.name,
                  "size": _formatBytes(plan.steps[i].asset.size),
                  "kind": _kindLabel(plan.steps[i].kind),
                })),
            trailing: i == 0
                ? TextButton(
                    onPressed: actionable ? () => _onInstallPressed(plan.steps[i]) : null,
                    child: Text(FlutterI18n.translate(context, "ls_ota_install")),
                  )
                : const Icon(Icons.lock_outline, size: 18),
          ),
        if (plan.steps.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              FlutterI18n.translate(context, "ls_ota_one_at_a_time"),
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Shown once the transfer itself is done: from here the scooter works on
  /// its own and the app can be closed — the session is re-adopted via
  /// STATUS_REQ when the screen is opened again.
  Widget _closableNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        FlutterI18n.translate(context, "ls_ota_closable_note"),
        style: const TextStyle(fontSize: 12),
      ),
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
          title: Text(FlutterI18n.translate(
              context,
              _transfer.state == OtaTransferState.hashing
                  ? "ls_ota_status_preparing"
                  : "ls_ota_status_contacting")),
        );
      case OtaTransferState.transferring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(FlutterI18n.translate(context, "ls_ota_transferring_to",
                  translationParams: {
                    "board": _activeStep != null
                        ? _boardLabel(_activeStep!.component)
                        : _boardLabel(OtaProtocol.componentMdb),
                  })),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_transfer_stats",
                      translationParams: {
                        "done": _formatBytes(_transfer.ackedBytes),
                        "total": _formatBytes(_transfer.totalBytes),
                        "rate": _formatBytes(_transfer.throughput),
                      }) +
                  _formatEta(_transfer.etaSeconds)),
              trailing: TextButton(
                onPressed: _transfer.abort,
                child: Text(FlutterI18n.translate(context, "cancel")),
              ),
            ),
            _progressBar(_transfer.progress),
          ],
        );
      case OtaTransferState.verifying:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(FlutterI18n.translate(context, "ls_ota_status_verifying")),
            ),
            _closableNote(),
          ],
        );
      case OtaTransferState.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(FlutterI18n.translate(context, "ls_ota_status_installing")),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_installing_percent",
                  translationParams: {"percent": "${_transfer.installPercent}"})),
            ),
            _progressBar(_transfer.installPercent / 100),
            _closableNote(),
          ],
        );
      case OtaTransferState.pendingReboot:
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(FlutterI18n.translate(context, "ls_ota_installed_title")),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_installed_subtitle")),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(FlutterI18n.translate(context, "ls_ota_check_again")),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_check_again_subtitle")),
              onTap: _refreshing ? null : () => _refresh(),
            ),
          ],
        );
      case OtaTransferState.success:
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(FlutterI18n.translate(context, "ls_ota_success")),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(FlutterI18n.translate(context, "ls_ota_check_again")),
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
              title: Text(FlutterI18n.translate(context, "ls_ota_failed")),
              subtitle: Text(_transfer.statusMessage),
              trailing: _transfer.resumable && active != null
                  ? TextButton(
                      onPressed: () => _executeStep(active),
                      child: Text(FlutterI18n.translate(context, "ls_ota_resume")))
                  : null,
            ),
            if (active != null && !active.isFullImage)
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: Text(FlutterI18n.translate(context, "ls_ota_try_full_title")),
                subtitle: Text(FlutterI18n.translate(context, "ls_ota_try_full_subtitle")),
                onTap: () => _tryFullImageInstead(active),
              ),
            // always offer a way out of the failure state
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(FlutterI18n.translate(context, "ls_ota_check_again")),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_check_again_subtitle")),
              onTap: _refreshing ? null : () => _refresh(),
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

    final actionable = connected && otaAvailable && !_transfer.active && !_downloading;

    return Scaffold(
      appBar: AppBar(title: Text(FlutterI18n.translate(context, "ls_ota_title"))),
      body: ListView(
        children: [
          if (!connected)
            ListTile(
              leading: const Icon(Icons.bluetooth_disabled),
              title: Text(FlutterI18n.translate(context, "ls_ota_not_connected")),
            )
          else if (!otaAvailable)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(FlutterI18n.translate(context, "ls_ota_not_supported_title")),
              subtitle: Text(FlutterI18n.translate(context, "ls_ota_not_supported_subtitle")),
            ),
          // After an app restart into a recovered session the versions were
          // never queried — hide the tiles instead of showing bogus warnings.
          if (_mdbVersion != null ||
              _dbcVersion != null ||
              _transfer.state == OtaTransferState.idle) ...[
            _versionTile("ls_ota_board_mdb", _mdbVersion, Icons.memory),
            _versionTile("ls_ota_board_dbc", _dbcVersion, Icons.speed),
          ],
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: Text(FlutterI18n.translate(context, "ls_ota_channel")),
            subtitle: _channelSwitch
                ? Text(FlutterI18n.translate(context, "ls_ota_channel_switch_note"),
                    style: const TextStyle(color: Colors.amber))
                : null,
            trailing: DropdownButton<String>(
              value: _channel,
              items: [
                for (final c in UpdatePlanner.channels)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (_transfer.active || _refreshing)
                  ? null
                  : (v) {
                      if (v != null) _onChannelSelected(v);
                    },
            ),
          ),
          if (_phase == _PlanPhase.queryingVersions)
            ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(FlutterI18n.translate(context, "ls_ota_reading_versions")),
            )
          else if (_phase == _PlanPhase.fetchingIndex)
            ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(FlutterI18n.translate(context, "ls_ota_checking")),
            )
          else if (_phase == _PlanPhase.upToDate)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(FlutterI18n.translate(context, "ls_ota_up_to_date")),
              trailing: TextButton(
                onPressed: _refreshing ? null : () => _refresh(),
                child: Text(FlutterI18n.translate(context, "ls_ota_check_again")),
              ),
            )
          else if (_phase == _PlanPhase.ready && _plan != null)
            _planList(_plan!, actionable: actionable),
          if (_downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(title: Text(FlutterI18n.translate(context, "ls_ota_downloading"))),
                _progressBar(_downloadProgress),
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
                      child: Text(FlutterI18n.translate(context, "ls_ota_retry")),
                    )
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              FlutterI18n.translate(context, "ls_ota_footer"),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
