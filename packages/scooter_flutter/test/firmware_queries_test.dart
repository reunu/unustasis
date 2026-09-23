import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/trip_expunge.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool get isDisconnected => false;
}

class _Channel extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  final writes = <String>[];
  List<String> replies = [];
  final Map<String, List<String>> repliesFor = {};
  Future<void> Function(String command)? onWrite;
  int notifyWrites = 0;
  @override
  bool get isNotifying => true;
  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    notifyWrites++;
    return true;
  }

  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    final command = ascii.decode(value);
    writes.add(command);
    await onWrite?.call(command);
    for (final reply in repliesFor[command] ?? replies) {
      values.add(utf8.encode(reply));
    }
  }
}

class _Repository extends Fake implements CharacteristicRepository {
  _Repository(this.channel);
  final _Channel channel;
  @override
  BluetoothCharacteristic get extendedCommandCharacteristic => channel;
  @override
  BluetoothCharacteristic get extendedResponseCharacteristic => channel;

  // Discovery accounting is not what these tests exercise; the transport calls
  // it on every command and response.
  @override
  void noteExtendedResponse() {}
  @override
  void noteSilentExtendedCommand() {}
  @override
  void noteGattRejection(Object error, String operation) {}
  @override
  bool extendedNotifyVerified = false;
  @override
  bool gattTableMismatch = false;
  @override
  bool extendedChannelUnresponsive = false;
  @override
  bool extendedChannelMissing = false;
  @override
  bool extendedChannelSilent = false;
  @override
  void noteStaleGattTable(String detail) {}
}

