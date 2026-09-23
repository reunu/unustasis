import 'package:scooter_flutter/scooter_runtime.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'service/update_release_provider.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_session.dart';
import 'package:scooter_flutter/scooter_telemetry.dart';
import 'dart:async';
import 'package:scooter_flutter/navigation_runtime.dart';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../domain/statistics_helper.dart';
import 'package:scooter_core/scooter_battery.dart';
import '../domain/scooter_candidate.dart';
import '../domain/nav_destination.dart';
import '../domain/saved_scooter.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../service/location_polling.dart' as location;
import '../state/scooter_identity.dart';
import '../service/scooter_storage.dart';
import '../service/ble_commands.dart' as commands;
import '../service/ble_scanner.dart';
import '../service/user_settings.dart';

export 'package:scooter_flutter/scooter_actions.dart'
    show ActionPollingTimer, keylessCooldownSeconds, handlebarCheckSeconds, wakeAndUnlockTimeout;

typedef WidgetActionDispatch = ExplicitActionDispatch;

const connectionPausedPreferenceKey = 'connectionPaused';

class ScooterService with ChangeNotifier, WidgetsBindingObserver {
  final log = Logger('ScooterService');

  // Composed modules
  final ScooterStorage store;
  final BluetoothDevice Function(String) _deviceFromId;
  late final ScooterSession _session;
  final Future<LatLng?> Function() _readLocation;
  final bool _runtimeInitialized;
  late final ScooterRuntime<SavedScooter> runtime;
  Future<void> get runtimeReady => _runtimeInitialized ? runtime.initialize() : Future.value();
  late final BleScanner scanner;
  late final UserSettings settings;

  // Observable state
  late final ScooterTelemetry _telemetry;
  BatteryState get battery => _telemetry.battery;
  VehicleStatus get vehicle => _telemetry.vehicle;
  final ScooterIdentity identity = ScooterIdentity();

  Map<String, SavedScooter>? _demoScooters;
  Map<String, SavedScooter> get savedScooters => _demoScooters ?? store.scooters;
  set savedScooters(Map<String, SavedScooter> value) {
    if (_demoScooters != null) {
      _demoScooters = value;
    } else {
      store.scooters = value;
    }
  }

  bool get demoMode => _demoScooters != null;
  String? get mostRecentSavedScooterId => store.getMostRecent()?.id;

  // The shared session owns the link; legacy command adapters read this view.
  BluetoothDevice? get myScooter => _session.device;
  set myScooter(BluetoothDevice? value) => _session.device = value;
  String? get currentScooterId => _session.device?.remoteId.toString();
  Object? get connectionToken => _session.currentConnection?.isCurrent == true ? _session.currentConnection : null;
  String? get selectedScooterId => _session.manualTargetId ?? currentScooterId ?? mostRecentSavedScooterId;
  void disconnectAndClearDevice() => _session.disconnectAndClearDevice();
  CharacteristicRepository get characteristicRepository =>
      _telemetry.currentRepository ?? (throw StateError('Scooter characteristics are unavailable'));
  bool get alarmAvailable => _telemetry.alarmAvailable;
  bool get otaAvailable => _telemetry.otaAvailable;
  String? get connectingScooterId => _session.connectingScooterId;
  late final UpdateController updateController;
  String? updateTargetName;
  late final NavigationRuntime navigation;
  late final ScooterActions actions;
  final _actionWarnings = StreamController<HandlebarWarning>.broadcast(sync: true);
  Stream<HandlebarWarning> get actionWarnings => _actionWarnings.stream;
  bool get autoUnlockCoolingDown => actions.coolingDown;

  /// In-range scooters with auto-unlock enabled, the connected one included.
  /// Refreshed from a throttled scan on the keyless poll cycle.
  int _autoUnlockScootersInRange = 0;
  Set<String> _scootersInRange = const {};
  bool _scooterPresenceKnown = false;
  String? _autoConnectPriorityId;
  bool _presenceScanRunning = false;
  Set<String> get scootersInRange => _scootersInRange;
  bool get scooterPresenceKnown => _scooterPresenceKnown;
  String? get autoConnectPriorityId => _autoConnectPriorityId;
  DateTime? _autoUnlockAmbiguityCheckedAt;
  bool _ambiguityScanRunning = false;
  static const int _autoUnlockAmbiguityTtlSeconds = 60;
  Future<Map<String, String?>> readInstalledVersions() => actions.readInstalledVersions();

  late ActionPollingTimer rssiTimer;
  late bool isInBackgroundService;
  final FlutterBluePlusMockable flutterBluePlus;
  bool _automaticActionsAllowed;
  bool _connectionsPaused;
  bool get connectionsPaused => _connectionsPaused;

  /// Set while the proximity countdown runs. The button fills for that window.
  DateTime? _keylessPendingSince;

  // Passthrough for optionalAuth (used by home_screen for biometrics)
  bool get optionalAuth => settings.optionalAuth;
  set optionalAuth(bool value) => settings.optionalAuth = value;

  void _telemetryChanged() => notifyListeners();
  void _sessionTargetChanged() => notifyListeners();

  void ping() => _pingScooter(myScooter?.remoteId.toString());

