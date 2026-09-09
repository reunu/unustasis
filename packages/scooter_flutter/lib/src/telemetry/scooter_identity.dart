import 'package:flutter/foundation.dart';
import 'package:scooter_core/telemetry.dart';
import 'package:logging/logging.dart';

import '../ble/characteristic_repository.dart';
import '../ble/scooter_reader.dart';

class FirmwareIdentity {
  FirmwareSnapshot get snapshot => FirmwareSnapshot(
        nrfVersion: nrfVersion,
        isLibrescoot: isLibrescoot,
        odometerMeters: odometerMeters,
        supportsHibernateFor: supportsHibernateFor,
        supportsScheduledHibernation: supportsScheduledHibernation,
        supportsApnConfig: supportsApnConfig,
        supportsBondForget: supportsBondForget,
        supportsBatteryKeepActive: supportsBatteryKeepActive,
        supportsAlarmControl: supportsAlarmControl,
      );

  final _log = Logger('ScooterIdentity');

  String? nrfVersion;
  bool? isLibrescoot;
  int? odometerMeters;

  // librescoot capability flags, probed after each connection.
  // null = unknown / not yet probed.
  bool? supportsHibernateFor;
  bool? supportsScheduledHibernation;
  bool? supportsApnConfig;
  bool? supportsBondForget;
  bool? supportsBatteryKeepActive;
  bool? supportsAlarmControl;

  void resetLsCapabilities() {
    supportsHibernateFor = null;
    supportsScheduledHibernation = null;
    supportsApnConfig = null;
    supportsBondForget = null;
    supportsBatteryKeepActive = null;
    supportsAlarmControl = null;
  }

  void wireOdometer(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
    bool Function()? isCurrent,
  }) {
    refreshOdometer(chars, onUpdate: onUpdate, isCurrent: isCurrent);
  }

  void refreshOdometer(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
    bool Function()? isCurrent,
  }) {
    final characteristic = chars.odometerCharacteristic;
    if (characteristic == null) return;

    _log.info('Reading odometer');
    readOdometer(characteristic, (meters) {
      // A read that starts on one connection can finish after a reconnect;
      // without the guard it would publish stale metres onto the new scooter.
      if (isCurrent?.call() == false) return;
      odometerMeters = meters;
      onUpdate();
    });
  }

  void wireNrfVersion(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
    bool Function()? isCurrent,
  }) {
    if (chars.nrfVersionCharacteristic != null) {
      _log.info('Reading nRF version');
      readNrfVersion(chars.nrfVersionCharacteristic!, (version, isLibre) {
        if (isCurrent?.call() == false) return;
        nrfVersion = version;
        isLibrescoot = isLibre;
        onUpdate();
      });
    }
  }
}
