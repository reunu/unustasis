enum ScooterType { unuPro, unuProLS, unuProSunshine, nova }

enum ScooterCapability {
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
  String get assetPrefix {
    switch (this) {
      case ScooterType.unuPro || ScooterType.unuProLS || ScooterType.unuProSunshine:
        return "unu_pro";
      case ScooterType.nova:
        return "nova";
    }
  }

  List<ScooterCapability> capabilities() {
    switch (this) {
      case ScooterType.unuPro:
        return [
          ScooterCapability.hazards,
          ScooterCapability.hibernate,
          ScooterCapability.batteryLevel,
        ];
      case ScooterType.unuProLS:
        return [
          ScooterCapability.hazards,
          ScooterCapability.hibernate,
          ScooterCapability.batteryLevel,
          ScooterCapability.firmwareUpdate,
          ScooterCapability.remoteLocate,
          ScooterCapability.btNavigate,
        ];
      case ScooterType.unuProSunshine:
        return [
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

  /// Returns a human-readable display name for the scooter type
  String get displayName {
    switch (this) {
      case ScooterType.unuPro:
        return "unu Scooter Pro";
      case ScooterType.unuProLS:
        return "unu Scooter Pro (librescoot)";
      case ScooterType.unuProSunshine:
        return "unu Scooter Pro (sunshine)";
      case ScooterType.nova:
        return "emco Nova";
    }
  }

  /// Returns the default name for a new scooter of this type
  String get defaultName {
    switch (this) {
      case ScooterType.unuPro:
        return "Scooter Pro";
      case ScooterType.unuProLS:
        return "Scooter Pro";
      case ScooterType.unuProSunshine:
        return "Scooter Pro";
      case ScooterType.nova:
        return "Nova";
    }
  }

  /// Returns whether this scooter type supports removable batteries
  bool get hasRemovableBatteries {
    switch (this) {
      case ScooterType.unuPro:
      case ScooterType.unuProLS:
      case ScooterType.unuProSunshine:
        return true;
      case ScooterType.nova:
        return false;
    }
  }

  /// Returns the maximum number of colors available for this scooter type
  int get maxColors {
    switch (this) {
      case ScooterType.unuPro:
      case ScooterType.unuProLS:
      case ScooterType.unuProSunshine:
        return 9;
      case ScooterType.nova:
        return 5;
    }
  }
}