  void _pingScooter(String? scooterId) {
    try {
      savedScooters[scooterId]!.lastPing = DateTime.now();
      lastPing = DateTime.now();
      notifyListeners();
    } catch (e, stack) {
      log.severe("Couldn't save ping", e, stack);
    }
  }

  // On initialization...
  /// Set [initializeRuntime] to false for manually driven tests: settings and
  /// scanner remain available, but cache restore, observers and timers do not run.
  /// In that mode [rssiTimer] is not initialized.
  ScooterService(
    this.flutterBluePlus, {
    this.isInBackgroundService = false,
    ScooterStorage? storage,
    BluetoothDevice Function(String)? deviceFromId,
    CharacteristicRepository Function(BluetoothDevice)? repositoryFactory,
    Future<LatLng?> Function()? pollLocation,
    bool initializeRuntime = true,
    bool allowAutomaticActions = true,
    bool connectionsPaused = false,
    Duration Function()? manualTargetElapsed,
  })  : store = storage ?? ScooterStorage(),
        _deviceFromId = deviceFromId ?? BluetoothDevice.fromId,
        _readLocation = pollLocation ?? location.pollLocation,
        _runtimeInitialized = initializeRuntime,
        _automaticActionsAllowed = allowAutomaticActions,
        _connectionsPaused = connectionsPaused {
    settings = UserSettings(isInBackgroundService: isInBackgroundService);
    scanner = BleScanner(flutterBluePlus);
    _telemetry = ScooterTelemetry(effects: _ServiceTelemetryEffects(this), identity: identity);
    _session = ScooterSession(
      flutterBluePlus: flutterBluePlus,
      deviceFromId: _deviceFromId,
      repositoryFactory: repositoryFactory,
      effects: _ServiceSessionEffects(this),
      onChanged: notifyListeners,
      findEligibleScooter: () => findEligibleScooter(),
      isScanning: () => scanning,
      onStart: () {
        Future.delayed(const Duration(milliseconds: 1500), FlutterNativeSplash.remove);
      },
    );
    updateController = UpdateController(
        session: _session,
        provider: AppUpdateReleaseProvider(),
        channel: 'stable',
        cacheDirectory: () async => Directory('${(await getApplicationSupportDirectory()).path}/ota'),
        onTargetCaptured: (id) => updateTargetName = savedScooters[id]?.name ?? id);
    actions = ScooterActions(
        session: _session,
        telemetry: _telemetry,
        settings: () => ActionSettings(
            openSeatOnUnlock: settings.openSeatOnUnlock,
            hazardLocking: settings.hazardLocking,
            warnOfUnlockedHandlebars: settings.warnOfUnlockedHandlebars,
            autoUnlock: _automaticActionsAllowed && settings.autoUnlock,
            autoUnlockPaused: keylessPaused,
            autoUnlockThreshold: settings.autoUnlockThreshold,
            optionalAuth: settings.optionalAuth,
            autoUnlockAmbiguous: _autoUnlockScootersInRange > 1),
        location: () => lastLocation == null ? null : ActionLocation(lastLocation!.latitude, lastLocation!.longitude),
        effects: _ServiceActionEffects(this));
    final navigationPreferences = SharedPreferencesAsync();
    navigation = NavigationRuntime(
      loadPending: () => navigationPreferences.getString('pendingNavigation'),
      savePending: (json) async {
        if (json == null) {
          await navigationPreferences.remove('pendingNavigation');
        } else {
          await navigationPreferences.setString('pendingNavigation', json);
        }
      },
      decodeDestination: NavDestination.fromJson,
      changed: notifyListeners,
      failed: (error, stack) => log.warning('Pending navigation dispatch failed', error, stack),
    );
    runtime = ScooterRuntime<SavedScooter>(
        session: _session,
        telemetry: _telemetry,
        actions: actions,
        navigation: navigation,
        settings: settings,
        store: store,
        idOf: (scooter) => scooter.id,
        cacheOf: _cachedTelemetry,
        presentCache: _presentCachedScooter,
        changed: notifyListeners,
        savedChanged: () => updateBackgroundService({"updateSavedScooters": true}),
        manualTargetHeartbeat: (target) => updateBackgroundService({"manualConnectionTarget": target}),
        scanningChanged: (value) => scanning = value,
        isScanning: () => scanning,
        readLocation: _readLocation,
        saveLocation: (id, position) => savedScooters[id]?.lastLocation = position,
        publishDisconnected: () => state = ScooterState.disconnected,
        automaticConnectionAllowed: () => !_connectionsPaused,
        manualTargetElapsed: manualTargetElapsed,
        deviceFromId: _deviceFromId);
    if (!_runtimeInitialized) return;
    runtime.initialize();
    if (!isInBackgroundService) WidgetsBinding.instance.addObserver(this);
    rssiTimer = actions.rssiTimer;
  }

  Future<SavedScooter?> getMostRecentScooter() => runtime.getMostRecentScooter();

  void updateScooterPing(String id) async {
    store.updatePing(id);
    updateBackgroundService({"updateSavedScooters": true});
  }

  void _presentCachedScooter(SavedScooter? scooter, {bool initial = false}) {
    if (initial) identity.rssi = null;
    identity.lastPing = scooter?.lastPing;
    identity.name = scooter?.name;
    identity.color = scooter?.color;
    identity.lastLocation = scooter?.lastLocation;
  }

