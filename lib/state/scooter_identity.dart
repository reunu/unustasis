import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

class ScooterIdentity {
  final _log = Logger('ScooterIdentity');

  String? name;
  int? color;
  DateTime? lastPing;
  LatLng? lastLocation;
  String? nrfVersion;
  bool? isLibrescoot;
  int? rssi;
  int? odometerMeters;

  // librescoot capability flags, probed after each connection.
  // null = unknown / not yet probed.
  bool? supportsHibernateFor;
  bool? supportsScheduledHibernation;
  bool? supportsApnConfig;
  bool? supportsBondForget;

  void resetLsCapabilities() {
    supportsHibernateFor = null;
    supportsScheduledHibernation = null;
    supportsApnConfig = null;
    supportsBondForget = null;
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
  }) {
    if (chars.nrfVersionCharacteristic != null) {
      _log.info('Reading nRF version');
      readNrfVersion(chars.nrfVersionCharacteristic!, (version, isLibre) {
        nrfVersion = version;
        isLibrescoot = isLibre;
        onUpdate();
      });
    }
  }
}
