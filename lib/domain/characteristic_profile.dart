import 'scooter_type.dart';

/// Defines the Bluetooth service and characteristic UUIDs for a scooter type
class CharacteristicProfile {
  // Command service
  final String commandService;
  final String commandCharacteristic;
  final String hibernationCommandCharacteristic;

  // State service
  final String stateService;
  final String stateCharacteristic;
  final String seatCharacteristic;
  final String handlebarCharacteristic;

  // Power state service
  final String powerStateService;
  final String powerStateCharacteristic;

  // Aux battery service
  final String auxBatteryService;
  final String auxSOCCharacteristic;
  final String auxVoltageCharacteristic;
  final String auxChargingCharacteristic;

  // CBB (main battery) service
  final String cbbBatteryService;
  final String cbbSOCCharacteristic;
  final String cbbVoltageCharacteristic;
  final String cbbCapacityCharacteristic;
  final String cbbChargingCharacteristic;

  // Removable battery service (optional - not all scooters have removable batteries)
  final String? removableBatteryService;
  final String? primaryCyclesCharacteristic;
  final String? primarySOCCharacteristic;
  final String? secondaryCyclesCharacteristic;
  final String? secondarySOCCharacteristic;

  // NRF version service
  final String nrfVersionService;
  final String nrfVersionCharacteristic;

  const CharacteristicProfile({
    required this.commandService,
    required this.commandCharacteristic,
    required this.hibernationCommandCharacteristic,
    required this.stateService,
    required this.stateCharacteristic,
    required this.seatCharacteristic,
    required this.handlebarCharacteristic,
    required this.powerStateService,
    required this.powerStateCharacteristic,
    required this.auxBatteryService,
    required this.auxSOCCharacteristic,
    required this.auxVoltageCharacteristic,
    required this.auxChargingCharacteristic,
    required this.cbbBatteryService,
    required this.cbbSOCCharacteristic,
    required this.cbbVoltageCharacteristic,
    required this.cbbCapacityCharacteristic,
    required this.cbbChargingCharacteristic,
    this.removableBatteryService,
    this.primaryCyclesCharacteristic,
    this.primarySOCCharacteristic,
    this.secondaryCyclesCharacteristic,
    this.secondarySOCCharacteristic,
    required this.nrfVersionService,
    required this.nrfVersionCharacteristic,
  });
}

/// unu Scooter Pro characteristic profile (shared by Pro, Pro LS, Pro Sunshine)
const unuProProfile = CharacteristicProfile(
  // Command service
  commandService: "9a590000-6e67-5d0d-aab9-ad9126b66f91",
  commandCharacteristic: "9a590001-6e67-5d0d-aab9-ad9126b66f91",
  hibernationCommandCharacteristic: "9a590002-6e67-5d0d-aab9-ad9126b66f91",

  // State service
  stateService: "9a590020-6e67-5d0d-aab9-ad9126b66f91",
  stateCharacteristic: "9a590021-6e67-5d0d-aab9-ad9126b66f91",
  seatCharacteristic: "9a590022-6e67-5d0d-aab9-ad9126b66f91",
  handlebarCharacteristic: "9a590023-6e67-5d0d-aab9-ad9126b66f91",

  // Power state service
  powerStateService: "9a5900a0-6e67-5d0d-aab9-ad9126b66f91",
  powerStateCharacteristic: "9a5900a1-6e67-5d0d-aab9-ad9126b66f91",

  // Aux battery service
  auxBatteryService: "9a590040-6e67-5d0d-aab9-ad9126b66f91",
  auxSOCCharacteristic: "9a590044-6e67-5d0d-aab9-ad9126b66f91",
  auxVoltageCharacteristic: "9a590041-6e67-5d0d-aab9-ad9126b66f91",
  auxChargingCharacteristic: "9a590043-6e67-5d0d-aab9-ad9126b66f91",

  // CBB (main battery) service
  cbbBatteryService: "9a590060-6e67-5d0d-aab9-ad9126b66f91",
  cbbSOCCharacteristic: "9a590061-6e67-5d0d-aab9-ad9126b66f91",
  cbbVoltageCharacteristic: "9a590065-6e67-5d0d-aab9-ad9126b66f91",
  cbbCapacityCharacteristic: "9a590063-6e67-5d0d-aab9-ad9126b66f91",
  cbbChargingCharacteristic: "9a590072-6e67-5d0d-aab9-ad9126b66f91",

  // Removable battery service
  removableBatteryService: "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
  primaryCyclesCharacteristic: "9a5900e6-6e67-5d0d-aab9-ad9126b66f91",
  primarySOCCharacteristic: "9a5900e9-6e67-5d0d-aab9-ad9126b66f91",
  secondaryCyclesCharacteristic: "9a5900f2-6e67-5d0d-aab9-ad9126b66f91",
  secondarySOCCharacteristic: "9a5900f5-6e67-5d0d-aab9-ad9126b66f91",

  // NRF version service
  nrfVersionService: "9a59a000-6e67-5d0d-aab9-ad9126b66f91",
  nrfVersionCharacteristic: "9a59a001-6e67-5d0d-aab9-ad9126b66f91",
);

/// Nova scooter characteristic profile
/// TODO: Replace with actual Nova UUIDs when available
const novaProfile = CharacteristicProfile(
  // Command service - placeholder UUIDs
  commandService: "00000000-0000-0000-0000-000000000000",
  commandCharacteristic: "00000000-0000-0000-0000-000000000001",
  hibernationCommandCharacteristic: "00000000-0000-0000-0000-000000000002",

  // State service
  stateService: "00000000-0000-0000-0000-000000000010",
  stateCharacteristic: "00000000-0000-0000-0000-000000000011",
  seatCharacteristic: "00000000-0000-0000-0000-000000000012",
  handlebarCharacteristic: "00000000-0000-0000-0000-000000000013",

  // Power state service
  powerStateService: "00000000-0000-0000-0000-000000000020",
  powerStateCharacteristic: "00000000-0000-0000-0000-000000000021",

  // Aux battery service
  auxBatteryService: "00000000-0000-0000-0000-000000000030",
  auxSOCCharacteristic: "00000000-0000-0000-0000-000000000031",
  auxVoltageCharacteristic: "00000000-0000-0000-0000-000000000032",
  auxChargingCharacteristic: "00000000-0000-0000-0000-000000000033",

  // CBB (main battery) service
  cbbBatteryService: "00000000-0000-0000-0000-000000000040",
  cbbSOCCharacteristic: "00000000-0000-0000-0000-000000000041",
  cbbVoltageCharacteristic: "00000000-0000-0000-0000-000000000042",
  cbbCapacityCharacteristic: "00000000-0000-0000-0000-000000000043",
  cbbChargingCharacteristic: "00000000-0000-0000-0000-000000000044",

  // Removable battery service - Nova doesn't have removable batteries

  // NRF version service
  nrfVersionService: "00000000-0000-0000-0000-000000000060",
  nrfVersionCharacteristic: "00000000-0000-0000-0000-000000000061",
);

extension CharacteristicProfileExtension on ScooterType {
  CharacteristicProfile get characteristicProfile {
    switch (this) {
      case ScooterType.unuPro:
      case ScooterType.unuProLS:
      case ScooterType.unuProSunshine:
        return unuProProfile;
      case ScooterType.nova:
        return novaProfile;
    }
  }
}