  void _showCachedScooter(SavedScooter? scooter) {
    _presentCachedScooter(scooter);
    identity.rssi = null;
    _telemetry.seed(_cachedTelemetry(scooter));
    notifyListeners();
  }

  void addDemoData() {
    if (connected || demoMode) return;
    stopAutoRestart(clearManualTarget: false);
    _session.foundScooter = true;
    flutterBluePlus.stopScan();
    _demoScooters = {
      "12345": SavedScooter(
        name: "Demo Scooter",
        id: "12345",
        color: 0,
        lastPing: DateTime.now(),
        lastLocation: const LatLng(0, 0),
        lastPrimarySOC: 53,
        lastSecondarySOC: 100,
        lastCbbSOC: 98,
        lastAuxSOC: 100,
      ),
      "678910": SavedScooter(
        name: "Demo Scooter 2",
        id: "678910",
        color: 2,
        lastPing: DateTime.now(),
        lastLocation: const LatLng(0, 0),
        lastPrimarySOC: 53,
        lastSecondarySOC: 100,
        lastCbbSOC: 98,
        lastAuxSOC: 100,
      ),
    };

    myScooter = BluetoothDevice(remoteId: const DeviceIdentifier("12345"));

    battery.primarySOC = 53;
    battery.secondarySOC = 100;
    battery.cbbSOC = 98;
    battery.cbbVoltage = 3700;
    battery.cbbCapacity = 3000;
    battery.cbbCharging = false;
    battery.auxSOC = 100;
    battery.auxVoltage = 15000;
    battery.auxCharging = AUXChargingState.absorptionCharge;
    battery.primaryCycles = 190;
    battery.secondaryCycles = 75;
    _session.setConnected(true, notify: false);
    _state = ScooterState.parked;
    vehicle.seatClosed = true;
    vehicle.handlebarsLocked = false;
    vehicle.navigationActive = false;
    identity.lastPing = DateTime.now();
    identity.name = "Demo Scooter";
    identity.color = 0;
    identity.lastLocation = const LatLng(0, 0);
    identity.nrfVersion = "demo-ls";
    identity.imxVersion = "demo";
    identity.isLibrescoot = true;
    notifyListeners();
  }

  void removeDemoData() {
    if (!demoMode) return;
    stopAutoRestart(clearManualTarget: false);
    _session.foundScooter = false;
    _session.setConnected(false, notify: false);
    myScooter = null;
    _demoScooters = null;
    _telemetry.invalidate();
    identity.odometerMeters = null;
    final recentId = mostRecentSavedScooterId;
    _showCachedScooter(recentId == null ? null : store.scooters[recentId]);
    _state = ScooterState.disconnected;
    notifyListeners();
    if (store.scooters.isNotEmpty) startAutoRestart();
  }

  // Compatibility presentation views; state and execution belong to shared navigation.
  NavDestination? get pendingNavigation =>
      navigation.pending == null ? null : NavDestination.fromDestination(navigation.pending!);
  NavDestination? get activeNavigation =>
      navigation.active == null ? null : NavDestination.fromDestination(navigation.active!);
  void setActiveNavigation(NavDestination? destination) => navigation.setActive(destination);
  Future<void> setPendingNavigation(NavDestination? destination) => navigation.setPending(destination);

  // Multi-hop route plan. The runtime owns the state; the app presents it.
  List<NavDestination> get routePlanStops {
    final stops = navigation.plan?.stops;
    if (stops == null) return const [];
    return stops.map(NavDestination.fromDestination).toList();
  }

  int get routePlanStep => navigation.plan?.currentStep ?? 0;
  bool get hasRoutePlan => navigation.plan?.isNotEmpty ?? false;

  Future<void> refreshRoutePlan() => navigation.refreshPlan();
  Future<List<NavDestination>> routePlanFavorites() async =>
      (await navigation.listFavorites()).map(NavDestination.fromDestination).toList();
  Future<void> addRouteStop(NavDestination stop) => navigation.addStop(stop);
  Future<void> removeRouteStop(int index) => navigation.removeStopAt(index);
  Future<void> skipRouteStop() => navigation.skipStop();
  Future<void> clearRoutePlan() => navigation.clearPlan();
  Future<void> reorderRoutePlan(List<NavDestination> ordered) => navigation.reorderPlan(ordered);

  // STATUS STREAMS
  bool get connected => _session.connected;
  set connected(bool connected) => _session.connected = connected;

  ScooterState? get _state => _telemetry.state;
  set _state(ScooterState? value) => _telemetry.state = value;
  ScooterState? get state => _state;
  set state(ScooterState? state) {
    _state = state;
    notifyListeners();
    actions.telemetryChanged();
  }

  // Passthrough getters for vehicle status
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  ScooterPowerState? get powerState => vehicle.powerState;
  bool? get seatClosed => vehicle.seatClosed;
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  bool? get navigationActive => vehicle.navigationActive;

  // Read-only total distance reported by Librescoot, in metres.
  int? get odometerMeters => identity.odometerMeters;
  int? get cachedOdometerMeters => settingsTargetScooter?.cachedOdometerMeters;
  TripCounterSnapshot? get cachedTripCounter => settingsTargetScooter?.cachedTripCounter;

  void refreshOdometer() {
    if (connected) _telemetry.refreshOdometer();
  }

