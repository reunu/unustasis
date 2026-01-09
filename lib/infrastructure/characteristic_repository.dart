import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../domain/characteristic_profile.dart';
import '../domain/scooter_type.dart';

class CharacteristicRepository {
  final log = Logger("CharacteristicRepository");
  BluetoothDevice scooter;
  ScooterType type;
  late BluetoothCharacteristic? commandCharacteristic;
  late BluetoothCharacteristic? hibernationCommandCharacteristic;
  late BluetoothCharacteristic? stateCharacteristic;
  late BluetoothCharacteristic? powerStateCharacteristic;
  late BluetoothCharacteristic? seatCharacteristic;
  late BluetoothCharacteristic? handlebarCharacteristic;
  late BluetoothCharacteristic? auxSOCCharacteristic;
  late BluetoothCharacteristic? auxVoltageCharacteristic;
  late BluetoothCharacteristic? auxChargingCharacteristic;
  late BluetoothCharacteristic? cbbSOCCharacteristic;
  late BluetoothCharacteristic? cbbVoltageCharacteristic;
  late BluetoothCharacteristic? cbbCapacityCharacteristic;
  late BluetoothCharacteristic? cbbChargingCharacteristic;
  late BluetoothCharacteristic? primaryCyclesCharacteristic;
  late BluetoothCharacteristic? primarySOCCharacteristic;
  late BluetoothCharacteristic? secondaryCyclesCharacteristic;
  late BluetoothCharacteristic? secondarySOCCharacteristic;
  late BluetoothCharacteristic? nrfVersionCharacteristic;

  CharacteristicRepository(this.scooter, this.type);

  Future<void> findAll() async {
    log.info("findAll running for scooter type: ${type.name}");
    final profile = type.characteristicProfile;

    await scooter.discoverServices();
    commandCharacteristic = findCharacteristic(scooter, profile.commandService, profile.commandCharacteristic);
    hibernationCommandCharacteristic =
        findCharacteristic(scooter, profile.commandService, profile.hibernationCommandCharacteristic);
    stateCharacteristic = findCharacteristic(scooter, profile.stateService, profile.stateCharacteristic);
    log.info("State characteristic initialized! It's $stateCharacteristic");
    powerStateCharacteristic = findCharacteristic(scooter, profile.powerStateService, profile.powerStateCharacteristic);
    seatCharacteristic = findCharacteristic(scooter, profile.stateService, profile.seatCharacteristic);
    handlebarCharacteristic = findCharacteristic(scooter, profile.stateService, profile.handlebarCharacteristic);
    auxSOCCharacteristic = findCharacteristic(scooter, profile.auxBatteryService, profile.auxSOCCharacteristic);
    auxVoltageCharacteristic = findCharacteristic(scooter, profile.auxBatteryService, profile.auxVoltageCharacteristic);
    auxChargingCharacteristic =
        findCharacteristic(scooter, profile.auxBatteryService, profile.auxChargingCharacteristic);
    cbbSOCCharacteristic = findCharacteristic(scooter, profile.cbbBatteryService, profile.cbbSOCCharacteristic);
    cbbVoltageCharacteristic = findCharacteristic(scooter, profile.cbbBatteryService, profile.cbbVoltageCharacteristic);
    cbbCapacityCharacteristic =
        findCharacteristic(scooter, profile.cbbBatteryService, profile.cbbCapacityCharacteristic);
    cbbChargingCharacteristic =
        findCharacteristic(scooter, profile.cbbBatteryService, profile.cbbChargingCharacteristic);
    if (profile.removableBatteryService != null) {
      primaryCyclesCharacteristic =
          findCharacteristic(scooter, profile.removableBatteryService!, profile.primaryCyclesCharacteristic!);
      primarySOCCharacteristic =
          findCharacteristic(scooter, profile.removableBatteryService!, profile.primarySOCCharacteristic!);
      secondaryCyclesCharacteristic =
          findCharacteristic(scooter, profile.removableBatteryService!, profile.secondaryCyclesCharacteristic!);
      secondarySOCCharacteristic =
          findCharacteristic(scooter, profile.removableBatteryService!, profile.secondarySOCCharacteristic!);
    }
    nrfVersionCharacteristic = findCharacteristic(scooter, profile.nrfVersionService, profile.nrfVersionCharacteristic);
    return;
  }

  bool anyAreNull() {
    return stateCharacteristic == null ||
        powerStateCharacteristic == null ||
        seatCharacteristic == null ||
        handlebarCharacteristic == null ||
        auxSOCCharacteristic == null ||
        cbbSOCCharacteristic == null ||
        cbbChargingCharacteristic == null ||
        primaryCyclesCharacteristic == null ||
        primarySOCCharacteristic == null ||
        secondaryCyclesCharacteristic == null ||
        secondarySOCCharacteristic == null;
  }

  static BluetoothCharacteristic? findCharacteristic(
      BluetoothDevice device, String serviceUuid, String characteristicUuid) {
    try {
      return device.servicesList
          .firstWhere((service) => service.serviceUuid.toString() == serviceUuid)
          .characteristics
          .firstWhere((char) => char.characteristicUuid.toString() == characteristicUuid);
    } catch (e) {
      Logger("findCharacteristic").severe("Characteristic $characteristicUuid not found!");
      return null;
    }
  }
}
