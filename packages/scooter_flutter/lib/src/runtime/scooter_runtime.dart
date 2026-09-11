import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/activity.dart';
import 'package:scooter_core/telemetry.dart';
import 'scooter_session.dart';
import 'navigation_runtime.dart';
import '../telemetry/scooter_telemetry.dart';
import 'scooter_actions.dart';
import '../storage/scooter_storage.dart';
import '../storage/user_settings.dart';
import '../ble/blue_plus_mockable.dart';

/// Captured readiness and issuance share the same session/pin predicate. The app
/// can check before claiming its native slot without preparing a new target.
class ExplicitActionDispatch {
  ExplicitActionDispatch._(this.isReady, this._dispatch);
  final bool Function() isReady;
  final Future<bool> Function() _dispatch;
  Future<bool> call() async {
    if (!isReady()) return false;
    return _dispatch();
  }
}

/// Orchestrates the existing owners; it never owns a connection attempt, retry
/// loop, transport FIFO or generation. Saved-record presentation and platform
/// publication remain effects supplied by the application.
class ScooterRuntime<T extends SavedScooterRecord> {
  ScooterRuntime(
      {required ScooterSession session,
      required this.telemetry,
      required this.actions,
      required this.navigation,
      required this.settings,
      required this.store,
      required this.idOf,
      required this.cacheOf,
      required this.presentCache,
      required this.changed,
      required this.savedChanged,
      required this.manualTargetHeartbeat,
      required this.scanningChanged,
      required bool Function() isScanning,
      required this.readLocation,
      required this.saveLocation,
      required this.publishDisconnected,
      required BluetoothDevice Function(String) deviceFromId})
      : _session = session,
        _isScanning = isScanning,
        _deviceFromId = deviceFromId;
  final ScooterSession _session;
  final ScooterTelemetry telemetry;
  final ScooterActions actions;
  final NavigationRuntime navigation;
  final UserSettings settings;
  final ScooterStorage<T> store;
  final String Function(T) idOf;
  final CachedTelemetry Function(T?) cacheOf;
  final void Function(T?, {required bool initial}) presentCache;
  final void Function() changed, savedChanged, publishDisconnected;
  final void Function(String) manualTargetHeartbeat;
  final void Function(bool) scanningChanged;
  final bool Function() _isScanning;
  final Future<LatLng?> Function() readLocation;
  final void Function(String, LatLng) saveLocation;
  final BluetoothDevice Function(String) _deviceFromId;
  final log = Logger('ScooterRuntime');
  FlutterBluePlusMockable get flutterBluePlus => _session.flutterBluePlus;
  BluetoothDevice? get _device => _session.device;
  bool get connected => _session.connected;
  set connected(bool value) => _session.connected = value;
  bool get scanning => _isScanning();
  ScooterState? get _state => telemetry.state;
  String? _externalManualTargetId;
  DateTime? _externalManualTargetSince;
  AppLifecycleState? _lastLifecycleState;
  bool _wasBackgrounded = false;
  Timer? _locationTimer, _heartbeatTimer;
  StreamSubscription<bool>? _scanSubscription;
  Future<void>? _initialization;
  bool _disposed = false;
  bool get _inactive => _disposed || _session.isDisposed;

