import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import '../../domain/ota_protocol.dart';
import '../../domain/update_planner.dart';
import '../../scooter_service.dart';
import '../../service/ota_transfer_service.dart';

import 'package:scooter_flutter/update_controller.dart';

class LsOtaScreen extends StatefulWidget {
  const LsOtaScreen({super.key});

  @override
  State<LsOtaScreen> createState() => _LsOtaScreenState();
}

class _LsOtaScreenState extends State<LsOtaScreen> {
  late final UpdateController _updates;
  OtaTransferService get _transfer => _updates.transfer;
  UpdatePlanPhase get _phase => _updates.phase;
  String get _channel => _updates.channel;
  String? get _inferredChannel => _updates.inferredChannel;
  bool get _channelSwitch => _updates.channelSwitch;
  String? get _mdbVersion => _updates.mdbVersion;
  String? get _dbcVersion => _updates.dbcVersion;
  UpdatePlan? get _plan => _updates.plan;
  bool get _downloading => _updates.downloading;
  double get _downloadProgress => _updates.downloadProgress;
  bool get _refreshing => _updates.refreshing;
  String? _presentationError;
  String? get _error => _presentationError ?? (_updates.error == null ? null : _errorText(_updates.error!));
  UpdateStep? get _activeStep => _transfer.activeStep;

  String _errorText(Object error) {
    if (error is UpdateCheckError) {
      return FlutterI18n.translate(context, 'ls_ota_error_check_failed',
          translationParams: {'error': _errorText(error.cause)});
    }
    if (error is UpdateHttpError) {
      return FlutterI18n.translate(context,
          error.index ? 'ls_ota_error_index' : 'ls_ota_error_download',
          translationParams: {'code': '${error.statusCode}'});
    }
    return error.toString();
  }

  @override
  void initState() {
    super.initState();
    _updates = context.read<ScooterService>().updateController;
    _updates.addListener(_onTransferChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _transfer.state == OtaTransferState.idle) _refresh();
    });
  }

  @override
  void dispose() {
    _updates.removeListener(_onTransferChanged);
    super.dispose();
  }

  void _onTransferChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh({bool channelSwitch = false, String? selectedChannel}) {
    setState(() => _presentationError = null);
    return _updates.refresh(channelSwitch: channelSwitch, selectedChannel: selectedChannel);
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
    _refresh(channelSwitch: isSwitch, selectedChannel: selected);
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

  Future<void> _executeStep(UpdateStep step) {
    setState(() => _presentationError = null);
    return _updates.executeStep(step);
  }

  Future<void> _tryFullImageInstead(UpdateStep deltaStep) async {
    final step = _updates.fullImageInstead(deltaStep);
    if (step == null) {
      setState(() => _presentationError = FlutterI18n.translate(context, "ls_ota_error_no_full_image",
          translationParams: {"channel": _channel}));
      return;
    }
    await _onInstallPressed(step);
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
            if (_transfer.awaitingReconnect)
              ListTile(
                leading: const Icon(Icons.bluetooth_disabled),
                title: Text(FlutterI18n.translate(context, 'ls_ota_awaiting_confirmation',
                    translationParams: {'scooter': context.read<ScooterService>().updateTargetName ?? _updates.targetId ?? ''})),
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
    final otaAvailable = _updates.otaAvailable;
    final actionable = connected && otaAvailable && !_updates.busy && !_transfer.awaitingReconnect;

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
              onChanged: (_updates.busy || _transfer.awaitingReconnect)
                  ? null
                  : (v) {
                      if (v != null) _onChannelSelected(v);
                    },
            ),
          ),
          if (_phase == UpdatePlanPhase.queryingVersions)
            ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(FlutterI18n.translate(context, "ls_ota_reading_versions")),
            )
          else if (_phase == UpdatePlanPhase.fetchingIndex)
            ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(FlutterI18n.translate(context, "ls_ota_checking")),
            )
          else if (_phase == UpdatePlanPhase.upToDate)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(FlutterI18n.translate(context, "ls_ota_up_to_date")),
              trailing: TextButton(
                onPressed: _refreshing ? null : () => _refresh(),
                child: Text(FlutterI18n.translate(context, "ls_ota_check_again")),
              ),
            )
          else if (_phase == UpdatePlanPhase.ready && _plan != null)
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
              trailing: _phase == UpdatePlanPhase.error
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
