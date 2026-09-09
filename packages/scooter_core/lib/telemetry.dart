import 'scooter_core.dart';
import 'scooter_battery.dart';

const String lsKeyScheduledHibernateEnabled = 'pm.scheduled-hibernate-enabled';
const String lsKeyBatteryKeepActiveOnSeatboxOpen =
    'scooter.battery-keep-active-on-seatbox-open';

enum UsbMode {
  normal,
  massStorage,
}

/// Splits `<source>,<RFC3339 timestamp>` into its two halves. The timestamp is
/// null if it doesn't parse, since the source alone is still worth showing.
({String source, DateTime? timestamp})? parseAlarmLastTrigger(String value) {
  final int comma = value.indexOf(',');
  if (comma < 0) {
    return value.isEmpty ? null : (source: value, timestamp: null);
  }
  final String source = value.substring(0, comma);
  if (source.isEmpty) return null;
  return (
    source: source,
    timestamp: DateTime.tryParse(value.substring(comma + 1))
  );
}

class BatterySnapshot {
  const BatterySnapshot(
      {this.primarySOC,
      this.primaryCycles,
      this.secondarySOC,
      this.secondaryCycles,
      this.cbbSOC,
      this.cbbVoltage,
      this.cbbCapacity,
      this.cbbCharging,
      this.auxSOC,
      this.auxVoltage,
      this.auxCharging});
  final int? primarySOC;
  final int? primaryCycles;
  final int? secondarySOC;
  final int? secondaryCycles;
  final int? cbbSOC;
  final int? cbbVoltage;
  final int? cbbCapacity;
  final bool? cbbCharging;
  final int? auxSOC;
  final int? auxVoltage;
  final AUXChargingState? auxCharging;
}

class VehicleSnapshot {
  const VehicleSnapshot(
      {this.seatClosed,
      this.handlebarsLocked,
      this.navigationActive,
      this.usbMode,
      this.vehicleState,
      this.powerState,
      this.alarmStatus,
      this.alarmLastTrigger,
      this.alarmWakeSources});
  final bool? seatClosed;
  final bool? handlebarsLocked;
  final bool? navigationActive;
  final UsbMode? usbMode;
  final ScooterVehicleState? vehicleState;
  final ScooterPowerState? powerState;
  final AlarmStatus? alarmStatus;
  final ({String source, DateTime? timestamp})? alarmLastTrigger;
  final AlarmWakeSources? alarmWakeSources;
}

class FirmwareSnapshot {
  const FirmwareSnapshot(
      {this.nrfVersion,
      this.isLibrescoot,
      this.odometerMeters,
      this.supportsHibernateFor,
      this.supportsScheduledHibernation,
      this.supportsApnConfig,
      this.supportsBondForget,
      this.supportsBatteryKeepActive,
      this.supportsAlarmControl});
  final String? nrfVersion;
  final bool? isLibrescoot;
  final int? odometerMeters;
  final bool? supportsHibernateFor;
  final bool? supportsScheduledHibernation;
  final bool? supportsApnConfig;
  final bool? supportsBondForget;
  final bool? supportsBatteryKeepActive;
  final bool? supportsAlarmControl;
}

class CachedTelemetry {
  const CachedTelemetry(
      {this.primarySOC,
      this.secondarySOC,
      this.cbbSOC,
      this.auxSOC,
      this.handlebarsLocked,
      this.isLibrescoot,
      this.supportsHibernateFor,
      this.supportsApnConfig});
  final int? primarySOC;
  final int? secondarySOC;
  final int? cbbSOC;
  final int? auxSOC;
  final bool? handlebarsLocked;
  final bool? isLibrescoot;
  final bool? supportsHibernateFor;
  final bool? supportsApnConfig;
}

/// A partial cache update: null means leave the saved field unchanged. Wire
/// callbacks only patch known values, including false and zero.
class TelemetryCachePatch {
  const TelemetryCachePatch(
      {this.primarySOC,
      this.secondarySOC,
      this.cbbSOC,
      this.auxSOC,
      this.handlebarsLocked,
      this.isLibrescoot,
      this.supportsHibernateFor,
      this.supportsApnConfig});
  final int? primarySOC;
  final int? secondarySOC;
  final int? cbbSOC;
  final int? auxSOC;
  final bool? handlebarsLocked;
  final bool? isLibrescoot;
  final bool? supportsHibernateFor;
  final bool? supportsApnConfig;
}

/// A copied view; no mutable BLE state or application metadata escapes here.
class TelemetrySnapshot {
  const TelemetrySnapshot(
      {required this.scooterId,
      required this.generation,
      required this.revision,
      required this.battery,
      required this.vehicle,
      required this.firmware,
      required this.state});
  final String? scooterId;
  final int? generation;
  final int revision;
  final BatterySnapshot battery;
  final VehicleSnapshot vehicle;
  final FirmwareSnapshot firmware;
  final ScooterState? state;
}
