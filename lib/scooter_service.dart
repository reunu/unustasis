import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../domain/statistics_helper.dart';
import '../domain/scooter_battery.dart';
import '../domain/nav_destination.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
import '../domain/scooter_vehicle_state.dart';
import '../domain/scooter_power_state.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../service/location_polling.dart' as location;
import '../state/battery_state.dart';
import '../state/scooter_identity.dart';
import '../state/vehicle_status.dart';
import '../service/scooter_storage.dart';
import '../service/ble_commands.dart' as commands;
import '../service/ble_scanner.dart';
import '../service/user_settings.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;
const handlebarCheckSeconds = 5;

class ScooterService with ChangeNotifier, WidgetsBindingObserver {
  final log = Logger('ScooterService');

  // Composed modules
  final ScooterStorage store = ScooterStorage();
  late final BleScanner scanner;
  late final UserSettings settings;

  // Observable state
  final BatteryState battery = BatteryState();
  final VehicleStatus vehicle = VehicleStatus();
  final ScooterIdentity identity = ScooterIdentity();

  Map<String, SavedScooter> get savedScooters => store.scooters;
  set savedScooters(Map<String, SavedScooter> value) => store.scooters = value;

  BluetoothDevice? myScooter; // reserved for a connected scooter!
  NavDestination? _pendingNavigation;
  bool _foundSth = false; // whether we've found a scooter yet
  bool _autoRestarting = false;
  String? _targetScooterId; // specific scooter ID to connect to during auto-restart
  bool _autoUnlockCooldown = false;
  AppLifecycleState? _lastLifecycleState;

  late Timer _locationTimer, _manualRefreshTimer;
  late PausableTimer rssiTimer;
  late CharacteristicRepository characteristicRepository;
  late bool isInBackgroundService;
  final FlutterBluePlusMockable flutterBluePlus;

  // Passthrough for optionalAuth (used by home_screen for biometrics)
  bool get optionalAuth => settings.optionalAuth;
  set optionalAuth(bool value) => settings.optionalAuth = value;

  void ping() {
    try {
      savedScooters[myScooter!.remoteId.toString()]!.lastPing = DateTime.now();
      lastPing = DateTime.now();
      notifyListeners();
    } catch (e, stack) {
      log.severe("Couldn't save ping", e, stack);
    }
  }

  void _loadCachedData() async {
    await store.load();
    log.info(
      "Loaded ${savedScooters.length} saved scooters from SharedPreferences",
    );
    await _seedStreamsWithCache();
    log.info("Seeded streams with cached values");
    settings.restore();
  }

