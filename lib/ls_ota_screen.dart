import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'domain/ota_protocol.dart';
import 'scooter_service.dart';
import 'service/ota_transfer_service.dart';

final log = Logger('LsOtaScreen');

/// A firmware bundle offered by the librescoot release index
/// (`https://downloads.librescoot.org/releases/[channel].json`, same index
/// update-service consumes).
class OtaRelease {
  final String tagName;
  final String assetName;
  final String url;
  final int size;

  OtaRelease({required this.tagName, required this.assetName, required this.url, required this.size});

  /// The `.mender` basename without extension; the scooter derives the
  /// displayed version from it.
  String get bundleId => assetName.endsWith(".mender") ? assetName.substring(0, assetName.length - 7) : assetName;
}

class LsOtaScreen extends StatefulWidget {
  const LsOtaScreen({super.key});

  @override
  State<LsOtaScreen> createState() => _LsOtaScreenState();
}

class _LsOtaScreenState extends State<LsOtaScreen> {
  static const _releasesBase = "https://downloads.librescoot.org/releases";
  static const _channels = ["stable", "testing", "nightly"];

  final OtaTransferService _transfer = OtaTransferService();

  String _channel = "stable";
  OtaRelease? _latest;
  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transfer.addListener(_onTransferChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  @override
  void dispose() {
    _transfer.removeListener(_onTransferChanged);
    super.dispose();
  }

  void _onTransferChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _latest = null;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse("$_releasesBase/$_channel.json"))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw "Release index unavailable (HTTP ${resp.statusCode})";
      }
      final releases = jsonDecode(resp.body) as List<dynamic>;
      for (final r in releases) {
        final assets = (r["assets"] as List<dynamic>? ?? []);
        for (final a in assets) {
          final name = a["name"] as String? ?? "";
          if (name.contains("mdb") && name.endsWith(".mender")) {
            setState(() {
              _latest = OtaRelease(
                tagName: r["tag_name"] as String? ?? "unknown",
                assetName: name,
                url: a["url"] as String? ?? "",
                size: (a["size"] as num?)?.toInt() ?? 0,
              );
            });
            return;
          }
        }
      }
      setState(() => _error = "No MDB bundle found on the $_channel channel");
    } catch (e) {
      log.warning("Update check failed: $e");
      setState(() => _error = "Update check failed: $e");
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<File> _downloadBundle(OtaRelease release) async {
    final dir = await getApplicationSupportDirectory();
    final file = File("${dir.path}/ota/${release.assetName}");
    if (await file.exists() && await file.length() == release.size) {
      return file; // already downloaded
    }
    await file.parent.create(recursive: true);

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    try {
      final req = http.Request("GET", Uri.parse(release.url));
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) {
        throw "Download failed (HTTP ${resp.statusCode})";
      }
      final total = resp.contentLength ?? release.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          setState(() => _downloadProgress = received / total);
        }
      }
      await sink.close();
      return file;
    } finally {
      setState(() => _downloading = false);
    }
  }

  Future<void> _startUpdate() async {
    final service = context.read<ScooterService>();
    final scooter = service.myScooter;
    final repo = service.characteristicRepository;
    final release = _latest;
    if (scooter == null || release == null) return;

    setState(() => _error = null);
    try {
      final bundle = await _downloadBundle(release);
      await _transfer.transfer(
        scooter,
        repo,
        bundle,
        bundleId: release.bundleId,
        component: OtaProtocol.componentMdb,
      );
    } catch (e) {
      log.warning("OTA update failed: $e");
      if (mounted) setState(() => _error = e.toString());
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
              title: const Text("Transferring to scooter"),
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
        return const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text("Installed"),
          subtitle: Text("Lock the scooter to reboot and finish the update."),
        );
      case OtaTransferState.success:
        return const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text("Update installed"),
        );
      case OtaTransferState.failure:
        return ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text("Update failed"),
          subtitle: Text(_transfer.statusMessage),
          trailing: _transfer.resumable
              ? TextButton(onPressed: _startUpdate, child: const Text("Resume"))
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final connected = service.connected;
    // characteristicRepository is late-initialized during connect
    final otaAvailable = connected && service.characteristicRepository.otaAvailable;

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
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: const Text("Channel"),
            trailing: DropdownButton<String>(
              value: _channel,
              items: [
                for (final c in _channels) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: _transfer.busy
                  ? null
                  : (v) {
                      if (v != null) {
                        setState(() => _channel = v);
                        _checkForUpdates();
                      }
                    },
            ),
          ),
          if (_checking)
            const ListTile(
              leading: CircularProgressIndicator(),
              title: Text("Checking for updates..."),
            )
          else if (_latest != null)
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: Text(_latest!.tagName),
              subtitle: Text("${_latest!.assetName} (${_formatBytes(_latest!.size)})"),
              trailing: TextButton(
                onPressed: (connected && otaAvailable && !_transfer.busy && !_downloading)
                    ? _startUpdate
                    : null,
                child: const Text("Install"),
              ),
            ),
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