  bool? get tripCounterSupported => identity.supportsTripCounter;
  TripCounterSnapshot? get tripCounter => _telemetry.tripCounter;
  bool get tripCounterLoading => _telemetry.tripLoading;
  Future<TripCounterSnapshot?> refreshTripCounter() async {
    final scooterId = currentScooterId;
    final snapshot = await _telemetry.refreshTripCounter();
    _cacheTripCounter(scooterId, snapshot);
    return snapshot;
  }

  Future<void> setTripCounterResetPolicy(TripResetPolicy policy) async {
    final scooterId = currentScooterId;
    await _telemetry.setTripCounterResetPolicy(policy);
    _cacheTripCounter(scooterId, _telemetry.tripCounter);
  }

  Future<void> resetTripCounter() async {
    final scooterId = currentScooterId;
    await _telemetry.resetTripCounter();
    _cacheTripCounter(scooterId, _telemetry.tripCounter);
  }

  void _cacheTripCounter(String? scooterId, TripCounterSnapshot? snapshot) {
    if (snapshot != null && scooterId != null && currentScooterId == scooterId) {
      savedScooters[scooterId]?.cacheTripCounter(snapshot);
    }
  }

  bool? get tripExpungeSupported => identity.supportsTripExpunge;
  TripExpunge? get tripExpunge => _telemetry.tripExpunge;
  bool get tripExpungeLoading => _telemetry.tripExpungeLoading;
  Future<TripExpunge?> refreshTripExpunge() => _telemetry.refreshTripExpunge();
  Future<void> setTripExpunge(TripExpunge policy) => _telemetry.setTripExpunge(policy);

  // Passthrough getters for battery state
  int? get primarySOC => battery.primarySOC;
  int? get secondarySOC => battery.secondarySOC;

  // Passthrough getters for identity
  String? get scooterName => identity.name;
  set scooterName(String? value) {
    identity.name = value;
    notifyListeners();
  }

  DateTime? get lastPing => identity.lastPing;
  set lastPing(DateTime? value) {
    identity.lastPing = value;
    notifyListeners();
  }

  int? get scooterColor => identity.color;
  set scooterColor(int? value) {
    identity.color = value;
    notifyListeners();
    updateBackgroundService({"scooterColor": value});
  }

  LatLng? get lastLocation => identity.lastLocation;

  int? get rssi => identity.rssi;
  set rssi(int? value) {
    identity.rssi = value;
    notifyListeners();
  }

  bool _scanning = false;
  bool get scanning => _scanning;
  set scanning(bool scanning) {
    log.info("Scanning: $scanning");
    _scanning = scanning;
    notifyListeners();
  }

  // MAIN FUNCTIONS

  void _publishScooterPresence(Set<String> ids, {String? priorityId}) {
    final next = Set<String>.unmodifiable(ids);
    final changed =
        !setEquals(_scootersInRange, next) || !_scooterPresenceKnown || _autoConnectPriorityId != priorityId;
    _scootersInRange = next;
    _scooterPresenceKnown = true;
    _autoConnectPriorityId = priorityId;
    if (changed) notifyListeners();
  }

  void _recordScooterInRange(String id) {
    if (_scootersInRange.contains(id)) return;
    _publishScooterPresence({..._scootersInRange, id}, priorityId: _autoConnectPriorityId);
  }

  /// Best-effort presence snapshot for the scooter picker. Existing connection
  /// scans also update this state, so opening the screen does not need to own a
  /// continuous BLE scan.
  Future<void> refreshScooterPresence() async {
    if (_presenceScanRunning || scanning || connectingScooterId != null) return;
    _presenceScanRunning = true;
    try {
      final ids = savedScooters.keys.toList();
      final inRange = await scanner.idsInRange(ids, settle: const Duration(seconds: 2));
      final current = currentScooterId;
      if (current != null) inRange.add(current);
      _publishScooterPresence(
        inRange,
        priorityId: inRange.contains(_autoConnectPriorityId) ? _autoConnectPriorityId : null,
      );
    } catch (e, stack) {
      log.warning("Couldn't refresh scooter presence", e, stack);
    } finally {
      _presenceScanRunning = false;
    }
  }

