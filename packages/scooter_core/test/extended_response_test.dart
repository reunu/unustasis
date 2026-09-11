import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:scooter_core/extended_response.dart';

List<int> enc(String s) => ascii.encode(s);

void main() {
  group('readExtendedList', () {
    test('reads a counted list', () async {
      final stream = Stream.fromIterable([
        'keycard:count:2',
        'keycard:card:aabb',
        'keycard:card:ccdd',
      ]);
      final got = await readExtendedList(stream, (msg) => msg.split(':').last);
      expect(got, ['aabb', 'ccdd']);
    });

    test('stops at the announced count and ignores trailing messages', () async {
      final stream = Stream.fromIterable([
        'keycard:count:1',
        'keycard:card:aabb',
        'keycard:card:ccdd',
      ]);
      final got = await readExtendedList(stream, (msg) => msg.split(':').last);
      expect(got, ['aabb']);
    });

    test('returns empty on a genuine zero count', () async {
      final stream = Stream.fromIterable(['keycard:count:0']);
      final got = await readExtendedList(stream, (msg) => msg);
      expect(got, isEmpty);
    });

    test('throws on an unparseable count instead of reporting zero items', () async {
      final stream = Stream.fromIterable(['error:unknown command']);
      expect(
        readExtendedList(stream, (msg) => msg),
        throwsA(isA<ExtendedResponseFormatException>()),
      );
    });

    test('throws on an error reply that ends in a non-numeric segment', () async {
      final stream = Stream.fromIterable(['cap:error:unsupported']);
      expect(
        readExtendedList(stream, (msg) => msg),
        throwsA(isA<ExtendedResponseFormatException>()),
      );
    });

    test('a zero count and a parse failure are distinguishable', () async {
      final zero = await readExtendedList(Stream.fromIterable(['cap:pm:count:0']), (msg) => msg);
      expect(zero, isEmpty);

      Object? thrown;
      try {
        await readExtendedList(Stream.fromIterable(['cap:pm:error']), (msg) => msg);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ExtendedResponseFormatException>());
      expect(thrown.toString(), contains('cap:pm:error'));
    });

    test('skips entries the parser rejects', () async {
      final stream = Stream.fromIterable([
        'keycard:count:2',
        'garbage',
        'keycard:card:aabb',
        'keycard:card:ccdd',
      ]);
      final got = await readExtendedList(
        stream,
        (msg) => msg.startsWith('keycard:card:') ? msg.split(':').last : null,
      );
      expect(got, ['aabb', 'ccdd']);
    });

    test('returns what it got when the stream ends early', () async {
      final stream = Stream.fromIterable([
        'keycard:count:3',
        'keycard:card:aabb',
      ]);
      final got = await readExtendedList(stream, (msg) => msg.split(':').last);
      expect(got, ['aabb']);
    });
  });

  group('parseCapabilityEntry', () {
    test('pulls the command name out of an entry', () {
      expect(parseCapabilityEntry('pm', 'cap:pm:hibernate-cancel'), 'hibernate-cancel');
      expect(parseCapabilityEntry('ble', 'cap:ble:forget'), 'forget');
    });

    test('drops the argument placeholder', () {
      expect(parseCapabilityEntry('pm', 'cap:pm:hibernate-for <duration>'), 'hibernate-for');
    });

    test('keeps colons inside a command name', () {
      expect(parseCapabilityEntry('nav', 'cap:nav:fav:add'), 'fav:add');
    });

    test('ignores entries for another category', () {
      expect(parseCapabilityEntry('ble', 'cap:pm:hibernate-cancel'), isNull);
      expect(parseCapabilityEntry('ble', 'ble:forget:ok'), isNull);
    });

    test('ignores an entry with nothing after the prefix', () {
      expect(parseCapabilityEntry('ble', 'cap:ble:'), isNull);
    });
  });

  group('ExtendedResponseListener', () {
    test('delivers responses emitted before the caller starts reading', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);

      // The response lands in the window between the command write and the
      // read. On a bare broadcast stream this would be dropped.
      source.add(enc('nav:ok'));
      await Future<void>.delayed(Duration.zero);

      expect(await listener.responses.first.timeout(const Duration(seconds: 1)), 'nav:ok');
      await listener.cancel();
      await source.close();
    });

    test('preserves order across the write window', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);

      source.add(enc('keycard:count:2'));
      source.add(enc('keycard:card:aabb'));
      await Future<void>.delayed(Duration.zero);
      source.add(enc('keycard:card:ccdd'));

      final got = await readExtendedList(
        listener.responses.timeout(const Duration(seconds: 1)),
        (msg) => msg.split(':').last,
      );
      expect(got, ['aabb', 'ccdd']);
      await listener.cancel();
      await source.close();
    });

    test('drops empty notifications and strips NUL padding', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);

      source.add(<int>[]);
      source.add([...enc('pm:ok'), 0, 0, 0]);
      await Future<void>.delayed(Duration.zero);

      expect(await listener.responses.first.timeout(const Duration(seconds: 1)), 'pm:ok');
      await listener.cancel();
      await source.close();
    });

    test('cancel completes even when nothing ever read the responses', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);
      source.add(enc('nav:ok'));
      await Future<void>.delayed(Duration.zero);

      await listener.cancel().timeout(const Duration(seconds: 1));
      await source.close();
    });

    test('decodes UTF-8 content without dropping malformed replies', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);
      final replies = listener.responses.take(2).toList();
      source.add(utf8.encode('nav:Café'));
      source.add([0xff, 0]);
      expect(await replies, ['nav:Café', '\uFFFD']);
      await listener.cancel();
      await source.close();
    });

    test('forwards transport errors to the response consumer', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);
      final error = StateError('link lost');
      final check = expectLater(listener.responses.first, throwsA(same(error)));
      source.addError(error);
      await check;
      await listener.cancel();
      await source.close();
    });

    test('stops buffering once cancelled', () async {
      final source = StreamController<List<int>>.broadcast();
      final listener = ExtendedResponseListener(source.stream);
      await listener.cancel();

      source.add(enc('nav:ok'));
      await Future<void>.delayed(Duration.zero);
      expect(source.hasListener, isFalse);
      await source.close();
    });
  });

}
