import 'dart:convert';

import 'package:scooter_core/battery_identity.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.utc(2026, 10, 27);

  test('canonical serial preserves zeroes and does not apply board conversion', () {
    expect(canonicalBatterySerial(' 00000000000000ab\x00 '), '00000000000000AB');
    expect(canonicalBatterySerial('0012345'), '0012345');
    expect(canonicalBatterySerial('T-UNU22205090007'), 'T-UNU22205090007');
    for (final invalid in ['', 'unknown', 'null', 'n/a', '0000', '---', 'has space', '\u0080', '\u00a0ABC', 'x' * 65]) {
      expect(() => canonicalBatterySerial(invalid), throwsFormatException);
    }
  });

  test('raw hash fields bind presence and serial to the requested slot', () {
    final identity = parseBatteryIdentityFields(['true', 'T-UNU22205090007'], 0, time)!;
    expect(identity.serialNumber, 'T-UNU22205090007');
    expect(identity.slot, 0);
    expect(identity.checkedAt, time);
    expect(identity.source, BatteryIdentitySource.ble);
    for (final serial in [null, '', 'unknown', 'retained']) {
      expect(parseBatteryIdentityFields(['false', serial], 1, time), isNull);
    }
    for (final invalid in <List<String?>>[
      [],
      [null, null],
      ['', 'SERIAL'],
      ['TRUE', 'SERIAL'],
      ['1', 'SERIAL'],
      ['unknown', 'SERIAL'],
      ['true'],
      ['true', null],
      ['true', ''],
      ['true', 'unknown'],
      ['true', 'SERIAL', 'extra'],
    ]) {
      expect(() => parseBatteryIdentityFields(invalid, 0, time), throwsFormatException);
    }
    expect(() => parseBatteryIdentityFields(['true', 'SERIAL'], 2, time), throwsArgumentError);
    expect(parseBatteryIdentityFields(['true', '00000000000000ab'], 1, time)!.serialNumber, '00000000000000AB');
  });

  test('NFC serial comes from both complete status blocks, never tag UID', () {
    final serial = ascii.encode('T-UNU22205090007');
    final first = [0, 0, 0, 0, ...serial.take(12)];
    final second = [...serial.skip(12), ...List.filled(12, 0)];
    expect(decodeNfcBatterySerial(first, second), 'T-UNU22205090007');
    expect(() => decodeNfcBatterySerial(first.take(15).toList(), second), throwsFormatException);
    expect(() => decodeNfcBatterySerial(first, second.take(4).toList()), throwsFormatException);
    first[4] = 0xff;
    expect(() => decodeNfcBatterySerial(first, second), throwsFormatException);
  });

  test('BLE and NFC identify the same pack independently of slot', () {
    final serial = ascii.encode('T-UNU22205090007');
    final nfc = decodeNfcBatterySerial([0, 0, 0, 0, ...serial.take(12)], [...serial.skip(12), ...List.filled(12, 0)]);
    final ble = parseBatteryIdentityFields(['true', nfc], 1, time)!;
    expect(ble.serialNumber, nfc);
  });

  test('management links contain no identity data and identity roundtrips unchanged', () {
    final identity =
        BatteryIdentity(serialNumber: 'T-UNU22205090007', source: BatteryIdentitySource.nfc, checkedAt: time);
    expect(BatteryIdentity.fromJson(identity.toJson()).serialNumber, identity.serialNumber);
    expect(batteryTrackerJoinUri().toString(), 'https://sunshine.rescoot.org/battery_tracker/join');
    expect(batteryTrackerRegistrationsUri().toString(), 'https://sunshine.rescoot.org/battery_tracker/registrations');
    expect(batteryTrackerJoinUri().hasQuery, isFalse);
    expect(batteryTrackerRegistrationsUri().hasQuery, isFalse);
  });
}
