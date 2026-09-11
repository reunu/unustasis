import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

class OtaDevice extends Fake implements BluetoothDevice {
  bool live = true;
  int negotiatedMtu = 247;
  int priorityRequests = 0;
  bool failPriority = false;
  @override
  Future<void> requestConnectionPriority(
      {required ConnectionPriority connectionPriorityRequest}) async {
    expect(connectionPriorityRequest, ConnectionPriority.high);
    priorityRequests++;
    if (failPriority) throw StateError('priority unavailable');
  }

  final states =
      StreamController<BluetoothConnectionState>.broadcast(sync: true);
  @override
  bool get isConnected => live;
  @override
  bool get isDisconnected => !live;
  @override
  int get mtuNow => negotiatedMtu;
  @override
  Stream<BluetoothConnectionState> get connectionState => states.stream;
  void drop() {
    live = false;
    states.add(BluetoothConnectionState.disconnected);
  }
}

class OtaCharacteristic extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  final writes = <List<int>>[];
  final flags = <(bool, bool)>[];
  final notifications = <bool>[];
  Future<void> Function(List<int>)? onWrite;
  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<bool> setNotifyValue(bool value,
      {int timeout = 15, bool forceIndications = false}) async {
    notifications.add(value);
    return true;
  }

  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    writes.add(List.of(value));
    flags.add((withoutResponse, allowLongWrite));
    await onWrite?.call(value);
  }
}

class OtaHarness {
  final device = OtaDevice();
  final data = OtaCharacteristic(),
      control = OtaCharacteristic(),
      status = OtaCharacteristic();
  final transfer = OtaTransferService();
  late final CharacteristicRepository repo = CharacteristicRepository(device)
    ..otaDataCharacteristic = data
    ..otaControlCharacteristic = control
    ..otaStatusCharacteristic = status;
  late Directory dir;
  late File file;
  int resume = 0,
      maxChunk = 240,
      window = 2,
      startStatus = 1,
      completeStatus = 0,
      phase = 4;
  bool immediateInstall = false;
  final phases = <OtaTransferState>[];
  Future<void> init({int size = 600}) async {
    dir = await Directory.systemTemp.createTemp('ota-test');
    file = await File('${dir.path}/bundle.delta')
        .writeAsBytes(List.generate(size, (i) => i % 256));
    configure();
  }

  void configure() {
    transfer.addListener(() => phases.add(transfer.state));
    control.onWrite = (v) async {
      if (v[0] == 1) {
        final ack = ByteData(11)
          ..setUint8(0, 0x81)
          ..setUint8(1, startStatus)
          ..setUint32(2, resume, Endian.little)
          ..setUint16(6, window, Endian.little)
          ..setUint8(8, 1)
          ..setUint16(9, maxChunk, Endian.little);
        status.values.add(ack.buffer.asUint8List());
      } else if (v[0] == 3) {
        status.values.add([0x83, completeStatus]);
        if (completeStatus != 0) return;
        if (immediateInstall) {
          status.values.add([0x84, phase, 100, 0]);
        } else {
          Timer(const Duration(milliseconds: 10),
              () => status.values.add([0x84, phase, 100, 0]));
        }
      }
    };
    data.onWrite = (v) async {
      ack(offset(v) + v.length - 4);
    };
  }

  static int offset(List<int> v) =>
      ByteData.sublistView(Uint8List.fromList(v)).getUint32(0, Endian.little);
  void ack(int value, {bool rewind = false}) {
    final b = ByteData(6)
      ..setUint8(0, 0x82)
      ..setUint8(1, rewind ? 1 : 0)
      ..setUint32(2, value, Endian.little);
    status.values.add(b.buffer.asUint8List());
  }

