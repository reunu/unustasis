import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

class CharacteristicRepository {
  final log = Logger("CharacteristicRepository");
  BluetoothDevice scooter;
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
  late BluetoothCharacteristic? cbbFullCapacityCharacteristic;
  late BluetoothCharacteristic? primaryStateCharacteristic;
  late BluetoothCharacteristic? primaryPresentCharacteristic;
  late BluetoothCharacteristic? primaryCyclesCharacteristic;
  late BluetoothCharacteristic? primarySOCCharacteristic;
  late BluetoothCharacteristic? secondaryCyclesCharacteristic;
  late BluetoothCharacteristic? secondarySOCCharacteristic;
  late BluetoothCharacteristic? nrfVersionCharacteristic;

  // librescoot-specific characteristics
  late BluetoothCharacteristic? imxVersionCharacteristic;
  late BluetoothCharacteristic? odometerCharacteristic;
  late BluetoothCharacteristic? systemTimeCharacteristic;
  late BluetoothCharacteristic? navigationActiveCharacteristic;
  late BluetoothCharacteristic? umsStatusCharacteristic;
  late BluetoothCharacteristic? extendedCommandCharacteristic;
  late BluetoothCharacteristic? extendedResponseCharacteristic;

  CharacteristicRepository(this.scooter);

  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {
    log.info("findAll running");
    await scooter.discoverServices();
    commandCharacteristic =
        findCharacteristic(scooter, "9a590000-6e67-5d0d-aab9-ad9126b66f91", "9a590001-6e67-5d0d-aab9-ad9126b66f91");
    hibernationCommandCharacteristic =
        findCharacteristic(scooter, "9a590000-6e67-5d0d-aab9-ad9126b66f91", "9a590002-6e67-5d0d-aab9-ad9126b66f91");
    stateCharacteristic =
        findCharacteristic(scooter, "9a590020-6e67-5d0d-aab9-ad9126b66f91", "9a590021-6e67-5d0d-aab9-ad9126b66f91");
    powerStateCharacteristic =
        findCharacteristic(scooter, "9a5900a0-6e67-5d0d-aab9-ad9126b66f91", "9a5900a1-6e67-5d0d-aab9-ad9126b66f91");
    seatCharacteristic =
        findCharacteristic(scooter, "9a590020-6e67-5d0d-aab9-ad9126b66f91", "9a590022-6e67-5d0d-aab9-ad9126b66f91");
    handlebarCharacteristic =
        findCharacteristic(scooter, "9a590020-6e67-5d0d-aab9-ad9126b66f91", "9a590023-6e67-5d0d-aab9-ad9126b66f91");
    auxSOCCharacteristic =
        findCharacteristic(scooter, "9a590040-6e67-5d0d-aab9-ad9126b66f91", "9a590044-6e67-5d0d-aab9-ad9126b66f91");
    auxVoltageCharacteristic =
        findCharacteristic(scooter, "9a590040-6e67-5d0d-aab9-ad9126b66f91", "9a590041-6e67-5d0d-aab9-ad9126b66f91");
    auxChargingCharacteristic =
        findCharacteristic(scooter, "9a590040-6e67-5d0d-aab9-ad9126b66f91", "9a590043-6e67-5d0d-aab9-ad9126b66f91");
    cbbSOCCharacteristic =
        findCharacteristic(scooter, "9a590060-6e67-5d0d-aab9-ad9126b66f91", "9a590061-6e67-5d0d-aab9-ad9126b66f91");
    cbbVoltageCharacteristic =
        findCharacteristic(scooter, "9a590060-6e67-5d0d-aab9-ad9126b66f91", "9a590065-6e67-5d0d-aab9-ad9126b66f91");
    cbbCapacityCharacteristic =
        findCharacteristic(scooter, "9a590060-6e67-5d0d-aab9-ad9126b66f91", "9a590063-6e67-5d0d-aab9-ad9126b66f91");
    cbbChargingCharacteristic =
        findCharacteristic(scooter, "9a590060-6e67-5d0d-aab9-ad9126b66f91", "9a590072-6e67-5d0d-aab9-ad9126b66f91");
    primaryCyclesCharacteristic =
        findCharacteristic(scooter, "9a5900e0-6e67-5d0d-aab9-ad9126b66f91", "9a5900e6-6e67-5d0d-aab9-ad9126b66f91");
    primarySOCCharacteristic =
        findCharacteristic(scooter, "9a5900e0-6e67-5d0d-aab9-ad9126b66f91", "9a5900e9-6e67-5d0d-aab9-ad9126b66f91");
    secondaryCyclesCharacteristic =
        findCharacteristic(scooter, "9a5900e0-6e67-5d0d-aab9-ad9126b66f91", "9a5900f2-6e67-5d0d-aab9-ad9126b66f91");
    secondarySOCCharacteristic =
        findCharacteristic(scooter, "9a5900e0-6e67-5d0d-aab9-ad9126b66f91", "9a5900f5-6e67-5d0d-aab9-ad9126b66f91");
    nrfVersionCharacteristic =
        findCharacteristic(scooter, "9a59a000-6e67-5d0d-aab9-ad9126b66f91", "9a59a001-6e67-5d0d-aab9-ad9126b66f91");

    if (additionalLibrescootFeatures) {
      imxVersionCharacteristic =
          findCharacteristic(scooter, "9a59a040-6e67-5d0d-aab9-ad9126b66f91", "9a59a041-6e67-5d0d-aab9-ad9126b66f91");
      odometerCharacteristic =
          findCharacteristic(scooter, "9a59a040-6e67-5d0d-aab9-ad9126b66f91", "9a59a042-6e67-5d0d-aab9-ad9126b66f91");
      systemTimeCharacteristic =
          findCharacteristic(scooter, "9a59a040-6e67-5d0d-aab9-ad9126b66f91", "9a59a043-6e67-5d0d-aab9-ad9126b66f91");
      navigationActiveCharacteristic =
          findCharacteristic(scooter, "9a59a040-6e67-5d0d-aab9-ad9126b66f91", "9a59a044-6e67-5d0d-aab9-ad9126b66f91");
      umsStatusCharacteristic =
          findCharacteristic(scooter, "9a59a040-6e67-5d0d-aab9-ad9126b66f91", "9a59a045-6e67-5d0d-aab9-ad9126b66f91");
      extendedCommandCharacteristic =
          findCharacteristic(scooter, "9a590400-6e67-5d0d-aab9-ad9126b66f91", "9a590401-6e67-5d0d-aab9-ad9126b66f91");
      extendedResponseCharacteristic =
          findCharacteristic(scooter, "9a590400-6e67-5d0d-aab9-ad9126b66f91", "9a590402-6e67-5d0d-aab9-ad9126b66f91");
    }
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
