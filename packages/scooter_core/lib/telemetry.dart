import 'scooter_core.dart';
import 'scooter_battery.dart';

const String lsKeyScheduledHibernateEnabled = 'pm.scheduled-hibernate-enabled';
const String lsKeyBatteryKeepActiveOnSeatboxOpen =
    'scooter.battery-keep-active-on-seatbox-open';

enum UsbMode {
  normal,
  massStorage,
}

const Set<String> alarmTriggerSources = {
  'motion',
  'seatbox',
  'handlebar_position',
  'handlebar_lock',
  'brake_left',
  'brake_right',
  'horn_button',
  'seatbox_button',
};

/// Parses `<known source>,<RFC3339 timestamp>`.
({String source, DateTime? timestamp})? parseAlarmLastTrigger(String value) {
  final int comma = value.indexOf(',');
  final String source = comma < 0 ? value : value.substring(0, comma);
  if (!alarmTriggerSources.contains(source)) return null;
  return (
    source: source,
    timestamp: comma < 0 ? null : DateTime.tryParse(value.substring(comma + 1))
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
      this.supportsAlarmControl,
      this.supportsTripCounter,
      this.supportsTripExpunge});
  final String? nrfVersion;
  final bool? isLibrescoot;
  final int? odometerMeters;
  final bool? supportsHibernateFor;
  final bool? supportsScheduledHibernation;
  final bool? supportsApnConfig;
  final bool? supportsBondForget;
  final bool? supportsBatteryKeepActive;
  final bool? supportsAlarmControl;
  final bool? supportsTripCounter;
  final bool? supportsTripExpunge;
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
      this.supportsApnConfig,
      this.supportsAlarmControl,
      this.supportsTripCounter,
      this.supportsTripExpunge,
      this.supportsScheduledHibernation,
      this.supportsBatteryKeepActive});
  final int? primarySOC;
  final int? secondarySOC;
  final int? cbbSOC;
  final int? auxSOC;
  final bool? handlebarsLocked;
  final bool? isLibrescoot;
  final bool? supportsHibernateFor;
  final bool? supportsApnConfig;

  /// Cached the same way, so a session does not start blind: an unknown
  /// capability hides settings sections and controls until the probe lands.
  final bool? supportsAlarmControl;
  final bool? supportsTripCounter;
  final bool? supportsTripExpunge;
  final bool? supportsScheduledHibernation;
  final bool? supportsBatteryKeepActive;
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
      this.supportsApnConfig,
      this.supportsAlarmControl,
      this.supportsTripCounter,
      this.supportsTripExpunge,
      this.supportsScheduledHibernation,
      this.supportsBatteryKeepActive});
  final int? primarySOC;
  final int? secondarySOC;
  final int? cbbSOC;
  final int? auxSOC;
  final bool? handlebarsLocked;
  final bool? isLibrescoot;
  final bool? supportsHibernateFor;
  final bool? supportsApnConfig;

  /// Cached the same way, so a session does not start blind: an unknown
  /// capability hides settings sections and controls until the probe lands.
  final bool? supportsAlarmControl;
  final bool? supportsTripCounter;
  final bool? supportsTripExpunge;
  final bool? supportsScheduledHibernation;
  final bool? supportsBatteryKeepActive;
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
