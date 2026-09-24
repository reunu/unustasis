import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

String uuid(String suffix) => '9a59$suffix-6e67-5d0d-aab9-ad9126b66f91';

class _Descriptor extends Fake implements BluetoothDescriptor {
  _Descriptor(this.readValue);
  final List<int> readValue;
  @override
  Guid get descriptorUuid => Guid('00002902-0000-1000-8000-00805f9b34fb');
  @override
  Future<List<int>> read({int timeout = 15}) async => readValue;
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic(String suffix,
      {this.descriptors = const [],
      this.properties = const CharacteristicProperties(notify: true)})
      : characteristicUuid = Guid(uuid(suffix));
  @override
  final Guid characteristicUuid;
  @override
  final List<BluetoothDescriptor> descriptors;
  @override
  final CharacteristicProperties properties;
}

class _Service extends Fake implements BluetoothService {
  _Service(String suffix, List<String> chars)
      : serviceUuid = Guid(uuid(suffix)),
        characteristics = chars.map(_Characteristic.new).toList();
  @override
  final Guid serviceUuid;
  @override
  final List<BluetoothCharacteristic> characteristics;
}

class _ValidationRepository extends CharacteristicRepository {
  _ValidationRepository(super.scooter,
      {BluetoothCharacteristic? command,
      BluetoothCharacteristic? response}) {
    extendedCommandCharacteristic = command;
    extendedResponseCharacteristic = response;
  }
  @override
  bool anyAreNull() => false;
}

class _Device extends Fake implements BluetoothDevice {
  _Device(this.servicesList);
  @override
  final List<BluetoothService> servicesList;
  int discoveries = 0;
  Object? failure;

  @override
  Future<List<BluetoothService>> discoverServices(
      {bool subscribeToServicesChanged = true, int timeout = 15}) async {
    discoveries++;
    if (failure case final error?) throw error;
    return servicesList;
  }
}

