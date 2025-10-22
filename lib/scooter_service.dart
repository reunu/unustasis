import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_battery.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_keyless_distance.dart';
import '../domain/scooter_state.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;
const handlebarCheckSeconds = 5;

class ScooterService with ChangeNotifier, WidgetsBindingObserver {
  final log = Logger('ScooterService');
  Map<String, SavedScooter> savedScooters = {};
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet
  bool _autoRestarting = false;
  String? _targetScooterId; // specific scooter ID to connect to during auto-restart
  bool _autoUnlock = false;
  int _autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool _openSeatOnUnlock = false;
  bool _hazardLocking = false;
  bool _warnOfUnlockedHandlebars = true;
  bool _autoUnlockCooldown = false;
  AppLifecycleState? _lastLifecycleState;
  SharedPreferencesOptions prefOptions = SharedPreferencesOptions();

  SharedPreferencesAsync prefs = SharedPreferencesAsync();
  late Timer _locationTimer, _manualRefreshTimer;
  late PausableTimer rssiTimer;
  bool optionalAuth = false;
  late CharacteristicRepository characteristicRepository;
  late ScooterReader _scooterReader;
  // get a random number
  late bool isInBackgroundService;
  final FlutterBluePlusMockable flutterBluePlus;

  void ping() {
    try {
      savedScooters[myScooter!.remoteId.toString()]!.lastPing = DateTime.now();
      lastPing = DateTime.now();
      notifyListeners();
    } catch (e, stack) {
      log.severe("Couldn't save ping", e, stack);
    }
  }

  void loadCachedData() async {
    savedScooters = await getSavedScooters();
    log.info(
      "Loaded ${savedScooters.length} saved scooters from SharedPreferences",
    );
    await seedStreamsWithCache();
    log.info("Seeded streams with cached values");
    restoreCachedSettings();
    log.info("Restored cached settings");
  }

