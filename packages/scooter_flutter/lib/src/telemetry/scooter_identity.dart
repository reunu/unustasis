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
        supportsTripCounter: supportsTripCounter,
        supportsTripExpunge: supportsTripExpunge,
      );

  final _log = Logger('ScooterIdentity');

  String? nrfVersion;
  bool? isLibrescoot;
  int? odometerMeters;

  /// Software version the system behind the link reports, if it reports one.
  /// Not cached: it belongs to the connection, and a stale value would be worse
  /// than none.
  String? imxVersion;

  // librescoot capability flags, probed after each connection.
  // null = unknown / not yet probed.
  bool? supportsHibernateFor;
  bool? supportsScheduledHibernation;
  bool? supportsApnConfig;
  bool? supportsBondForget;
  bool? supportsBatteryKeepActive;
  bool? supportsAlarmControl;
  bool? supportsTripCounter;
  bool? supportsTripExpunge;

  /// Session-only, like [supportsBondForget]: both answer a question the
  /// firmware reports in `cap:ext` either way, so caching them would go stale
  /// the moment the scooter's other components change.
  bool? supportsServiceMode;
  bool? supportsNavigation;
  int? navigationCapabilityVersion;
  bool? supportsClockSync;
  bool? supportsUsbMode;

  /// True when this connection shows a GATT table that cannot be the scooter's
  /// current one, i.e. the phone's cached table predates its firmware.
  bool? bluetoothTableOutOfDate;

  void resetLsCapabilities() {
    supportsHibernateFor = null;
    supportsScheduledHibernation = null;
    supportsApnConfig = null;
    supportsBondForget = null;
    supportsBatteryKeepActive = null;
    supportsAlarmControl = null;
    supportsTripCounter = null;
    supportsTripExpunge = null;
    supportsServiceMode = null;
    supportsNavigation = null;
    navigationCapabilityVersion = null;
    supportsClockSync = null;
    supportsUsbMode = null;
    bluetoothTableOutOfDate = null;
  }

  bool get supportsRoutePlans =>
      supportsNavigation == true && (navigationCapabilityVersion ?? 0) >= 2;

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

  /// One characteristic read. Failure or an empty value leaves [imxVersion]
  /// null, which the caller reads as "no answer" rather than "stock".
  Future<void> refreshImxVersion(
    CharacteristicRepository chars, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) return;
    imxVersion = null;
    final characteristic = chars.imxVersionCharacteristic;
    if (characteristic == null) return;
    await readAnonImxVersion(characteristic, (version) {
      if (isCurrent?.call() == false) return;
      imxVersion = version;
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