void main() {
  late _Channel channel;
  late _Repository repo;
  final device = _Device();
  setUp(() {
    channel = _Channel();
    repo = _Repository(channel);
  });
  tearDown(() async {
    expect(channel.values.hasListener, isFalse);
    await channel.values.close();
  });

  test('cap:ext reads unsuffixed and versioned complete groups once', () async {
    channel.replies = ['cap:ext:trip:pm=2:ble'];
    final groups = await discoverLsCapabilityGroupsCommand(device, repo);
    expect(groups.versions, {'trip': null, 'pm': 2, 'ble': null});
    expect(groups.usedFallback, isFalse);
    expect(groups.answered, isTrue);
    expect(channel.writes, ['cap:ext']);
  });

  test('cap:list is used when cap:ext is unknown', () async {
    channel.repliesFor['cap:ext'] = ['error:unknown command'];
    channel.repliesFor['cap:list'] = ['cap:count:2', 'cap:trip', 'cap:status'];
    final groups = await discoverLsCapabilityGroupsCommand(device, repo);
    expect(groups.versions.keys, {'trip', 'status'});
    expect(groups.usedFallback, isTrue);
    expect(groups.answered, isTrue);
    expect(channel.writes, ['cap:ext', 'cap:list']);
  });

  test('cap:list fails closed for malformed counted categories', () async {
    channel.repliesFor['cap:ext'] = ['error:unknown command'];
    channel.repliesFor['cap:list'] = [
      'cap:count:2',
      'cap:trip',
      'cap:bad:evil'
    ];
    final groups = await discoverLsCapabilityGroupsCommand(device, repo);
    expect(groups.versions, isEmpty);
    expect(groups.usedFallback, isTrue);
    expect(groups.answered, isTrue);
  });

  test('a silent capability query reports no answer, not an empty list',
      () async {
    final groups = await discoverLsCapabilityGroupsCommand(device, repo,
        responseTimeout: const Duration(milliseconds: 1));
    expect(groups.answered, isFalse);
    expect(groups.versions, isEmpty);
    expect(channel.writes, ['cap:ext', 'cap:list']);
  });

  test('version response retains the complete component version', () async {
    channel.replies = ['status:version:mdb:1.4:custom'];
    expect(await getInstalledVersionCommand(device, repo, 'mdb'), '1.4:custom');
    expect(channel.writes, ['status:version:mdb']);
  });

  test('version rejects a response for a different component', () async {
    channel.replies = ['status:version:dbc:1.4'];
    expect(await getInstalledVersionCommand(device, repo, 'mdb'), isNull);
  });

  test('unknown installed version is preserved, not treated as no response',
      () async {
    channel.replies = ['status:version:dbc:unknown'];
    expect(await getInstalledVersionCommand(device, repo, 'dbc'), 'unknown');
  });

  test('a queued capability probe rechecks freshness before notify or write',
      () async {
    final gate = Completer<void>();
    final blocker = withExtendedChannel(() => gate.future);
    await Future<void>.delayed(Duration.zero);
    var current = true;
    final probe =
        getLsCapabilitiesCommand(device, repo, 'pm', isCurrent: () => current);
    current = false;
    gate.complete();
    await blocker;
    await expectLater(probe, throwsStateError);
    expect(channel.notifyWrites, 0);
    expect(channel.writes, isEmpty);
  });

  test('power capabilities retain names and discard argument syntax', () async {
    channel.replies = [
      'cap:pm:count:2',
      'cap:pm:hibernate-for <duration>',
      'cap:pm:hibernate-cancel'
    ];
    expect(await getPmCapabilitiesCommand(device, repo),
        {'hibernate-for', 'hibernate-cancel'});
    expect(channel.writes, ['cap:pm']);
  });

  test('unsupported capability response yields an empty set', () async {
    channel.replies = ['error:unknown command'];
    expect(await getLsCapabilitiesCommand(device, repo, 'ble'), isEmpty);
  });

  test('empty capability list is supported', () async {
    channel.replies = ['cap:config:count:0'];
    expect(await getLsCapabilitiesCommand(device, repo, 'config'), isEmpty);
  });

  test('trip commands parse zero and reject negative acknowledgements',
      () async {
    channel.replies = [
      'trip:data:distance-m:0:duration-s:0:average-speed-kmh:0:reset-policy:manual:reset-at:0:reset-reason:initial:generation:0:status:idle'
    ];
    expect((await getTripCounterCommand(device, repo))!.distanceMeters, 0);
    channel.replies = ['trip:reset:error:busy'];
    await expectLater(
      resetTripCounterCommand(device, repo),
      throwsA(isA<TripResetException>()
          .having((error) => error.failure, 'failure', TripResetFailure.busy)),
    );
  });

  test('trip get reports an expired service lease as unavailable', () async {
    channel.replies = ['trip:data:error:unavailable'];
    await expectLater(
      getTripCounterCommand(device, repo),
      throwsA(isA<TripCounterUnavailableException>()),
    );
  });

  test('trip reset maps a transport timeout to its timeout failure', () async {
    await expectLater(
      resetTripCounterCommand(device, repo,
          responseTimeout: const Duration(milliseconds: 1)),
      throwsA(isA<TripResetException>().having(
          (error) => error.failure, 'failure', TripResetFailure.timeout)),
    );
  });

  test('delayed reset response holds the channel until its acknowledgement',
      () async {
    channel.repliesFor['trip:get'] = [
      'trip:data:distance-m:0:duration-s:0:average-speed-kmh:0:reset-policy:manual:reset-at:0:reset-reason:initial:generation:1:status:idle'
    ];
    final reset = resetTripCounterCommand(device, repo);
    await Future<void>.delayed(Duration.zero);
    final read = getTripCounterCommand(device, repo);
    expect(channel.writes, ['trip:reset']);
    channel.values.add(ascii.encode('trip:reset:ok'));
    await reset;
    expect((await read)!.generation, 1);
    expect(channel.writes, ['trip:reset', 'trip:get']);
  });

  test('setting values preserve spaces and colons', () async {
    channel.replies = ['get:example:value with spaces:and:colons'];
    expect(await getLsSettingCommand(device, repo, 'example'),
        'value with spaces:and:colons');
    expect(channel.writes, ['get:example']);
  });

  test('empty setting is distinct from unsupported setting', () async {
    channel.replies = ['get:example:'];
    expect(await getLsSettingCommand(device, repo, 'example'), '');
    channel.replies = ['get:error:unknown key'];
    expect(await getLsSettingCommand(device, repo, 'example'), isNull);
  });

  test('trip retention uses the generic atomic setting transport', () async {
    channel.replies = ['get:trip.expunge:age:365d'];
    expect((await getTripExpungePolicySetting(device, repo))!.wireValue,
        'age:365d');
    expect(channel.writes, ['get:trip.expunge']);

    channel.replies = ['set:ok:trip.expunge'];
    await setTripExpungePolicySetting(
        device, repo, TripExpunge(TripExpungePolicy.count, '0'));
    expect(channel.writes, ['get:trip.expunge', 'set:trip.expunge:count:0']);
  });

  test('trip retention rejects malformed firmware values', () async {
    channel.replies = ['get:trip.expunge:count:01'];
    await expectLater(
        getTripExpungePolicySetting(device, repo), throwsFormatException);
  });

  test('empty write is rejected before sending', () async {
    await expectLater(setLsSettingCommand(device, repo, 'example', ''),
        throwsA('Setting value must not be empty'));
    expect(channel.writes, isEmpty);
  });

  test('setting write requires acknowledgement for exactly its own key',
      () async {
    channel.replies = ['set:ok:example'];
    await setLsSettingCommand(device, repo, 'example', 'some:value');
    expect(channel.writes, ['set:example:some:value']);
    channel.replies = ['set:ok:different'];
    await expectLater(setLsSettingCommand(device, repo, 'example', 'value'),
        throwsA('Failed to set example, response: set:ok:different'));
  });
}
