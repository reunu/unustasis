import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:scooter_core/actions.dart';
import 'package:scooter_core/telemetry.dart'
    show lsKeyScheduledHibernateEnabled;
import 'package:scooter_core/scooter_core.dart';
import '../ble/action_commands.dart' as commands;
import '../ble/firmware_queries.dart' as queries;
import '../ble/command_transport.dart' as transport;
import '../ble/characteristic_repository.dart';
import '../telemetry/scooter_telemetry.dart';
import 'scooter_session.dart';
import 'state_waiter.dart';

abstract interface class ScooterActionEffects {
  void acknowledged(ActionEvent event);
  void handlebarWarning(HandlebarWarning warning);
  void cooldownStarted();
  void rssiChanged(int value);
  void failed(Object error, StackTrace stack);
}

class _Target {
  _Target(this.connection, this.repository, this.settings, this.soc1, this.soc2,
      this.location, this.deadline);
  final SessionConnection connection;
  final CharacteristicRepository repository;
  final ActionSettings settings;
  final int? soc1, soc2;
  final ActionLocation? location;
  final Duration? deadline;
  bool expired = false;
  void Function()? onWriteIssued;
  ActionEvent event(EventType kind, EventSource source) => ActionEvent(
      scooterId: connection.id,
      generation: connection.generation,
      kind: kind,
      source: source,
      primarySOC: kind == EventType.lock ||
              kind == EventType.unlock ||
              kind == EventType.openSeat
          ? soc1
          : null,
      secondarySOC: kind == EventType.lock ||
              kind == EventType.unlock ||
              kind == EventType.openSeat
          ? soc2
          : null,
      location: kind == EventType.lock ? location : null);
}

/// Executes against the sole session's captured token and repository, never a
/// mutable device getter after an await. Basic actions remain concurrent; all
/// extended operations use the transport's existing single FIFO.
class ScooterActions {
  ScooterActions(
      {required this.session,
      required this.telemetry,
      required this.settings,
      required this.effects,
      this.location,
      Future<void> Function(Duration)? delay,
      Duration Function()? now})
      : _delay = delay ?? Future<void>.delayed,
        _now = now ?? _monotonicClock() {
    rssiTimer = ActionPollingTimer(
        const Duration(seconds: 3), () => _background(pollRssi),
        now: _now);
  }
  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final ScooterSession session;
  final ScooterTelemetry telemetry;
  final ActionSettings Function() settings;
  final ActionLocation? Function()? location;
  final ScooterActionEffects effects;
  final Future<void> Function(Duration) _delay;
  final Duration Function() _now;
  final _changes = _ActionChanges();
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  bool _disposed = false;
  bool _cooldown = false;
  final Set<Timer> _cooldowns = {};
  Timer? _refreshTimer;
  late final ActionPollingTimer rssiTimer;
  bool get coolingDown => _cooldown;

  void bind(SessionConnection connection, CharacteristicRepository repository) {
    invalidate();
    if (_disposed || !connection.isCurrent) return;
    _connection = connection;
    _repository = repository;
  }

  /// A connected session can have partial discovery. Explicit native requests
  /// require this owner's bound command characteristic, not connectivity alone.
  bool canDispatchExplicitAction(SessionConnection connection) =>
      !_disposed && identical(_connection, connection) &&
      identical(session.currentConnection, connection) && connection.isCurrent &&
      _repository?.commandCharacteristic != null;

  /// False means no native command write was invoked. Once write is invoked,
  /// any later error propagates: retrying that uncertain actuation is unsafe.
  Future<bool> dispatchExplicitAction(SessionConnection connection, EventType kind) async {
    var issued = false;
    try {
      if (!canDispatchExplicitAction(connection)) return false;
      final target = _capture();
      target.onWriteIssued = () => issued = true;
      switch (kind) {
        case EventType.lock:
          await _lock(target, false, EventSource.background);
        case EventType.unlock:
          await _unlock(target, false, EventSource.background);
        case EventType.openSeat:
          await _seat(target, EventSource.app); // Existing native seat source.
        default:
          return false;
      }
      return true;
    } catch (_) {
      if (!issued) return false;
      rethrow;
    }
  }