  Future<BluetoothDevice?> findEligibleScooter({
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    stopAutoRestart();

    final found = await scanner.findEligibleScooters(
      getIds: getSavedScooterIds,
      excludedScooterIds: excludedScooterIds,
      includeSystemScooters: includeSystemScooters,
    );
    if (found.isEmpty) {
      _publishScooterPresence(const {});
      return null;
    }
    // Everything in range is known before anything is chosen, so the scooter
    // used most recently wins instead of whichever answered the scan first.
    DateTime lastPingOf(BluetoothDevice device) =>
        savedScooters[device.remoteId.toString()]?.lastPing ?? DateTime.fromMillisecondsSinceEpoch(0);
    final autoConnect =
        found.where((device) => savedScooters[device.remoteId.toString()]?.autoConnect == true).toList();
    final pool = autoConnect.isEmpty ? found : autoConnect;
    pool.sort((a, b) => lastPingOf(b).compareTo(lastPingOf(a)));
    final chosen = pool.first;
    _publishScooterPresence(
      found.map((device) => device.remoteId.toString()).toSet(),
      priorityId: chosen.remoteId.toString(),
    );
    return chosen;
  }

  /// Live list of scooters the user could pick from, growing while the scan
  /// runs. Unlike [findEligibleScooter] this reports everything it finds and
  /// leaves the choice to the caller, and it includes scooters this phone has
  /// already bonded, which a scan on its own cannot see.
  Stream<List<ScooterCandidate>> discoverScooters({
    List<String> excludedScooterIds = const [],
    Duration timeout = const Duration(seconds: 30),
    bool androidCheckLocationServices = true,
  }) {
    stopAutoRestart();

    return scanner.discoverScooters(
      getIds: getSavedScooterIds,
      excludedScooterIds: excludedScooterIds,
      timeout: timeout,
      androidCheckLocationServices: androidCheckLocationServices,
    );
  }

  Future<void> connectToScooterId(
    String id, {
    bool automatic = false,
    int? expectedIntentGeneration,
  }) async {
    if (!automatic && _connectionsPaused) await setConnectionsPaused(false);
    return _session.connectToScooterId(
      id,
      automatic: automatic,
      expectedIntentGeneration: expectedIntentGeneration,
    );
  }

  Future<void> setConnectionsPaused(bool paused, {bool publish = true}) async {
    _connectionsPaused = paused;
    final persistence = SharedPreferencesAsync().setBool(connectionPausedPreferenceKey, paused);
    if (paused) {
      stopAutoRestart();
      disconnectAndClearDevice();
      _session.setConnected(false, notify: false);
      _telemetry.invalidate();
      state = ScooterState.disconnected;
    }
    await persistence;
    if (paused) {
      try {
        final prefs = SharedPreferencesAsync();
        await prefs.setBool('pendingWidgetAction', false);
        await prefs.remove('pendingWidgetActionName');
      } catch (error, stack) {
        log.warning("Couldn't clear pending widget work while disconnecting", error, stack);
      }
    }
    if (publish) updateBackgroundService({"connectionPaused": paused});
  }

  Future<void> pauseConnections() => setConnectionsPaused(true);

  void start({bool restart = true}) => runtime.start(restart: restart);

  void startAutoRestart({String? targetScooterId}) {
    if (!_connectionsPaused) _session.startAutoRestart(targetScooterId: targetScooterId);
  }

  void stopAutoRestart({bool clearManualTarget = true}) =>
      _session.stopAutoRestart(clearManualTarget: clearManualTarget);

  SavedScooter? get settingsTargetScooter {
    final String? id = currentScooterId ?? mostRecentSavedScooterId;
    return id == null ? null : savedScooters[id];
  }

  void setAutoUnlock(bool enabled) {
    unawaited(settings.setAutoUnlock(enabled));
    unawaited(refreshAutoUnlockAmbiguity(force: true));
    notifyListeners();
  }

  /// Controls automatic proximity actuation for this runtime without changing
  /// the user's persisted keyless preference. Explicit user/widget actions are
  /// unaffected.
  void setAutomaticActionsAllowed(bool allowed) {
    _automaticActionsAllowed = allowed;
  }

  void setAutoUnlockThreshold(int threshold) {
    settings.setAutoUnlockThreshold(threshold);
  }

  void setOpenSeatOnUnlock(bool enabled) {
    unawaited(settings.setOpenSeatOnUnlock(enabled));
    notifyListeners();
  }

  void setHazardLocking(bool enabled) {
    unawaited(settings.setHazardLocking(enabled));
    notifyListeners();
  }

  bool get autoUnlock => settings.autoUnlock;

  /// True while proximity unlocking is suspended for the target scooter. The
  /// keyless setting itself is unchanged.
  bool get keylessPaused => settingsTargetScooter?.keylessPaused ?? false;

  /// Non-null while proximity has been met and the unlock is counting down.
  DateTime? get keylessPendingSince => _keylessPendingSince;

  void _keylessPendingChanged(bool pending) {
    _keylessPendingSince = pending ? DateTime.now() : null;
    notifyListeners();
  }

  void setKeylessPaused(bool paused) {
    final scooter = settingsTargetScooter;
    if (scooter == null) return;
    scooter.keylessPaused = paused;
    // A pause has to reach a countdown that is already running.
    if (paused) actions.cancelAutoUnlock();
    notifyListeners();
  }

  /// Clears the keyless pause; called for manual unlocks and park transitions.
  void rearmKeyless() {
    if (settingsTargetScooter?.keylessPaused == true) setKeylessPaused(false);
  }

  void _rearmKeylessOnPark(ScooterState? previous, ScooterState? next) {
    if (next != ScooterState.parked || previous == ScooterState.parked) return;
    rearmKeyless();
  }

  int get autoUnlockThreshold => settings.autoUnlockThreshold;
  bool get openSeatOnUnlock => settings.openSeatOnUnlock;
  bool get hazardLocking => settings.hazardLocking;

  /// Refuse proximity unlocking when multiple saved scooters are in range.
  /// Best effort: a failed scan leaves the previous answer in place.
  Future<void> refreshAutoUnlockAmbiguity({bool force = false}) async {
    if (!settings.autoUnlock) {
      _autoUnlockScootersInRange = 0;
      return;
    }
    final checkedAt = _autoUnlockAmbiguityCheckedAt;
    if (!force &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < const Duration(seconds: _autoUnlockAmbiguityTtlSeconds)) {
      return;
    }
    if (_ambiguityScanRunning) return;
    _ambiguityScanRunning = true;
    try {
      final watching = savedScooters.keys.toList();
      final inRange = await scanner.idsInRange(watching);
      final connected = currentScooterId;
      // The scooter we are connected to is in range by definition, and it does
      // not advertise while connected, so the scan cannot see it.
      final int connectedIncluded =
          connected != null && watching.contains(connected) && !inRange.contains(connected) ? 1 : 0;
      _autoUnlockScootersInRange = inRange.length + connectedIncluded;
      _autoUnlockAmbiguityCheckedAt = DateTime.now();
      if (_autoUnlockScootersInRange > 1) {
        log.warning("$_autoUnlockScootersInRange scooters in range have auto-unlock on; "
            "proximity will not unlock");
      }
    } catch (e, stack) {
      log.warning("Couldn't check which scooters are in range", e, stack);
    } finally {
      _ambiguityScanRunning = false;
    }
  }

  // SCOOTER ACTIONS

  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) {
    rearmKeyless();
    actions.cancelAutoUnlock();
    return actions.unlock(checkHandlebars: checkHandlebars, source: source);
  }

