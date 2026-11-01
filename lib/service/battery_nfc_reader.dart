import 'dart:typed_data';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:scooter_core/battery_identity.dart';

class BatteryNfcReader {
  bool _active = false;
  bool _reading = false;
  int _generation = 0;

  Future<void> cancel() async {
    _generation++;
    await _finish();
  }

  Future<void> _finish() async {
    if (!_active) return;
    _active = false;
    await FlutterNfcKit.finish();
  }

  Future<BatteryIdentity> read() async {
    if (_reading) throw StateError('NFC scan already active');
    _reading = true;
    final generation = ++_generation;
    void check() {
      if (generation != _generation) throw StateError('NFC scan cancelled');
    }

    late final BatteryIdentity identity;
    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      check();
      if (availability != NFCAvailability.available) {
        throw StateError('NFC unavailable');
      }
      _active = true;
      final tag = await FlutterNfcKit.poll(androidCheckNDEF: false);
      check();
      if (tag.type != NFCTagType.mifare_ultralight) {
        throw const FormatException('Unsupported battery tag');
      }
      Future<String> serial() async {
        // READ is read-only on Type 2 tags. Do not issue battery commands,
        // writes, authentication attempts or use the tag UID as pack identity.
        final first = await FlutterNfcKit.transceive<Uint8List>(Uint8List.fromList([0x30, 0xc4]));
        check();
        final second = await FlutterNfcKit.transceive<Uint8List>(Uint8List.fromList([0x30, 0xc8]));
        check();
        return decodeNfcBatterySerial(first, second);
      }

      final first = await serial();
      final second = await serial();
      if (first != second) throw const FormatException('Battery identity changed');
      check();
      identity = BatteryIdentity(serialNumber: first, source: BatteryIdentitySource.nfc, checkedAt: DateTime.now());
    } finally {
      try {
        await _finish();
      } finally {
        _reading = false;
      }
    }
    check();
    return identity;
  }
}
