import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

class CharacteristicRepository {
  final log = Logger("CharacteristicRepository");
  BluetoothDevice scooter;
  BluetoothCharacteristic? commandCharacteristic;
  BluetoothCharacteristic? hibernationCommandCharacteristic;
  BluetoothCharacteristic? stateCharacteristic;
  BluetoothCharacteristic? powerStateCharacteristic;
  BluetoothCharacteristic? seatCharacteristic;
  BluetoothCharacteristic? handlebarCharacteristic;
  BluetoothCharacteristic? auxSOCCharacteristic;
  BluetoothCharacteristic? cbbSOCCharacteristic;
  BluetoothCharacteristic? cbbChargingCharacteristic;
  BluetoothCharacteristic? primaryCyclesCharacteristic;
  BluetoothCharacteristic? primarySOCCharacteristic;
  BluetoothCharacteristic? secondaryCyclesCharacteristic;
  BluetoothCharacteristic? secondarySOCCharacteristic;

  CharacteristicRepository(this.scooter);

  findAll() async {
    await scooter.discoverServices();
    commandCharacteristic = _findCharacteristic(
        scooter,
        "9a590000-6e67-5d0d-aab9-ad9126b66f91",
        "9a590001-6e67-5d0d-aab9-ad9126b66f91");
    hibernationCommandCharacteristic = _findCharacteristic(
        scooter,
        "9a590000-6e67-5d0d-aab9-ad9126b66f91",
        "9a590002-6e67-5d0d-aab9-ad9126b66f91");
    stateCharacteristic = _findCharacteristic(
        scooter,
        "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590021-6e67-5d0d-aab9-ad9126b66f91");
    powerStateCharacteristic = _findCharacteristic(
        scooter,
        "9a5900a0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900a1-6e67-5d0d-aab9-ad9126b66f91");
    seatCharacteristic = _findCharacteristic(
        scooter,
        "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590022-6e67-5d0d-aab9-ad9126b66f91");
    handlebarCharacteristic = _findCharacteristic(
        scooter,
        "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590023-6e67-5d0d-aab9-ad9126b66f91");
    auxSOCCharacteristic = _findCharacteristic(
        scooter,
        "9a590040-6e67-5d0d-aab9-ad9126b66f91",
        "9a590044-6e67-5d0d-aab9-ad9126b66f91");
    cbbSOCCharacteristic = _findCharacteristic(
        scooter,
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590061-6e67-5d0d-aab9-ad9126b66f91");
    cbbChargingCharacteristic = _findCharacteristic(
        scooter,
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590072-6e67-5d0d-aab9-ad9126b66f91");
    primaryCyclesCharacteristic = _findCharacteristic(
        scooter,
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900e6-6e67-5d0d-aab9-ad9126b66f91");
    primarySOCCharacteristic = _findCharacteristic(
        scooter,
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900e9-6e67-5d0d-aab9-ad9126b66f91");
    secondaryCyclesCharacteristic = _findCharacteristic(
        scooter,
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900f2-6e67-5d0d-aab9-ad9126b66f91");
    secondarySOCCharacteristic = _findCharacteristic(
        scooter,
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900f5-6e67-5d0d-aab9-ad9126b66f91");
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

  BluetoothCharacteristic? _findCharacteristic(
      BluetoothDevice device, String serviceUuid, String characteristicUuid) {
    log.info(
        "Finding characteristic $characteristicUuid in service $serviceUuid...");
    try {
      return device.servicesList
          .firstWhere(
              (service) => service.serviceUuid.toString() == serviceUuid)
          .characteristics
          .firstWhere((char) =>
              char.characteristicUuid.toString() == characteristicUuid);
    } catch (e) {
      log.severe("Characteristic $characteristicUuid not found!");
      return null;
    }
  }
}