  Future<void> lock({bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) {
    warnIfLockingWithOpenSeatbox();
    return actions.lock(checkHandlebars: checkHandlebars, confirmOpenSeat: confirmOpenSeat, source: source);
  }

  /// App-only diagnostic; explicit consumers call this only at ready dispatch.
  void warnIfLockingWithOpenSeatbox() {
    if (vehicle.seatClosed == false) log.warning("Locking with open seatbox!");
  }

  Future<void> wakeUpAndUnlock({EventSource? source}) {
    rearmKeyless();
    actions.cancelAutoUnlock();
    return actions.wakeUpAndUnlock(source: source);
  }

  void autoUnlockCooldown() => actions.autoUnlockCooldown();
  Future<void> openSeat({EventSource source = EventSource.app}) => actions.openSeat(source: source);

  /// Silences a sounding alarm without changing the alarm setting. The alarm
  /// service re-arms it as usual once the scooter is parked again.
  Future<void> disarmAlarm() => actions.disarmAlarm();
  Future<void> blink({required bool left, required bool right}) => actions.blink(left: left, right: right);
  Future<void> hazard({int times = 1}) => actions.hazard(times: times);
  Future<void> wakeUp() => actions.wakeUp();
  Future<void> hibernate() => actions.hibernate();
  Future<void> hibernateFor(Duration wakeAfter) => actions.hibernateFor(wakeAfter);
  Future<String?> getCellularApn() => actions.getSetting(commands.lsKeyCellularApn);
  Future<void> setCellularApn(String apn) => actions.setCellularApn(apn);
  Future<void> clearCellularApn() => actions.clearCellularApn();
  Future<bool?> getBatteryKeepActive() => actions.getBoolSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen);
  Future<void> setBatteryKeepActive(bool enabled) =>
      actions.setSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen, enabled.toString());
  Future<bool?> getAlarmEnabled() => actions.getBoolSetting(commands.lsKeyAlarmEnabled);
  Future<void> setAlarmEnabled(bool enabled) => actions.setSetting(commands.lsKeyAlarmEnabled, enabled.toString());
  Future<bool?> getAlarmHonk() => actions.getBoolSetting(commands.lsKeyAlarmHonk);
  Future<void> setAlarmHonk(bool enabled) => actions.setSetting(commands.lsKeyAlarmHonk, enabled.toString());
  Future<void> reboot() => actions.reboot();
  Future<void> hardReboot() => actions.hardReboot();

  void _pollLocation() => runtime.pollLocation();

  static Future<void> sendStaticPowerCommand(String id, String command) async {
    await commands.sendStaticPowerCommand(id, command);
  }

  void setManualConnectionTarget(String? id) => runtime.setManualConnectionTarget(id);
  void touchManualConnectionTarget() => runtime.touchManualConnectionTarget();
  Future<WidgetActionDispatch?> prepareWidgetAction(String actionName) => switch (actionName) {
        'lock' => runtime.prepareExplicitAction(EventType.lock),
        'unlock' => runtime.prepareExplicitAction(EventType.unlock),
        'openseat' => runtime.prepareExplicitAction(EventType.openSeat),
        _ => Future.value(null),
      };
  Future<bool> attemptLatestAutoConnection() => runtime.attemptLatestAutoConnection();

  Future<void> refetchSavedScooters() => runtime.refetchSavedScooters();

  Future<List<String>> getSavedScooterIds({
    bool onlyAutoConnect = false,
  }) async {
    return store.getIds(onlyAutoConnect: onlyAutoConnect);
  }

  Future<void> forgetSavedScooter(String id) => runtime.forgetSavedScooter(id);

  // Keep the public fire-and-forget API; shared runtime owns mutation/selection.
  void renameSavedScooter({String? id, required String name}) => runtime.renameSavedScooter(
        id: id,
        name: name,
        missingId: () => log.warning(
          "Attempted to rename scooter, but no ID was given and we're not connected to anything!",
        ),
        publish: (isMostRecent) {
          if (isMostRecent) scooterName = name;
          updateBackgroundService({
            "updateSavedScooters": true,
            if (isMostRecent) "scooterName": name,
          });
        },
      );

  void recolorSavedScooter({String? id, required int color}) => runtime.recolorSavedScooter(
        id: id,
        color: color,
        missingId: () => log.warning(
          "Attempted to recolor scooter, but no ID was given and we're not connected to anything!",
        ),
        publish: (isMostRecent) {
          if (isMostRecent) scooterColor = color;
          updateBackgroundService({
            "updateSavedScooters": true,
            if (isMostRecent) "scooterColor": color,
          });
        },
      );

  void updateBackgroundService(dynamic data) {
    if (!isInBackgroundService) {
      FlutterBackgroundService().invoke("update", data);
    }
  }

  void addSavedScooter(String id) => runtime.addSavedScooter(id, () {
        scooterName = "Scooter Pro";
        notifyListeners();
      });

  @override
  void dispose() {
    runtime.dispose();
    updateController.dispose();
    navigation.dispose();
    actions.dispose();
    _actionWarnings.close();
    _session.dispose();
    _telemetry.dispose();

    // Unregister lifecycle observer
    if (_runtimeInitialized && !isInBackgroundService) {
      WidgetsBinding.instance.removeObserver(this);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      runtime.didChangeAppLifecycleState(state);
      return;
    }
    unawaited(() async {
      _connectionsPaused = await SharedPreferencesAsync().getBool(connectionPausedPreferenceKey) ?? false;
      runtime.didChangeAppLifecycleState(state);
    }());
  }
}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}

