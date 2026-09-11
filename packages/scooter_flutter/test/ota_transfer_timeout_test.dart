import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
// fake_async is supplied by flutter_test at the pinned SDK version.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'ota_transfer_service_test.dart';

class MemoryBundle extends Fake implements File {
  final raf = MemoryReader();
  @override
  Future<int> length() async => 600;
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(List.filled(600, 42));
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async => raf;
}

class MemoryReader extends Fake implements RandomAccessFile {
  int offset = 0;
  bool closed = false;
  @override
  Future<RandomAccessFile> setPosition(int value) async {
    offset = value;
    return this;
  }

  @override
  Future<Uint8List> read(int count) async =>
      Uint8List.fromList(List.filled(count, 42));
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late OtaHarness h;
  Future<void> pump(FakeAsync clock) async {
    for (var i = 0; i < 12; i++) {
      clock.flushMicrotasks();
      // Stream.cancel may return the SDK's root-zone completed future.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> timed(Future<void> Function(FakeAsync) body) async {
    final clock = FakeAsync();
    clock.run((_) {
      h = OtaHarness()..file = MemoryBundle();
      h.configure();
    });
    await body(clock);
    h.transfer.dispose();
    h.data.values.close();
    h.control.values.close();
    h.status.values.close();
    h.device.states.close();
    await pump(clock);
  }

  test(
      'START retries three times at exactly five seconds and releases timer/subscriptions',
      () async {
    await timed((clock) async {
      h.file = MemoryBundle();
      h.control.onWrite = (_) async {};
      Object? error;
      clock.run((_) => h.run()).catchError((Object e) {
        error = e;
      });
      await pump(clock);
      expect(h.control.writes.length, 1);
      clock.elapse(const Duration(milliseconds: 4999));
      await pump(clock);
      expect(h.control.writes.length, 1);
      clock.elapse(const Duration(milliseconds: 1));
      await pump(clock);
      expect(h.control.writes.length, 2);
      clock.elapse(const Duration(seconds: 5));
      await pump(clock);
      expect(h.control.writes.length, 3);
      clock.elapse(const Duration(seconds: 5));
      await pump(clock);
      expect(error, 'Scooter did not answer the transfer request');
      expect(h.status.values.hasListener, false);
      expect(h.device.states.hasListener, false);
      expect(clock.nonPeriodicTimerCount, 0);
      expect(h.transfer.resumable, true);
    });
  });
  test('ACK timeout go-back-N at >5s and 30 rewind budget retained', () async {
    await timed((clock) async {
      final file = MemoryBundle();
      final transfer =
          OtaTransferService(now: () => DateTime(2026).add(clock.elapsed));
      h.data.onWrite = (_) async {};
      Object? error;
      clock
          .run((_) => transfer.transfer(h.device, h.repo, file,
              bundleId: 'bundle.delta'))
          .catchError((Object e) {
        error = e;
      });
      await pump(clock);
      expect(h.data.writes.map(OtaHarness.offset), [0, 240]);
      clock.elapse(const Duration(seconds: 5));
      await pump(clock);
      expect(h.data.writes.length, 2);
      clock.elapse(const Duration(milliseconds: 20));
      await pump(clock);
      expect(h.data.writes.map(OtaHarness.offset), [0, 240, 0, 240]);
      clock.elapse(const Duration(seconds: 156));
      await pump(clock);
      expect(error, 'Link too unstable (too many retransmissions)');
      expect(file.raf.closed, true);
      expect(h.status.values.hasListener, false);
      expect(clock.nonPeriodicTimerCount, 0);
      transfer.dispose();
    });
  });
  test(
      'COMPLETE waits thirty seconds, fails nonresumable and closes file/subscriptions',
      () async {
    await timed((clock) async {
      final file = MemoryBundle();
      h.file = file;
      final previous = h.control.onWrite!;
      h.control.onWrite = (v) async {
        if (v[0] == 1) await previous(v);
      };
      Object? error;
      clock.run((_) => h.run()).catchError((Object e) {
        error = e;
      });
      await pump(clock);
      expect(h.transfer.state, OtaTransferState.verifying);
      clock.elapse(const Duration(seconds: 29));
      await pump(clock);
      expect(error, null);
      clock.elapse(const Duration(seconds: 1));
      await pump(clock);
      expect(error, isA<TimeoutException>());
      expect(h.transfer.resumable, false);
      expect(file.raf.closed, true);
      expect(h.status.values.hasListener, false);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test('disconnect while parked on ACK exits promptly rather than 30 rewinds',
      () async {
    await timed((clock) async {
      h.file = MemoryBundle();
      h.data.onWrite = (_) async {};
      Object? error;
      clock.run((_) => h.run()).catchError((Object e) {
        error = e;
      });
      await pump(clock);
      h.device.drop();
      clock.elapse(const Duration(milliseconds: 20));
      await pump(clock);
      expect(error.toString(), 'Connection to scooter lost');
      expect(h.transfer.resumable, true);
      expect(h.status.values.hasListener, false);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test(
      'disconnect before COMPLETE_ACK fails instead of claiming accepted install',
      () async {
    await timed((clock) async {
      h.file = MemoryBundle();
      final previous = h.control.onWrite!;
      h.control.onWrite = (v) async {
        if (v[0] == 3) {
          h.device.drop();
        } else {
          await previous(v);
        }
      };
      Object? error;
      clock.run((_) => h.run()).catchError((Object e) {
        error = e;
      });
      await pump(clock);
      expect(error, isNotNull);
      expect(h.transfer.state, OtaTransferState.failure);
      expect(h.transfer.awaitingReconnect, false);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test(
      'write failure with pending response cancels waiter without later unhandled timeout',
      () async {
    await timed((clock) async {
      h.file = MemoryBundle();
      h.control.onWrite = (_) async {
        throw StateError('write failed');
      };
      Object? error;
      clock.run((_) => h.run()).catchError((Object e) {
        error = e;
      });
      await pump(clock);
      expect(error, isA<StateError>());
      expect(h.status.values.hasListener, false);
      clock.elapse(const Duration(seconds: 40));
      await pump(clock);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test('native write may outlive response budget but cannot leak timeout error',
      () async {
    await timed((clock) async {
      h.file = MemoryBundle();
      final gate = Completer<void>();
      var count = 0;
      final previous = h.control.onWrite!;
      h.control.onWrite = (v) async {
        if (++count == 1) {
          await gate.future;
        } else {
          await previous(v);
        }
      };
      var finished = false;
      clock.run((_) => h.run()).then((_) => finished = true);
      await pump(clock);
      clock.elapse(const Duration(seconds: 6));
      await pump(clock);
      expect(finished, false);
      expect(h.control.writes.length, 1);
      gate.complete();
      await pump(clock);
      clock.elapse(const Duration(milliseconds: 10));
      await pump(clock);
      expect(finished, true);
      expect(h.control.writes.length, 3);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test('STATUS query four-second timeout releases its observation', () async {
    await timed((clock) async {
      h.control.onWrite = (_) async {};
      bool? adopted;
      clock
          .run((_) => h.transfer.syncFromScooter(h.device, h.repo))
          .then((v) => adopted = v);
      await pump(clock);
      clock.elapse(const Duration(seconds: 3));
      await pump(clock);
      expect(adopted, null);
      clock.elapse(const Duration(seconds: 1));
      await pump(clock);
      expect(adopted, false);
      expect(h.status.values.hasListener, false);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
}
