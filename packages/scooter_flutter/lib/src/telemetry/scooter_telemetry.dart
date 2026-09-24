import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/telemetry.dart';
import '../ble/trip_commands.dart' as trip;
import '../ble/trip_expunge_policy.dart' as expunge;

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
            BluetoothDevice?, CharacteristicRepository, String,
            {bool Function()? isCurrent})?
        capabilities,
    Future<String?> Function(BluetoothDevice?, CharacteristicRepository, String,
            {bool Function()? isCurrent})?
        setting,
    Future<queries.LsCapabilityGroups> Function(
            BluetoothDevice?, CharacteristicRepository,
            {bool Function()? isCurrent})?
        capabilityGroups,
    Future<void> Function(
            BluetoothDevice?, CharacteristicRepository, String, String,
            {bool Function()? isCurrent})?
        settingWrite,
  })  : identity = identity ?? FirmwareIdentity(),
        _capabilities = capabilities ?? queries.getLsCapabilitiesCommand,
        _setting = setting ?? queries.getLsSettingCommand,
        _capabilityGroups =
            capabilityGroups ?? queries.discoverLsCapabilityGroupsCommand,
        _settingWrite = settingWrite ?? queries.setLsSettingCommand;

  final _log = Logger('ScooterTelemetry');

  final ScooterTelemetryEffects effects;
  final BatteryState battery = BatteryState();
  final VehicleStatus vehicle = VehicleStatus();
  final FirmwareIdentity identity;
  final Future<Set<String>> Function(
      BluetoothDevice?, CharacteristicRepository, String,
      {bool Function()? isCurrent}) _capabilities;
  final Future<String?> Function(
      BluetoothDevice?, CharacteristicRepository, String,
      {bool Function()? isCurrent}) _setting;
  final Future<queries.LsCapabilityGroups> Function(
      BluetoothDevice?, CharacteristicRepository,
      {bool Function()? isCurrent}) _capabilityGroups;
  final Future<void> Function(
      BluetoothDevice?, CharacteristicRepository, String, String,
      {bool Function()? isCurrent}) _settingWrite;
  TripCounterSnapshot? tripCounter;
  TripExpunge? tripExpunge;
  bool _tripExpungeLoading = false;
  bool get tripExpungeLoading => _tripExpungeLoading;
  int? _tripGeneration;
  bool _tripLoading = false;
  bool get tripLoading => _tripLoading;
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  int _revision = 0;
  bool _disposed = false;
  ScooterState? state = ScooterState.disconnected;

  CharacteristicRepository? get currentRepository =>
      _connection?.isCurrent == true ? _repository : null;
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
    tripCounter = null;
    tripExpunge = null;
    _tripGeneration = null;
    _tripLoading = false;
    _tripExpungeLoading = false;
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
    identity.imxVersion = null;
    identity.isLibrescoot = cache.isLibrescoot;
    _seedCapabilities(cache);
  }

  void prepare(CachedTelemetry cache) {
    identity.odometerMeters = null;
    _seedCapabilities(cache);
  }

  /// Capabilities are persisted per scooter. A session starts with what the last
  /// probe learned instead of an unknown, which would hide settings sections and
  /// controls until the probe lands (or until the rider reconnects).
  void _seedCapabilities(CachedTelemetry cache) {
    identity.resetLsCapabilities();
    identity.supportsHibernateFor = cache.supportsHibernateFor;
    identity.supportsApnConfig = cache.supportsApnConfig;
    identity.supportsAlarmControl = cache.supportsAlarmControl;
    identity.supportsTripCounter = cache.supportsTripCounter;
    identity.supportsTripExpunge = cache.supportsTripExpunge;
    identity.supportsScheduledHibernation = cache.supportsScheduledHibernation;
    identity.supportsBatteryKeepActive = cache.supportsBatteryKeepActive;
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

  Future<TripCounterSnapshot?> refreshTripCounter() async {
    final connection = _connection;
    final repository = _repository;
    if (identity.supportsTripCounter != true ||
        connection == null ||
        repository == null ||
        !_current(connection)) {
      return null;
    }
    _tripLoading = true;
    _notify(connection);
    try {
      final snapshot = await trip.getTripCounterCommand(
          connection.device, repository,
          isCurrent: () => _current(connection));
      if (_current(connection)) {
        if (snapshot != null &&
            _tripGeneration != null &&
            snapshot.generation < _tripGeneration!) {
          throw StateError('Stale trip counter response');
        }
        tripCounter = snapshot;
        _tripGeneration = snapshot?.generation;
        _notify(connection);
      }
      return snapshot;
    } on trip.TripCounterUnavailableException {
      if (_current(connection)) {
        tripCounter = null;
        _tripGeneration = null;
        _notify(connection);
      }
      rethrow;
    } finally {
      if (_current(connection)) {
        _tripLoading = false;
        _notify(connection);
      }
    }
  }

  Future<void> setTripCounterResetPolicy(TripResetPolicy policy) async {
    final connection = _connection;
    final repository = _repository;
    if (identity.supportsTripCounter != true ||
        connection == null ||
        repository == null ||
        !_current(connection)) {
      throw StateError('Trip counter is unavailable');
    }
    await trip.setTripCounterResetPolicyCommand(
        connection.device, repository, policy,
        isCurrent: () => _current(connection));
    await refreshTripCounter();
  }

  Future<TripExpunge?> refreshTripExpunge() async {
    final connection = _connection;
    final repository = _repository;
    if (identity.supportsTripExpunge != true ||
        connection == null ||
        repository == null ||
        !_current(connection)) {
      return null;
    }
    _tripExpungeLoading = true;
    _notify(connection);
    try {
      final value = await _setting(
        connection.device,
        repository,
        expunge.lsKeyTripExpunge,
        isCurrent: () => _current(connection),
      );
      if (value == null) throw StateError('Trip retention is unavailable');
      final policy = TripExpunge.parse(value);
      if (_current(connection)) {
        tripExpunge = policy;
        _notify(connection);
      }
      return policy;
    } finally {
      if (_current(connection)) {
        _tripExpungeLoading = false;
        _notify(connection);
      }
    }
  }

  Future<void> setTripExpunge(TripExpunge policy) async {
    final connection = _connection;
    final repository = _repository;
    if (identity.supportsTripExpunge != true ||
        connection == null ||
        repository == null ||
        !_current(connection)) {
      throw StateError('Trip retention is unavailable');
    }
    _tripExpungeLoading = true;
    _notify(connection);
    try {
      await _settingWrite(
        connection.device,
        repository,
        expunge.lsKeyTripExpunge,
        policy.wireValue,
        isCurrent: () => _current(connection),
      );
      await refreshTripExpunge();
    } catch (_) {
      // Do not leave the UI on a locally assumed value after a rejected write.
      try {
        await refreshTripExpunge();
      } catch (_) {}
      rethrow;
    } finally {
      if (_current(connection)) {
        _tripExpungeLoading = false;
        _notify(connection);
      }
    }
  }

  Future<void> resetTripCounter() async {
    final connection = _connection;
    final repository = _repository;
    if (identity.supportsTripCounter != true ||
        connection == null ||
        repository == null ||
        !_current(connection)) {
      throw StateError('Trip counter is unavailable');
    }
    await trip.resetTripCounterCommand(connection.device, repository,
        isCurrent: () => _current(connection));
    await refreshTripCounter();
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
      if (!current()) return;
      // Nothing that depends on the librescoot verdict may start until the
      // system behind the nRF has had its say, or a stock system gets probed
      // for services it does not have.
      unawaited(_identifySystem(connection, repository));
    });
  }

  /// Settles what this scooter is, then probes accordingly.
  ///
  /// The nRF reports its own build, and flashing a stock image does not
  /// downgrade the nRF: a librescoot nRF over a stock system still says
  /// `-ls` while nothing behind it answers. The system's own version, which
  /// the nRF only fills in from the iMX over usock, is one characteristic
  /// read, so ask for it before believing the nRF build string.
  Future<void> _identifySystem(
      SessionConnection connection, CharacteristicRepository repository) async {
    bool current() =>
        _current(connection) && identical(_repository, repository);
    if (identity.isLibrescoot == true) {
      await identity.refreshImxVersion(repository, isCurrent: current);
      if (!current()) return;
      final imxVersion = identity.imxVersion;
      if (imxVersion != null) {
        // Only a librescoot system answers with a version over usock.
        _log.info('nRF ${identity.nrfVersion} runs a $imxVersion system');
      } else if (repository.imxVersionCharacteristic != null &&
          vehicle.systemCanAnswer) {
        _log.info(
            'nRF ${identity.nrfVersion} reported no system version, so this is not a librescoot scooter');
        // Everything gated on librescoot follows the system, not the nRF.
        identity.isLibrescoot = false;
      }
      // A firmware without the characteristic, or one that is powered down, is
      // expected to stay silent, so the nRF verdict stands.
    }
    effects.cachePatch(connection.id,
        TelemetryCachePatch(isLibrescoot: identity.isLibrescoot));
    if (!current()) return;
    effects.firmwareIdentified(connection, identity.snapshot);
    if (!current()) return;
    if (identity.isLibrescoot != true) {
      _clearLsCapabilities(connection);
    } else if (!vehicle.systemCanAnswer) {
      _log.info(
          'System is off or hibernating; keeping the cached capabilities');
    } else {
      await _probeLsCapabilities(connection, repository);
      if (!current()) return;
    }
    identity.bluetoothTableOutOfDate = _bluetoothTableOutOfDate(repository);
    _notify(connection);
  }

  /// Nothing on this scooter answered, so nothing is supported. Without this
  /// the flags keep whatever the last successful probe cached and the settings
  /// screen goes on offering controls the scooter cannot honour.
  void _clearLsCapabilities(SessionConnection connection) {
    identity.supportsHibernateFor = false;
    identity.supportsScheduledHibernation = false;
    identity.supportsApnConfig = false;
    identity.supportsBondForget = false;
    identity.supportsBatteryKeepActive = false;
    identity.supportsAlarmControl = false;
    identity.supportsTripCounter = false;
    identity.supportsTripExpunge = false;
    identity.supportsServiceMode = false;
    identity.supportsNavigation = false;
    identity.navigationCapabilityVersion = null;
    identity.supportsClockSync = false;
    identity.supportsUsbMode = false;
    effects.cachePatch(
        connection.id,
        const TelemetryCachePatch(
            supportsHibernateFor: false,
            supportsScheduledHibernation: false,
            supportsApnConfig: false,
            supportsAlarmControl: false,
            supportsTripCounter: false,
            supportsTripExpunge: false,
            supportsBatteryKeepActive: false));
  }

  Future<void> _probeLsCapabilities(
      SessionConnection connection, CharacteristicRepository repository) async {
    final scooter = connection.device;
    bool current() =>
        _current(connection) && identical(_repository, repository);
    if (repository.gattTableMismatch ||
        repository.extendedChannelUnresponsive) {
      _clearLsCapabilities(connection);
      return;
    }
    queries.LsCapabilityGroups groups;
    try {
      groups = await _capabilityGroups(scooter, repository, isCurrent: current);
    } catch (e, stack) {
      effects.probeFailed("capability discovery failed", e, stack);
      return;
    }
    if (!current()) return;
    if (!groups.answered) {
      _log.info('No capability answer; keeping the cached capabilities');
      _notify(connection);
      return;
    }
    // A listed group is its complete initial contract unless it supplies a
    // future version. Only status and BLE have historically varied details.
    final supportsHibernateFor = groups.contains('pm');
    if (!current()) return;
    identity.supportsHibernateFor = supportsHibernateFor;
    // cache the capability so the next session doesn't wait for the probe
    effects.cachePatch(connection.id,
        TelemetryCachePatch(supportsHibernateFor: supportsHibernateFor));
    if (!_publishTableState(connection, repository)) return;

    bool? supportsScheduledHibernation;
    try {
      final value = await _setting(
        scooter,
        repository,
        lsKeyScheduledHibernateEnabled,
        isCurrent: current,
      );
      supportsScheduledHibernation = value != null;
    } catch (e, stack) {
      effects.probeFailed("scheduled hibernation probe failed", e, stack);
      supportsScheduledHibernation = false;
    }
    if (!current()) return;
    identity.supportsScheduledHibernation = supportsScheduledHibernation;
    effects.cachePatch(
        connection.id,
        TelemetryCachePatch(
            supportsScheduledHibernation: supportsScheduledHibernation));
    if (!_publishTableState(connection, repository)) return;

    final supportsApnConfig = groups.contains('config');
    if (!current()) return;
    identity.supportsApnConfig = supportsApnConfig;
    // cached like the pm capability, so the APN tile does not vanish and
    // reappear every time the probe re-runs on a reconnect
    effects.cachePatch(connection.id,
        TelemetryCachePatch(supportsApnConfig: supportsApnConfig));
    if (!_publishTableState(connection, repository)) return;

    bool supportsBondForget = groups.contains('ble');
    // `ble` is complete in cap:ext. Legacy cap:list only reports categories,
    // so it still needs the one historically variable detail query.
    if (groups.usedFallback && supportsBondForget) {
      try {
        final caps =
            await _capabilities(scooter, repository, 'ble', isCurrent: current);
        supportsBondForget = caps.contains('forget');
      } catch (e, stack) {
        effects.probeFailed('ble capability probe failed', e, stack);
        supportsBondForget = false;
      }
    }
    if (!current()) return;
    // Not cached on the SavedScooter, unlike the two above. Nothing renders it,
    // so there is no flicker to avoid, and the answer depends on the nRF
    // firmware rather than the app: a cache would go stale the moment the
    // scooter takes a firmware update.
    identity.supportsBondForget = supportsBondForget;
    if (!_publishTableState(connection, repository)) return;

    bool? supportsBatteryKeepActive;
    try {
      final value = await _setting(
        scooter,
        repository,
        lsKeyBatteryKeepActiveOnSeatboxOpen,
        isCurrent: current,
      );
      supportsBatteryKeepActive = value != null;
    } catch (e, stack) {
      effects.probeFailed("battery keep-active probe failed", e, stack);
      supportsBatteryKeepActive = false;
    }
    if (!current()) return;
    identity.supportsBatteryKeepActive = supportsBatteryKeepActive;
    effects.cachePatch(
        connection.id,
        TelemetryCachePatch(
            supportsBatteryKeepActive: supportsBatteryKeepActive));
    if (!_publishTableState(connection, repository)) return;

    final supportsAlarmControl = groups.contains('alarm');
    if (!current()) return;
    identity.supportsAlarmControl = supportsAlarmControl;
    // Both are advertised by the firmware in cap:ext, so the app can gate the
    // controls on the answer instead of assuming every librescoot scooter
    // still has the services behind them.
    identity.supportsServiceMode = groups.contains('service-mode');
    identity.supportsNavigation = groups.contains('nav');
    identity.navigationCapabilityVersion = groups.versions['nav'];
    identity.supportsClockSync = groups.contains('time');
    identity.supportsUsbMode = groups.contains('usb');
    final supportsTripCounter = groups.contains('trip');
    identity.supportsTripCounter = supportsTripCounter;
    effects.cachePatch(
        connection.id,
        TelemetryCachePatch(
            supportsAlarmControl: supportsAlarmControl,
            supportsTripCounter: supportsTripCounter));
    if (identity.supportsTripCounter == true) {
      try {
        final value = await _setting(
          scooter,
          repository,
          expunge.lsKeyTripExpunge,
          isCurrent: current,
        );
        if (!current()) return;
        if (value == null) {
          identity.supportsTripExpunge = false;
        } else {
          tripExpunge = TripExpunge.parse(value);
          identity.supportsTripExpunge = true;
        }
      } catch (e, stack) {
        effects.probeFailed('trip retention probe failed', e, stack);
        identity.supportsTripExpunge = false;
      }
    } else {
      identity.supportsTripExpunge = false;
    }
    if (!current()) return;
    // Retention decides whether its row is offered at all, so cache the answer
    // rather than let a failed probe hide it for the session.
    effects.cachePatch(connection.id,
        TelemetryCachePatch(supportsTripExpunge: identity.supportsTripExpunge));
    identity.bluetoothTableOutOfDate = _bluetoothTableOutOfDate(repository);
    _notify(connection);
    if (identity.supportsTripCounter == true && current()) {
      // Opportunistic: a failure here is reported, not thrown into the void.
      unawaited(
          refreshTripCounter().catchError((Object error, StackTrace stack) {
        effects.probeFailed('trip counter refresh failed', error, stack);
        return null;
      }));
    }
  }

  /// Publishes the table verdict, and reports whether probing further is worth
  /// another response timeout.
  bool _publishTableState(
      SessionConnection connection, CharacteristicRepository repo) {
    if (!_current(connection) || !identical(_repository, repo)) return false;
    identity.bluetoothTableOutOfDate = _bluetoothTableOutOfDate(repo);
    // Mid-probe silence means the answers still to come will never arrive, so
    // drop the capabilities rather than leaving the cached ones standing.
    final usable =
        !(repo.gattTableMismatch || repo.extendedChannelUnresponsive);
    if (!usable) _clearLsCapabilities(connection);
    _notify(connection);
    // A listener can invalidate the connection while being notified.
    if (!_current(connection) || !identical(_repository, repo)) return false;
    return usable;
  }

  /// Whether this connection shows a GATT table that cannot be the scooter's
  /// current one. Only un-pairing clears the phone's copy, so this reports and
  /// does not act.
  bool _bluetoothTableOutOfDate(CharacteristicRepository repo) {
    if (repo.gattTableMismatch) return true;
    if (repo.anyAreNull()) return true;
    // The original unu firmware has no extended channel, so its absence only
    // means something on librescoot firmware.
    if (identity.isLibrescoot != true) return false;
    return repo.extendedChannelMissing;
  }
}
