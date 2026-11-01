import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/service/battery_nfc_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_nfc_kit/method');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final serial = ascii.encode('T-UNU22205090007');
  var unsupported = false;
  var changeSerial = false;
  var reads = 0;
  Completer<String>? poll;
  Completer<void>? finish;

  setUp(() {
    calls.clear();
    reads = 0;
    unsupported = false;
    changeSerial = false;
    poll = null;
    finish = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getNFCAvailability':
          return 'available';
        case 'poll':
          return poll?.future ??
              jsonEncode({
                'type': unsupported ? 'iso7816' : 'mifare_ultralight',
                'id': 'NOT-THE-SERIAL',
                'standard': 'ISO 14443-3A'
              });
        case 'transceive':
          reads++;
          final data = (call.arguments as Map)['data'] as Uint8List;
          expect(data[0], 0x30);
          expect(data[1], anyOf(0xc4, 0xc8));
          if (data[1] == 0xc4) return Uint8List.fromList([0, 0, 0, 0, ...serial.take(12)]);
          return Uint8List.fromList(
              [...(changeSerial && reads > 2 ? ascii.encode('9999') : serial.skip(12)), ...List.filled(12, 0)]);
        case 'finish':
          await finish?.future;
          return null;
        default:
          fail('Unexpected NFC operation ${call.method}');
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses only read commands and checks the full serial twice', () async {
    final identity = await BatteryNfcReader().read();
    expect(identity.serialNumber, 'T-UNU22205090007');
    expect(reads, 4);
    expect(calls.where((call) => call.method == 'finish').length, 1);
  });

  test('unsupported tags and changing identities fail and finish the session', () async {
    unsupported = true;
    await expectLater(BatteryNfcReader().read(), throwsFormatException);
    expect(reads, 0);
    unsupported = false;
    changeSerial = true;
    await expectLater(BatteryNfcReader().read(), throwsFormatException);
    expect(calls.where((call) => call.method == 'finish').length, 2);
  });

  test('cancellation during session teardown discards the checked identity', () async {
    finish = Completer<void>();
    final reader = BatteryNfcReader();
    final reading = reader.read();
    final error = expectLater(reading, throwsStateError);
    while (!calls.any((call) => call.method == 'finish')) {
      await Future<void>.delayed(Duration.zero);
    }
    await reader.cancel();
    finish!.complete();
    await error;
    expect(calls.where((call) => call.method == 'finish').length, 1);
  });

  test('cancelled polling cannot produce an identity or terminate another session later', () async {
    poll = Completer<String>();
    final reader = BatteryNfcReader();
    final reading = reader.read();
    final error = expectLater(reading, throwsStateError);
    await expectLater(reader.read(), throwsStateError);
    while (!calls.any((call) => call.method == 'poll')) {
      await Future<void>.delayed(Duration.zero);
    }
    await reader.cancel();
    poll!.complete(jsonEncode({'type': 'mifare_ultralight', 'id': 'tag', 'standard': 'ISO 14443-3A'}));
    await error;
    expect(reads, 0);
    expect(calls.where((call) => call.method == 'finish').length, 1);
  });
}
