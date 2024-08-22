import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_keyless_distance.dart';
import '../domain/scooter_state.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;

class ScooterService {
  Map<String, SavedScooter> savedScooters = {};
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet
  bool _autoRestarting = false;
  bool _scanning = false;
  bool _autoUnlock = false;
  int _autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool _openSeatOnUnlock = false;
  bool _hazardLocking = false;
  bool _autoUnlockCooldown = false;
  SharedPreferences? prefs;
  late Timer _locationTimer, _rssiTimer, _manualRefreshTimer;
  bool optionalAuth = false;
  late CharacteristicRepository characteristicRepository;
  late ScooterReader _scooterReader;

  final FlutterBluePlusMockable flutterBluePlus;

  void ping() {
    try {
      savedScooters[myScooter!.remoteId.toString()]!.lastPing = DateTime.now();
      _lastPingController.add(DateTime.now());
    } catch (e) {
      log("Couldn't save ping");
    }
  }

  // On initialization...
  ScooterService(this.flutterBluePlus) {
    // Load saved scooter ID and cached values from SharedPrefs
    SharedPreferences.getInstance().then((prefs) {
      this.prefs = prefs;

      savedScooters = getSavedScooters();

      seedStreamsWithCache();
      restoreCachedSettings();
    });

    // start the location polling timer
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        _pollLocation();
      }
    });
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (myScooter != null && myScooter!.isConnected && _autoUnlock) {
        int? rssi;
        try {
          rssi = await myScooter!.readRssi();
        } catch (e) {
          // probably not connected anymore
        }
        if (_autoUnlock &&
            rssi != null &&
            rssi > _autoUnlockThreshold &&
            _stateController.value == ScooterState.standby &&
            !_autoUnlockCooldown &&
            optionalAuth) {
          unlock();
          _autoUnlockCooldown = true;
          await Future.delayed(const Duration(seconds: keylessCooldownSeconds));
          _autoUnlockCooldown = false;
        }
      }
    });
    _manualRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        // only refresh state and seatbox, for now
        log("Auto-refresh...");
        characteristicRepository.stateCharacteristic.read();
        characteristicRepository.seatCharacteristic.read();
      }
    });
  }

  void restoreCachedSettings() {
    _autoUnlock = prefs?.getBool("autoUnlock") ?? false;
    _autoUnlockThreshold = prefs?.getInt("autoUnlockThreshold") ??
        ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(prefs?.getBool("biometrics") ?? false);
    _openSeatOnUnlock = prefs?.getBool("openSeatOnUnlock") ?? false;
    _hazardLocking = prefs?.getBool("hazardLocking") ?? false;
  }

  void seedStreamsWithCache() {
    // get the saved scooter with the most recent ping
    SavedScooter? mostRecentScooter;
    for (var scooter in savedScooters.values) {
      if (mostRecentScooter == null ||
          mostRecentScooter.lastPing.isAfter(mostRecentScooter.lastPing)) {
        mostRecentScooter = scooter;
      }
    }

    _lastPingController.add(mostRecentScooter?.lastPing);
    _primarySOCController.add(mostRecentScooter?.lastPrimarySOC);
    _secondarySOCController.add(mostRecentScooter?.lastSecondarySOC);
    _cbbSOCController.add(mostRecentScooter?.lastCbbSOC);
    _auxSOCController.add(mostRecentScooter?.lastAuxSOC);
    _scooterNameController.add(mostRecentScooter?.name);
    _scooterColorController.add(mostRecentScooter?.color);
  }

  void addDemoData() {
    savedScooters = {
      "12345": SavedScooter(
        name: "Demo Scooter",
        id: "12345",
        color: 1,
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

    _primarySOCController.add(53);
    _secondarySOCController.add(100);
    _cbbSOCController.add(98);
    _auxSOCController.add(100);
    _primaryCyclesController.add(190);
    _secondaryCyclesController.add(75);
    _connectedController.add(true);
    _stateController.add(ScooterState.standby);
    _seatClosedController.add(true);
    _handlebarController.add(false);
    _cbbChargingController.add(false);
    _lastPingController.add(DateTime.now());
    _scooterNameController.add("Demo Scooter");
  }

  // STATUS STREAMS
  final BehaviorSubject<bool> _connectedController =
      BehaviorSubject<bool>.seeded(false);
  Stream<bool> get connected => _connectedController.stream;

  final BehaviorSubject<ScooterState?> _stateController =
      BehaviorSubject<ScooterState?>.seeded(ScooterState.disconnected);
  Stream<ScooterState?> get state => _stateController.stream;

  final BehaviorSubject<bool?> _seatClosedController = BehaviorSubject<bool?>();
  Stream<bool?> get seatClosed => _seatClosedController.stream;

  final BehaviorSubject<bool?> _handlebarController = BehaviorSubject<bool?>();
  Stream<bool?> get handlebarsLocked => _handlebarController.stream;

  final BehaviorSubject<int?> _auxSOCController = BehaviorSubject<int?>();
  Stream<int?> get auxSOC => _auxSOCController.stream;

  final BehaviorSubject<double?> _cbbHealthController =
      BehaviorSubject<double?>();
  Stream<double?> get cbbHealth => _cbbHealthController.stream;

  final BehaviorSubject<int?> _cbbSOCController = BehaviorSubject<int?>();
  Stream<int?> get cbbSOC => _cbbSOCController.stream;

  final BehaviorSubject<bool?> _cbbChargingController =
      BehaviorSubject<bool?>();
  Stream<bool?> get cbbCharging => _cbbChargingController.stream;

  final BehaviorSubject<int?> _primaryCyclesController =
      BehaviorSubject<int?>();
  Stream<int?> get primaryCycles => _primaryCyclesController.stream;

  final BehaviorSubject<int?> _primarySOCController = BehaviorSubject<int?>();
  Stream<int?> get primarySOC => _primarySOCController.stream;

  final BehaviorSubject<int?> _secondaryCyclesController =
      BehaviorSubject<int?>();
  Stream<int?> get secondaryCycles => _secondaryCyclesController.stream;

  final BehaviorSubject<int?> _secondarySOCController = BehaviorSubject<int?>();
  Stream<int?> get secondarySOC => _secondarySOCController.stream;

  final BehaviorSubject<String?> _scooterNameController =
      BehaviorSubject<String?>();
  Stream<String?> get scooterName => _scooterNameController.stream;

  final BehaviorSubject<DateTime?> _lastPingController =
      BehaviorSubject<DateTime?>();
  Stream<DateTime?> get lastPing => _lastPingController.stream;

  final BehaviorSubject<int?> _scooterColorController = BehaviorSubject<int?>();
  Stream<int?> get scooterColor => _scooterColorController.stream;

  Stream<bool> get scanning => flutterBluePlus.isScanning;

  Stream<int?> get rssi => flutterBluePlus.events.onReadRssi.asyncMap((event) {
        log("RSSI: ${event.rssi}, device: ${event.device.remoteId}");
        if (event.device.remoteId == myScooter?.remoteId) {
          return event.rssi;
        }
        return null;
      });

  // MAIN FUNCTIONS

  Future<BluetoothDevice?> findEligibleScooter({
    List<String> excludedScooterIds = const [],
  }) async {
    List<BluetoothDevice> foundScooters = await getSystemScooters();
    if (foundScooters.isNotEmpty) {
      return foundScooters.firstWhere(
        (foundScooter) {
          return !excludedScooterIds.contains(foundScooter.remoteId.toString());
        },
      );
    }
    await for (BluetoothDevice foundScooter in getNearbyScooters()) {
      if (!excludedScooterIds.contains(foundScooter.remoteId.toString())) {
        flutterBluePlus.stopScan();
        return foundScooter;
      }
    }
    return null;
  }

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await flutterBluePlus.systemDevices;
    List<BluetoothDevice> systemScooters = [];
    List<String> savedScooterIds = await getSavedScooterIds();
    for (var device in systemDevices) {
      // criteria: it's named "unu Scooter" or it's one we saved
      if (device.advName == "unu Scooter" ||
          savedScooterIds.contains(device.remoteId.toString())) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters() async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> savedScooterIds = await getSavedScooterIds();
    if (savedScooterIds.isNotEmpty) {
      flutterBluePlus.startScan(
        withRemoteIds: savedScooterIds, // look for OUR scooter
        timeout: const Duration(seconds: 30),
      );
    } else {
      flutterBluePlus.startScan(
        withNames: [
          "unu Scooter",
        ], // if we don't have a saved scooter, look for ANY scooter
        timeout: const Duration(seconds: 30),
      );
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

  // spins up the whole connection process, and connects/bonds with the nearest scooter
  void start({bool restart = true}) async {
    // Remove the splash screen
    Future.delayed(const Duration(milliseconds: 1500), () {
      FlutterNativeSplash.remove();
    });
    if (Platform.isAndroid) {
      await flutterBluePlus.turnOn();
    }
    // TODO: prompt the user to turn it on manually on iOS
    log("Starting connection process...");
    _foundSth = false;
    // Cleanup in case this is a restart
    _connectedController.add(false);
    _stateController.add(ScooterState.disconnected);
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // First, see if the phone is already actively connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // get the first one, hook into its connection, and remember the ID for future reference
      // there's one! Attempt to connect to it
      _foundSth = true;
      _stateController.add(ScooterState.linking);
      // attempt to connect to what we found
      await systemScooters.first.connect();
      // wait for the connection to be established
      // Set up this scooter as ours
      myScooter = systemScooters.first;
      addSavedScooter(myScooter!.remoteId.toString());
      await setUpCharacteristics(myScooter!);
      // save this as the last known location
      _pollLocation();
      // Let everybody know
      _connectedController.add(true);
      _scooterNameController
          .add(savedScooters[myScooter!.remoteId.toString()]?.name);
      // listen for disconnects
      myScooter!.connectionState.listen((BluetoothConnectionState state) async {
        if (state == BluetoothConnectionState.disconnected) {
          _connectedController.add(false);
          _stateController.add(ScooterState.disconnected);
          log("Lost connection to scooter! :(");
          // Restart the process if we're not already doing so
          // start(); // this leads to some conflicts right now if the phone auto-connects, so we're not doing it
        }
      });
    } else {
      try {
        // If not, start scanning for nearby scooters
        getNearbyScooters().listen((foundScooter) async {
          // there's one! Attempt to connect to it
          _foundSth = true;
          _stateController.add(ScooterState.linking);
          // we could have some race conditions here if we find multiple scooters at once
          // so let's stop scanning immediately to avoid that
          flutterBluePlus.stopScan();
          // attempt to connect to what we found
          await foundScooter.connect();
          // wait for the connection to be established
          // Set up this scooter as ours
          myScooter = foundScooter;
          addSavedScooter(foundScooter.remoteId.toString());
          await setUpCharacteristics(foundScooter);
          // save this as the last known location
          _pollLocation();
          // Let everybody know
          _connectedController.add(true);
          _scooterNameController
              .add(savedScooters[myScooter!.remoteId.toString()]?.name);
          // listen for disconnects
          foundScooter.connectionState
              .listen((BluetoothConnectionState state) async {
            if (state == BluetoothConnectionState.disconnected) {
              _connectedController.add(false);
              _stateController.add(ScooterState.disconnected);
              log("Lost connection to scooter! :(");
              // Restart the process if we're not already doing so
              // start(); // this leads to some conflicts right now if the phone auto-connects, so we're not doing it
            }
          });
        });
      } catch (e) {
        // Guess this one is not happy with us
        // TODO: Handle errors more elegantly
        print("Error during search or connect!");
        print(e.toString());
        Fluttertoast.showToast(
            msg: "Error during search or connect!"); // TODO: Localize
      }
    }
    if (restart) {
      startAutoRestart();
    }
  }

  void startWithFoundDevice({required BluetoothDevice device}) async {
    try {
      log("Connecting...");
      await device.connect();
      if (Platform.isAndroid) {
        log("Bonding...");
        await device.createBond();
      }
      myScooter = device;
      addSavedScooter(device.remoteId.toString());
      await setUpCharacteristics(device);
      // save this as the last known location
      _pollLocation();
      _connectedController.add(true);
      device.connectionState.listen((BluetoothConnectionState state) async {
        if (state == BluetoothConnectionState.disconnected) {
          _connectedController.add(false);
          _stateController.add(ScooterState.disconnected);
          log("Lost connection to scooter! :(");
        }
      });
    } catch (e) {
      log("Error in startWithFoundDevice: $e");
      throw "Failed to connect to scooter!";
    }
  }

  late StreamSubscription<bool> _autoRestartSubscription;
  void startAutoRestart() async {
    if (!_autoRestarting) {
      _autoRestarting = true;
      _autoRestartSubscription =
          flutterBluePlus.isScanning.listen((scanState) async {
        _scanning = scanState;
        // retry if we stop scanning without having found anything
        if (_scanning == false && !_foundSth) {
          await Future.delayed(const Duration(seconds: 3));
          if (!_foundSth && !_scanning) {
            // make sure nothing happened in these few seconds
            log("Auto-restarting...");
            start();
          }
        }
      });
    }
  }

  void stopAutoRestart() {
    _autoRestarting = false;
    _autoRestartSubscription.cancel();
  }

  void setAutoUnlock(bool enabled) {
    _autoUnlock = enabled;
    prefs?.setBool("autoUnlock", enabled);
  }

  void setAutoUnlockThreshold(ScooterKeylessDistance distance) {
    _autoUnlockThreshold = distance.threshold;
    prefs?.setInt("autoUnlockThreshold", distance.threshold);
  }

  void setOpenSeatOnUnlock(bool enabled) {
    _openSeatOnUnlock = enabled;
    prefs?.setBool("openSeatOnUnlock", enabled);
  }

  void setHazardLocking(bool enabled) {
    _hazardLocking = enabled;
    prefs?.setBool("hazardLocking", enabled);
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

      _scooterReader = ScooterReader(
          characteristicRepository: characteristicRepository,
          stateController: _stateController,
          seatClosedController: _seatClosedController,
          handlebarController: _handlebarController,
          auxSOCController: _auxSOCController,
          cbbSOCController: _cbbSOCController,
          cbbChargingController: _cbbChargingController,
          primarySOCController: _primarySOCController,
          secondarySOCController: _secondarySOCController,
          primaryCyclesController: _primaryCyclesController,
          secondaryCyclesController: _secondaryCyclesController,
          service: this);
      _scooterReader.readAndSubscribe();
    } catch (e) {
      rethrow;
    }
  }

  // SCOOTER ACTIONS

  void unlock() {
    _sendCommand("scooter:state unlock");
    HapticFeedback.heavyImpact();

    if (_hazardLocking) {
      hazard(times: 2);
    }

    if (_openSeatOnUnlock) {
      openSeat();
    }
  }

  Future<void> wakeUpAndUnlock() async {
    wakeUp();

    await _waitForScooterState(
        ScooterState.standby, const Duration(seconds: bootingTimeSeconds + 5));

    if (_stateController.value == ScooterState.standby) {
      unlock();
    }
  }

  Future<void> lock() async {
    if (_seatClosedController.value == false) {
      log("Seat seems to be open, checking again...");
      // make really sure nothing has changed
      await characteristicRepository.seatCharacteristic.read();
      if (_seatClosedController.value == false) {
        log("Locking aborted, because seat is open!");
        throw SeatOpenException();
      }
    }
    _sendCommand("scooter:state lock");
    HapticFeedback.heavyImpact();

    if (_hazardLocking) {
      hazard(times: 1);
    }

    // don't immediately unlock again automatically
    _autoUnlockCooldown = true;
    await _sleepSeconds(keylessCooldownSeconds.toDouble());
    _autoUnlockCooldown = false;
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
    _sendCommand("wakeup",
        characteristic:
            characteristicRepository.hibernationCommandCharacteristic);
  }

  Future<void> hibernate() async {
    _sendCommand("hibernate",
        characteristic:
            characteristicRepository.hibernationCommandCharacteristic);
  }

  void _pollLocation() async {
    // Test if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw "Location services are not enabled";
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw "Location permissions are/were denied";
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      throw "Location permissions are denied forever";
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    Position position = await Geolocator.getCurrentPosition();
    savedScooters[myScooter!.remoteId.toString()]!.lastLocation =
        LatLng(position.latitude, position.longitude);
  }

  // HELPER FUNCTIONS

  void _sendCommand(String command, {BluetoothCharacteristic? characteristic}) {
    log("Sending command: $command");
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

    try {
      characteristicToSend.write(ascii.encode(command));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _waitForScooterState(
      ScooterState expectedScooterState, Duration limit) async {
    Completer<void> completer = Completer<void>();

    // Check new state every 2s
    var timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      ScooterState? scooterState = _stateController.value;
      log("Waiting for $expectedScooterState, and got: $scooterState...");
      if (scooterState == expectedScooterState) {
        log("Found $expectedScooterState, cancel timer...");
        timer.cancel();
        completer.complete();
      }
    });

    // Clean up
    Future.delayed(limit, () {
      log("Timer limit reached after $limit");
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  Map<String, SavedScooter> getSavedScooters() {
    Map<String, SavedScooter> scooters = {};

    try {
      if (prefs!.containsKey("savedScooters")) {
        Map<String, dynamic> savedScooterData =
            jsonDecode(prefs!.getString("savedScooters")!)
                as Map<String, dynamic>;

        for (String id in savedScooterData.keys) {
          if (savedScooterData[id] is Map<String, dynamic>) {
            scooters[id] = SavedScooter.fromJson(id, savedScooterData[id]);

            // Migration stuff
            if (prefs!.containsKey("lastPing")) {
              scooters[id]!.lastPing = DateTime.fromMicrosecondsSinceEpoch(
                  prefs!.getInt("lastPing")!);
            }
            if (prefs!.containsKey("lastLat") &&
                prefs!.containsKey("lastLng")) {
              scooters[id]!.lastLocation = LatLng(
                  prefs!.getDouble("lastLat")!, prefs!.getDouble("lastLng")!);
            }
            if (prefs!.containsKey("color")) {
              scooters[id]!.color = prefs!.getInt("color")!;
            }
            if (prefs!.containsKey("primarySOC")) {
              scooters[id]!.lastPrimarySOC = prefs!.getInt("primarySOC");
            }
            if (prefs!.containsKey("secondarySOC")) {
              scooters[id]!.lastSecondarySOC = prefs!.getInt("secondarySOC");
            }
            if (prefs!.containsKey("cbbSOC")) {
              scooters[id]!.lastCbbSOC = prefs!.getInt("cbbSOC");
            }
            if (prefs!.containsKey("auxSOC")) {
              scooters[id]!.lastAuxSOC = prefs!.getInt("auxSOC");
            }

            // Remove old format
            prefs!.remove("lastPing");
            prefs!.remove("lastLat");
            prefs!.remove("lastLng");
            prefs!.remove("color");
            prefs!.remove("primarySOC");
            prefs!.remove("secondarySOC");
            prefs!.remove("cbbSOC");
            prefs!.remove("auxSOC");
          }
        }
      } else if (prefs!.containsKey("savedScooterId")) {
        // Migrate old caching scheme for the scooter ID
        String id = prefs!.getString("savedScooterId")!;

        SavedScooter newScooter = SavedScooter(
          name: "Scooter Pro",
          id: id,
          color: prefs?.getInt("color"),
          lastPing: prefs!.containsKey("lastPing")
              ? DateTime.fromMicrosecondsSinceEpoch(prefs!.getInt("lastPing")!)
              : null,
          lastLocation: prefs!.containsKey("lastLat")
              ? LatLng(
                  prefs!.getDouble("lastLat")!, prefs!.getDouble("lastLng")!)
              : null,
          lastPrimarySOC: prefs?.getInt("primarySOC"),
          lastSecondarySOC: prefs?.getInt("secondarySOC"),
          lastCbbSOC: prefs?.getInt("cbbSOC"),
          lastAuxSOC: prefs?.getInt("auxSOC"),
        );

        // Merge with existing scooters
        scooters[id] = newScooter;

        // Update the preference storage with the merged data
        prefs!.setString("savedScooters", jsonEncode(scooters));

        // Remove old format
        prefs!.remove("savedScooterId");
      }
    } catch (e) {
      // Handle potential errors gracefully
      log("Error fetching saved scooters: $e");
    }

    return scooters;
  }

  Future<List<String>> getSavedScooterIds() async {
    if (savedScooters.isNotEmpty) {
      return savedScooters.keys.toList();
    } else {
      // nothing saved locally yet, check prefs
      prefs ??= await SharedPreferences.getInstance();
      if (prefs!.containsKey("savedScooters")) {
        savedScooters = getSavedScooters();
        return savedScooters.keys.toList();
      } else if (prefs!.containsKey("savedScooterId")) {
        return [prefs!.getString("savedScooterId")!];
      } else {
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
      } catch (e) {
        log(e.toString());
      }
    }

    // if the ID is not specified, we're forgetting the currently connected scooter
    if (savedScooters.isNotEmpty) {
      savedScooters.remove(id);
      prefs ??= await SharedPreferences.getInstance();
      prefs!.setString("savedScooters", jsonEncode(savedScooters));
    }
    _connectedController.add(false);
    if (Platform.isAndroid) {}
  }

  void renameSavedScooter({String? id, required String name}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log("Attempted to rename scooter, but no ID was given and we're not connected to anything!");
      return;
    }
    if (savedScooters[id] == null) {
      savedScooters[id] = SavedScooter(
        name: name,
        id: id,
      );
    } else {
      savedScooters[id]!.name = name;
    }

    prefs ??= await SharedPreferences.getInstance();
    prefs!.setString("savedScooters", jsonEncode(savedScooters));
    _scooterNameController.add(name);
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
    prefs ??= await SharedPreferences.getInstance();
    prefs!.setString("savedScooters", jsonEncode(savedScooters));
    _scooterNameController.add("Scooter Pro");
  }

  void dispose() {
    _connectedController.close();
    _stateController.close();
    _seatClosedController.close();
    _handlebarController.close();
    _auxSOCController.close();
    _cbbSOCController.close();
    _primaryCyclesController.close();
    _primarySOCController.close();
    _secondarySOCController.close();
    _secondaryCyclesController.close();
    _lastPingController.close();
    _locationTimer.cancel();
    _rssiTimer.cancel();
    _manualRefreshTimer.cancel();
  }

  Future<void> _sleepSeconds(double seconds) {
    return Future.delayed(Duration(milliseconds: (seconds * 1000).floor()));
  }
}

class SeatOpenException {}