  void invalidate() {
    _connection = null;
    _repository = null;
    if (!_disposed) _changes.changed();
  }

  void telemetryChanged() {
    if (!_disposed) _changes.changed();
  }

  _Target _capture({Duration? budget}) {
    final connection = _connection;
    final repository = _repository;
    if (_disposed ||
        connection == null ||
        repository == null ||
        !connection.isCurrent) {
      throw StateError('Scooter not connected');
    }
    final target = _Target(
        connection,
        repository,
        settings(),
        telemetry.battery.primarySOC,
        telemetry.battery.secondarySOC,
        location?.call(),
        budget == null ? null : _now() + budget);
    _check(target);
    return target;
  }

  bool _current(_Target t) =>
      !_disposed &&
      !t.expired &&
      identical(_connection, t.connection) &&
      identical(_repository, t.repository) &&
      t.connection.isCurrent &&
      (t.deadline == null || _now() < t.deadline!);
  void _check(_Target t) {
    if (!_current(t)) throw StateError('Action session expired');
  }

  Future<T> _command<T>(
      _Target t,
      Future<T> Function(
              BluetoothDevice, CharacteristicRepository, bool Function())
          run) async {
    _check(t);
    final result =
        await run(t.connection.device, t.repository, () => _current(t));
    _check(t);
    return result;
  }

  Future<void> _ack(
      _Target t,
      EventType kind,
      EventSource source,
      Future<void> Function(
              BluetoothDevice, CharacteristicRepository, bool Function())
          run) async {
    await _command(t, run);
    effects.acknowledged(t.event(kind, source));
  }

  Future<void> _wait(_Target t, Duration duration) async {
    _check(t);
    await _delay(duration);
    _check(t);
  }

  void _background(Future<void> Function() work) {
    unawaited(work().catchError((Object error, StackTrace stack) {
      if (!_disposed) effects.failed(error, stack);
    }));
  }

  Future<void> unlock(
          {bool checkHandlebars = true,
          EventSource source = EventSource.app}) =>
      _unlock(_capture(), checkHandlebars, source);
  Future<void> _unlock(
      _Target t, bool checkHandlebars, EventSource source) async {
    await _ack(t, EventType.unlock, source,
        (d, r, c) => commands.unlockScooter(d, r, isCurrent: c, onWriteIssued: t.onWriteIssued));
    _check(t);
    if (t.settings.openSeatOnUnlock) {
      await _wait(t, const Duration(seconds: 1));
      // Legacy delay is awaited, seat acknowledgement is not.
      _background(() => _seat(t, EventSource.auto));
    }
    if (t.settings.hazardLocking) {
      await _wait(t, const Duration(seconds: 2));
      _background(() => _hazard(t, 2));
    }
    if (checkHandlebars) {
      await _wait(t, const Duration(seconds: handlebarCheckSeconds));
      if (telemetry.vehicle.handlebarsLocked == true) {
        effects.handlebarWarning(
            HandlebarWarning(t.event(EventType.unlock, source)));
      }
    }
  }

  Future<void> lock(
      {bool checkHandlebars = true,
      bool confirmOpenSeat = false,
      EventSource source = EventSource.app}) async =>
      _lock(_capture(), checkHandlebars, source, confirmOpenSeat: confirmOpenSeat);
  Future<void> _lock(_Target t, bool checkHandlebars, EventSource source,
      {bool confirmOpenSeat = false}) async {
    // Explicit open-seat intent is two sequential ordinary writes, not a retry.
    // Both use the same captured connection/repository; any failure stops here.
    await _command(t,
        (d, r, c) => commands.lockScooter(d, r, isCurrent: c, onWriteIssued: t.onWriteIssued));
    if (confirmOpenSeat) {
      await _command(t,
          (d, r, c) => commands.lockScooter(d, r, isCurrent: c, onWriteIssued: t.onWriteIssued));
    }
    effects.acknowledged(t.event(EventType.lock, source));
    _check(t);
    if (t.settings.hazardLocking) {
      _background(() async {
        await _wait(t, const Duration(seconds: 1));
        await _hazard(t, 1);
      });
    }
    if (checkHandlebars) {
      await _wait(t, const Duration(seconds: handlebarCheckSeconds));
      if (telemetry.vehicle.handlebarsLocked == false &&
          t.settings.warnOfUnlockedHandlebars) {
        effects.handlebarWarning(
            HandlebarWarning(t.event(EventType.lock, source)));
      }
    }
    _check(t);
    autoUnlockCooldown();
  }