/// Only model/publication and application integrations cross this boundary.
class _ServiceSessionEffects implements ScooterSessionEffects {
  _ServiceSessionEffects(this.service);
  final ScooterService service;

  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {
    service._sessionTargetChanged();
    service.updateBackgroundService({
      "manualConnectionTarget": id ?? "",
      if (includeMetadata) "scooterName": service.savedScooters[id]?.name,
      if (includeMetadata) "scooterColor": service.savedScooters[id]?.color,
    });
  }

  @override
  void invalidateTelemetry() {
    service.updateController.invalidate();
    service.navigation.invalidate();
    service.actions.invalidate();
    service._telemetry.invalidate();
  }

  @override
  void linking(SessionConnection connection) {
    service.state = ScooterState.linking;
    if (!connection.isCurrentAttempt) return;
    service._showCachedScooter(service.savedScooters[connection.id]);
  }

  @override
  void transportConnected(SessionConnection connection) {
    service._recordScooterInRange(connection.id);
    service._telemetry.prepare(_cachedTelemetry(service.savedScooters[connection.id]));
    service.addSavedScooter(connection.id);
  }

  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {
    await HomeWidget.setAppGroupId('group.com.librescoot.app');
    if (!connection.isCurrent) return;
    passToWidget(scooterId: connection.id);
    service.log.info("Saved scooter ID to widget: ${connection.id}");
  }

  @override
  void wireTelemetry(SessionConnection connection, CharacteristicRepository repository) {
    service.updateController.bind(connection, repository);
    service.navigation.bind(connection, repository);
    service.actions.bind(connection, repository);
    service._telemetry.bind(connection, repository);
  }

  @override
  void readyMetadata(SessionConnection connection) {
    service.scooterName = service.savedScooters[connection.id]?.name;
    if (!connection.isCurrent) return;
    service.scooterColor = service.savedScooters[connection.id]?.color;
  }

