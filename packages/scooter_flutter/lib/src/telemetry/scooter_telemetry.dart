import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/telemetry.dart';

import '../ble/characteristic_repository.dart';
import '../ble/firmware_queries.dart' as queries;
import '../runtime/scooter_session.dart';
import 'battery_state.dart';
import 'vehicle_status.dart';
import 'scooter_identity.dart';

abstract interface class ScooterTelemetryEffects {
  void cachePatch(String scooterId, TelemetryCachePatch patch);
  void ping(String scooterId);
  void changed(TelemetrySnapshot snapshot);
  void firmwareIdentified(
      SessionConnection connection, FirmwareSnapshot firmware);
  void navigationChanged(bool? active);
  void aggregateTransition(ScooterState? previous, ScooterState? next);
  void probeFailed(String message, Object error, StackTrace stack);
}

/// Owns live telemetry only. SessionConnection remains the sole link freshness
/// authority; invalidate cancels listeners without creating connection intent.
class ScooterTelemetry {
  ScooterTelemetry({
    required this.effects,
    FirmwareIdentity? identity,
    Future<Set<String>> Function(
            BluetoothDevice?, CharacteristicRepository, String)?
        capabilities,
    Future<String?> Function(
            BluetoothDevice?, CharacteristicRepository, String)?
        setting,
  })  : identity = identity ?? FirmwareIdentity(),
        _capabilities = capabilities ?? queries.getLsCapabilitiesCommand,
        _setting = setting ?? queries.getLsSettingCommand;

  final ScooterTelemetryEffects effects;
  final BatteryState battery = BatteryState();
  final VehicleStatus vehicle = VehicleStatus();
  final FirmwareIdentity identity;
  final Future<Set<String>> Function(
      BluetoothDevice?, CharacteristicRepository, String) _capabilities;
  final Future<String?> Function(
      BluetoothDevice?, CharacteristicRepository, String) _setting;
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  int _revision = 0;
  bool _disposed = false;
  ScooterState? state = ScooterState.disconnected;

  bool get alarmAvailable => _repository?.alarmAvailable ?? false;
  bool get otaAvailable => _repository?.otaAvailable ?? false;

  TelemetrySnapshot get snapshot => TelemetrySnapshot(
      scooterId: _connection?.id,
      generation: _connection?.generation,
      revision: _revision,
      battery: battery.snapshot,
      vehicle: vehicle.snapshot,
      firmware: identity.snapshot,
      state: state);

  bool _current(SessionConnection connection) =>
      identical(_connection, connection) && connection.isCurrent;

  void _notify(SessionConnection connection) {
    if (!_current(connection)) return;
    _revision++;
    effects.changed(snapshot);
  }

