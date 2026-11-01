import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

import 'support/hash_test_server.dart';

class _Device extends Fake implements BluetoothDevice {
  bool live = true;
  int attMtu = 23;
  final states = StreamController<BluetoothConnectionState>.broadcast(sync: true);
  @override
  bool get isDisconnected => !live;
  @override
  int get mtuNow => attMtu;
  @override
  Stream<BluetoothConnectionState> get connectionState => states.stream;
}

class _Wire extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  Future<void> Function(String)? onWrite;
  final writes = <String>[];
  final notifications = <List<int>>[];
  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) async => true;
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    expect(allowLongWrite, isTrue); // ATT23 uses prepared writes for <=100B commands.
    expect(value.length, lessThanOrEqualTo(100));
    final command = ascii.decode(value);
    writes.add(command);
    await onWrite?.call(command);
  }

  void reply(String text) => raw(ascii.encode(text));
  void raw(List<int> value) {
    notifications.add(value);
    values.add(value);
  }
}

class _Harness {
  _Harness() {
    repo = CharacteristicRepository(device)
      ..extendedCommandCharacteristic = wire
      ..extendedResponseCharacteristic = wire;
    wire.onWrite = (text) async => wire.reply(server.answer(text));
    addTearDown(() async {
      await wire.values.close();
      await device.states.close();
    });
  }
  final device = _Device();
  final wire = _Wire();
  final server = HashTestServer();
  late final CharacteristicRepository repo;
  bool current = true;
  Future<List<String?>> read(
          {String hash = 'battery:0',
          List<String> fields = const ['present', 'serial-number'],
          Duration timeout = const Duration(seconds: 1),
          Duration total = const Duration(seconds: 5)}) =>
      readHashFieldsCommand(device, repo, hash, fields,
          isCurrent: () => current, responseTimeout: timeout, readTimeout: total);
}

