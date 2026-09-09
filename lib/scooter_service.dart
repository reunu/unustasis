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

  Map<String, SavedScooter> get savedScooters => store.scooters;
  set savedScooters(Map<String, SavedScooter> value) => store.scooters = value;

  // Legacy test/demo view only; production consumers use currentScooterId.
  // The shared session owns the actual link.
  @visibleForTesting
  BluetoothDevice? get myScooter => _session.device;
  @visibleForTesting
  set myScooter(BluetoothDevice? value) => _session.device = value;
  String? get currentScooterId => _session.device?.remoteId.toString();
  void disconnectAndClearDevice() => _session.disconnectAndClearDevice();
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

  late ActionPollingTimer rssiTimer;
  late bool isInBackgroundService;
  final FlutterBluePlusMockable flutterBluePlus;

  // Passthrough for optionalAuth (used by home_screen for biometrics)
  bool get optionalAuth => settings.optionalAuth;
  set optionalAuth(bool value) => settings.optionalAuth = value;

  void _telemetryChanged() => notifyListeners();

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
  }) : store = storage ?? ScooterStorage(),
       _deviceFromId = deviceFromId ?? BluetoothDevice.fromId,
       _readLocation = pollLocation ?? location.pollLocation,
       _runtimeInitialized = initializeRuntime {
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
    updateController = UpdateController(session: _session, provider: AppUpdateReleaseProvider(),
      channel: 'stable', cacheDirectory: () async => Directory('${(await getApplicationSupportDirectory()).path}/ota'),
      onTargetCaptured: (id) => updateTargetName = savedScooters[id]?.name ?? id);
    actions = ScooterActions(session: _session, telemetry: _telemetry,
      settings: () => ActionSettings(openSeatOnUnlock: settings.openSeatOnUnlock,
        hazardLocking: settings.hazardLocking, warnOfUnlockedHandlebars: settings.warnOfUnlockedHandlebars,
        autoUnlock: settings.autoUnlock, autoUnlockThreshold: settings.autoUnlockThreshold,
        optionalAuth: settings.optionalAuth),
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
    runtime = ScooterRuntime<SavedScooter>(session: _session, telemetry: _telemetry,
      actions: actions, navigation: navigation, settings: settings, store: store,
      idOf: (scooter) => scooter.id, cacheOf: _cachedTelemetry,
      presentCache: _presentCachedScooter, changed: notifyListeners,
      savedChanged: () => updateBackgroundService({"updateSavedScooters": true}),
      manualTargetHeartbeat: (target) => updateBackgroundService({"manualConnectionTarget": target}),
      scanningChanged: (value) => scanning = value, isScanning: () => scanning,
      readLocation: _readLocation,
      saveLocation: (id, position) => savedScooters[id]?.lastLocation = position,
      publishDisconnected: () => state = ScooterState.disconnected,
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
    stopAutoRestart(clearManualTarget: false);
    _session.foundScooter = true;
    flutterBluePlus.stopScan();
    savedScooters = {
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

    store.save();
    updateBackgroundService({"updateSavedScooters": true});
    passToWidget(
      scooterId: "12345",
    );
    notifyListeners();
  }

  // Shared state snapshots; Unustasis presentation still uses vehicle telemetry.
  NavDestination? get pendingNavigation => navigation.pending == null ? null : NavDestination.fromDestination(navigation.pending!);
  NavDestination? get activeNavigation => navigation.active == null ? null : NavDestination.fromDestination(navigation.active!);
  void setActiveNavigation(NavDestination? destination) => navigation.setActive(destination);
  Future<void> setPendingNavigation(NavDestination? destination) => navigation.setPending(destination);

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

  void refreshOdometer() {
    if (connected) _telemetry.refreshOdometer();
  }

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

  Future<BluetoothDevice?> findEligibleScooter({
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    stopAutoRestart();

    return scanner.findEligibleScooter(
      getIds: getSavedScooterIds,
      excludedScooterIds: excludedScooterIds,
      includeSystemScooters: includeSystemScooters,
    );
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
  }) => _session.connectToScooterId(
    id,
    automatic: automatic,
    expectedIntentGeneration: expectedIntentGeneration,
  );

  void start({bool restart = true}) => runtime.start(restart: restart);

  void startAutoRestart({String? targetScooterId}) =>
      _session.startAutoRestart(targetScooterId: targetScooterId);

  void stopAutoRestart({bool clearManualTarget = true}) =>
      _session.stopAutoRestart(clearManualTarget: clearManualTarget);

  void setAutoUnlock(bool enabled) {
    settings.setAutoUnlock(enabled);
  }

  void setAutoUnlockThreshold(int threshold) {
    settings.setAutoUnlockThreshold(threshold);
  }

  void setOpenSeatOnUnlock(bool enabled) {
    settings.setOpenSeatOnUnlock(enabled);
  }

  void setHazardLocking(bool enabled) {
    settings.setHazardLocking(enabled);
  }

  bool get autoUnlock => settings.autoUnlock;
  int get autoUnlockThreshold => settings.autoUnlockThreshold;
  bool get openSeatOnUnlock => settings.openSeatOnUnlock;
  bool get hazardLocking => settings.hazardLocking;

  // SCOOTER ACTIONS

  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) =>
      actions.unlock(checkHandlebars: checkHandlebars, source: source);
  Future<void> lock({bool checkHandlebars = true, bool ignoreSeatbox = false, EventSource source = EventSource.app}) {
    warnIfLockingWithOpenSeatbox();
    return actions.lock(checkHandlebars: checkHandlebars, ignoreSeatbox: ignoreSeatbox, source: source);
  }

  /// App-only diagnostic; explicit consumers call this only at ready dispatch.
  void warnIfLockingWithOpenSeatbox() {
    if (vehicle.seatClosed == false) log.warning("Locking with open seatbox!");
  }
  Future<void> wakeUpAndUnlock({EventSource? source}) => actions.wakeUpAndUnlock(source: source);
  void autoUnlockCooldown() => actions.autoUnlockCooldown();
  Future<void> openSeat({EventSource source = EventSource.app}) => actions.openSeat(source: source);
  Future<void> blink({required bool left, required bool right}) => actions.blink(left: left, right: right);
  Future<void> hazard({int times = 1}) => actions.hazard(times: times);
  Future<void> wakeUp() => actions.wakeUp();
  Future<void> hibernate() => actions.hibernate();
  Future<void> hibernateFor(Duration wakeAfter) => actions.hibernateFor(wakeAfter);
  Future<String?> getCellularApn() => actions.getSetting(commands.lsKeyCellularApn);
  Future<void> setCellularApn(String apn) => actions.setCellularApn(apn);
  Future<void> clearCellularApn() => actions.clearCellularApn();
  Future<bool?> getBatteryKeepActive() => actions.getBoolSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen);
  Future<void> setBatteryKeepActive(bool enabled) => actions.setSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen, enabled.toString());
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
  void didChangeAppLifecycleState(AppLifecycleState state) => runtime.didChangeAppLifecycleState(state);

}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}

