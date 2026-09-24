import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

final _cccd = Guid("00002902-0000-1000-8000-00805f9b34fb");

class _Descriptor extends Fake implements BluetoothDescriptor {
  _Descriptor(this.readValue, {this.fails = false});
  final List<int> readValue;
  final bool fails;

  @override
  Guid get descriptorUuid => _cccd;

  @override
  Future<List<int>> read({int timeout = 15}) async {
    if (fails) throw StateError('read refused');
    return readValue;
  }
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic({this.descriptors = const []});

  @override
  final List<BluetoothDescriptor> descriptors;

  @override
  CharacteristicProperties get properties =>
      const CharacteristicProperties(notify: true, indicate: true);

  int notifyWrites = 0;

  @override
  bool get isNotifying => true;

  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    notifyWrites++;
    return true;
  }
}

CharacteristicRepository _repo() =>
    CharacteristicRepository(BluetoothDevice.fromId('A'));

void main() {
  test('a subscription that did not take marks the table stale', () async {
    final repo = _repo();
    await verifyExtendedNotify(
        repo,
        _Characteristic(descriptors: [
          _Descriptor(const [0x00, 0x00])
        ]));
    expect(repo.gattTableMismatch, isTrue);
  });

  test('notify or indicate read back clean', () async {
    for (final value in [
      const [0x01, 0x00],
      const [0x02, 0x00]
    ]) {
      final repo = _repo();
      await verifyExtendedNotify(
          repo, _Characteristic(descriptors: [_Descriptor(value)]));
      expect(repo.gattTableMismatch, isFalse, reason: 'value $value');
    }
  });

  test('a collided long value cannot pass from its 01 00 prefix', () async {
    final repo = _repo();
    await verifyExtendedNotify(
        repo,
        _Characteristic(descriptors: [
          _Descriptor(<int>[0x01, 0x00, ...List<int>.filled(46, 0)])
        ]));
    expect(repo.gattTableMismatch, isTrue);
  });

  test('a refused or impossible read proves nothing', () async {
    final repo = _repo();
    await verifyExtendedNotify(
        repo,
        _Characteristic(descriptors: [
          _Descriptor(const [0x01, 0x00], fails: true)
        ]));
    expect(repo.gattTableMismatch, isFalse);
    await verifyExtendedNotify(repo, _Characteristic());
    expect(repo.gattTableMismatch, isFalse);
  });

  test('the CCCD write happens even when the cache claims it is on', () async {
    final repo = _repo();
    final characteristic = _Characteristic(descriptors: [
      _Descriptor(const [0x01, 0x00])
    ]);
    expect(characteristic.isNotifying, isTrue);
    await ensureExtendedNotify(repo, characteristic);
    expect(characteristic.notifyWrites, 1);
    await ensureExtendedNotify(repo, characteristic);
    expect(characteristic.notifyWrites, 1, reason: 'once per connection');
  });
}
