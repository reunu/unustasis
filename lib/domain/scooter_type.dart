enum ScooterType { unuPro, unuProLS, unuProSunshine, nova }

enum ScooterCapability {
  lock,
  hazards,
  hibernate,
  remoteLocate,
  drivemodes,
  theftAlarm,
  theftAlert,
  honk,
  batteryLevel,
  remoteNavigate,
  btNavigate,
  firmwareUpdate,
  customColor,
}

extension ScooterCapabilityExtension on ScooterType {
  List<ScooterCapability> capabilities() {
    switch (this) {
      case ScooterType.unuPro:
        return [
          ScooterCapability.lock,
          ScooterCapability.hazards,
          ScooterCapability.hibernate,
          ScooterCapability.batteryLevel,
        ];
      case ScooterType.unuProLS:
        return [
          ScooterCapability.lock,
          ScooterCapability.hazards,
          ScooterCapability.hibernate,
          ScooterCapability.batteryLevel,
          ScooterCapability.firmwareUpdate,
          ScooterCapability.remoteLocate,
          ScooterCapability.btNavigate,
        ];
      case ScooterType.unuProSunshine:
        return [
          ScooterCapability.lock,
          ScooterCapability.hazards,
          ScooterCapability.hibernate,
          ScooterCapability.batteryLevel,
          ScooterCapability.firmwareUpdate,
          ScooterCapability.remoteLocate,
          ScooterCapability.btNavigate,
          ScooterCapability.remoteLocate,
          ScooterCapability.customColor,
        ];
      case ScooterType.nova:
        return [];
    }
  }

  bool has(ScooterCapability capability) {
    return capabilities().contains(capability);
  }
}