  // On initialization...
  ScooterService(this.flutterBluePlus, {this.isInBackgroundService = false}) {
    loadCachedData();

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
      if (myScooter != null && myScooter!.isConnected && _autoUnlock) {
        try {
          rssi = await myScooter!.readRssi();
        } catch (e) {
          // probably not connected anymore
        }
        if (_autoUnlock &&
            _rssi != null &&
            _rssi! > _autoUnlockThreshold &&
            _state == ScooterState.standby &&
            !_autoUnlockCooldown &&
            optionalAuth) {
          unlock();
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

  Future<void> restoreCachedSettings() async {
    _autoUnlock = await prefs.getBool("autoUnlock") ?? false;
    _autoUnlockThreshold = await prefs.getInt("autoUnlockThreshold") ?? ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(await prefs.getBool("biometrics") ?? false);
    _openSeatOnUnlock = await prefs.getBool("openSeatOnUnlock") ?? false;
    _hazardLocking = await prefs.getBool("hazardLocking") ?? false;
    _warnOfUnlockedHandlebars = await prefs.getBool("unlockedHandlebarsWarning") ?? true;
  }

  Future<SavedScooter?> getMostRecentScooter() async {
    log.info("Getting most recent scooter from savedScooters");
    SavedScooter? mostRecentScooter;
    // don't seed with scooters that have auto-connect disabled
    if (savedScooters.isEmpty) {
      log.info("No saved scooters found, returning null");
      return null;
    } else if (savedScooters.length == 1) {
      log.info("Only one saved scooter found, returning it one way or another");
      if (savedScooters.values.first.autoConnect == false) {
        log.info(
          "we'll reenable autoconnect for this scooter, since it's the only one available",
        );
        savedScooters.values.first.autoConnect = true;
        updateBackgroundService({"updateSavedScooters": true});
      }
      return savedScooters.values.first;
    } else {
      List<SavedScooter> autoConnectScooters = filterAutoConnectScooters(
        savedScooters,
      ).values.toList();
      // get the saved scooter with the most recent ping
      for (var scooter in autoConnectScooters) {
        if (mostRecentScooter == null || scooter.lastPing.isAfter(mostRecentScooter.lastPing)) {
          mostRecentScooter = scooter;
        }
      }
      log.info("Most recent scooter: $mostRecentScooter");
      return mostRecentScooter;
    }
  }

  void updateScooterPing(String id) async {
    savedScooters[id]!.lastPing = DateTime.now();
    updateBackgroundService({"updateSavedScooters": true});
  }

  Future<void> seedStreamsWithCache() async {
    SavedScooter? mostRecentScooter = await getMostRecentScooter();
    log.info("Most recent scooter: $mostRecentScooter");
    // assume this is the one we'll connect to, and seed the streams
    _lastPing = mostRecentScooter?.lastPing;
    _primarySOC = mostRecentScooter?.lastPrimarySOC;
    _secondarySOC = mostRecentScooter?.lastSecondarySOC;
    _cbbSOC = mostRecentScooter?.lastCbbSOC;
    _auxSOC = mostRecentScooter?.lastAuxSOC;
    _scooterName = mostRecentScooter?.name;
    _scooterColor = mostRecentScooter?.color;
    _lastLocation = mostRecentScooter?.lastLocation;
    _handlebarsLocked = mostRecentScooter?.handlebarsLocked;
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

    _primarySOC = 53;
    _secondarySOC = 100;
    _cbbSOC = 98;
    _cbbVoltage = 15000;
    _cbbCapacity = 33000;
    _cbbCharging = false;
    _auxSOC = 100;
    _auxVoltage = 15000;
    _auxCharging = AUXChargingState.absorptionCharge;
    _primaryCycles = 190;
    _secondaryCycles = 75;
    _connected = true;
    _state = ScooterState.parked;
    _seatClosed = true;
    _handlebarsLocked = false;
    _lastPing = DateTime.now();
    _scooterName = "Demo Scooter";

    //SharedPreferencesAsync().setString(
    //  "savedScooters",
    //  jsonEncode(
    //      savedScooters.map((key, value) => MapEntry(key, value.toJson()))),
    //);
    //updateBackgroundService({"updateSavedScooters": true});

    notifyListeners();
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

  bool? _seatClosed;
  bool? get seatClosed => _seatClosed;
  set seatClosed(bool? seatClosed) {
    _seatClosed = seatClosed;
    notifyListeners();
  }

  bool? _handlebarsLocked;
  bool? get handlebarsLocked => _handlebarsLocked;
  set handlebarsLocked(bool? handlebarsLocked) {
    _handlebarsLocked = handlebarsLocked;
    // Cache the value in SavedScooter if possible
    if (myScooter != null && savedScooters.containsKey(myScooter!.remoteId.toString())) {
      savedScooters[myScooter!.remoteId.toString()]!.handlebarsLocked = handlebarsLocked;
    }
    notifyListeners();
  }

  int? _auxSOC;
  int? get auxSOC => _auxSOC;
  set auxSOC(int? auxSOC) {
    _auxSOC = auxSOC;
    notifyListeners();
  }

  int? _auxVoltage;
  int? get auxVoltage => _auxVoltage;
  set auxVoltage(int? auxVoltage) {
    _auxVoltage = auxVoltage;
    notifyListeners();
  }

  AUXChargingState? _auxCharging;
  AUXChargingState? get auxCharging => _auxCharging;
  set auxCharging(AUXChargingState? auxCharging) {
    _auxCharging = auxCharging;
    notifyListeners();
  }

  double? _cbbHealth;
  double? get cbbHealth => _cbbHealth;
  set cbbHealth(double? cbbHealth) {
    _cbbHealth = cbbHealth;
    notifyListeners();
  }

  int? _cbbSOC;
  int? get cbbSOC => _cbbSOC;
  set cbbSOC(int? cbbSOC) {
    _cbbSOC = cbbSOC;
    notifyListeners();
  }

  int? _cbbVoltage;
  int? get cbbVoltage => _cbbVoltage;
  set cbbVoltage(int? cbbVoltage) {
    _cbbVoltage = cbbVoltage;
    notifyListeners();
  }

  int? _cbbCapacity;
  int? get cbbCapacity => _cbbCapacity;
  set cbbCapacity(int? cbbCapacity) {
    _cbbCapacity = cbbCapacity;
    notifyListeners();
  }

  bool? _cbbCharging;
  bool? get cbbCharging => _cbbCharging;
  set cbbCharging(bool? cbbCharging) {
    _cbbCharging = cbbCharging;
    notifyListeners();
  }

  int? _primaryCycles;
  int? get primaryCycles => _primaryCycles;
  set primaryCycles(int? primaryCycles) {
    _primaryCycles = primaryCycles;
    notifyListeners();
  }

  int? _primarySOC;
  int? get primarySOC => _primarySOC;
  set primarySOC(int? primarySOC) {
    _primarySOC = primarySOC;
    notifyListeners();
  }

  int? _secondaryCycles;
  int? get secondaryCycles => _secondaryCycles;
  set secondaryCycles(int? secondaryCycles) {
    _secondaryCycles = secondaryCycles;
    notifyListeners();
  }

  int? _secondarySOC;
  int? get secondarySOC => _secondarySOC;
  set secondarySOC(int? secondarySOC) {
    _secondarySOC = secondarySOC;
    notifyListeners();
  }

  String? _nrfVersion;
  String? get nrfVersion => _nrfVersion;
  set nrfVersion(String? nrfVersion) {
    _nrfVersion = nrfVersion;
    notifyListeners();
  }

  bool? _isLibrescoot;
  bool? get isLibrescoot => _isLibrescoot;
  set isLibrescoot(bool? isLibrescoot) {
    _isLibrescoot = isLibrescoot;
    notifyListeners();
  }

  String? _scooterName;
  String? get scooterName => _scooterName;
  set scooterName(String? scooterName) {
    _scooterName = scooterName;
    notifyListeners();
  }

  DateTime? _lastPing;
  DateTime? get lastPing => _lastPing;
  set lastPing(DateTime? lastPing) {
    _lastPing = lastPing;
    notifyListeners();
  }

  int? _scooterColor;
  int? get scooterColor => _scooterColor;
  set scooterColor(int? scooterColor) {
    _scooterColor = scooterColor;
    notifyListeners();
    updateBackgroundService({"scooterColor": scooterColor});
  }

  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  bool _scanning = false;
  bool get scanning => _scanning;
  set scanning(bool scanning) {
    log.info("Scanning: $scanning");
    _scanning = scanning;
    notifyListeners();
  }

  int? _rssi;
  int? get rssi => _rssi;
  set rssi(int? rssi) {
    _rssi = rssi;
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

    if (includeSystemScooters) {
      log.fine("Searching system devices");
      List<BluetoothDevice> foundScooters = await getSystemScooters();
      if (foundScooters.isNotEmpty) {
        log.fine("Found system scooter");
        foundScooters = foundScooters.where((foundScooter) {
          return !excludedScooterIds.contains(foundScooter.remoteId.toString());
        }).toList();
        if (foundScooters.isNotEmpty) {
          log.fine("System scooter is not excluded from search, returning!");
          return foundScooters.first;
        }
      }
    }
    log.info("Searching nearby devices");
    await for (BluetoothDevice foundScooter in getNearbyScooters(
      preferSavedScooters: excludedScooterIds.isEmpty,
    )) {
      log.fine("Found scooter: ${foundScooter.remoteId.toString()}");
      if (!excludedScooterIds.contains(foundScooter.remoteId.toString())) {
        log.fine("Scooter's ID is not excluded, stopping scan and returning!");
        flutterBluePlus.stopScan();
        return foundScooter;
      }
    }
    log.info("Scan over, nothing found");
    return null;
  }

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await flutterBluePlus.systemDevices([
      Guid("9a590000-6e67-5d0d-aab9-ad9126b66f91"),
    ]);
    List<BluetoothDevice> systemScooters = [];
    List<String> savedScooterIds = await getSavedScooterIds(
      onlyAutoConnect: true,
    );
    for (var device in systemDevices) {
      // see if this is a scooter we saved and want to (auto-)connect to
      if (savedScooterIds.contains(device.remoteId.toString())) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters({
    bool preferSavedScooters = true,
  }) async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> savedScooterIds = await getSavedScooterIds(
      onlyAutoConnect: true,
    );
    if (savedScooterIds.isEmpty && savedScooters.isNotEmpty) {
      log.info(
        "We have ${savedScooters.length} saved scooters, but getSavedScooterIds returned an empty list. Probably no auto-connect enabled scooters, so we're not even scanning.",
      );
      return;
    }
    if (savedScooters.isNotEmpty && preferSavedScooters) {
      log.info(
        "Looking for our scooters, since we have ${savedScooters.length} saved scooters",
      );
      try {
        flutterBluePlus.startScan(
          withRemoteIds: savedScooterIds, // look for OUR scooter
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        log.severe("Failed to start scan", e, stack);
      }
    } else {
      log.info("Looking for any scooter, since we have no saved scooters");
      try {
        flutterBluePlus.startScan(
          withNames: [
            "unu Scooter",
          ], // if we don't have a saved scooter, look for ANY scooter
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        log.severe("Failed to start scan", e, stack);
      }
    }
    await for (var scanResult in flutterBluePlus.onScanResults) {
      if (scanResult.isNotEmpty) {
        ScanResult r = scanResult.last; // the most recently found device
        if (!foundScooterCache.contains(r.device)) {
          foundScooterCache.add(r.device);
          yield r.device;
        }
      }
    }
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
      try {
        await setUpCharacteristics(myScooter!);
      } on UnavailableCharacteristicsException {
        log.warning(
          "Some characteristics are null, if this turns out to be a rare issue we might display a toast here in the future",
        );
        // Fluttertoast.showToast(
        // msg: "Scooter firmware outdated, some features may not work");
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

    // TODO: prompt users to turn on bluetooth manually

    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // SCAN
    // TODO: replace with getEligibleScooters, why do we still have this duplicated?!

    // First, see if the phone is already actively connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // get the first one, hook into its connection, and remember the ID for future reference
      connectToScooterId(systemScooters.first.remoteId.toString());
    } else {
      try {
        log.fine("Looking for nearby scooters");
        // If not, start scanning for nearby scooters
        getNearbyScooters().listen((foundScooter) async {
          // there's one! Attempt to connect to it
          flutterBluePlus.stopScan();
          connectToScooterId(foundScooter.remoteId.toString());
        });
      } catch (e, stack) {
        // Guess this one is not happy with us
        // TODO: Handle errors more elegantly
        log.severe("Error during search or connect!", e, stack);
        Fluttertoast.showToast(msg: "Error during search or connect!");
      }
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
    _autoUnlock = enabled;
    prefs.setBool("autoUnlock", enabled);
    updateBackgroundService({"autoUnlock": enabled});
  }

  void setAutoUnlockThreshold(int threshold) {
    _autoUnlockThreshold = threshold;
    prefs.setInt("autoUnlockThreshold", threshold);
    updateBackgroundService({"autoUnlockThreshold": threshold});
  }

  void setOpenSeatOnUnlock(bool enabled) {
    _openSeatOnUnlock = enabled;
    prefs.setBool("openSeatOnUnlock", enabled);
    updateBackgroundService({"openSeatOnUnlock": enabled});
  }

  void setHazardLocking(bool enabled) {
    _hazardLocking = enabled;
    prefs.setBool("hazardLocking", enabled);
    updateBackgroundService({"hazardLocking": enabled});
  }

  bool get autoUnlock => _autoUnlock;
  int get autoUnlockThreshold => _autoUnlockThreshold;
  bool get openSeatOnUnlock => _openSeatOnUnlock;
  bool get hazardLocking => _hazardLocking;

  Future<void> setUpCharacteristics(BluetoothDevice scooter) async {
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected, can't set up characteristics!";
    }
    try {
      characteristicRepository = CharacteristicRepository(myScooter!);
      await characteristicRepository.findAll();

      log.info(
        "Found all characteristics! StateCharacteristic is: ${characteristicRepository.stateCharacteristic}",
      );
      _scooterReader = ScooterReader(
        characteristicRepository: characteristicRepository,
        service: this,
      );
      _scooterReader.readAndSubscribe();

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

  // SCOOTER ACTIONS

  Future<void> unlock({bool checkHandlebars = true}) async {
    _sendCommand("scooter:state unlock");
    HapticFeedback.heavyImpact();

    if (_openSeatOnUnlock) {
      await Future.delayed(const Duration(seconds: 1), () {
        openSeat();
      });
    }

    if (_hazardLocking) {
      await Future.delayed(const Duration(seconds: 2), () {
        hazard(times: 2);
      });
    }

    if (checkHandlebars) {
      await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
        if (_handlebarsLocked == true) {
          log.warning("Handlebars didn't unlock, sending warning");
          throw HandlebarLockException();
        }
      });
    }
  }

  Future<void> wakeUpAndUnlock() async {
    wakeUp();

    await _waitForScooterState(
      ScooterState.standby,
      const Duration(seconds: bootingTimeSeconds + 5),
    );

    if (_state == ScooterState.standby) {
      unlock();
    }
  }

  Future<void> lock({bool checkHandlebars = true}) async {
    if (_seatClosed == false) {
      log.warning("Seat seems to be open, checking again...");
      // make really sure nothing has changed
      await characteristicRepository.seatCharacteristic!.read();
      if (_seatClosed == false) {
        log.warning("Locking aborted, because seat is open!");

        throw SeatOpenException();
      } else {
        log.info("Seat state was $_seatClosed this time, proceeding...");
      }
    }

    // send the command
    _sendCommand("scooter:state lock");
    HapticFeedback.heavyImpact();

    if (_hazardLocking) {
      Future.delayed(const Duration(seconds: 1), () {
        hazard(times: 1);
      });
    }

    if (checkHandlebars) {
      await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
        if (_handlebarsLocked == false && _warnOfUnlockedHandlebars) {
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

  void openSeat() {
    _sendCommand("scooter:seatbox open");
  }

  void blink({required bool left, required bool right}) {
    if (left && !right) {
      _sendCommand("scooter:blinker left");
    } else if (!left && right) {
      _sendCommand("scooter:blinker right");
    } else if (left && right) {
      _sendCommand("scooter:blinker both");
    } else {
      _sendCommand("scooter:blinker off");
    }
  }

  Future<void> hazard({int times = 1}) async {
    blink(left: true, right: true);
    await _sleepSeconds((0.6) * times);
    blink(left: false, right: false);
  }

  Future<void> wakeUp() async {
    _sendCommand(
      "wakeup",
      characteristic: characteristicRepository.hibernationCommandCharacteristic,
    );
  }

  Future<void> hibernate() async {
    _sendCommand(
      "hibernate",
      characteristic: characteristicRepository.hibernationCommandCharacteristic,
    );
  }

  void _pollLocation() async {
    // Test if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log.warning("Location services are not enabled");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log.warning("Location permissions are/were denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      log.info("Location permissions are denied forever");
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    Position position = await Geolocator.getCurrentPosition();
    savedScooters[myScooter!.remoteId.toString()]!.lastLocation = LatLng(
      position.latitude,
      position.longitude,
    );
  }

  // HELPER FUNCTIONS

  void _sendCommand(String command, {BluetoothCharacteristic? characteristic}) {
    log.fine("Sending command: $command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }

    var characteristicToSend = characteristicRepository.commandCharacteristic;
    if (characteristic != null) {
      characteristicToSend = characteristic;
    }

    // commandCharcteristic should never be null, so we can assume it's not
    // if the given characteristic is null, we'll "fail" quitely by sending garbage to the default command characteristic instead

    try {
      characteristicToSend!.write(ascii.encode(command));
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> sendStaticPowerCommand(String id, String command) async {
    BluetoothDevice scooter = BluetoothDevice.fromId(id);
    if (scooter.isDisconnected) {
      await scooter.connect();
    }
    await scooter.discoverServices();
    BluetoothCharacteristic? commandCharacteristic = CharacteristicRepository.findCharacteristic(
      scooter,
      "9a590000-6e67-5d0d-aab9-ad9126b66f91",
      "9a590001-6e67-5d0d-aab9-ad9126b66f91",
    );
    await commandCharacteristic!.write(ascii.encode(command));
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

  Future<Map<String, SavedScooter>> getSavedScooters() async {
    log.info("Fetching saved scooters from SharedPreferences");
    Map<String, SavedScooter> scooters = {};
    try {
      Map<String, dynamic> savedScooterData =
          jsonDecode((await prefs.getString("savedScooters"))!) as Map<String, dynamic>;
      log.info("Found ${savedScooterData.length} saved scooters");
      // convert the saved scooter data to SavedScooter objects
      for (String id in savedScooterData.keys) {
        if (savedScooterData[id] is Map<String, dynamic>) {
          scooters[id] = SavedScooter.fromJson(id, savedScooterData[id]);
        }
      }
      log.info("Successfully fetched saved scooters: $scooters");
    } catch (e, stack) {
      // Handle potential errors gracefully
      log.severe("Error fetching saved scooters", e, stack);
    }
    return scooters;
  }

  Map<String, SavedScooter> filterAutoConnectScooters(
    Map<String, SavedScooter> scooters,
  ) {
    if (scooters.length == 1) {
      return Map.from(scooters);
    } else {
      // Return a copy to avoid modifying the original
      Map<String, SavedScooter> filteredScooters = Map.from(scooters);
      filteredScooters.removeWhere((key, value) => !value.autoConnect);
      return filteredScooters;
    }
  }

  Future<void> refetchSavedScooters() async {
    savedScooters = await getSavedScooters();
    if (!connected) {
      // update the most recent scooter and streams
      SavedScooter? mostRecentScooter = await getMostRecentScooter();
      if (mostRecentScooter != null) {
        _lastPing = mostRecentScooter.lastPing;
        _primarySOC = mostRecentScooter.lastPrimarySOC;
        _secondarySOC = mostRecentScooter.lastSecondarySOC;
        _cbbSOC = mostRecentScooter.lastCbbSOC;
        _auxSOC = mostRecentScooter.lastAuxSOC;
        _scooterName = mostRecentScooter.name;
        _scooterColor = mostRecentScooter.color;
        _lastLocation = mostRecentScooter.lastLocation;
        _handlebarsLocked = mostRecentScooter.handlebarsLocked;
      } else {
        // no saved scooters, reset streams
        _lastPing = null;
        _primarySOC = null;
        _secondarySOC = null;
        _cbbSOC = null;
        _auxSOC = null;
        _scooterName = null;
        _scooterColor = null;
        _lastLocation = null;
      }
    }
    notifyListeners();
  }

  Future<List<String>> getSavedScooterIds({
    bool onlyAutoConnect = false,
  }) async {
    if (savedScooters.isNotEmpty) {
      log.info("Getting ids of already fetched scooters");
      if (onlyAutoConnect) {
        return filterAutoConnectScooters(savedScooters).keys.toList();
      } else {
        return savedScooters.keys.toList();
      }
    } else {
      // nothing saved locally yet, check prefs
      log.info("No saved scooters, checking SharedPreferences");
      if (await prefs.containsKey("savedScooters")) {
        log.info("Found saved scooters in SharedPreferences, fetching...");
        savedScooters = await getSavedScooters();
        if (onlyAutoConnect) {
          return filterAutoConnectScooters(savedScooters).keys.toList();
        }
        return savedScooters.keys.toList();
      } else {
        log.info(
          "No saved scooters found in SharedPreferences, returning empty list",
        );
        return [];
      }
    }
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
      savedScooters.remove(id);
      await prefs.setString("savedScooters", jsonEncode(savedScooters));
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
    if (savedScooters[id] == null) {
      savedScooters[id] = SavedScooter(name: name, id: id);
    } else {
      savedScooters[id]!.name = name;
    }

    await prefs.setString("savedScooters", jsonEncode(savedScooters));

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
    if (savedScooters[id] == null) {
      savedScooters[id] = SavedScooter(color: color, id: id);
    } else {
      savedScooters[id]!.color = color;
    }

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
    if (savedScooters.containsKey(id)) {
      // we already know this scooter!
      return;
    }
    savedScooters[id] = SavedScooter(
      name: "Scooter Pro",
      id: id,
      color: 1,
      lastPing: DateTime.now(),
    );
    await prefs.setString("savedScooters", jsonEncode(savedScooters));
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

  Future<void> _sleepSeconds(double seconds) {
    return Future.delayed(Duration(milliseconds: (seconds * 1000).floor()));
  }
}

class SeatOpenException {}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}