void main() {
  test('lookup requires both the service and characteristic IDs', () {
    final service = _Service('0500', ['0501']);
    final device = _Device([service]);
    expect(
        CharacteristicRepository.findCharacteristic(
            device, uuid('0500'), uuid('0501')),
        same(service.characteristics.single));
    expect(
        CharacteristicRepository.findCharacteristic(
            device, uuid('0400'), uuid('0501')),
        isNull);
    expect(
        CharacteristicRepository.findCharacteristic(
            device, uuid('0500'), uuid('0502')),
        isNull);
  });

  test('empty service list is tolerated but mandatory fields are unavailable',
      () async {
    final device = _Device([]);
    final repo = CharacteristicRepository(device);
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(device.discoveries, 1);
    expect(repo.anyAreNull(), isTrue);
    expect(repo.otaAvailable, isFalse);
    expect(repo.alarmAvailable, isFalse);
    expect(repo.odometerCharacteristic, isNull);
  });

  test('optional groups require every member; odometer uses its own service',
      () async {
    final ota = _Service('0500', ['0501', '0502', '0503']);
    final alarm = _Service('0220', ['0221', '0222', '0223']);
    final identity = _Service('a040', ['a042']);
    final device = _Device([ota, alarm, identity]);
    final repo = CharacteristicRepository(device);
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(repo.otaAvailable, isTrue);
    expect(repo.alarmAvailable, isTrue);
    expect(repo.odometerCharacteristic, same(identity.characteristics.single));
    ota.characteristics.removeLast();
    alarm.characteristics.removeLast();
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(device.discoveries, 2);
    expect(repo.otaAvailable, isFalse);
    expect(repo.alarmAvailable, isFalse);
  });

  test('optional discovery is not enabled implicitly', () async {
    final device = _Device([
      _Service('0500', ['0501', '0502', '0503']),
      _Service('0220', ['0221', '0222', '0223']),
    ]);
    final repo = CharacteristicRepository(device);
    await repo.findAll();
    expect(repo.otaAvailable, isFalse);
    expect(repo.alarmAvailable, isFalse);
  });

  test('missing characteristics are recorded by label, in discovery order',
      () async {
    final device = _Device([
      _Service('a040', ['a042']),
    ]);
    final repo = CharacteristicRepository(device);
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(repo.missingCharacteristics, contains('command'));
    expect(repo.missingCharacteristics, contains('extended-command'));
    expect(repo.missingCharacteristics, contains('extended-response'));
    expect(repo.missingCharacteristics, contains('alarm-status'));
    expect(repo.missingCharacteristics, isNot(contains('odometer')));
    expect(repo.extendedChannelMissing, isTrue);
    expect(repo.missingCharacteristics.length, greaterThan(20));
  });

  test('a complete table records nothing missing', () async {
    final device = _Device([
      _Service('0400', ['0401', '0402']),
    ]);
    final repo = CharacteristicRepository(device);
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(repo.extendedChannelMissing, isFalse);
    expect(repo.missingCharacteristics, isNot(contains('extended-command')));
  });

  test('rediscovery clears what an earlier pass recorded as missing', () async {
    final device = _Device([]);
    final repo = CharacteristicRepository(device);
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(repo.missingCharacteristics, isNotEmpty);
    device.servicesList.add(_Service('0400', ['0401', '0402']));
    await repo.findAll(additionalLibrescootFeatures: true);
    expect(repo.missingCharacteristics, isNot(contains('extended-command')));
  });

  test('Android accepts only an exact valid extended-response CCCD', () async {
    for (final value in [const [0x00, 0x00], const [0x01, 0x00]]) {
      final response = _Characteristic('0402', descriptors: [_Descriptor(value)]);
      final repo = _ValidationRepository(_Device([]),
          command: _Characteristic('0401'), response: response);
      expect(await repo.validateGattTable(isAndroid: true), isNull,
          reason: '$value');
    }

    final collidedAlarmValue = <int>[0x01, 0x00, ...List<int>.filled(46, 0)];
    final response = _Characteristic('0402',
        descriptors: [_Descriptor(collidedAlarmValue)]);
    final repo = _ValidationRepository(_Device([]),
        command: _Characteristic('0401'), response: response);
    expect(await repo.validateGattTable(isAndroid: true),
        contains('invalid shape'));
  });

  test('stock absence and iOS do not require the Android CCCD probe', () async {
    expect(
        await _ValidationRepository(_Device([]))
            .validateGattTable(isAndroid: true),
        isNull);
    final response = _Characteristic('0402',
        descriptors: [_Descriptor(List<int>.filled(48, 1))]);
    expect(
        await _ValidationRepository(_Device([]),
                command: _Characteristic('0401'), response: response)
            .validateGattTable(isAndroid: false),
        isNull);
  });

  for (final missingSide in ['command', 'response']) {
    test('a channel missing its $missingSide characteristic is unsafe',
        () async {
      final repo = _ValidationRepository(_Device([]),
          command: missingSide == 'command' ? null : _Characteristic('0401'),
          response: missingSide == 'response' ? null : _Characteristic('0402'));
      expect(await repo.validateGattTable(isAndroid: false),
          contains('characteristics are incomplete'));
    });
  }

  test('an extended response without its CCCD is unsafe on Android', () async {
    final response = _Characteristic('0402');
    expect(
        await _ValidationRepository(_Device([]),
                command: _Characteristic('0401'), response: response)
            .validateGattTable(isAndroid: true),
        contains('has no CCCD'));
  });

  test('CCCD enabled bits must match the characteristic properties', () async {
    final response = _Characteristic('0402',
        descriptors: [_Descriptor(const [0x02, 0x00])],
        properties: const CharacteristicProperties(notify: true));
    expect(
        await _ValidationRepository(_Device([]),
                command: _Characteristic('0401'), response: response)
            .validateGattTable(isAndroid: true),
        contains('invalid shape'));
  });

  test('a silent channel needs several unanswered commands and no response',
      () async {
    final device = _Device([]);
    final repo = CharacteristicRepository(device);
    expect(repo.extendedChannelSilent, isFalse);
    repo.noteSilentExtendedCommand();
    expect(repo.extendedChannelSilent, isFalse,
        reason: 'one timeout can be an unsupported command');
    repo.noteSilentExtendedCommand();
    expect(repo.extendedChannelSilent, isTrue);
    // A single answer proves the channel is heard, whatever else times out.
    repo.noteExtendedResponse();
    expect(repo.extendedChannelSilent, isFalse);
  });

  test('only Android refusal codes count as a stale-table mismatch', () {
    FlutterBluePlusException android(int code) => FlutterBluePlusException(
        ErrorPlatform.android, 'writeCharacteristic', code, 'x');
    expect(isGattTableMismatch(android(3)), isTrue,
        reason: 'GATT_WRITE_NOT_PERMITTED');
    expect(isGattTableMismatch(android(13)), isTrue,
        reason: 'GATT_INVALID_ATTRIBUTE_LENGTH');
    expect(isGattTableMismatch(android(133)), isFalse,
        reason: 'generic GATT_ERROR');
    expect(
        isGattTableMismatch(FlutterBluePlusException(
            ErrorPlatform.fbp, 'writeCharacteristic', 13, 'x')),
        isFalse);
    expect(isGattTableMismatch(StateError('nope')), isFalse);
  });

  test('a stale-table rejection is remembered and logged once', () async {
    final device = _Device([]);
    final repo = CharacteristicRepository(device);
    expect(repo.gattTableMismatch, isFalse);
    repo.noteGattRejection(StateError('unrelated failure'), 'Command write');
    expect(repo.gattTableMismatch, isFalse);
    repo.noteGattRejection(
        FlutterBluePlusException(
            ErrorPlatform.android, 'writeCharacteristic', 13, 'x'),
        'Command write');
    expect(repo.gattTableMismatch, isTrue);
  });

  test('discovery failures propagate to connection owner', () async {
    final error = StateError('disconnected');
    final device = _Device([])..failure = error;
    await expectLater(
        CharacteristicRepository(device).findAll(), throwsA(same(error)));
    expect(device.discoveries, 1);
  });
}
