import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

// Models a callback already handed to a platform dispatch queue before cancel.
class LateStream extends Stream<List<int>> {
  final callbacks = <void Function(List<int>)>[];
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    callbacks.add(onData!);
    return const Stream<List<int>>.empty().listen(null);
  }

  void deliver(List<int> bytes) {
    for (final callback in List.of(callbacks)) {
      callback(bytes);
    }
  }
}

class Characteristic extends Fake implements BluetoothCharacteristic {
  final values = LateStream();
  @override
  Stream<List<int>> get lastValueStream => values;
  @override
  Stream<List<int>> get onValueReceived => values;
  @override
  Future<bool> setNotifyValue(bool notify,
          {int timeout = 15, bool forceIndications = false}) async =>
      true;
  @override
  Future<List<int>> read({int timeout = 15}) async => [];
}

void main() {
  test('cancelled battery and vehicle callbacks cannot mutate live values', () {
    final c = Characteristic();
    final repo = CharacteristicRepository(BluetoothDevice.fromId('A'))
      ..primarySOCCharacteristic = c
      ..primaryCyclesCharacteristic = c
      ..secondarySOCCharacteristic = c
      ..secondaryCyclesCharacteristic = c
      ..cbbSOCCharacteristic = c
      ..cbbChargingCharacteristic = c
      ..cbbVoltageCharacteristic = c
      ..cbbCapacityCharacteristic = c
      ..auxSOCCharacteristic = c
      ..auxChargingCharacteristic = c
      ..auxVoltageCharacteristic = c
      ..stateCharacteristic = c
      ..powerStateCharacteristic = null
      ..seatCharacteristic = c
      ..handlebarCharacteristic = c
      ..umsStatusCharacteristic = null
      ..navigationActiveCharacteristic = null;
    final battery = BatteryState();
    final vehicle = VehicleStatus();
    battery.wireSubscriptions(repo, onUpdate: () {});
    vehicle.wireSubscriptions(repo,
        onStateUpdate: () {},
        onSeatUpdate: () {},
        onNavigationChanged: () {},
        onUsbModeChanged: () {},
        onHandlebarsChanged: (_) {},
        onAlarmChanged: () {});
    battery.cancelSubscriptions();
    vehicle.cancelSubscriptions();
    c.values.deliver([42, 0, 0, 0]);
    expect(battery.primarySOC, isNull);
    expect(vehicle.seatClosed, isNull);
  });
}
