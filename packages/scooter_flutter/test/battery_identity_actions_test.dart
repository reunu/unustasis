// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'scooter_actions_test.dart' as runtime;
import 'support/hash_test_server.dart';

void main() {
  test('battery reads require hash=1 and preserve both slot semantics', () async {
    final h = runtime.Harness(FakeAsync());
    await runtime.settleTransport();
    final server = HashTestServer();
    h.wire.onWrite = (command) async => h.wire.reply(command == 'cap:ext' ? 'cap:ext:hash=1' : server.answer(command));
    final identities = await h.actions.readBatteryIdentities();
    expect(identities.single.serialNumber, 'T-UNU22205090007');
    expect(identities.single.slot, 0);
    expect(server.requests.where((s) => s.startsWith('hash:read:')), [
      matches(r'^hash:read:[0-9a-f]{8}:20:battery:0/present,serial-number$'),
      matches(r'^hash:read:[0-9a-f]{8}:20:battery:1/present,serial-number$'),
    ]);
    expect(h.effects.events, isEmpty);
    h.dispose();
    await runtime.settleTransport();
  });
  for (final capability in ['status', 'hash', 'hash=2', 'battery=1']) {
    test('unverified capability $capability cannot enable serial reads', () async {
      final h = runtime.Harness(FakeAsync());
      await runtime.settleTransport();
      h.trace.clear();
      h.wire.onWrite = (_) async => h.wire.reply('cap:ext:$capability');
      await expectLater(h.actions.readBatteryIdentities(), throwsUnsupportedError);
      expect(h.trace, ['A:cap:ext']);
      h.dispose();
      await runtime.settleTransport();
    });
  }
  test('absent retained serial is ignored and leading zeroes survive', () async {
    final h = runtime.Harness(FakeAsync());
    await runtime.settleTransport();
    final server = HashTestServer();
    server.hashes['battery:0'] = {'present': 'false', 'serial-number': 'invalid retained'};
    server.hashes['battery:1'] = {'present': 'true', 'serial-number': '00000000000000ab'};
    h.wire.onWrite = (command) async => h.wire.reply(command == 'cap:ext' ? 'cap:ext:hash=1' : server.answer(command));
    final identities = await h.actions.readBatteryIdentities();
    expect(identities.single.serialNumber, '00000000000000AB');
    expect(identities.single.slot, 1);
    h.dispose();
    await runtime.settleTransport();
  });
  test('invalid second slot rejects the whole reading', () async {
    final h = runtime.Harness(FakeAsync());
    await runtime.settleTransport();
    final server = HashTestServer();
    server.hashes['battery:1'] = {'present': null, 'serial-number': ''};
    h.wire.onWrite = (command) async => h.wire.reply(command == 'cap:ext' ? 'cap:ext:hash=1' : server.answer(command));
    await expectLater(h.actions.readBatteryIdentities(), throwsFormatException);
    h.dispose();
    await runtime.settleTransport();
  });
  for (final change in ['disconnect', 'same-id', 'other-id']) {
    test('session change $change cannot produce a partial or retargeted battery read', () async {
      final h = runtime.Harness(FakeAsync());
      await runtime.settleTransport();
      final wire = h.wire;
      final server = HashTestServer();
      wire.onWrite = (command) async {
        wire.reply(command == 'cap:ext' ? 'cap:ext:hash=1' : server.answer(command));
        if (command.startsWith('hash:read:')) {
          if (change == 'disconnect') {
            h.device.drop();
          } else {
            if (change == 'same-id') h.session.connected = false;
            h.connect(change == 'same-id' ? 'A' : 'B');
          }
        }
      };
      await expectLater(h.actions.readBatteryIdentities(), throwsStateError);
      expect(server.requests.where((s) => s.startsWith('hash:read:')), hasLength(1));
      h.dispose();
      await runtime.settleTransport();
    });
  }
}