  Future<void> initialize() {
    if (_inactive) return Future.value();
    if (_initialization != null) return _initialization!;
    _initialization = _restore();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final target = _session.manualTargetId;
      if (!_inactive && target != null) manualTargetHeartbeat(target);
    });
    _scanSubscription = flutterBluePlus.isScanning.listen((value) {
      if (!_inactive) scanningChanged(value);
    });
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_device?.isConnected == true) pollLocation();
    });
    actions.startPolling();
    return _initialization!;
  }

  Future<void> _restore() async {
    final current = _session.captureOperationFreshness();
    await store.load();
    if (_inactive) return;
    if (!_inactive && current()) {
      final recent = await getMostRecentScooter();
      if (!_inactive && current()) {
        presentCache(recent, initial: true);
        if (!_inactive && current()) telemetry.seed(cacheOf(recent));
        if (!_inactive && current()) changed();
      }
    }
    // Global preferences are lifetime-owned, not tied to a startup target.
    if (_inactive) return;
    await navigation.restorePending();
    if (_inactive) return;
    await settings.restore();
  }

  Future<T?> getMostRecentScooter() async {
    final recent = store.getMostRecent();
    if (recent != null &&
        store.scooters.length == 1 &&
        store.scooters.values.first.autoConnect) {
      savedChanged();
    }
    return recent;
  }

  Future<String?> _mostRecentId() async {
    final recent = await getMostRecentScooter();
    return recent == null ? null : idOf(recent);
  }

  Future<void> refetchSavedScooters({bool Function()? isCurrent}) async {
    final fresh = _session.captureOperationFreshness();
    bool current() => !_inactive && fresh() && (isCurrent?.call() ?? true);
    await store.load();
    if (!current()) return;
    if (!connected) {
      final recent = await getMostRecentScooter();
      if (!current()) return;
      presentCache(recent, initial: false);
      if (!current()) return;
      telemetry.refetchCache(recent == null ? null : cacheOf(recent));
    }
    if (!_inactive && current()) changed();
  }

  Future<void> forgetSavedScooter(String id) async {
    if (_inactive || _session.hasPendingConnectionAttempt) return;
    final fresh = _session.captureOperationFreshness();
    bool current() => !_inactive && fresh();
    if (!current()) return;
    if (_device?.remoteId.toString() == id) {
      await actions.forgetCurrentScooter();
    } else {
      // we're not currently connected to this scooter
      try {
        await _deviceFromId(id).removeBond();
      } catch (e, stack) {
        log.severe("Couldn't forget scooter", e, stack);
      }
    }

    // Do not let completion of an old forget clear a replacement's state.
    if (!current()) return;
    if (store.scooters.isNotEmpty) {
      await store.remove(id);
    }
    if (!current()) return;
    savedChanged();
    if (!current()) return;
    if (_device == null || _device?.remoteId.toString() == id) {
      connected = false;
    }
    if (!current()) return;
    // The background isolate is told to refetch, but this one was left holding
    // the forgotten scooter's name and battery levels, so the home screen went
    // on showing a scooter that no longer exists. refetchSavedScooters resets
    // the streams when nothing is saved, and notifies for us.
    await refetchSavedScooters(isCurrent: current);
  }

  Future<void> addSavedScooter(String id, void Function() presentAdded) async {
    final connection = _session.currentConnection;
    final added = await store.add(id);
    if (!added || _inactive) return;
    savedChanged();
    if (connection != null && !connection.isCurrent) return;
    presentAdded();
  }

  Future<void> renameSavedScooter({
    String? id,
    required String name,
    required void Function() missingId,
    required void Function(bool isMostRecent) publish,
  }) =>
      _updateSavedScooter(
        id: id,
        mutate: (target) => store.rename(target, name),
        missingId: missingId,
        publish: publish,
      );

  Future<void> recolorSavedScooter({
    String? id,
    required int color,
    required void Function() missingId,
    required void Function(bool isMostRecent) publish,
  }) =>
      _updateSavedScooter(
        id: id,
        mutate: (target) => store.recolor(target, color),
        missingId: missingId,
        publish: publish,
      );

  Future<void> _updateSavedScooter({
    String? id,
    required Future<void> Function(String) mutate,
    required void Function() missingId,
    required void Function(bool) publish,
  }) async {
    final target = id ?? _device?.remoteId.toString();
    if (target == null) {
      missingId();
      return;
    }
    // Preserve the saved-metadata contract: capture the ID now, select after
    // mutation, and publish the supplied value (not a reread). These operations
    // are independent, not session-fresh transactions or serialized edits.
    await mutate(target);
    final recent = await getMostRecentScooter();
    publish(recent != null && idOf(recent) == target);
    changed();
  }

  Future<void> pollLocation() async {
    final scooter = _device;
    final connection = _session.currentConnection;
    if (_inactive || scooter == null) return;
    final position = await readLocation();
    if (!_inactive &&
        position != null &&
        connection?.isCurrent == true &&
        connected &&
        scooter.isConnected &&
        _device?.remoteId == scooter.remoteId) {
      saveLocation(scooter.remoteId.toString(), position);
    }
  }

  void dispose() {
    _disposed = true;
    _locationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _scanSubscription?.cancel();
    actions.stopPolling();
  }

  void start({bool restart = true}) {
    if (_inactive) return;
    final target = _session.manualTargetId;
    if (target == null) {
      _session.start(restart: restart);
      return;
    }
    if (_inactive || connected || _session.hasPendingConnectionAttempt) return;
    // Onboarding leaves explicit intent pinned. Home/resume must recover that
    // target, not call the generic startup path which deliberately ignores it.
    // Silent resume can invalidate the link without a disconnect notification.
    _session.foundScooter = false;
    if (restart) {
      _session.startAutoRestart(targetScooterId: target);
    } else {
      unawaited(_session
          .connectToScooterId(target,
              automatic: true,
              expectedIntentGeneration: _session.intentGeneration)
          .catchError((Object error, StackTrace stack) {
        log.warning('Targeted reconnect failed', error, stack);
      }));
    }
  }

  /// Called on the background isolate's service when the foreground reports
  /// that the user is manually connecting a specific scooter. Empty string
  /// means the manual intent is over.
  void setManualConnectionTarget(String? id) {
    _externalManualTargetId = (id == null || id.isEmpty) ? null : id;
    _externalManualTargetSince =
        _externalManualTargetId == null ? null : DateTime.now();
    log.info(
        "Background manual connection target: ${_externalManualTargetId ?? "(cleared)"}");
  }

  /// Any message from the foreground is proof of life: extend the suppression
  /// window so a live foreground session doesn't get raced after the expiry,
  /// while a killed foreground's stale flag still lapses.
  void touchManualConnectionTarget() {
    if (_externalManualTargetId != null) {
      _externalManualTargetSince = DateTime.now();
    }
  }

  /// Prepares one explicit widget/notification request through the existing
  /// session. Unlike passive auto-connect it may connect under the foreground
  /// gate, but only to its captured pin. No scan, retry loop or intent release.
  Future<ExplicitActionDispatch?> prepareExplicitAction(
      EventType eventType) async {
    if (!const [EventType.lock, EventType.unlock, EventType.openSeat]
            .contains(eventType) ||
        _inactive ||
        _session.hasPendingConnectionAttempt) {
      return null;
    }
    _expireManualConnectionTarget();
    final externalTarget = _externalManualTargetId;
    final manualTarget = _session.manualTargetId;
    var operationCurrent = _session.captureOperationFreshness();
    bool pinsUnchanged() =>
        _externalManualTargetId == externalTarget &&
        _session.manualTargetId == manualTarget;
    final target = externalTarget ??
        manualTarget ??
        (connected ? _device?.remoteId.toString() : null) ??
        await _mostRecentId();
    if (_inactive ||
        target == null ||
        !operationCurrent() ||
        !pinsUnchanged() ||
        _session.hasPendingConnectionAttempt) {
      return null;
    }
    if (!connected ||
        _session.currentConnection?.isCurrent != true ||
        _device?.remoteId.toString() != target) {
      final connecting = _session.connectToScooterId(target,
          automatic: true, expectedIntentGeneration: _session.intentGeneration);
      // Capture the existing owner's generation after starting our own attempt;
      // a same-ID replacement must not become this request's continuation.
      operationCurrent = _session.captureOperationFreshness();
      await connecting;
    }
    final connection = _session.currentConnection;
    bool usable() =>
        !_inactive &&
        operationCurrent() &&
        pinsUnchanged() &&
        connected &&
        !_session.hasPendingConnectionAttempt &&
        connection?.isCurrent == true &&
        connection!.id == target &&
        actions.canDispatchExplicitAction(connection);
    if (!usable()) return null;
    return ExplicitActionDispatch._(usable,
        () => actions.dispatchExplicitAction(connection!, eventType));
  }

  void _expireManualConnectionTarget() {
    if (_externalManualTargetId != null &&
        DateTime.now()
                .difference(_externalManualTargetSince ?? DateTime.now()) >=
            const Duration(minutes: 5)) {
      _externalManualTargetId = null;
      _externalManualTargetSince = null;
    }
  }

  Future<bool> attemptLatestAutoConnection() async {
    if (_inactive || _session.hasPendingConnectionAttempt) return false;
    // While the foreground is manually connecting a scooter, the background
    // must not race it with its own auto-connect target. The flag expires so
    // a killed foreground can't suspend background reconnects forever.
    _expireManualConnectionTarget();
    if (_externalManualTargetId != null) {
      log.info(
          "Skipping background auto-connect: foreground is manually connecting $_externalManualTargetId");
      return false;
    }
    T? latestScooter = await getMostRecentScooter();
    if (_externalManualTargetId != null) {
      // A manual intent arrived while we were picking a candidate; don't
      // start racing it now.
      log.info(
          "Manual connection target appeared during auto-connect preparation");
      return false;
    }
    if (latestScooter != null) {
      try {
        await _session.connectToScooterId(
          idOf(latestScooter),
          automatic: true,
          expectedIntentGeneration: _session.intentGeneration,
        );
        if (_deviceFromId(idOf(latestScooter)).isConnected) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    log.info("App lifecycle state changed: $_lastLifecycleState -> $state");

    // Only paused/hidden count as leaving the app. `inactive -> resumed` also
    // happens without backgrounding (iOS cold start, biometric prompt, system
    // dialogs) and used to fire a second start() that raced the initial
    // connection attempt, leaving a redundant scan running for seconds.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    }

    if (_wasBackgrounded && state == AppLifecycleState.resumed) {
      _wasBackgrounded = false;
      log.info("App resumed from background - checking connection status");
      _handleAppResumedFromBackground();
    }

    _lastLifecycleState = state;
  }

  bool get _connectionAttemptInFlight =>
      scanning || _state == ScooterState.linking;

  void _handleAppResumedFromBackground() async {
    if (_inactive || store.scooters.isEmpty) return;

    try {
      // Small delay so the platform can deliver events that were queued
      // while the app was suspended (disconnects, scan stops) before we
      // judge any cached state
      await Future.delayed(const Duration(milliseconds: 500));

      // iOS kills an active scan during suspension without a final
      // isScanning event, leaving `scanning` stuck true — which disables
      // the manual reconnect button and blocks every automatic reconnect
      // path until the app is restarted.
      if (_inactive) return;
      if (scanning != flutterBluePlus.isScanningNow) {
        log.info(
            "App resumed: resync scanning flag (cached: $scanning, platform: $flutterBluePlus.isScanningNow)");
        scanningChanged(flutterBluePlus.isScanningNow);
      }

      // The BLE link can also die during suspension without a disconnect
      // event ever reaching us, so probe the link instead of trusting the
      // cached connected flag.
      if (connected && _device != null) {
        final connection = _session.currentConnection;
        final device = _device!;
        try {
          await device.readRssi();
        } catch (e, stack) {
          if (_inactive ||
              !identical(connection, _session.currentConnection) ||
              !identical(device, _device)) {
            return;
          }
          log.info("App resumed: connection is stale, marking as disconnected",
              e, stack);
          connected = false;
          publishDisconnected();
        }
      }

      if (_inactive) return;
      if (!connected && !_connectionAttemptInFlight) {
        log.info("App resumed: attempting automatic reconnection");
        // Try to reconnect to the last known scooter
        start();
      } else {
        log.info(
          "App resumed: no reconnection needed (connected: $connected, scanning: $scanning, saved scooters: ${store.scooters.length})",
        );
      }
    } catch (e, stack) {
      log.warning(
        "Error during automatic reconnection on app resume",
        e,
        stack,
      );
    }
  }
}
