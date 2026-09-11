import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/state/scooter_identity.dart';

// No device construction, service discovery, platform channels, or networking.
class _ReadCharacteristic implements BluetoothCharacteristic {
  final reads = <Completer<List<int>>>[];

  @override
  Future<List<int>> read({int timeout = 15}) {
    final result = Completer<List<int>>();
    reads.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class _Repository implements CharacteristicRepository {
  @override
  BluetoothCharacteristic? nrfVersionCharacteristic;

  @override
  BluetoothCharacteristic? odometerCharacteristic;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

// Snapshot all three read-owned fields so a discarded read cannot silently
// mutate one field while leaving the other fields and callback count intact.
(String?, bool?, int?) _snapshot(ScooterIdentity identity) =>
    (identity.nrfVersion, identity.isLibrescoot, identity.odometerMeters);

void main() {
  for (final nrf in [true, false]) {
    group(nrf ? 'wireNrfVersion' : 'refreshOdometer', () {
      late ScooterIdentity identity;
      late _Repository repository;
      late _ReadCharacteristic characteristic;
      late List<(String?, bool?, int?)> updates;
      const initial = ('existing-ls', true, 900);
      final current = nrf ? ('2.0', false, 900) : ('existing-ls', true, 123456);
      final currentBytes = nrf ? utf8.encode(' \t2.0\u0000\n') : <int>[0x40, 0xe2, 0x01, 0x00];
      final staleBytes = nrf ? utf8.encode('old-ls') : <int>[0x01, 0x00, 0x00, 0x00];

      void start({bool Function()? isCurrent}) {
        void onUpdate() => updates.add(_snapshot(identity));
        if (nrf) {
          identity.wireNrfVersion(repository, onUpdate: onUpdate, isCurrent: isCurrent);
        } else {
          identity.refreshOdometer(repository, onUpdate: onUpdate, isCurrent: isCurrent);
        }
      }

      setUp(() {
        identity = ScooterIdentity()
          ..nrfVersion = initial.$1
          ..isLibrescoot = initial.$2
          ..odometerMeters = initial.$3;
        characteristic = _ReadCharacteristic();
        repository = _Repository();
        if (nrf) {
          repository.nrfVersionCharacteristic = characteristic;
        } else {
          repository.odometerCharacteristic = characteristic;
        }
        updates = [];
      });

      for (final guarded in [true, false]) {
        test('current result publishes once (${guarded ? 'guarded' : 'no predicate'})', () async {
          var checks = 0;
          start(
              isCurrent: guarded
                  ? () {
                      checks++;
                      return true;
                    }
                  : null);
          expect(characteristic.reads, hasLength(1));
          expect(_snapshot(identity), initial);
          expect(updates, isEmpty);
          expect(checks, 0);

          characteristic.reads.single.complete(currentBytes);
          await pumpEventQueue(times: 2);
          expect(_snapshot(identity), current);
          expect(updates, [current]);
          expect(checks, guarded ? 1 : 0);
          await pumpEventQueue(times: 2);
          expect(updates, [current]);
          expect(characteristic.reads, hasLength(1));
        });
      }

      test('invalidation while read is pending preserves values and emits nothing', () async {
        var valid = true;
        var checks = 0;
        start(isCurrent: () {
          checks++;
          return valid;
        });
        expect(characteristic.reads, hasLength(1));
        expect(checks, 0);
        valid = false;
        characteristic.reads.single.complete(currentBytes);
        await pumpEventQueue(times: 2);
        expect(checks, 1);
        expect(_snapshot(identity), initial);
        expect(updates, isEmpty);
      });

      for (final staleFirst in [true, false]) {
        test('interleaved session reads discard stale ${staleFirst ? 'first' : 'last'} result', () async {
          // Deliberately reuse the repository and characteristic: validity is
          // supplied by the caller, not inferred from either object's identity.
          var session = 1;
          final firstSession = session;
          start(isCurrent: () => session == firstSession);
          session = 2;
          final secondSession = session;
          start(isCurrent: () => session == secondSession);
          expect(characteristic.reads, hasLength(2));
          expect(_snapshot(identity), initial);
          expect(updates, isEmpty);

          if (staleFirst) {
            characteristic.reads[0].complete(staleBytes);
            await pumpEventQueue(times: 2);
            expect(_snapshot(identity), initial);
            expect(updates, isEmpty);
            characteristic.reads[1].complete(currentBytes);
          } else {
            characteristic.reads[1].complete(currentBytes);
            await pumpEventQueue(times: 2);
            expect(_snapshot(identity), current);
            expect(updates, [current]);
            characteristic.reads[0].complete(staleBytes);
          }
          await pumpEventQueue(times: 2);
          expect(_snapshot(identity), current);
          expect(updates, [current]);
          expect(characteristic.reads, hasLength(2));
        });
      }

      test('read failure preserves state and emits nothing; next read succeeds', () async {
        var checks = 0;
        start(isCurrent: () {
          checks++;
          return true;
        });
        characteristic.reads.single.completeError(StateError('fake read failed'));
        await pumpEventQueue(times: 2);
        expect(_snapshot(identity), initial);
        expect(updates, isEmpty);
        expect(checks, 0);
        expect(characteristic.reads, hasLength(1));

        start(isCurrent: () => true);
        characteristic.reads[1].complete(currentBytes);
        await pumpEventQueue(times: 2);
        expect(_snapshot(identity), current);
        expect(updates, [current]);
      });

      test('missing optional characteristic is a no-op', () async {
        repository.nrfVersionCharacteristic = null;
        repository.odometerCharacteristic = null;
        var checks = 0;
        start(isCurrent: () {
          checks++;
          return true;
        });
        await pumpEventQueue(times: 2);
        expect(characteristic.reads, isEmpty);
        expect(checks, 0);
        expect(_snapshot(identity), initial);
        expect(updates, isEmpty);
      });

      if (nrf) {
        final cases = <(String, List<int>, String, bool)>[
          ('malformed UTF-8', [0xff, 45, 108, 115], '\uFFFD-ls', true),
          ('empty payload', [], '', false),
          ('NUL and whitespace only', [0, 32, 0], '', false),
        ];
        for (final entry in cases) {
          test('${entry.$1} publishes the permissively decoded version', () async {
            start(isCurrent: () => true);
            characteristic.reads.single.complete(entry.$2);
            await pumpEventQueue(times: 2);
            final expected = (entry.$3, entry.$4, 900);
            expect(_snapshot(identity), expected);
            expect(updates, [expected]);
          });
        }
      } else {
        for (var length = 0; length < 4; length++) {
          test('truncated $length-byte payload preserves state without publishing', () async {
            var checks = 0;
            start(isCurrent: () {
              checks++;
              return true;
            });
            characteristic.reads.single.complete(List.filled(length, 0));
            await pumpEventQueue(times: 2);
            expect(_snapshot(identity), initial);
            expect(updates, isEmpty);
            expect(checks, 0);
            expect(characteristic.reads, hasLength(1));
          });
        }
      }
    });
  }
}
