import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:lottie/lottie.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

/// Extracts the UID from an [NfcTag] on Android and iOS.
/// Returns uppercase hex, e.g. "04A1B2C3D4E5F6", or null if not readable.
String? extractKeycardUid(NfcTag tag) {
  List<int>? bytes;
  if (Platform.isAndroid) {
    bytes = NfcTagAndroid.from(tag)?.id;
  } else if (Platform.isIOS) {
    bytes = MiFareIos.from(tag)?.identifier ?? Iso7816Ios.from(tag)?.identifier ?? Iso15693Ios.from(tag)?.identifier;
  }
  // Uppercase to match the format sent by the scooter firmware over BLE.
  return bytes?.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

/// A dialog that walks the user through a two-tap NFC keycard enrolment flow.
/// Pops with the confirmed UID string on success, or null on cancellation.
class KeycardAddDialog extends StatefulWidget {
  const KeycardAddDialog({super.key, required this.existingUids});

  final List<String> existingUids;

  @override
  State<KeycardAddDialog> createState() => _KeycardAddDialogState();
}

class _KeycardAddDialogState extends State<KeycardAddDialog> {
  String? _firstUid;
  String? _errorMessage;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  void _startScanning() {
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        final uid = extractKeycardUid(tag);
        if (!mounted) return;

        if (uid == null) {
          setState(() => _errorMessage = FlutterI18n.translate(context, "ls_keycard_read_error"));
          return;
        }

        if (_firstUid == null) {
          // First tap
          if (widget.existingUids.contains(uid)) {
            await HapticFeedback.lightImpact();
            await Future.delayed(const Duration(milliseconds: 50));
            await HapticFeedback.lightImpact();
            if (!mounted) return;
            setState(() => _errorMessage = FlutterI18n.translate(context, "ls_keycard_already_registered"));
            return;
          }
          await HapticFeedback.mediumImpact();
          if (!mounted) return;
          setState(() {
            _firstUid = uid;
            _errorMessage = null;
          });
        } else {
          // Second tap — confirm
          if (uid == _firstUid) {
            await NfcManager.instance.stopSession();
            await HapticFeedback.mediumImpact();
            if (!mounted) return;
            setState(() => _confirmed = true);
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted) Navigator.of(context).pop(_firstUid);
            });
          } else {
            await HapticFeedback.vibrate();
            if (!mounted) return;
            setState(() => _errorMessage = FlutterI18n.translate(context, "ls_keycard_mismatch"));
          }
        }
      },
    );
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