void main() {
  for (final mtu in [23, 64, 247, 512]) {
    test('ordered snapshot at ATT MTU $mtu respects notification budget and EOF', () async {
      final h = _Harness();
      h.device.attMtu = mtu;
      final values = await h.read(fields: ['serial-number', 'present']);
      expect(values, ['T-UNU22205090007', 'true']);
      final id = h.wire.writes.first.split(':')[2];
      expect(id, matches(r'^(?!00000000)[0-9a-f]{8}$'));
      expect(h.wire.writes.first, 'hash:read:$id:${mtu < 247 ? mtu - 3 : 244}:battery:0/serial-number,present');
      expect(h.wire.writes.last, startsWith('hash:get:$id:'));
      expect(h.wire.notifications.last,
          ascii.encode('r:e:$id:${utf8.encode(jsonEncode(values)).length.toRadixString(36)}'));
      expect(h.wire.notifications.every((v) => v.length <= (mtu < 247 ? mtu - 3 : 244)), isTrue);
      expect(h.wire.values.hasListener, isFalse);
      expect(h.device.states.hasListener, isFalse);
    });
  }

  for (final mtu in [23, 64, 247, 512]) {
    test('zero-filled radio notifications at ATT MTU $mtu preserve the snapshot', () async {
      final h = _Harness();
      h.device.attMtu = mtu;
      final budget = mtu < 247 ? mtu - 3 : 244;
      h.server.hashes['battery:0'] = {'present': 'ä🛵\u0000', 'serial-number': ''};
      h.wire.onWrite = (text) async {
        final bytes = ascii.encode(h.server.answer(text));
        h.wire.raw([...bytes, ...List.filled(budget - bytes.length, 0)]);
      };
      expect(await h.read(), ['ä🛵\u0000', '']);
      expect(h.wire.notifications.every((frame) => frame.length == budget), isTrue);
      expect(h.wire.values.hasListener, isFalse);
    });
  }
  test('244-byte snapshot header with 230 trailing zeroes is valid framing', () async {
    final h = _Harness();
    h.device.attMtu = 247;
    h.server.rawSnapshot = ascii.encode('["true",null]');
    h.wire.onWrite = (text) async {
      final bytes = ascii.encode(h.server.answer(text));
      if (text.startsWith('hash:read:')) expect(bytes.length, 14);
      h.wire.raw([...bytes, ...List.filled(244 - bytes.length, 0)]);
    };
    expect(await h.read(), ['true', null]);
  });
  test('zero padding cannot hide an oversized notification', () async {
    final h = _Harness();
    h.wire.onWrite = (text) async {
      final bytes = ascii.encode(h.server.answer(text));
      h.wire.raw([...bytes, ...List.filled(21 - bytes.length, 0)]);
    };
    await expectLater(h.read(), throwsFormatException);
  });
  test('embedded NUL is not padding and cannot repair a malformed chunk', () async {
    final h = _Harness();
    h.wire.onWrite = (text) async {
      if (text.startsWith('hash:read:')) {
        h.wire.reply(h.server.answer(text));
      } else {
        h.wire.raw([...ascii.encode('r:p:${text.split(':')[2]}:0:W'), 0, ...ascii.encode('w'), 0]);
      }
    };
    await expectLater(h.read(), throwsFormatException);
  });

  test('raw strings, Unicode and escaped data survive byte-sized chunks', () async {
    final h = _Harness();
    final value = 'ä🛵"\\\n\u0000';
    h.server.hashes['battery:0'] = {'present': value, 'serial-number': ''};
    expect(await h.read(), [value, '']);
    expect(h.wire.writes.length, greaterThan(10));
  });
  test('missing fields and hashes remain null; field spelling is unchanged', () async {
    final h = _Harness();
    expect(await h.read(hash: 'missing', fields: ['Present', 'serial-number']), [null, null]);
    expect(h.wire.writes.first, endsWith(':missing/Present,serial-number'));
    expect(await h.read(fields: ['serial-number']), ['T-UNU22205090007']);
  });
  test('IDs never repeat across concurrent reads, repositories or reconnect', () async {
    final h = _Harness();
    await Future.wait([h.read(), h.read()]);
    h.device.states.add(BluetoothConnectionState.disconnected);
    h.device.states.add(BluetoothConnectionState.connected);
    await h.read();
    final other = _Harness();
    await other.read();
    final starts = [...h.wire.writes, ...other.wire.writes].where((s) => s.startsWith('hash:read:')).toList();
    expect(starts.map((s) => s.split(':')[2]).toSet(), hasLength(4));
  });
  test('stale and zero-ID replies are ignored, including same-device reconnect', () async {
    final h = _Harness();
    await h.read();
    final stale = ascii.decode(h.wire.notifications.first);
    h.device.states.add(BluetoothConnectionState.disconnected);
    h.device.states.add(BluetoothConnectionState.connected);
    h.wire.onWrite = (text) async {
      h.wire.reply(stale);
      h.wire.reply('r:x:00000000:id');
      h.wire.reply(h.server.answer(text));
    };
    expect(await h.read(), ['true', 'T-UNU22205090007']);
  });
  for (final foreign in [
    'long capability',
    'legacy Unicode',
    'foreign oversize',
    'foreign binary',
    'reserved binary',
    'ID suffix',
    'headerless binary'
  ]) {
    test('ignores $foreign before validating the active reply', () async {
      final h = _Harness();
      h.wire.onWrite = (text) async {
        final id = text.split(':')[2];
        final otherId = id == 'ffffffff' ? 'fffffffe' : 'ffffffff';
        final frame = switch (foreign) {
          'long capability' => ascii.encode('cap:ext:${'status:' * 10}'),
          'legacy Unicode' => utf8.encode('status:destination:Grüße 🛵'),
          'foreign oversize' => ascii.encode('r:p:$otherId:0:${'A' * 100}'),
          'foreign binary' => [...ascii.encode('r:p:$otherId:0:'), 0xff, 0],
          'reserved binary' => [...ascii.encode('r:x:00000000:'), 0xff, 0],
          'ID suffix' => ascii.encode('r:s:${id}0:${'A' * 100}'),
          _ => [0xff],
        };
        h.wire.raw(frame);
        h.wire.reply(h.server.answer(text));
      };
      expect(await h.read(), ['true', 'T-UNU22205090007']);
    });
  }
  test('paced worst-case ATT23 snapshot fits the default five-minute deadline', () async {
    final h = _Harness();
    h.server.hashes['battery:0'] = {
      'present': '\u0000' * 256,
      'serial-number': '\u0000' * 256,
    };
    expect(
        await readHashFieldsCommand(h.device, h.repo, 'battery:0', ['present', 'serial-number'],
            isCurrent: () => h.current),
        ['\u0000' * 256, '\u0000' * 256]);
    final pacedDuration = Duration(milliseconds: h.wire.notifications.length * 100);
    expect(pacedDuration, greaterThan(const Duration(minutes: 2)));
    expect(hashReadTimeout, const Duration(minutes: 5));
    expect(pacedDuration, lessThan(hashReadTimeout));
    expect(h.wire.notifications.every((v) => v.length <= 20), isTrue);
  });
  test('old generation cannot use a reply after reconnecting the same device', () async {
    final h = _Harness();
    h.wire.onWrite = (text) async {
      h.wire.reply(h.server.answer(text));
      h.current = false;
      h.device.states.add(BluetoothConnectionState.disconnected);
      h.device.states.add(BluetoothConnectionState.connected);
    };
    await expectLater(h.read(), throwsStateError);
    expect(h.wire.writes, hasLength(1));
  });
  test('disconnect is latched even if the same device reconnects before write completes', () async {
    final h = _Harness();
    h.wire.onWrite = (text) async {
      h.wire.reply(h.server.answer(text));
      h.device.states.add(BluetoothConnectionState.disconnected);
      h.device.states.add(BluetoothConnectionState.connected);
    };
    await expectLater(h.read(), throwsStateError);
    expect(h.wire.writes, hasLength(1));
  });
  test('a closed response stream cannot turn the final EOF into success', () async {
    final h = _Harness();
    h.wire.onWrite = (text) async {
      final reply = h.server.answer(text);
      h.wire.reply(reply);
      if (reply.startsWith('r:e:')) await h.wire.values.close();
    };
    await expectLater(h.read(), throwsStateError);
  });
  test('disconnect aborts a pending read without waiting for timeout', () async {
    final h = _Harness();
    h.wire.onWrite = (_) async {
      h.device.live = false;
      h.device.states.add(BluetoothConnectionState.disconnected);
    };
    await expectLater(h.read(), throwsStateError);
    expect(h.wire.values.hasListener, isFalse);
  });
  test('timeout, stale-only notifications and a subsequent read do not reuse IDs', () async {
    final h = _Harness();
    h.wire.onWrite = (_) async => h.wire.reply('r:x:00000000:id');
    await expectLater(h.read(timeout: const Duration(milliseconds: 10)), throwsA(isA<TimeoutException>()));
    final first = h.wire.writes.first.split(':')[2];
    h.wire.onWrite = (text) async => h.wire.reply(h.server.answer(text));
    expect(await h.read(), ['true', 'T-UNU22205090007']);
    expect(h.wire.writes[1].split(':')[2], isNot(first));
  });
  test('silent handler-overload drop times out once and removes listeners', () async {
    final h = _Harness();
    h.wire.onWrite = (_) async {};
    await expectLater(h.read(timeout: const Duration(milliseconds: 10)), throwsA(isA<TimeoutException>()));
    expect(h.wire.writes, hasLength(1));
    expect(h.wire.values.hasListener, isFalse);
    expect(h.device.states.hasListener, isFalse);
  });
  test('whole read has a bounded deadline', () async {
    final h = _Harness();
    await expectLater(h.read(total: Duration.zero), throwsA(isA<TimeoutException>()));
    expect(h.wire.writes, isEmpty);
  });
  test('failed writes and notification errors propagate and remove listeners', () async {
    final h = _Harness();
    h.wire.onWrite = (_) async => throw StateError('write failed');
    await expectLater(h.read(), throwsStateError);
    h.wire.onWrite = (_) async => h.wire.values.addError(StateError('notify failed'));
    await expectLater(h.read(), throwsStateError);
    expect(h.wire.values.hasListener, isFalse);
  });

  for (final error in ['command', 'denied', 'redis', 'large', 'utf8', 'busy', 'session', 'offset', 'budget', 'id']) {
    test('server error $error is not a missing or absent value', () async {
      final h = _Harness();
      h.wire.onWrite = (text) async => h.wire.reply('r:x:${text.split(':')[2]}:$error');
      await expectLater(h.read(), throwsA(isA<HashReadException>().having((e) => e.code, 'code', error)));
      expect(h.wire.writes, hasLength(1));
    });
  }
  for (final length in ['0', '1', '035', 'ABC', '-1', '+2', '35t', 'zzzz', '2:extra']) {
    test('rejects adversarial declared length $length', () async {
      final h = _Harness();
      h.wire.onWrite = (text) async => h.wire.reply('r:s:${text.split(':')[2]}:$length');
      await expectLater(h.read(), throwsFormatException);
      expect(h.wire.writes, hasLength(1));
    });
  }
  for (final corrupt in [
    'offset',
    'uppercase-offset',
    'padded',
    'pad-bits',
    'empty',
    'overflow',
    'early-eof',
    'wrong-type',
    'bad-error',
    'oversize',
    'non-ascii',
    'nul',
    'unknown-kind',
    'missing-colon'
  ]) {
    test('rejects adversarial $corrupt response', () async {
      final h = _Harness();
      h.wire.onWrite = (text) async {
        final id = text.split(':')[2];
        final proper = h.server.answer(text);
        if (text.startsWith('hash:read:')) {
          h.wire.reply(proper);
        } else {
          switch (corrupt) {
            case 'offset':
              h.wire.reply('r:p:$id:1:Ww');
            case 'uppercase-offset':
              h.wire.reply('r:p:$id:A:Ww');
            case 'padded':
              h.wire.reply('r:p:$id:0:Ww==');
            case 'pad-bits':
              h.wire.reply('r:p:$id:0:Wx');
            case 'empty':
              h.wire.reply('r:p:$id:0:');
            case 'overflow':
              h.wire.reply('r:p:$id:0:AAAA');
            case 'early-eof':
              h.wire.reply('r:e:$id:0');
            case 'wrong-type':
              h.wire.reply('r:s:$id:2');
            case 'bad-error':
              h.wire.reply('r:x:$id:nope');
            case 'oversize':
              h.wire.reply('r:p:$id:0:${'A' * 20}');
            case 'non-ascii':
              h.wire.raw([...ascii.encode('r:p:$id:0:'), 0xff]);
            case 'nul':
              h.wire.raw([...ascii.encode('r:p:$id:0:'), 0]);
            case 'unknown-kind':
              h.wire.reply('r:q:$id:0:Ww');
            case 'missing-colon':
              h.wire.reply('r:p:$id');
          }
        }
      };
      if (corrupt == 'overflow') h.server.rawSnapshot = ascii.encode('[]');
      await expectLater(h.read(), throwsFormatException);
    });
  }
  for (final body in [
    '{}',
    '[true,null]',
    '[1,null]',
    '[[],null]',
    '[{},null]',
    '[]',
    '[null]',
    '[null,null,null]',
    '["${'a' * 257}",null]',
    '["${'ä' * 129}",null]',
    '["\\ud800",null]',
    '["unterminated,null]'
  ]) {
    test(
        'rejects invalid JSON type/count/value ${body.length} ${body.substring(0, body.length < 16 ? body.length : 16)}',
        () async {
      final h = _Harness();
      h.server.rawSnapshot = utf8.encode(body);
      await expectLater(h.read(), throwsFormatException);
      expect(ascii.decode(h.wire.notifications.last), startsWith('r:e:'));
    });
  }
  test('invalid UTF8 across chunks fails rather than being replaced', () async {
    final h = _Harness();
    h.server.rawSnapshot = [91, 34, 0xc3, 0x28, 34, 44, 110, 117, 108, 108, 93];
    await expectLater(h.read(), throwsFormatException);
  });
  test('256 UTF8 bytes per value is accepted', () async {
    final h = _Harness();
    h.server.hashes['battery:0'] = {'present': 'ä' * 128, 'serial-number': 'x' * 256};
    expect(await h.read(), ['ä' * 128, 'x' * 256]);
  });
  test('rejects invalid selections before writing or subscribing', () async {
    final h = _Harness();
    for (final fields in <List<String>>[
      [],
      ['present', 'present'],
      ['a', 'b', 'c'],
      ['a,b'],
      ['a/b'],
      ['ä'],
      [' a'],
      ['']
    ]) {
      expect(() => h.read(fields: fields), throwsArgumentError);
    }
    expect(() => h.read(hash: 'battery:0/serial-number'), throwsArgumentError);
    await expectLater(h.read(hash: 'a' * 100), throwsArgumentError);
    h.device.attMtu = 22;
    await expectLater(h.read(), throwsStateError);
    expect(h.wire.writes, isEmpty);
    expect(h.wire.values.hasListener, isFalse);
  });
  test('a 100-byte ASCII request is accepted, not 101 bytes', () async {
    final h = _Harness();
    // hash:read:<8>:20:<hash>/present totals 30 bytes plus the hash.
    await h.read(hash: 'a' * 70, fields: ['present']);
    expect(h.wire.writes.first.length, 100);
    await expectLater(h.read(hash: 'a' * 71, fields: ['present']), throwsArgumentError);
  });

  final vectors = jsonDecode(File('test/fixtures/hash_read_vectors.json').readAsStringSync()) as List;
  for (final vector in vectors.cast<Map<String, dynamic>>()) {
    test('service golden vector ${vector['name']}', () async {
      final h = _Harness();
      h.device.attMtu = (vector['budget'] as int) + 3;
      final steps = <Map<String, dynamic>>[
        {'request': vector['readRequest'], 'response': vector['readResponse']},
        ...(vector['chunks'] as List).cast<Map<String, dynamic>>(),
      ];
      var step = 0;
      h.wire.onWrite = (text) async {
        final id = h.wire.writes.first.split(':')[2];
        final expected = steps[step++];
        expect(text, (expected['request'] as String).replaceAll('1234abcd', id));
        h.wire.reply((expected['response'] as String).replaceAll('1234abcd', id));
      };
      expect(await h.read(hash: vector['hash'] as String, fields: (vector['fields'] as List).cast<String>()),
          vector['values']);
      expect(step, steps.length);
    });
  }

  test('the 4096-byte JSON ceiling is inclusive', () async {
    final h = _Harness();
    h.device.attMtu = 247;
    h.server.rawSnapshot = ascii.encode('[null,null]'.padRight(4096));
    expect(await h.read(), [null, null]);
  });
  for (final wrongId in ['00000000', 'ABCDEF01', '123abcd', '1234abcd0']) {
    test('uncorrelated ID $wrongId cannot finish the read', () async {
      final h = _Harness();
      h.wire.onWrite = (_) async => h.wire.reply('r:s:$wrongId:2');
      await expectLater(h.read(timeout: const Duration(milliseconds: 10)), throwsA(isA<TimeoutException>()));
    });
  }
  test('EOF must correlate both ID and canonical final byte offset', () async {
    final h = _Harness();
    h.server.rawSnapshot = ascii.encode('[null,null]');
    h.wire.onWrite = (text) async {
      final reply = h.server.answer(text);
      h.wire.reply(reply.startsWith('r:e:') ? '${reply}0' : reply);
    };
    await expectLater(h.read(), throwsFormatException);
  });
}