  Future<void> wakeUpAndUnlock({EventSource? source}) async {
    final t = _capture(budget: wakeAndUnlockTimeout);
    final waiter = StateWaiter<ScooterState?>(
        notifier: _changes,
        value: () => _current(t) ? telemetry.state : ScooterState.disconnected,
        expected: ScooterState.standby,
        timeout: wakeAndUnlockTimeout,
        isDisconnected: (state) => state == ScooterState.disconnected);
    final standby = waiter.wait(); // Subscribe before issuing wake.
    try {
      await (() async {
        await Future.wait([_wake(t), standby], eagerError: true);
        _check(t);
        await _unlock(t, true, source ?? EventSource.app);
      })()
          .timeout(wakeAndUnlockTimeout);
    } catch (_) {
      t.expired = true; // Future.timeout alone does not cancel delayed writes.
      rethrow;
    } finally {
      waiter.cancel();
    }
  }

  Future<void> _wake(_Target t) => _ack(t, EventType.wakeUp, EventSource.app,
      (d, r, c) => commands.wakeUpCommand(d, r, isCurrent: c));
  Future<void> wakeUp() => _wake(_capture());
  Future<void> _seat(_Target t, EventSource source) => _ack(
      t,
      EventType.openSeat,
      source,
      (d, r, c) => commands.openSeatCommand(d, r, isCurrent: c, onWriteIssued: t.onWriteIssued));
  Future<void> openSeat({EventSource source = EventSource.app}) =>
      _seat(_capture(), source);
  Future<void> _blink(_Target t, bool left, bool right) => _command(
      t,
      (d, r, c) =>
          commands.blinkCommand(d, r, left: left, right: right, isCurrent: c));
  Future<void> blink({required bool left, required bool right}) =>
      _blink(_capture(), left, right);
  Future<void> _hazard(_Target t, int times) async {
    _check(t);
    _background(() => _blink(t, true, true));
    await _wait(t, Duration(milliseconds: 600 * times));
    _background(() => _blink(t, false, false));
  }

  Future<void> hazard({int times = 1}) => _hazard(_capture(), times);
  Future<void> hibernate() => _ack(
      _capture(),
      EventType.hibernate,
      EventSource.app,
      (d, r, c) => commands.hibernateCommand(d, r, isCurrent: c));
  Future<void> hibernateFor(Duration wakeAfter) => _ack(
      _capture(),
      EventType.hibernate,
      EventSource.app,
      (d, r, c) => commands.hibernateForCommand(d, r, wakeAfter, isCurrent: c));
  Future<void> hibernateCancel() => _command(_capture(),
      (d, r, c) => commands.hibernateCancelCommand(d, r, isCurrent: c));
  Future<void> reboot() => _command(
      _capture(), (d, r, c) => commands.rebootCommand(d, r, isCurrent: c));
  Future<void> hardReboot() => _command(
      _capture(), (d, r, c) => commands.hardRebootCommand(d, r, isCurrent: c));
  Future<void> enterUMSMode() => _command(_capture(),
      (d, r, c) => commands.enterUMSModeCommand(d, r, isCurrent: c));
  Future<void> enterNormalUsbMode() => _command(_capture(),
      (d, r, c) => commands.enterNormalUsbModeCommand(d, r, isCurrent: c));
  Future<int?> countKeycards() => _command(_capture(),
      (d, r, c) => commands.countKeycardsCommand(d, r, isCurrent: c));
  Future<List<String>> listKeycards() => _command(_capture(),
      (d, r, c) => commands.listKeycardsCommand(d, r, isCurrent: c));
  Future<void> addKeycard(String uid) => _command(_capture(),
      (d, r, c) => commands.addKeycardCommand(d, r, uid, isCurrent: c));
  Future<void> deleteKeycard(String uid) => _command(_capture(),
      (d, r, c) => commands.deleteKeycardCommand(d, r, uid, isCurrent: c));
  Future<String?> setClock(DateTime time) => _command(
      _capture(),
      (d, r, c) => transport.sendLsExtendedCommand(d, r, clockPayload(time),
          isCurrent: c));
  Future<bool?> getBoolSetting(String key) async {
    final value = await getSetting(key);
    return value == null ? null : value == 'true';
  }