  // On initialization...
  ScooterService(this.flutterBluePlus, {this.isInBackgroundService = false}) {
    settings = UserSettings(isInBackgroundService: isInBackgroundService);
    scanner = BleScanner(flutterBluePlus);
    _loadCachedData();

    // Register for app lifecycle callbacks (only if not in background service)
    if (!isInBackgroundService) {
      WidgetsBinding.instance.addObserver(this);
      log.info("Registered for app lifecycle callbacks");
    }

    // update the "scanning" listener
    flutterBluePlus.isScanning.listen((isScanning) {
      scanning = isScanning;
    });

    // start the location polling timer
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        _pollLocation();
      }
    });
    rssiTimer = PausableTimer.periodic(const Duration(seconds: 3), () async {
      if (myScooter != null && myScooter!.isConnected && settings.autoUnlock) {
        try {
          rssi = await myScooter!.readRssi();
        } catch (e) {
          // probably not connected anymore
        }
        if (settings.autoUnlock &&
            identity.rssi != null &&
            identity.rssi! > settings.autoUnlockThreshold &&
            _state == ScooterState.standby &&
            !_autoUnlockCooldown &&
            settings.optionalAuth) {
          unlock(source: EventSource.auto);
          autoUnlockCooldown();
        }
      }
    })
      ..start();
    _manualRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        try {
          log.info("Auto-refresh...");
          characteristicRepository.stateCharacteristic!.read();
          characteristicRepository.seatCharacteristic!.read();
        } on StateError catch (_) {
          log.fine(
            "Characteristics not yet initialized, skipping auto-refresh",
          );
        }
      }
    });
  }

  Future<SavedScooter?> getMostRecentScooter() async {
    SavedScooter? recent = store.getMostRecent();
    if (recent != null && savedScooters.length == 1 && savedScooters.values.first.autoConnect == true) {
      // store.getMostRecent() may have re-enabled autoConnect for a single scooter
      updateBackgroundService({"updateSavedScooters": true});
    }
    return recent;
  }

  void updateScooterPing(String id) async {
    store.updatePing(id);
    updateBackgroundService({"updateSavedScooters": true});
  }

  Future<void> _seedStreamsWithCache() async {
    SavedScooter? mostRecentScooter = await getMostRecentScooter();
    log.info("Most recent scooter: $mostRecentScooter");
    // assume this is the one we'll connect to, and seed the streams
    identity.lastPing = mostRecentScooter?.lastPing;
    battery.primarySOC = mostRecentScooter?.lastPrimarySOC;
    battery.secondarySOC = mostRecentScooter?.lastSecondarySOC;
    battery.cbbSOC = mostRecentScooter?.lastCbbSOC;
    battery.auxSOC = mostRecentScooter?.lastAuxSOC;
    identity.name = mostRecentScooter?.name;
    identity.color = mostRecentScooter?.color;
    identity.lastLocation = mostRecentScooter?.lastLocation;
    identity.isLibrescoot = mostRecentScooter?.isLibrescoot;
    vehicle.handlebarsLocked = mostRecentScooter?.handlebarsLocked;

    // Load pending navigation from persistent storage
    final prefs = SharedPreferencesAsync();
    final pendingJson = await prefs.getString('pendingNavigation');
    if (pendingJson != null) {
      try {
        _pendingNavigation = NavDestination.fromJson(
          jsonDecode(pendingJson) as Map<String, dynamic>,
        );
      } catch (_) {
        await prefs.remove('pendingNavigation');
      }
    }
    return;
  }

  void addDemoData() {
    _autoRestarting = false;
    _foundSth = true;
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
    battery.cbbVoltage = 15000;
    battery.cbbCapacity = 33000;
    battery.cbbCharging = false;
    battery.auxSOC = 100;
    battery.auxVoltage = 15000;
    battery.auxCharging = AUXChargingState.absorptionCharge;
    battery.primaryCycles = 190;
    battery.secondaryCycles = 75;
    _connected = true;
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

  // PENDING NAVIGATION
  NavDestination? get pendingNavigation => _pendingNavigation;

  Future<void> setPendingNavigation(NavDestination? dest) async {
    _pendingNavigation = dest;
    final prefs = SharedPreferencesAsync();
    if (dest != null) {
      await prefs.setString('pendingNavigation', jsonEncode(dest.toJson()));
    } else {
      await prefs.remove('pendingNavigation');
    }
    notifyListeners();
  }

  Future<void> _dispatchPendingNavigation() async {
    if (_pendingNavigation == null || myScooter == null) return;
    try {
      final success = await commands.navigateCommand(
        myScooter!,
        characteristicRepository,
        _pendingNavigation!,
      );
      if (success) {
        log.info('Pending navigation dispatched to ${_pendingNavigation!.name}');
        await setPendingNavigation(null);
      } else {
        log.warning('Pending navigation dispatch failed (nav:ok not received)');
      }
    } catch (e) {
      log.warning('Error dispatching pending navigation', e);
    }
  }

  // STATUS STREAMS
  bool _connected = false;
  bool get connected => _connected;
  set connected(bool connected) {
    _connected = connected;
    notifyListeners();
  }

  ScooterState? _state = ScooterState.disconnected;
  ScooterState? get state => _state;
  set state(ScooterState? state) {
    _state = state;
    notifyListeners();
  }

  // Passthrough getters for vehicle status
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  ScooterPowerState? get powerState => vehicle.powerState;
  bool? get seatClosed => vehicle.seatClosed;
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  bool? get navigationActive => vehicle.navigationActive;

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
    try {
      stopAutoRestart();
      log.fine("Auto-restart stopped");
    } catch (e) {
      log.info("Didn't stop auto-restart, might not have been running yet");
    }

    return scanner.findEligibleScooter(
      getIds: getSavedScooterIds,
      hasSavedScooters: savedScooters.isNotEmpty,
      excludedScooterIds: excludedScooterIds,
      includeSystemScooters: includeSystemScooters,
    );
  }

  Future<void> connectToScooterId(
    String id, {
    bool initialConnect = false,
  }) async {
    log.info("Connecting to scooter with ID: $id");
    _foundSth = true;
    state = ScooterState.linking;
    try {
      // attempt to connect to what we found
      BluetoothDevice attemptedScooter = BluetoothDevice.fromId(id);
      // wait for the connection to be established
      log.info("Connecting to ${attemptedScooter.remoteId}");
      await attemptedScooter.connect(timeout: const Duration(seconds: 30));
      if (initialConnect && Platform.isAndroid) {
        await attemptedScooter.createBond(timeout: 30);
        log.info("Bond established");
      }
      log.info("Connected to ${attemptedScooter.remoteId}");
      // Set up this scooter as ours
      myScooter = attemptedScooter;
      addSavedScooter(myScooter!.remoteId.toString());

      // Save scooter ID directly for iOS widget native Bluetooth access
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId('group.de.freal.unustasis');
        passToWidget(
          scooterId: myScooter!.remoteId.toString(),
        );
        log.info("Saved scooter ID to widget: ${myScooter!.remoteId.toString()}");
      }

      try {
        await _setUpCharacteristics(
          myScooter!,
          additionalLibrescootFeatures: true,
        );
      } on UnavailableCharacteristicsException {
        log.warning(
          "Some characteristics are null, if this turns out to be a rare issue we might display a toast here in the future",
        );
        // TODO: warn of old firmware that doesn't support all characteristics w/ a popup
      }

      // save this as the last known location
      _pollLocation();
      // Let everybody know
      connected = true;
      scooterName = savedScooters[myScooter!.remoteId.toString()]?.name;
      scooterColor = savedScooters[myScooter!.remoteId.toString()]?.color;
      updateBackgroundService({
        "scooterName": scooterName,
        "scooterColor": scooterColor,
        "lastPingInt": DateTime.now().millisecondsSinceEpoch,
      });
      // listen for disconnects
      myScooter!.connectionState.listen((BluetoothConnectionState state) async {
        if (state == BluetoothConnectionState.disconnected) {
          connected = false;
          this.state = ScooterState.disconnected;
          log.info("Lost connection to scooter! :(");
          // update the ping again
          updateScooterPing(myScooter!.remoteId.toString());
          // Restart the process if we're not already doing so
          // start(); // this leads to some conflicts right now if the phone auto-connects, so we're not doing it
        }
      });
    } catch (e, stack) {
      // something went wrong, roll back!
      log.shout("Couldn't connect to scooter!", e, stack);
      _foundSth = false;
      state = ScooterState.disconnected;
      rethrow;
    }
  }

  // spins up the whole connection process, and connects/bonds with the nearest scooter
  void start({bool restart = true}) async {
    log.info("START called on service");
    // GETTING READY
    // Remove the splash screen
    Future.delayed(const Duration(milliseconds: 1500), () {
      FlutterNativeSplash.remove();
    });
    // Try to turn on Bluetooth (Android-Only)
    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // SCAN
    try {
      BluetoothDevice? eligibleScooter = await findEligibleScooter();
      if (eligibleScooter != null) {
        await connectToScooterId(eligibleScooter.remoteId.toString());
      } else {
        log.info("No eligible scooters found during start()");
      }
    } catch (e, stack) {
      log.warning("Error during search or connect!", e, stack);
      // fail quietly, there can be benign reasons like race conditions for this
    }

    if (restart) {
      startAutoRestart();
    }
  }

  late StreamSubscription<bool> _autoRestartSubscription;
  void startAutoRestart({String? targetScooterId}) async {
    if (!_autoRestarting) {
      _autoRestarting = true;
      _targetScooterId = targetScooterId;
      log.info("Starting auto-restart${targetScooterId != null ? " for scooter $targetScooterId" : ""}");
      _autoRestartSubscription = flutterBluePlus.isScanning.listen((
        scanState,
      ) async {
        // retry if we stop scanning without having found anything
        if (scanState == false && !_foundSth) {
          await Future.delayed(const Duration(seconds: 3));
          if (!_foundSth && !scanning && _autoRestarting) {
            // make sure nothing happened in these few seconds
            log.info("Auto-restarting...${_targetScooterId != null ? " targeting $_targetScooterId" : ""}");
            if (_targetScooterId != null) {
              // Try to connect to the specific scooter the user selected
              try {
                await connectToScooterId(_targetScooterId!);
              } catch (e) {
                log.warning("Failed to connect to target scooter $_targetScooterId during auto-restart: $e");
              }
            } else {
              // Fall back to generic start() for auto-connect behavior
              start();
            }
          }
        }
      });
    } else {
      log.info("Auto-restart already running, avoiding duplicate");
    }
  }

  void stopAutoRestart() {
    _autoRestarting = false;
    _targetScooterId = null;
    _autoRestartSubscription.cancel();
    log.fine("Auto-restart stopped.");
  }

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

  Future<void> _setUpCharacteristics(BluetoothDevice scooter, {bool additionalLibrescootFeatures = false}) async {
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected, can't set up characteristics!";
    }
    try {
      characteristicRepository = CharacteristicRepository(myScooter!);
      await characteristicRepository.findAll(additionalLibrescootFeatures: additionalLibrescootFeatures);

      log.info(
        "Found all characteristics! StateCharacteristic is: ${characteristicRepository.stateCharacteristic}",
      );

      _subscribeToAllCharacteristics();

      // check if any of the characteristics are null, and if so, throw an error
      if (characteristicRepository.anyAreNull()) {
        log.warning(
          "Some characteristics are null, throwing exception to warn further up the chain!",
        );
        throw UnavailableCharacteristicsException();
      }
    } catch (e) {
      rethrow;
    }
  }

  void _subscribeToAllCharacteristics() {
    var chars = characteristicRepository;

    vehicle.wireSubscriptions(
      chars,
      onStateUpdate: () {
        _updateAggregateState();
      },
      onSeatUpdate: () {
        ping();
        notifyListeners();
      },
      onNavigationChanged: () {
        ping();
        notifyListeners();
      },
      onHandlebarsChanged: (locked) {
        // Cache the value in SavedScooter if possible
        if (myScooter != null && savedScooters.containsKey(myScooter!.remoteId.toString())) {
          savedScooters[myScooter!.remoteId.toString()]!.handlebarsLocked = locked;
        }
        ping();
        notifyListeners();
      },
    );

    battery.wireSubscriptions(
      chars,
      onUpdate: () {
        ping();
        notifyListeners();
      },
      cacheSoc: _cacheSocForScooter,
    );

    identity.wireNrfVersion(
      chars,
      onUpdate: () {
        // Persist the discovered isLibrescoot flag to saved scooter data
        final scooterId = myScooter?.remoteId.toString();
        if (scooterId != null && savedScooters.containsKey(scooterId)) {
          savedScooters[scooterId]!.isLibrescoot = identity.isLibrescoot;
        }
        // Dispatch any queued navigation to this librescoot
        if (identity.isLibrescoot == true && _pendingNavigation != null) {
          _dispatchPendingNavigation();
        }
        notifyListeners();
      },
    );
  }

  void _updateAggregateState() {
    ScooterState? oldState = _state;
    ScooterState? newState = vehicle.computeAggregateState();
    state = newState;
    ping();

    // if someone just locked the scooter with their keycard, stop keyless from unlocking again
    // this might (will) cause the cooldown to run even on app locks, but that's okay
    if (oldState?.isOn == true && newState?.isOn == false) {
      autoUnlockCooldown();
    }
  }

  void _cacheSocForScooter(void Function(SavedScooter) update) {
    try {
      update(savedScooters[myScooter!.remoteId.toString()]!);
    } catch (e) {
      // scooter might not be in savedScooters yet
    }
  }

  // SCOOTER ACTIONS

  Future<void> unlock({
    bool checkHandlebars = true,
    EventSource source = EventSource.app,
  }) async {
    commands.unlockScooter(
      myScooter,
      characteristicRepository,
      primarySOC: battery.primarySOC,
      secondarySOC: battery.secondarySOC,
      source: source,
    );

    if (settings.openSeatOnUnlock) {
      await Future.delayed(const Duration(seconds: 1), () {
        openSeat(source: EventSource.auto);
      });
    }

    if (settings.hazardLocking) {
      await Future.delayed(const Duration(seconds: 2), () {
        hazard(times: 2);
      });
    }

    if (checkHandlebars) {
      await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
        if (vehicle.handlebarsLocked == true) {
          log.warning("Handlebars didn't unlock, sending warning");
          throw HandlebarLockException();
        }
      });
    }
  }

  Future<void> wakeUpAndUnlock({EventSource? source}) async {
    wakeUp();

    await _waitForScooterState(
      ScooterState.standby,
      const Duration(seconds: bootingTimeSeconds + 5),
    );

    if (_state == ScooterState.standby) {
      unlock();
    }
  }

  Future<void> lock({
    bool checkHandlebars = true,
    EventSource source = EventSource.app,
  }) async {
    if (vehicle.seatClosed == false) {
      log.warning("Locking with open seatbox!");
    }

    commands.lockScooter(
      myScooter,
      characteristicRepository,
      primarySOC: battery.primarySOC,
      secondarySOC: battery.secondarySOC,
      source: source,
      lastLocation: lastLocation,
    );

    if (settings.hazardLocking) {
      Future.delayed(const Duration(seconds: 1), () {
        hazard(times: 1);
      });
    }

    if (checkHandlebars) {
      await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
        if (vehicle.handlebarsLocked == false && settings.warnOfUnlockedHandlebars) {
          log.warning("Handlebars didn't lock, sending warning");
          throw HandlebarLockException();
        }
      });
    }

    // don't immediately unlock again automatically
    autoUnlockCooldown();
  }

  void autoUnlockCooldown() {
    try {
      FlutterBackgroundService().invoke("autoUnlockCooldown");
    } catch (e) {
      // closing the loop
    }
    _autoUnlockCooldown = true;
    Future.delayed(const Duration(seconds: keylessCooldownSeconds), () {
      _autoUnlockCooldown = false;
    });
  }

  void openSeat({EventSource source = EventSource.app}) {
    commands.openSeatCommand(
      myScooter,
      characteristicRepository,
      primarySOC: battery.primarySOC,
      secondarySOC: battery.secondarySOC,
      source: source,
    );
  }

  void blink({required bool left, required bool right}) {
    commands.blinkCommand(myScooter, characteristicRepository, left: left, right: right);
  }

  Future<void> hazard({int times = 1}) async {
    blink(left: true, right: true);
    await Future.delayed(Duration(milliseconds: (600 * times)));
    blink(left: false, right: false);
  }

  Future<void> wakeUp() async {
    commands.wakeUpCommand(myScooter, characteristicRepository);
  }

  Future<void> hibernate() async {
    commands.hibernateCommand(myScooter, characteristicRepository);
  }

  void _pollLocation() async {
    LatLng? position = await location.pollLocation();
    if (position != null && myScooter != null) {
      savedScooters[myScooter!.remoteId.toString()]!.lastLocation = position;
    }
  }

  static Future<void> sendStaticPowerCommand(String id, String command) async {
    await commands.sendStaticPowerCommand(id, command);
  }

  Future<bool> attemptLatestAutoConnection() async {
    SavedScooter? latestScooter = await getMostRecentScooter();
    if (latestScooter != null) {
      try {
        await connectToScooterId(latestScooter.id);
        if (BluetoothDevice.fromId(latestScooter.id).isConnected) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  Future<void> _waitForScooterState(
    ScooterState expectedScooterState,
    Duration limit,
  ) async {
    Completer<void> completer = Completer<void>();

    // Check new state every 2s
    var timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      ScooterState? scooterState = _state;
      log.info("Waiting for $expectedScooterState, and got: $scooterState...");
      if (scooterState == expectedScooterState) {
        log.info("Found $expectedScooterState, cancel timer...");
        timer.cancel();
        completer.complete();
      }
    });

    // Clean up
    Future.delayed(limit, () {
      log.info("Timer limit reached after $limit");
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  // SAVED SCOOTER MANAGEMENT

  Future<void> refetchSavedScooters() async {
    await store.load();
    if (!connected) {
      // update the most recent scooter and streams
      SavedScooter? mostRecentScooter = await getMostRecentScooter();
      if (mostRecentScooter != null) {
        identity.lastPing = mostRecentScooter.lastPing;
        battery.primarySOC = mostRecentScooter.lastPrimarySOC;
        battery.secondarySOC = mostRecentScooter.lastSecondarySOC;
        battery.cbbSOC = mostRecentScooter.lastCbbSOC;
        battery.auxSOC = mostRecentScooter.lastAuxSOC;
        identity.name = mostRecentScooter.name;
        identity.color = mostRecentScooter.color;
        identity.lastLocation = mostRecentScooter.lastLocation;
        vehicle.handlebarsLocked = mostRecentScooter.handlebarsLocked;
      } else {
        // no saved scooters, reset streams
        identity.lastPing = null;
        battery.primarySOC = null;
        battery.secondarySOC = null;
        battery.cbbSOC = null;
        battery.auxSOC = null;
        identity.name = null;
        identity.color = null;
        identity.lastLocation = null;
      }
    }
    notifyListeners();
  }

  Future<List<String>> getSavedScooterIds({
    bool onlyAutoConnect = false,
  }) async {
    return store.getIds(onlyAutoConnect: onlyAutoConnect);
  }

  void forgetSavedScooter(String id) async {
    if (myScooter?.remoteId.toString() == id) {
      // this is the currently connected scooter
      stopAutoRestart();
      await myScooter?.disconnect();
      myScooter?.removeBond();
      myScooter = null;
    } else {
      // we're not currently connected to this scooter
      try {
        await BluetoothDevice.fromId(id).removeBond();
      } catch (e, stack) {
        log.severe("Couldn't forget scooter", e, stack);
      }
    }

    // if the ID is not specified, we're forgetting the currently connected scooter
    if (savedScooters.isNotEmpty) {
      await store.remove(id);
    }
    updateBackgroundService({"updateSavedScooters": true});
    connected = false;
    notifyListeners();
  }

  void renameSavedScooter({String? id, required String name}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
        "Attempted to rename scooter, but no ID was given and we're not connected to anything!",
      );
      return;
    }
    await store.rename(id, name);

    bool isMostRecent = (await getMostRecentScooter())?.id == id;
    if (isMostRecent) {
      scooterName = name;
    }

    updateBackgroundService({
      "updateSavedScooters": true,
      if (isMostRecent) "scooterName": name,
    });
    // let the background service know too right away
    notifyListeners();
  }

  void recolorSavedScooter({String? id, required int color}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
        "Attempted to recolor scooter, but no ID was given and we're not connected to anything!",
      );
      return;
    }
    await store.recolor(id, color);

    bool isMostRecent = (await getMostRecentScooter())?.id == id;
    if (isMostRecent) {
      scooterColor = color;
    }
    updateBackgroundService({
      "updateSavedScooters": true,
      if (isMostRecent) "scooterColor": color,
    });
    // let the background service know too right away
    notifyListeners();
  }

  void updateBackgroundService(dynamic data) {
    if (!isInBackgroundService) {
      FlutterBackgroundService().invoke("update", data);
    }
  }

  void addSavedScooter(String id) async {
    bool added = await store.add(id);
    if (!added) return;
    updateBackgroundService({"updateSavedScooters": true});
    scooterName = "Scooter Pro";
    notifyListeners();
  }

  @override
  void dispose() {
    _locationTimer.cancel();
    rssiTimer.cancel();
    _manualRefreshTimer.cancel();

    // Unregister lifecycle observer
    if (!isInBackgroundService) {
      WidgetsBinding.instance.removeObserver(this);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    log.info("App lifecycle state changed: $_lastLifecycleState -> $state");

    // Check if app is returning to foreground from background
    if (_lastLifecycleState != null &&
        (_lastLifecycleState == AppLifecycleState.paused ||
            _lastLifecycleState == AppLifecycleState.inactive ||
            _lastLifecycleState == AppLifecycleState.hidden) &&
        state == AppLifecycleState.resumed) {
      log.info("App resumed from background - checking connection status");
      _handleAppResumedFromBackground();
    }

    _lastLifecycleState = state;
  }

  void _handleAppResumedFromBackground() async {
    // Only attempt reconnection if we have saved scooters and are not currently connected
    if (savedScooters.isNotEmpty && !connected && !scanning) {
      log.info("App resumed: attempting automatic reconnection");

      try {
        // Small delay to let the app settle
        await Future.delayed(const Duration(milliseconds: 500));

        // Try to reconnect to the last known scooter
        start();
      } catch (e, stack) {
        log.warning(
          "Error during automatic reconnection on app resume",
          e,
          stack,
        );
      }
    } else {
      log.info(
        "App resumed: no reconnection needed (connected: $connected, scanning: $scanning, saved scooters: ${savedScooters.length})",
      );
    }
  }
}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}
