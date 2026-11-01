import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../feature_flags.dart';
import '../../scooter_service.dart';
import '../../service/battery_nfc_reader.dart';
import '../../service/battery_handoff_client.dart';
import '../../service/battery_read_failure.dart';
import '../widgets/battery_tracking_intro.dart';

enum _TrackerStep { welcome, read, verify, share, browser }

class BatteryTrackerScreen extends StatefulWidget {
  const BatteryTrackerScreen({
    super.key,
    this.readBluetooth,
    this.readNfc,
    this.openBrowser,
    this.prepareHandoff,
    this.bluetoothSupported,
    this.startWithScan = false,
    this.registrationEnabled = sunshineBatteryRegistrationEnabled,
  });

  final Future<List<BatteryIdentity>> Function()? readBluetooth;
  final Future<BatteryIdentity> Function()? readNfc;
  final Future<bool> Function(Uri)? openBrowser;
  final Future<BatteryHandoff> Function(BatteryIdentity)? prepareHandoff;
  final bool? bluetoothSupported;
  final bool startWithScan;
  final bool registrationEnabled;

  @override
  State<BatteryTrackerScreen> createState() => _BatteryTrackerScreenState();
}

class _BatteryTrackerScreenState extends State<BatteryTrackerScreen> {
  final _nfc = BatteryNfcReader();
  final _handoffs = BatteryHandoffClient();
  BatteryHandoff? _handoff;
  late _TrackerStep _step = widget.startWithScan ? _TrackerStep.read : _TrackerStep.welcome;
  List<BatteryIdentity> _readings = [];
  BatteryIdentity? _selected;
  bool _busy = false;
  bool _scanningNfc = false;
  String? _error;
  int _readGeneration = 0;

  String _text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');

  @override
  void dispose() {
    _readGeneration++;
    _handoffs.cancel();
    unawaited(_nfc.cancel().catchError((Object _) {}));
    super.dispose();
  }

  void _startReading() {
    _readGeneration++;
    _handoffs.cancel();
    _handoff = null;
    setState(() {
      _step = _TrackerStep.read;
      _busy = false;
      _scanningNfc = false;
      _readings = [];
      _selected = null;
      _error = null;
    });
  }

  void _back() {
    _readGeneration++;
    _handoffs.cancel();
    _handoff = null;
    if (_scanningNfc) unawaited(_nfc.cancel().catchError((Object _) {}));
    setState(() {
      _busy = false;
      _scanningNfc = false;
      _error = null;
      _step = switch (_step) {
        _TrackerStep.verify => _TrackerStep.read,
        _TrackerStep.share => _TrackerStep.verify,
        _ => _TrackerStep.welcome,
      };
      if (_step == _TrackerStep.read || _step == _TrackerStep.welcome) {
        _readings = [];
        _selected = null;
      }
    });
  }

