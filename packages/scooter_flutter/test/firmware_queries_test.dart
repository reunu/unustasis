import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool get isDisconnected => false;
}

class _Channel extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  final writes = <String>[];
  List<String> replies = [];
  @override
  bool get isNotifying => true;
  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    writes.add(ascii.decode(value));
    for (final reply in replies) {
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

  test('version response retains the complete component version', () async {
    channel.replies = ['status:version:mdb:1.4:custom'];
    expect(await getInstalledVersionCommand(device, repo, 'mdb'), '1.4:custom');
    expect(channel.writes, ['status:version:mdb']);
  });

  test('version rejects a response for a different component', () async {
    channel.replies = ['status:version:dbc:1.4'];
    expect(await getInstalledVersionCommand(device, repo, 'mdb'), isNull);
  });

  test('unknown installed version is preserved, not treated as no response', () async {
    channel.replies = ['status:version:dbc:unknown'];
    expect(await getInstalledVersionCommand(device, repo, 'dbc'), 'unknown');
  });

  test('power capabilities retain names and discard argument syntax', () async {
    channel.replies = ['cap:pm:count:2', 'cap:pm:hibernate-for <duration>', 'cap:pm:hibernate-cancel'];
    expect(await getPmCapabilitiesCommand(device, repo), {'hibernate-for', 'hibernate-cancel'});
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

  test('setting values preserve spaces and colons', () async {
    channel.replies = ['get:example:value with spaces:and:colons'];
    expect(await getLsSettingCommand(device, repo, 'example'), 'value with spaces:and:colons');
    expect(channel.writes, ['get:example']);
  });

  test('empty setting is distinct from unsupported setting', () async {
    channel.replies = ['get:example:'];
    expect(await getLsSettingCommand(device, repo, 'example'), '');
    channel.replies = ['get:error:unknown key'];
    expect(await getLsSettingCommand(device, repo, 'example'), isNull);
  });

  test('empty write is rejected before sending', () async {
    await expectLater(setLsSettingCommand(device, repo, 'example', ''), throwsA('Setting value must not be empty'));
    expect(channel.writes, isEmpty);
  });

  test('setting write requires acknowledgement for exactly its own key', () async {
    channel.replies = ['set:ok:example'];
    await setLsSettingCommand(device, repo, 'example', 'some:value');
    expect(channel.writes, ['set:example:some:value']);
    channel.replies = ['set:ok:different'];
    await expectLater(setLsSettingCommand(device, repo, 'example', 'value'),
        throwsA('Failed to set example, response: set:ok:different'));
  });
}
