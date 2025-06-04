import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

enum ScooterBatteryType {
  primary,
  secondary,
  aux,
  cbb,
  nfc;
}

extension BatteryExtension on ScooterBatteryType {
  String name(BuildContext context) {
    switch (this) {
      case ScooterBatteryType.primary:
        return FlutterI18n.translate(context, "stats_primary_name");
      case ScooterBatteryType.secondary:
        return FlutterI18n.translate(context, "stats_secondary_name");
      case ScooterBatteryType.cbb:
        return FlutterI18n.translate(context, "stats_cbb_name");
      case ScooterBatteryType.aux:
        return FlutterI18n.translate(context, "stats_aux_name");
      case ScooterBatteryType.nfc:
        return FlutterI18n.translate(context, "stats_nfc_name");
    }
  }

  String description(BuildContext context) {
    switch (this) {
      case ScooterBatteryType.primary:
        return FlutterI18n.translate(context, "stats_primary_desc");
      case ScooterBatteryType.secondary:
        return FlutterI18n.translate(context, "stats_secondary_desc");
      case ScooterBatteryType.cbb:
        return FlutterI18n.translate(context, "stats_cbb_desc");
      case ScooterBatteryType.aux:
        return FlutterI18n.translate(context, "stats_aux_desc");
      case ScooterBatteryType.nfc:
        return FlutterI18n.translate(context, "stats_nfc_desc");
    }
  }

  String socText(int soc, BuildContext context) {
    if (this == ScooterBatteryType.aux) {
      switch (soc ~/ 25) {
        case 0:
          return FlutterI18n.translate(context, "stats_aux_0");
        case 1:
          return FlutterI18n.translate(context, "stats_aux_25");
        case 2:
          return FlutterI18n.translate(context, "stats_aux_50");
        case 3:
          return FlutterI18n.translate(context, "stats_aux_75");
        case 4:
          return FlutterI18n.translate(context, "stats_aux_100");
      }
    }
    return "$soc%";
  }

  String imagePath(int soc) {
    switch (this) {
      case ScooterBatteryType.primary:
      case ScooterBatteryType.secondary:
      case ScooterBatteryType.nfc:
        if (soc > 85) {
          return "images/battery/batt_full.webp";
        } else if (soc > 60) {
          return "images/battery/batt_75.webp";
        } else if (soc > 35) {
          return "images/battery/batt_50.webp";
        } else if (soc > 10) {
          return "images/battery/batt_25.webp";
        } else {
          return "images/battery/batt_empty.webp";
        }
      case ScooterBatteryType.cbb:
        return "images/battery/batt_internal.webp";
      case ScooterBatteryType.aux:
        return 'images/battery/batt_internal.webp';
    }
  }
}

enum AUXChargingState {
  floatCharge,
  absorptionCharge,
  bulkCharge,
  none;
}

extension AUXChargingExtension on AUXChargingState {
  String name(BuildContext context) {
    switch (this) {
      case AUXChargingState.floatCharge:
        return FlutterI18n.translate(context, "stats_aux_charging_float");
      case AUXChargingState.absorptionCharge:
        return FlutterI18n.translate(context, "stats_aux_charging_absorption");
      case AUXChargingState.bulkCharge:
        return FlutterI18n.translate(context, "stats_aux_charging_bulk");
      case AUXChargingState.none:
        return FlutterI18n.translate(context, "stats_aux_charging_none");
    }
  }
}