/// Only model/publication and application integrations cross this boundary.
class _ServiceSessionEffects implements ScooterSessionEffects {
  _ServiceSessionEffects(this.service);
  final ScooterService service;

  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {
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
    service._telemetry.prepare(_cachedTelemetry(service.savedScooters[connection.id]));
    service.addSavedScooter(connection.id);
  }

  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {
    await HomeWidget.setAppGroupId('group.de.freal.unustasis');
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
  }
}

CachedTelemetry _cachedTelemetry(SavedScooter? scooter) => CachedTelemetry(
  primarySOC: scooter?.lastPrimarySOC, secondarySOC: scooter?.lastSecondarySOC,
  cbbSOC: scooter?.lastCbbSOC, auxSOC: scooter?.lastAuxSOC,
  handlebarsLocked: scooter?.handlebarsLocked, isLibrescoot: scooter?.isLibrescoot,
  supportsHibernateFor: scooter?.supportsHibernateFor, supportsApnConfig: scooter?.supportsApnConfig);

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
  }

  @override
  void ping(String scooterId) => service._pingScooter(scooterId);

  @override
  void changed(TelemetrySnapshot snapshot) {
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
    service.actions.aggregateTransition(previous, next);
  }

  @override
  void probeFailed(String message, Object error, StackTrace stack) =>
      service.log.warning(message, error, stack);
}

class _ServiceActionEffects implements ScooterActionEffects {
  _ServiceActionEffects(this.service);
  final ScooterService service;
  @override
  void acknowledged(ActionEvent event) => acknowledgeAppAction(event);
  @override
  void handlebarWarning(HandlebarWarning warning) {
    service.log.warning(warning.didNotUnlock ? "Handlebars didn't unlock, sending warning" : "Handlebars didn't lock, sending warning");
    final connection = service._session.currentConnection;
    if (connection?.isCurrent != true || connection!.id != warning.action.scooterId ||
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
      try { FlutterBackgroundService().invoke("autoUnlockCooldown"); } catch (_) {}
    }
  }
  @override
  void rssiChanged(int value) => service.rssi = value;
  @override
  void failed(Object error, StackTrace stack) => service.log.warning('Action effect failed', error, stack);
}

void acknowledgeAppAction(ActionEvent event) {
  if (event.kind == EventType.lock || event.kind == EventType.unlock) HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(eventType: event.kind, scooterId: event.scooterId,
    source: event.source, soc1: event.primarySOC, soc2: event.secondarySOC,
    location: event.location == null ? null : LatLng(event.location!.latitude, event.location!.longitude));
}