  Future<String?> getSetting(String key) => _command(_capture(),
      (d, r, c) => queries.getLsSettingCommand(d, r, key, isCurrent: c));
  Future<void> setSetting(String key, String value) => _command(_capture(),
      (d, r, c) => queries.setLsSettingCommand(d, r, key, value, isCurrent: c));

  /// First enable writes supplied defaults before the enabled flag. This is not
  /// transactional: acknowledged earlier settings remain if a later step fails.
  Future<void> setScheduledHibernationEnabled(bool enabled,
      {String? cron, Duration? wakeAfter}) async {
    final t = _capture();
    Future<void> write(String key, String value) => _command(
        t,
        (d, r, c) =>
            queries.setLsSettingCommand(d, r, key, value, isCurrent: c));
    if (enabled) {
      if (cron != null) await write(lsKeyScheduledHibernateCron, cron);
      if (wakeAfter != null) {
        await write(
            lsKeyScheduledHibernateDuration, formatGoDuration(wakeAfter));
      }
    }
    await write(lsKeyScheduledHibernateEnabled, enabled.toString());
  }

  Future<void> setAutoStandbyTime(Duration time) => _command(
      _capture(),
      (d, r, c) =>
          commands.setAutoStandbyTimeCommand(d, r, time, isCurrent: c));
  Future<void> setAutoHibernateTime(Duration time) => _command(
      _capture(),
      (d, r, c) =>
          commands.setAutoHibernateTimeCommand(d, r, time, isCurrent: c));
  Future<void> setCellularApn(String apn) => _command(_capture(),
      (d, r, c) => commands.setCellularApnCommand(d, r, apn, isCurrent: c));
  Future<void> clearCellularApn() => _command(_capture(),
      (d, r, c) => commands.clearCellularApnCommand(d, r, isCurrent: c));