  void invalidate() {
    _connection = null;
    _repository = null;
    battery.cancelSubscriptions();
    vehicle.cancelSubscriptions();
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  /// Refresh persisted levels without changing live-only fields, matching a
  /// background saved-record refetch rather than a new linking publication.
  void refetchCache(CachedTelemetry? cache) {
    battery.primarySOC = cache?.primarySOC;
    battery.secondarySOC = cache?.secondarySOC;
    battery.cbbSOC = cache?.cbbSOC;
    battery.auxSOC = cache?.auxSOC;
    _revision++;
  }

  /// Seed cached fields and reset live-only fields on the same compatibility
  /// objects. Protection is never restored from persisted telemetry.
  /// App name/color/location never enter the wire runtime.
  void seed(CachedTelemetry cache) {
    vehicle.cancelSubscriptions();
    refetchCache(cache);
    battery.primaryCycles = null;
    battery.secondaryCycles = null;
    battery.cbbVoltage = null;
    battery.cbbCapacity = null;
    battery.cbbCharging = null;
    battery.auxVoltage = null;
    battery.auxCharging = null;
    vehicle.seatClosed = null;
    vehicle.navigationActive = null;
    vehicle.usbMode = null;
    vehicle.vehicleState = null;
    vehicle.powerState = null;
    identity.nrfVersion = null;
    identity.isLibrescoot = cache.isLibrescoot;
    _seedCapabilities(cache);
  }

  void prepare(CachedTelemetry cache) {
    identity.odometerMeters = null;
    _seedCapabilities(cache);
  }

  void _seedCapabilities(CachedTelemetry cache) {
    identity.resetLsCapabilities();
    identity.supportsHibernateFor = cache.supportsHibernateFor;
    identity.supportsApnConfig = cache.supportsApnConfig;
  }

  void refreshOdometer() {
    final connection = _connection;
    final repository = _repository;
    if (connection == null || repository == null || !_current(connection)) {
      return;
    }
    identity.refreshOdometer(repository,
        onUpdate: () => _notify(connection),
        isCurrent: () => _current(connection));
  }

  void bind(SessionConnection connection, CharacteristicRepository repository) {
    invalidate();
    if (_disposed || !connection.isCurrent) return;
    _connection = connection;
    _repository = repository;
    bool current() => _current(connection);
    void update() {
      if (!current()) return;
      effects.ping(connection.id);
      _notify(connection);
    }

    void cache(TelemetryCachePatch patch) {
      if (current()) effects.cachePatch(connection.id, patch);
    }

    vehicle.wireSubscriptions(repository,
        isCurrent: current,
        onStateUpdate: () {
          final previous = state;
          state = vehicle.computeAggregateState();
          final next = state;
          _notify(connection);
          if (!current()) return;
          effects.ping(connection.id);
          if (!current()) return;
          effects.aggregateTransition(previous, next);
        },
        onSeatUpdate: update,
        onNavigationChanged: () {
          effects.navigationChanged(vehicle.navigationActive);
          update();
        },
        onUsbModeChanged: update,
        onAlarmChanged: () => _notify(connection),
        onHandlebarsChanged: (locked) {
          cache(TelemetryCachePatch(handlebarsLocked: locked));
          update();
        });
    if (!current()) return;
    battery.wireSubscriptions(repository,
        isCurrent: current, onUpdate: update, cacheSoc: cache);
    if (!current()) return;
    identity.wireOdometer(repository,
        isCurrent: current, onUpdate: () => _notify(connection));
    identity.wireNrfVersion(repository, isCurrent: current, onUpdate: () {
      cache(TelemetryCachePatch(isLibrescoot: identity.isLibrescoot));
      if (!current()) return;
      effects.firmwareIdentified(connection, identity.snapshot);
      if (!current()) return;
      if (identity.isLibrescoot == true) {
        unawaited(_probeLsCapabilities(connection, repository));
      } else {
        identity.supportsHibernateFor = false;
        identity.supportsScheduledHibernation = false;
        identity.supportsApnConfig = false;
        identity.supportsBondForget = false;
        identity.supportsBatteryKeepActive = false;
        identity.supportsAlarmControl = false;
      }
      _notify(connection);
    });
  }

  Future<void> _probeLsCapabilities(
      SessionConnection connection, CharacteristicRepository repository) async {
    final scooter = connection.device;
    bool? supportsHibernateFor;
    try {
      final caps = await _capabilities(scooter, repository, "pm");
      supportsHibernateFor = caps.contains("hibernate-for");
    } catch (e, stack) {
      effects.probeFailed("pm capability probe failed", e, stack);
      supportsHibernateFor = false;
    }
    if (!_current(connection)) return;
    identity.supportsHibernateFor = supportsHibernateFor;
    // cache the capability so the next session doesn't wait for the probe
    effects.cachePatch(connection.id,
        TelemetryCachePatch(supportsHibernateFor: supportsHibernateFor));
    _notify(connection);
    if (!_current(connection)) return;

    bool? supportsScheduledHibernation;
    try {
      final value = await _setting(
        scooter,
        repository,
        lsKeyScheduledHibernateEnabled,
      );
      supportsScheduledHibernation = value != null;
    } catch (e, stack) {
      effects.probeFailed("scheduled hibernation probe failed", e, stack);
      supportsScheduledHibernation = false;
    }
    if (!_current(connection)) return;
    identity.supportsScheduledHibernation = supportsScheduledHibernation;
    _notify(connection);
    if (!_current(connection)) return;

    bool? supportsApnConfig;
    try {
      final caps = await _capabilities(scooter, repository, "config");
      supportsApnConfig = caps.contains("apn");
    } catch (e, stack) {
      effects.probeFailed("config capability probe failed", e, stack);
      supportsApnConfig = false;
    }
    if (!_current(connection)) return;
    identity.supportsApnConfig = supportsApnConfig;
    // cached like the pm capability, so the APN tile does not vanish and
    // reappear every time the probe re-runs on a reconnect
    effects.cachePatch(connection.id,
        TelemetryCachePatch(supportsApnConfig: supportsApnConfig));
    _notify(connection);
    if (!_current(connection)) return;

    bool? supportsBondForget;
    try {
      final caps = await _capabilities(scooter, repository, "ble");
      supportsBondForget = caps.contains("forget");
    } catch (e, stack) {
      effects.probeFailed("ble capability probe failed", e, stack);
      supportsBondForget = false;
    }
    if (!_current(connection)) return;
    // Not cached on the SavedScooter, unlike the two above. Nothing renders it,
    // so there is no flicker to avoid, and the answer depends on the nRF
    // firmware rather than the app: a cache would go stale the moment the
    // scooter takes a firmware update.
    identity.supportsBondForget = supportsBondForget;
    _notify(connection);
    if (!_current(connection)) return;

    bool? supportsBatteryKeepActive;
    try {
      final value = await _setting(
        scooter,
        repository,
        lsKeyBatteryKeepActiveOnSeatboxOpen,
      );
      supportsBatteryKeepActive = value != null;
    } catch (e, stack) {
      effects.probeFailed("battery keep-active probe failed", e, stack);
      supportsBatteryKeepActive = false;
    }
    if (!_current(connection)) return;
    identity.supportsBatteryKeepActive = supportsBatteryKeepActive;
    _notify(connection);
    if (!_current(connection)) return;

    bool? supportsAlarmControl;
    try {
      final caps = await _capabilities(scooter, repository, "alarm");
      supportsAlarmControl = caps.contains("enable");
    } catch (e, stack) {
      effects.probeFailed("alarm capability probe failed", e, stack);
      supportsAlarmControl = false;
    }
    if (!_current(connection)) return;
    identity.supportsAlarmControl = supportsAlarmControl;
    _notify(connection);
  }
}