  Future<void> _read({required bool nfc}) async {
    if (_busy) return;
    final generation = ++_readGeneration;
    _handoff = null;
    setState(() {
      _busy = true;
      _scanningNfc = nfc;
      _readings = [];
      _selected = null;
      _error = null;
    });
    try {
      final readings = nfc
          ? [await (widget.readNfc?.call() ?? _nfc.read())]
          : await (widget.readBluetooth?.call() ?? context.read<ScooterService>().actions.readBatteryIdentities());
      if (!mounted || generation != _readGeneration) return;
      final unique = <String, BatteryIdentity>{for (final reading in readings) reading.serialNumber: reading};
      setState(() {
        _readings = unique.values.toList();
        if (_readings.isEmpty) {
          _error = 'no_readings';
        } else {
          _selected = _readings.length == 1 ? _readings.first : null;
          _step = _TrackerStep.verify;
        }
      });
    } catch (error) {
      if (mounted && generation == _readGeneration) {
        final reason = batteryReadFailureReason(error);
        Logger('BatteryTracker').warning('Battery read failed: source=${nfc ? 'nfc' : 'ble'} reason=$reason');
        setState(() => _error = batteryReadFailureMessage(reason, nfc: nfc));
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _busy = false;
          _scanningNfc = false;
        });
      }
    }
  }

  Future<void> _openBrowser(Uri uri) async {
    if (_busy || !widget.registrationEnabled) return;
    final generation = _readGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await (widget.openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Browser unavailable');
    } catch (_) {
      if (mounted && generation == _readGeneration) setState(() => _error = 'account_open_error');
    } finally {
      if (mounted && generation == _readGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _continueRegistration() async {
    if (_busy || !widget.registrationEnabled || _selected == null) return;
    final generation = _readGeneration;
    final battery = _selected!;
    var openingBrowser = false;
    bool isCurrent() => mounted && generation == _readGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var handoff = _handoff;
      if (handoff == null || !handoff.expiresAt.isAfter(DateTime.now())) {
        handoff = await (widget.prepareHandoff?.call(battery) ?? _handoffs.prepare(battery));
      }
      if (!isCurrent()) return;
      _handoff = handoff;
      openingBrowser = true;
      final opened =
          await (widget.openBrowser?.call(handoff.uri) ?? launchUrl(handoff.uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Browser unavailable');
      if (isCurrent()) setState(() => _step = _TrackerStep.browser);
    } catch (error) {
      if (isCurrent()) {
        setState(() => _error = openingBrowser
            ? 'account_open_error'
            : error is BatteryHandoffException && error.reason == BatteryHandoffFailure.rateLimited
                ? 'handoff_rate_limited'
                : 'handoff_error');
      }
    } finally {
      if (isCurrent()) setState(() => _busy = false);
    }
  }

  Widget _primary(String label, VoidCallback? action, {Key? key, IconData icon = Icons.arrow_forward}) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.icon(
      key: key,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        foregroundColor: colors.primary.computeLuminance() > 0.179 ? Colors.black : Colors.white,
      ),
      onPressed: _busy ? null : action,
      icon: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 20),
      label: Text(_text(label), textAlign: TextAlign.center),
    );
  }

  Widget _heading(String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
              header: true,
              child: Text(_text(title),
                  style:
                      Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.12))),
          const SizedBox(height: 12),
          Text(_text(body), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
        ]),
      );

  Widget _progress() {
    final current = switch (_step) {
      _TrackerStep.read => 0,
      _TrackerStep.verify => 1,
      _ => 2,
    };
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: FlutterI18n.translate(context, 'battery_tracker_step', translationParams: {'number': '${current + 1}'}),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
                child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: i <= current ? colors.primary : colors.onSurface.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)))),
          ],
        ]),
        const SizedBox(height: 12),
        Text(_text(['step_read', 'step_verify', 'step_share'][current]),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
      ]),
    );
  }

  Widget _details() => ExpansionTile(
        key: const ValueKey('battery-tracker-details'),
        tilePadding: EdgeInsets.zero,
        title: Text(_text('how_it_works'), style: Theme.of(context).textTheme.bodyMedium),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text('how_it_works_body')),
          const SizedBox(height: 12),
          Text(_text('claim_short'), style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _errorNotice() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18)),
                child: Text(_text(_error!), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              )),
        );

  Widget _manage() => TextButton(
        key: const ValueKey('manage-battery-tracker'),
        onPressed: _busy ? null : () => _openBrowser(batteryTrackerRegistrationsUri()),
        child: Text(_text('manage_account')),
      );

  List<Widget> _welcome() => [
        const SizedBox(height: 8),
        BatteryTrackingIntro(registrationEnabled: widget.registrationEnabled),
        const SizedBox(height: 36),
        _errorNotice(),
        _primary('add', _startReading, key: const ValueKey('add-battery'), icon: Icons.add),
        const SizedBox(height: 8),
        if (widget.registrationEnabled) _manage(),
        const SizedBox(height: 28),
        _details(),
      ];

  Widget _source({required bool nfc, required bool enabled, required String subtitle}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Color.alphaBlend(colors.primary.withValues(alpha: 0.035), colors.surface),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), side: BorderSide(color: colors.onSurface.withValues(alpha: 0.12))),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('battery-source-${nfc ? 'nfc' : 'bluetooth'}'),
          enabled: enabled && !_busy,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: enabled ? 0.1 : 0.04), borderRadius: BorderRadius.circular(16)),
            child: Icon(nfc ? Icons.nfc_rounded : Icons.bluetooth_rounded,
                color: enabled ? colors.primary : colors.onSurfaceVariant),
          ),
          title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_text(nfc ? 'read_nfc' : 'read_ble')),
            if (!nfc) const BatteryFirmwareBadge(),
          ]),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(_text(subtitle))),
          trailing: enabled ? const Icon(Icons.chevron_right) : null,
          onTap: enabled && !_busy ? () => _read(nfc: nfc) : null,
        ),
      ),
    );
  }

  List<Widget> _chooseSource() {
    final service = widget.readBluetooth == null ? context.watch<ScooterService>() : null;
    final connected = widget.readBluetooth != null || service!.connected;
    final supported =
        widget.readBluetooth != null ? widget.bluetoothSupported ?? true : service!.identity.supportsBatteryIdentity;
    final bluetooth = _source(
        nfc: false,
        enabled: connected && supported == true,
        subtitle: !connected
            ? 'ble_connect'
            : supported == null
                ? 'ble_checking'
                : supported
                    ? 'ble_ready'
                    : 'ble_unsupported');
    final nfc = _source(
        nfc: true,
        enabled: widget.readNfc != null || Platform.isAndroid || Platform.isIOS,
        subtitle: widget.readNfc != null || Platform.isAndroid || Platform.isIOS ? 'nfc_short' : 'nfc_unavailable');
    return [
      _progress(),
      const SizedBox(height: 28),
      const BatteryRegistrationArt(icon: Icons.nfc_rounded, height: 132),
      _heading('read_title', 'read_body'),
      _errorNotice(),
      if (_busy) ...[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(_text(_scanningNfc ? 'nfc_notice' : 'reading_ble'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextButton(onPressed: _back, child: Text(_text('cancel'))),
      ] else ...[
        if (connected && supported == true) ...[bluetooth, nfc] else ...[nfc, bluetooth],
        const SizedBox(height: 12),
        Text(_text('check_privacy'), style: Theme.of(context).textTheme.bodySmall),
      ],
    ];
  }

  Widget _serialPanel(BatteryIdentity battery, {bool selected = true, bool selectable = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color.alphaBlend(colors.primary.withValues(alpha: selected ? 0.065 : 0.025), colors.surface),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: selected ? colors.primary.withValues(alpha: 0.4) : colors.onSurface.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_text('serial'), style: Theme.of(context).textTheme.labelMedium)),
          if (selectable) Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
        ]),
        const SizedBox(height: 10),
        if (selectable)
          Text(battery.serialNumber, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'monospace'))
        else
          SelectableText(battery.serialNumber,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 10),
        Text(_text(battery.source == BatteryIdentitySource.ble ? 'source_ble' : 'source_nfc'),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  List<Widget> _verify() => [
        _progress(),
        const SizedBox(height: 28),
        const BatteryRegistrationArt(icon: Icons.fact_check_outlined, height: 132),
        _heading('verify_title', _readings.length > 1 ? 'verify_multiple' : 'verify_body'),
        for (final battery in _readings)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _readings.length == 1
                ? _serialPanel(battery)
                : Semantics(
                    selected: identical(battery, _selected),
                    button: true,
                    child: InkWell(
                      key: ValueKey('battery-reading-${battery.serialNumber}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _selected = battery),
                      child: _serialPanel(battery, selected: identical(battery, _selected), selectable: true),
                    ),
                  ),
          ),
        const SizedBox(height: 12),
        _primary('verify_match', _selected == null ? null : () => setState(() => _step = _TrackerStep.share),
            key: const ValueKey('battery-label-verification'), icon: Icons.check),
        const SizedBox(height: 8),
        TextButton(onPressed: _startReading, child: Text(_text('verify_mismatch'))),
      ];

  List<Widget> _share() => [
        _progress(),
        _heading('share_title', 'share_body'),
        _serialPanel(_selected!),
        const SizedBox(height: 24),
        Text(_text('upload_consent'),
            key: const ValueKey('battery-sharing-disclosure'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.location_off_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(_text('no_location'), style: Theme.of(context).textTheme.bodySmall)),
        ]),
        const SizedBox(height: 24),
        _errorNotice(),
        _primary('continue', widget.registrationEnabled ? _continueRegistration : null,
            key: const ValueKey('battery-register-continue'), icon: Icons.open_in_browser),
        if (!widget.registrationEnabled) ...[
          const SizedBox(height: 12),
          Text(_text('account_unavailable')),
        ],
        const SizedBox(height: 16),
        _details(),
      ];

  List<Widget> _browser() => [
        const SizedBox(height: 32),
        const BatteryRegistrationArt(icon: Icons.open_in_browser, height: 180),
        _heading('finish_title', 'finish_browser'),
        _serialPanel(_selected!),
        const SizedBox(height: 24),
        _errorNotice(),
        _primary('return_browser', _continueRegistration, icon: Icons.open_in_browser),
        const SizedBox(height: 8),
        TextButton(onPressed: _startReading, child: Text(_text('add_another'))),
        const SizedBox(height: 12),
        if (widget.registrationEnabled) _manage(),
      ];

  @override
  Widget build(BuildContext context) {
    final children = switch (_step) {
      _TrackerStep.welcome => _welcome(),
      _TrackerStep.read => _chooseSource(),
      _TrackerStep.verify => _verify(),
      _TrackerStep.share => _share(),
      _TrackerStep.browser => _browser(),
    };
    return Theme(
        data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
        )),
        child: PopScope(
          canPop: _step == _TrackerStep.welcome,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_text('title')),
              leading: _step == _TrackerStep.welcome ? null : BackButton(onPressed: _back),
            ),
            body: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
                      children: [
                        ...children,
                      ],
                    ),
                  ),
                )),
          ),
        ));
  }
}