  /// Transport half only. Persistence and background/name effects stay app-side.
  Future<void> forgetCurrentScooter() async {
    // A disconnected session retains its device but has no action binding.
    // Phone-side forgetting must not depend on live characteristics.
    if (_disposed ||
        session.isDisposed ||
        session.hasPendingConnectionAttempt) {
      return;
    }
    final device = session.device;
    final operationIsCurrent = session.captureOperationFreshness();
    final t = _connection?.isCurrent == true && _repository != null
        ? _capture()
        : null;
    bool current() =>
        !_disposed && operationIsCurrent() && identical(session.device, device);
    session.stopAutoRestart();
    if (device == null || !current()) return;
    if (t != null &&
        telemetry.identity.isLibrescoot == true &&
        telemetry.identity.supportsBondForget != false) {
      final disconnected = Completer<void>();
      final subscription = t.connection.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            !disconnected.isCompleted) {
          disconnected.complete();
        }
      });
      try {
        await commands.forgetBondCommand(t.connection.device, t.repository,
            isCurrent: () => _current(t));
        // Listen before the ACK: firmware may drop the link immediately after
        // replying. Only an accepted command enters the five-second wait.
        await disconnected.future.timeout(const Duration(seconds: 5));
      } catch (e, stack) {
        effects.failed(e, stack);
      } finally {
        await subscription.cancel();
      }
    }
    // A firmware disconnect is expected; replacement/disposal is not.
    if (!current()) return;
    try {
      await device.disconnect();
    } catch (e, stack) {
      if (t != null) rethrow;
      effects.failed(e, stack); // Offline cleanup remains best effort.
    }
    if (!current()) return;
    _background(() => device.removeBond());
    if (current()) session.device = null;
  }

  void aggregateTransition(ScooterState? previous, ScooterState? next) {
    if (previous?.isOn == true && next?.isOn == false) autoUnlockCooldown();
  }

  void autoUnlockCooldown() {
    if (_disposed) return;
    _cooldown = true;
    late final Timer timer;
    timer = Timer(const Duration(seconds: keylessCooldownSeconds), () {
      _cooldowns.remove(timer);
      _cooldown =
          false; // Preserve overlapping legacy cooldown expiry semantics.
    });
    _cooldowns.add(timer);
    effects.cooldownStarted();
  }

  void startPolling() {
    if (_disposed) return;
    rssiTimer.start();
    _refreshTimer ??= Timer.periodic(
        const Duration(seconds: 10), (_) => _background(refresh));
  }

  void stopPolling() {
    rssiTimer.pause();
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> pollRssi() async {
    if (_disposed || _connection?.isCurrent != true || !settings().autoUnlock) {
      return;
    }
    // Match readRssi's transport timeout and reject even a late underlying result.
    final t = _capture(budget: const Duration(seconds: 15));
    final pollRevision = rssiTimer.revision;
    final int value;
    try {
      value = await t.connection.device
          .readRssi()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return;
    }
    if (!_current(t) ||
        !rssiTimer.enabled ||
        pollRevision != rssiTimer.revision) {
      return;
    }
    effects.rssiChanged(value);
    if (!_current(t) ||
        !rssiTimer.enabled ||
        pollRevision != rssiTimer.revision) {
      return;
    }
    final currentSettings = settings();
    if (currentSettings.autoUnlock &&
        value > currentSettings.autoUnlockThreshold &&
        telemetry.state == ScooterState.standby &&
        !_cooldown &&
        currentSettings.optionalAuth) {
      // The RSSI budget bounds the read, not the subsequent basic unlock.
      final action = _Target(t.connection, t.repository, t.settings, t.soc1,
          t.soc2, t.location, null);
      _background(() => _unlock(action, true, EventSource.auto));
      if (_current(t)) autoUnlockCooldown();
    }
  }

  Future<void> refresh() async {
    if (_disposed || _connection?.isCurrent != true) return;
    final t = _capture();
    _background(() async {
      await t.repository.stateCharacteristic?.read();
    });
    if (_current(t)) {
      _background(() async {
        await t.repository.seatCharacteristic?.read();
      });
    }
  }

  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    stopPolling();
    rssiTimer.cancel();
    for (final timer in _cooldowns) {
      timer.cancel();
    }
    _cooldowns.clear();
    _changes.dispose();
  }
}

/// Compatibility start/pause/cancel handle. Pause retains the remaining interval;
/// cancel is terminal, and repeated starts never allocate another polling loop.
class ActionPollingTimer {
  ActionPollingTimer(this.interval, this.callback, {Duration Function()? now})
      : _remaining = interval,
        _now = now ?? ScooterActions._monotonicClock();
  final Duration interval;
  final void Function() callback;
  Duration _remaining;
  Timer? _timer;
  final Duration Function() _now;
  Duration _started = Duration.zero;
  int revision = 0;
  bool _cancelled = false;
  bool get enabled => _timer != null;
  void start() {
    if (_cancelled || enabled) return;
    _started = _now();
    _timer = Timer(_remaining, () {
      _timer = null;
      _remaining = interval;
      start();
      callback();
    });
  }

  void pause() {
    if (!enabled) return;
    revision++;
    _remaining -= _now() - _started;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
    _timer!.cancel();
    _timer = null;
  }

  void cancel() {
    pause();
    _cancelled = true;
  }
}

class _ActionChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}