  @override
  void ready(SessionConnection connection) {
    service.updateController.sessionReady();
    service._pollLocation();
    service.updateBackgroundService({
      "scooterName": service.savedScooters[connection.id]?.name,
      "scooterColor": service.savedScooters[connection.id]?.color,
      "lastPingInt": DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void disconnected(String? id) {
    service.updateController.invalidate();
    service.navigation.invalidate();
    service.actions.invalidate();
    service._telemetry.invalidate();
    service.state = ScooterState.disconnected;
    if (id != null) service.updateScooterPing(id);
    // Telemetry has stopped, so nothing will carry the coalesced writes out.
    unawaited(SavedScooter.flushPendingWrites());
  }
}

CachedTelemetry _cachedTelemetry(SavedScooter? scooter) => CachedTelemetry(
    primarySOC: scooter?.lastPrimarySOC,
    secondarySOC: scooter?.lastSecondarySOC,
    cbbSOC: scooter?.lastCbbSOC,
    auxSOC: scooter?.lastAuxSOC,
    handlebarsLocked: scooter?.handlebarsLocked,
    isLibrescoot: scooter?.isLibrescoot,
    supportsHibernateFor: scooter?.supportsHibernateFor,
    supportsApnConfig: scooter?.supportsApnConfig,
    supportsAlarmControl: scooter?.supportsAlarmControl,
    supportsTripCounter: scooter?.supportsTripCounter,
    supportsTripExpunge: scooter?.supportsTripExpunge,
    supportsScheduledHibernation: scooter?.supportsScheduledHibernation,
    supportsBatteryKeepActive: scooter?.supportsBatteryKeepActive);

bool _sameTripCounter(TripCounterSnapshot? a, TripCounterSnapshot b) =>
    a != null &&
    a.distanceMeters == b.distanceMeters &&
    a.ridingSeconds == b.ridingSeconds &&
    a.averageSpeedKph == b.averageSpeedKph &&
    a.resetPolicy == b.resetPolicy &&
    a.lastReset?.seconds == b.lastReset?.seconds &&
    a.lastResetReason == b.lastResetReason &&
    a.generation == b.generation &&
    a.status == b.status;

class _ServiceTelemetryEffects implements ScooterTelemetryEffects {
  _ServiceTelemetryEffects(this.service);
  final ScooterService service;

  @override
  void cachePatch(String scooterId, TelemetryCachePatch patch) {
    final saved = service.savedScooters[scooterId];
    if (saved == null) return;
    if (patch.primarySOC != null) saved.lastPrimarySOC = patch.primarySOC;
    if (patch.secondarySOC != null) saved.lastSecondarySOC = patch.secondarySOC;
    if (patch.cbbSOC != null) saved.lastCbbSOC = patch.cbbSOC;
    if (patch.auxSOC != null) saved.lastAuxSOC = patch.auxSOC;
    if (patch.handlebarsLocked != null) saved.handlebarsLocked = patch.handlebarsLocked;
    if (patch.isLibrescoot != null) saved.isLibrescoot = patch.isLibrescoot;
    if (patch.supportsHibernateFor != null) saved.supportsHibernateFor = patch.supportsHibernateFor;
    if (patch.supportsApnConfig != null) saved.supportsApnConfig = patch.supportsApnConfig;
    if (patch.supportsAlarmControl != null) saved.supportsAlarmControl = patch.supportsAlarmControl;
    if (patch.supportsTripCounter != null) saved.supportsTripCounter = patch.supportsTripCounter;
    if (patch.supportsTripExpunge != null) saved.supportsTripExpunge = patch.supportsTripExpunge;
    if (patch.supportsScheduledHibernation != null) {
      saved.supportsScheduledHibernation = patch.supportsScheduledHibernation;
    }
    if (patch.supportsBatteryKeepActive != null) {
      saved.supportsBatteryKeepActive = patch.supportsBatteryKeepActive;
    }
  }

  @override
  void ping(String scooterId) => service._pingScooter(scooterId);

  @override
  void changed(TelemetrySnapshot snapshot) {
    final scooterId = snapshot.scooterId;
    final odometer = snapshot.firmware.odometerMeters;
    final saved = scooterId == null ? null : service.savedScooters[scooterId];
    if (saved != null && odometer != null && saved.cachedOdometerMeters != odometer) {
      saved.cacheOdometer(odometer);
    }
    final trip = service._telemetry.tripCounter;
    if (saved != null && trip != null && !_sameTripCounter(saved.cachedTripCounter, trip)) {
      saved.cacheTripCounter(trip);
    }
    service._telemetryChanged();
    service.actions.telemetryChanged();
  }

  @override
  void firmwareIdentified(SessionConnection connection, FirmwareSnapshot firmware) {
    service.navigation.firmwareIdentified(connection, firmware);
  }

  @override
  void navigationChanged(bool? active) {
    service.navigation.navigationChanged(active);
  }

  @override
  void aggregateTransition(ScooterState? previous, ScooterState? next) {
    service._rearmKeylessOnPark(previous, next);
    service.actions.aggregateTransition(previous, next);
  }

  @override
  void probeFailed(String message, Object error, StackTrace stack) => service.log.warning(message, error, stack);
}

class _ServiceActionEffects implements ScooterActionEffects {
  _ServiceActionEffects(this.service);
  final ScooterService service;
  @override
  void acknowledged(ActionEvent event) => acknowledgeAppAction(event);
  @override
  void handlebarWarning(HandlebarWarning warning) {
    service.log.warning(
        warning.didNotUnlock ? "Handlebars didn't unlock, sending warning" : "Handlebars didn't lock, sending warning");
    final connection = service._session.currentConnection;
    if (connection?.isCurrent != true ||
        connection!.id != warning.action.scooterId ||
        connection.generation != warning.action.generation) {
      return;
    }
    service._actionWarnings.add(warning);
  }

  @override
  void cooldownStarted() {
    // FlutterBackgroundService is the UI-isolate facade, not ServiceInstance.
    // Always retain the local cooldown, but never relay from the service isolate.
    if (!service.isInBackgroundService) {
      try {
        FlutterBackgroundService().invoke("autoUnlockCooldown");
      } catch (_) {}
    }
  }

  @override
  void rssiChanged(int value) {
    service.rssi = value;
    service.log.info('RSSI: $value dBm');
    // Cheap no-op unless a scan is due, and the keyless decision happens right
    // after this on the same poll.
    unawaited(service.refreshAutoUnlockAmbiguity());
  }

  @override
  void autoUnlockPendingChanged(bool pending) => service._keylessPendingChanged(pending);

  @override
  void autoUnlockRefused() =>
      service.log.info("More than one scooter in range has auto-unlock on, so proximity did not unlock");
  @override
  void failed(Object error, StackTrace stack) => service.log.warning('Action effect failed', error, stack);
}

void acknowledgeAppAction(ActionEvent event) {
  if (event.kind == EventType.lock || event.kind == EventType.unlock) HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
      eventType: event.kind,
      scooterId: event.scooterId,
      source: event.source,
      soc1: event.primarySOC,
      soc2: event.secondarySOC,
      location: event.location == null ? null : LatLng(event.location!.latitude, event.location!.longitude));
}
