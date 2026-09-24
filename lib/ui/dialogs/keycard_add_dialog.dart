import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:lottie/lottie.dart';
import 'package:logging/logging.dart';

/// Extracts the UID from a polled [NFCTag].
/// Returns uppercase hex, e.g. "04A1B2C3D4E5F6", or null if unknown.
String? extractKeycardUid(NFCTag tag) {
  final id = tag.id.toUpperCase();
  return id == 'UNKNOWN' || id.isEmpty ? null : id;
}

/// A dialog that walks the user through a two-tap NFC keycard enrolment flow.
/// Pops with the confirmed UID string on success, or null on cancellation.
class KeycardAddDialog extends StatefulWidget {
  const KeycardAddDialog({super.key, required this.existingUids});

  final List<String> existingUids;

  @override
  State<KeycardAddDialog> createState() => _KeycardAddDialogState();
}

class _KeycardAddDialogState extends State<KeycardAddDialog> with WidgetsBindingObserver {
  String? _firstUid;
  String? _errorMessage;
  bool _confirmed = false;
  final _log = Logger('KeycardAddDialog');
  Completer<void>? _resumeCompleter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _log.info('[enrolment] Dialog opened; existingUids=${widget.existingUids}');
    _doFirstTap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.fine('[enrolment] App lifecycle → $state');
    if (state == AppLifecycleState.resumed) {
      final completer = _resumeCompleter;
      _resumeCompleter = null;
      completer?.complete();
    }
  }

  /// Waits until the app is in the [AppLifecycleState.resumed] state.
  /// Returns immediately if already resumed (e.g. on Android, or after iOS
  /// NFC sheet has fully dismissed).
  Future<void> _waitForAppResumed() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
    _log.info('[enrolment] Waiting for app to resume (NFC sheet still visible)');
    _resumeCompleter ??= Completer<void>();
    await _resumeCompleter!.future;
    _log.info('[enrolment] App resumed — NFC sheet dismissed');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _log.info('[enrolment] Dialog disposed; _firstUid=$_firstUid _confirmed=$_confirmed');
    // Unblock any pending _waitForAppResumed() so it doesn't leak.
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    // Ensure any active session is closed if the dialog is dismissed early.
    FlutterNfcKit.finish().catchError((e) {
      _log.warning('[enrolment] finish() in dispose threw: $e');
    });
    super.dispose();
  }

  Future<void> _doFirstTap() async {
    _log.info('[enrolment] _doFirstTap() called');
    setState(() => _errorMessage = null);
    try {
      _log.info('[enrolment] Starting poll() for first tap');
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: FlutterI18n.translate(context, 'ls_keycard_add_tap1'),
        readIso14443A: true,
        readIso14443B: false,
        readIso18092: false,
        readIso15693: true,
      );
      _log.info('[enrolment] poll() returned: id=${tag.id} type=${tag.type} standard=${tag.standard}');
      // Brief pause before finish() so the iOS NFCTagReaderSession's connect
      // callback fully completes before we call invalidate(). Without this,
      // invalidate() fires didInvalidateWithError while the session is still
      // active, which delivers a spurious error to the Dart side.
      _log.fine('[enrolment] Waiting 200ms before finish()');
      await Future.delayed(const Duration(milliseconds: 200));
      _log.info('[enrolment] Calling finish() after first tap');
      await FlutterNfcKit.finish();
      _log.info('[enrolment] finish() completed after first tap');

      final uid = extractKeycardUid(tag);
      _log.info('[enrolment] Extracted UID: $uid (raw id=${tag.id})');
      if (!mounted) {
        _log.warning('[enrolment] Widget unmounted after first tap finish()');
        return;
      }

      if (uid == null) {
        _log.warning('[enrolment] Could not extract UID from tag: ${tag.id}');
        setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_read_error'));
        _log.info('[enrolment] Retrying first tap (null UID)');
        _doFirstTap();
        return;
      }

      _log.fine('[enrolment] First tap UID: $uid');

      if (widget.existingUids.contains(uid)) {
        _log.info('[enrolment] UID $uid already registered; showing error and retrying');
        await HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 50));
        await HapticFeedback.lightImpact();
        if (!mounted) return;
        setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_already_registered'));
        _log.info('[enrolment] Retrying first tap (duplicate UID)');
        _doFirstTap();
        return;
      }

      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      _log.info('[enrolment] First tap accepted; advancing to second tap');
      setState(() {
        _firstUid = uid;
        _errorMessage = null;
      });
      _doSecondTap(uid);
    } on PlatformException catch (e) {
      _log.warning('[enrolment] PlatformException on first tap: code=${e.code} message=${e.message} details=${e.details}');
      if (!mounted) return;
      // iOS incorrectly reports MIFARE NDEF failures as code 409 (user-canceled).
      // Never auto-close the dialog on NFC errors — show the error and retry.
      // The user can cancel intentionally via the Cancel button in the dialog.
      setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_read_error'));
      _log.info('[enrolment] Waiting 1500ms before retrying first tap after PlatformException');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        _log.info('[enrolment] Retrying first tap after PlatformException');
        _doFirstTap();
      }
    } catch (e, stack) {
      _log.severe('[enrolment] Unexpected error on first tap', e, stack);
      if (mounted) setState(() => _errorMessage = 'Failed to start NFC: $e');
    }
  }

  Future<void> _doSecondTap(String expectedUid) async {
    _log.info('[enrolment] _doSecondTap() called; expectedUid=$expectedUid');
    if (!mounted) {
      _log.warning('[enrolment] Widget unmounted at start of _doSecondTap()');
      return;
    }
    setState(() => _errorMessage = null);
    // Wait for the iOS NFC sheet from the previous session to fully dismiss
    // before opening a new NFCTagReaderSession. A fixed delay is not reliable —
    // the sheet can take >2 s to animate out. Starting a new session while the
    // old sheet is still visible causes iOS to immediately cancel it with 409.
    await _waitForAppResumed();
    // Small buffer so the sheet is visually gone before the next one appears.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      _log.warning('[enrolment] Widget unmounted after waiting for app resume');
      return;
    }
    _log.info('[enrolment] Starting poll() for second tap');
    try {
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: FlutterI18n.translate(context, 'ls_keycard_add_tap2'),
        readIso14443A: true,
        readIso14443B: false,
        readIso18092: false,
        readIso15693: true,
      );
      _log.info('[enrolment] poll() returned on second tap: id=${tag.id} type=${tag.type} standard=${tag.standard}');
      _log.fine('[enrolment] Waiting 200ms before finish() on second tap');
      await Future.delayed(const Duration(milliseconds: 200));
      _log.info('[enrolment] Calling finish() after second tap');
      await FlutterNfcKit.finish();
      _log.info('[enrolment] finish() completed after second tap');

      final uid = extractKeycardUid(tag);
      _log.info('[enrolment] Extracted UID on second tap: $uid (raw id=${tag.id})');
      if (!mounted) {
        _log.warning('[enrolment] Widget unmounted after second tap finish()');
        return;
      }

      if (uid == null) {
        _log.warning('[enrolment] Could not extract UID on second tap');
        setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_read_error'));
        _log.info('[enrolment] Retrying second tap (null UID)');
        _doSecondTap(expectedUid);
        return;
      }

      if (uid == expectedUid) {
        _log.info('[enrolment] Second tap confirmed: $uid — enrolment complete');
        await HapticFeedback.mediumImpact();
        if (!mounted) return;
        setState(() => _confirmed = true);
        _log.info('[enrolment] Popping dialog with confirmed UID in 1200ms');
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            _log.info('[enrolment] Popping dialog now');
            Navigator.of(context).pop(_firstUid);
          }
        });
      } else {
        _log.warning('[enrolment] Second tap mismatch: expected=$expectedUid got=$uid');
        await HapticFeedback.vibrate();
        if (!mounted) return;
        setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_mismatch'));
        _log.info('[enrolment] Retrying second tap after mismatch');
        _doSecondTap(expectedUid);
      }
    } on PlatformException catch (e) {
      _log.warning('[enrolment] PlatformException on second tap: code=${e.code} message=${e.message} details=${e.details}');
      if (!mounted) return;
      setState(() => _errorMessage = FlutterI18n.translate(context, 'ls_keycard_read_error'));
      _log.info('[enrolment] Waiting 1500ms before retrying second tap after PlatformException');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        _log.info('[enrolment] Retrying second tap after PlatformException');
        _doSecondTap(expectedUid);
      }
    } catch (e, stack) {
      _log.severe('[enrolment] Unexpected error on second tap', e, stack);
      if (mounted) setState(() => _errorMessage = 'Failed to start NFC: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Lottie.asset(
            _confirmed ? "assets/anim/keycard_enrolment_done.json" : "assets/anim/keycard_enrolment_tap.json",
            key: ValueKey(_confirmed),
            height: 160,
            repeat: _confirmed ? false : true,
          ),
          const SizedBox(height: 24),
          Text(
            _firstUid == null
                ? FlutterI18n.translate(context, "ls_keycard_add_tap1")
                : FlutterI18n.translate(context, "ls_keycard_add_tap2"),
          ),
        ],
      ),
      content: (_firstUid == null && _errorMessage == null)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_firstUid != null)
                  Text(
                    _firstUid!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                if (_errorMessage != null) ...[
                  if (_firstUid != null) const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
      actions: [
        if (!_confirmed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(FlutterI18n.translate(context, "cancel")),
          ),
      ],
    );
  }
}