  Future<void> run() =>
      transfer.transfer(device, repo, file, bundleId: 'bundle.delta');
  Future<void> close() async {
    transfer.dispose();
    await data.values.close();
    await control.values.close();
    await status.values.close();
    await device.states.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  late OtaHarness h;
  setUp(() async {
    h = OtaHarness();
    await h.init();
  });
  tearDown(() async {
    await h.close();
  });
  test('real file hash, START bytes, DATA flags, completion and cleanup',
      () async {
    await h.run();
    expect(h.control.writes.first.sublist(9, 41),
        sha256.convert(await h.file.readAsBytes()).bytes);
    expect(h.control.writes.first.sublist(42), 'bundle.delta'.codeUnits);
    expect(h.control.flags.first, (false, true));
    expect(h.data.flags.every((f) => f == (true, false)), true);
    expect(h.data.writes.map(OtaHarness.offset), [0, 240, 480]);
    expect(h.transfer.state, OtaTransferState.success);
    expect(h.transfer.progress, 1);
    expect(h.transfer.ackedBytes, 600);
    expect(h.status.notifications, [true, false]);
    expect(h.status.values.hasListener, false);
    expect(h.device.states.hasListener, false);
    expect(
        h.phases,
        containsAllInOrder([
          OtaTransferState.hashing,
          OtaTransferState.handshaking,
          OtaTransferState.transferring,
          OtaTransferState.verifying,
          OtaTransferState.installing,
          OtaTransferState.success
        ]));
  });
  for (final resume in [1, 240, 599, 600]) {
    test('resume offset $resume', () async {
      h.resume = resume;
      h.startStatus = 0;
      await h.run();
      expect(
          h.data.writes.isEmpty ? 600 : OtaHarness.offset(h.data.writes.first),
          resume);
      expect(h.transfer.ackedBytes, 600);
    });
  }
  for (final mtu in [23, 100, 247, 512]) {
    test('negotiated MTU $mtu caps DATA payload', () async {
      h.device.negotiatedMtu = mtu;
      await h.run();
      expect(h.data.writes.every((v) => v.length <= mtu - 3 && v.length <= 244),
          true);
    });
  }
  test('scooter max chunk and zero window floor', () async {
    h.maxChunk = 11;
    h.window = 0;
    await h.run();
    expect(h.data.writes.first.length, 15);
  });
  test('too small MTU fails with cleanup', () async {
    h.device.negotiatedMtu = 7;
    await expectLater(h.run(), throwsA(contains('too small')));
    expect(h.transfer.state, OtaTransferState.failure);
    expect(h.transfer.resumable, true);
    expect(h.status.notifications, [true, false]);
  });
  for (final code in [0x10, 0x11, 0x12, 0x13, 0x14]) {
    test('START rejection $code', () async {
      h.startStatus = code;
      await expectLater(h.run(), throwsA(isA<String>()));
      expect(h.data.writes, isEmpty);
      expect(h.status.values.hasListener, false);
    });
  }
  for (final code in [1, 2, 3]) {
    test('COMPLETE rejection $code not resumable', () async {
      h.completeStatus = code;
      await expectLater(h.run(), throwsA(isA<String>()));
      expect(h.transfer.resumable, false);
      expect(h.transfer.state, OtaTransferState.failure);
    });
  }
  test('pending reboot is settled and reset clears active step and progress',
      () async {
    h.phase = 2;
    await h.run();
    expect(h.transfer.busy, true);
    expect(h.transfer.active, false);
    h.transfer.reset();
    expect(h.transfer.state, OtaTransferState.idle);
    expect(h.transfer.progress, 0);
  });
  test('installation failure preserves detail and disables resume', () async {
    h.phase = 5;
    await expectLater(h.run(), throwsA(contains('Installation failed')));
    expect(h.transfer.resumable, false);
    expect(h.transfer.statusMessage, 'Installation failed');
  });
  test('abort stops DATA without emitting wire ABORT (resume cache retained)',
      () async {
    h.data.onWrite = (_) async {
      h.transfer.abort();
    };
    await expectLater(h.run(), throwsA('Transfer cancelled'));
    expect(h.data.writes.length, 1);
    expect(h.control.writes.length, 1);
    expect(h.transfer.resumable, true);
    expect(await h.file.exists(), true);
  });
  test('reset cannot clear active transfer', () async {
    h.data.onWrite = (v) async {
      h.transfer.reset();
      expect(h.transfer.state, OtaTransferState.transferring);
      h.ack(OtaHarness.offset(v) + v.length - 4);
    };
    await h.run();
  });
  test('tunnel ERROR is diagnostic, cumulative ACK continues', () async {
    h.data.onWrite = (v) async {
      h.status.values.add([0x86, 2, 0]);
      h.ack(OtaHarness.offset(v) + v.length - 4);
    };
    await h.run();
    expect(h.transfer.state, OtaTransferState.success);
  });
  test('rewind retransmits from requested offset', () async {
    h.data.onWrite = (v) async {
      if (h.data.writes.length == 2) {
        h.ack(0, rewind: true);
      } else {
        h.ack(OtaHarness.offset(v) + v.length - 4);
      }
    };
    await h.run();
    // Existing send loop increments its position after an inline ACK.
    expect(h.data.writes.map(OtaHarness.offset), [0, 240, 240, 480]);
  });
  test('immediate install terminal notification is not lost', () async {
    h.immediateInstall = true;
    var finished = false;
    final run = h.run().then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final observed = finished;
    // Release the inherited lost-notification hang before asserting.
    if (!finished) h.status.values.add([0x84, 4, 100, 0]);
    await run;
    expect(observed, true);
  });
  test('missing bundle publishes failure instead of remaining idle', () async {
    await h.file.delete();
    await expectLater(h.run(), throwsA(isA<FileSystemException>()));
    expect(h.transfer.state, OtaTransferState.failure);
  });
  test('disconnect after accepted COMPLETE retains installation state',
      () async {
    h.control.onWrite = (v) async {
      if (v[0] == 1) {
        h.status.values.add([0x81, 1, 0, 0, 0, 0, 2, 0, 1, 240, 0]);
      }
      if (v[0] == 3) {
        h.status.values.add([0x83, 0]);
        Timer(const Duration(milliseconds: 10), h.device.drop);
      }
    };
    try {
      await h.run();
    } catch (_) {}
    expect(h.transfer.state, OtaTransferState.installing);
    expect(h.status.values.hasListener, false);
  });
  for (final fail in [false, true]) {
    test('Android priority requested, failure=$fail is best effort', () async {
      h.device.failPriority = fail;
      final service = OtaTransferService(isAndroid: true);
      await service.transfer(h.device, h.repo, h.file,
          bundleId: 'bundle.delta');
      expect(h.device.priorityRequests, 1);
      expect(service.state, OtaTransferState.success);
      service.dispose();
    });
  }
  for (final phase in [0, 1, 2, 3, 4, 5, 6]) {
    test('STATUS phase $phase adoption and cleanup', () async {
      h.control.onWrite = (_) async {
        h.status.values.add([0x84, phase, 42, 0]);
      };
      final adopted = await h.transfer.syncFromScooter(h.device, h.repo);
      expect(adopted, phase < 4);
      if (phase == 2) expect(h.transfer.state, OtaTransferState.pendingReboot);
      if (phase == 0 || phase == 1 || phase == 3) {
        expect(h.status.values.hasListener, true);
        h.status.values.add([0x84, 4, 100, 0]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(h.transfer.state, OtaTransferState.success);
      }
      expect(h.status.values.hasListener, false);
      expect(h.device.states.hasListener, false);
      expect(h.status.notifications, [true, false]);
    });
  }
  test(
      'adopted installation disconnect retains unconfirmed state and releases resources',
      () async {
    h.control.onWrite = (_) async {
      h.status.values.add([0x84, 1, 42, 0]);
    };
    expect(await h.transfer.syncFromScooter(h.device, h.repo), true);
    h.device.drop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.transfer.awaitingReconnect, true);
    expect(h.transfer.state, OtaTransferState.installing);
    expect(h.status.values.hasListener, false);
    expect(h.device.states.hasListener, false);
    h.transfer.reset();
    expect(h.transfer.state, OtaTransferState.installing);
  });
  test('install verifying/progress then pending reboot preserves percent',
      () async {
    h.control.onWrite = (v) async {
      if (v[0] == 1) {
        h.status.values.add([0x81, 1, 0, 0, 0, 0, 2, 0, 1, 240, 0]);
      }
      if (v[0] == 3) {
        h.status.values.add([0x83, 0]);
        for (final m in [
          [0x84, 0, 0, 0],
          [0x84, 1, 67, 0],
          [0x84, 2, 100, 0]
        ]) {
          h.status.values.add(m);
        }
      }
    };
    await h.run();
    expect(h.transfer.state, OtaTransferState.pendingReboot);
    expect(h.transfer.installPercent, 67);
    expect(
        h.phases,
        containsAllInOrder([
          OtaTransferState.installing,
          OtaTransferState.verifying,
          OtaTransferState.installing,
          OtaTransferState.pendingReboot
        ]));
  });
  test('immediate install failure detail survives buffered COMPLETE transition',
      () async {
    h.immediateInstall = true;
    h.phase = 5;
    await expectLater(h.run(), throwsA(contains('Installation failed')));
    expect(h.transfer.state, OtaTransferState.failure);
    expect(h.status.values.hasListener, false);
  });
  test(
      'accepted install dispose releases resources without late notifier errors',
      () async {
    final service = OtaTransferService();
    var notifications = 0;
    service.addListener(() {
      notifications++;
      if (service.state == OtaTransferState.installing) {
        scheduleMicrotask(service.dispose);
      }
    });
    await service.transfer(h.device, h.repo, h.file, bundleId: 'bundle.delta');
    final count = notifications;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications, count);
    expect(h.status.values.hasListener, false);
    expect(h.device.states.hasListener, false);
  });
  test('freshness loss after hashing/notify never writes START', () async {
    var current = true;
    h.transfer.addListener(() {
      if (h.transfer.state == OtaTransferState.hashing) current = false;
    });
    await expectLater(
        h.transfer.transfer(h.device, h.repo, h.file,
            bundleId: 'bundle.delta', isCurrent: () => current),
        throwsA('Update session replaced'));
    expect(h.control.writes, isEmpty);
    expect(h.status.values.hasListener, false);
  });
}
