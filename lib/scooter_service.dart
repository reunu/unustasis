import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_keyless_distance.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/domain/scooter_state.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;

class ScooterService {
  String? savedScooterId;
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet
  int? cbbRemainingCap, cbbFullCap;
  String? _state, _powerState;
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

  // some useful characteristsics to save
  List<BluetoothCharacteristic> _characteristics = [];
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _hibernationCommandCharacteristic;
  BluetoothCharacteristic? _stateCharacteristic;
  BluetoothCharacteristic? _powerStateCharacteristic;
  BluetoothCharacteristic? _seatCharacteristic;
  BluetoothCharacteristic? _handlebarCharacteristic;
  BluetoothCharacteristic? _auxSOCCharacteristic;
  // BluetoothCharacteristic? _cbbRemainingCapCharacteristic;
  // BluetoothCharacteristic? _cbbFullCapCharacteristic;
  BluetoothCharacteristic? _cbbSOCCharacteristic;
  BluetoothCharacteristic? _cbbChargingCharacteristic;
  BluetoothCharacteristic? _primaryCyclesCharacteristic;
  BluetoothCharacteristic? _primarySOCCharacteristic;
  BluetoothCharacteristic? _secondaryCyclesCharacteristic;
  BluetoothCharacteristic? _secondarySOCCharacteristic;

  final FlutterBluePlusMockable flutterBluePlus;

  // On initialization...
  ScooterService(this.flutterBluePlus) {
    // Load saved scooter ID and cached values from SharedPrefs
    SharedPreferences.getInstance().then((prefs) {
      this.prefs = prefs;
      if (prefs.containsKey("savedScooterId")) {
        savedScooterId = prefs.getString("savedScooterId");
        int? lastPing = prefs.getInt("lastPing");
        if (lastPing != null) {
          _lastPingController
              .add(DateTime.fromMicrosecondsSinceEpoch(lastPing));
          _primarySOCController.add(prefs.getInt("primarySOC"));
          _secondarySOCController.add(prefs.getInt("secondarySOC"));
          _cbbSOCController.add(prefs.getInt("cbbSOC"));
          _auxSOCController.add(prefs.getInt("auxSOC"));
          double? lastLat = prefs.getDouble("lastLat");
          double? lastLon = prefs.getDouble("lastLon");
          _autoUnlock = prefs.getBool("autoUnlock") ?? false;
          _autoUnlockThreshold = prefs.getInt("autoUnlockThreshold") ??
              ScooterKeylessDistance.regular.threshold;
          // if biometrics are disabled, we can treat everything as authenticated
          optionalAuth = !(prefs.getBool("biometrics") ?? false);
          _openSeatOnUnlock = prefs.getBool("openSeatOnUnlock") ?? false;
          _hazardLocking = prefs.getBool("hazardLocking") ?? false;
          if (lastLat != null && lastLon != null) {
            _lastLocationController.add(LatLng(lastLat, lastLon));
          }
        }
      }
    });
    // start the location polling timer
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        _pollLocation();
      }
    });
    _rssiTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (myScooter != null && myScooter!.isConnected) {
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
        _stateCharacteristic!.read();
        _seatCharacteristic!.read();
      }
    });
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

  final BehaviorSubject<LatLng?> _lastLocationController =
      BehaviorSubject<LatLng?>();
  Stream<LatLng?> get lastLocation => _lastLocationController.stream;

  // PINGING
  // We store the most recent SOC values (and, in the future, location) to SharedPrefs so that we can see the last known state even when disconnected
  //
  final BehaviorSubject<DateTime?> _lastPingController =
      BehaviorSubject<DateTime?>();
  Stream<DateTime?> get lastPing => _lastPingController.stream;

  Stream<bool> get scanning => flutterBluePlus.isScanning;

  Stream<int?> get rssi => flutterBluePlus.events.onReadRssi.asyncMap((event) {
        log("RSSI: ${event.rssi}, device: ${event.device.remoteId}");
        if (event.device.remoteId == myScooter?.remoteId) {
          return event.rssi;
        }
        return null;
      });

  // MAIN FUNCTIONS

  Future<BluetoothDevice> findEligibleScooter() async {
    List<BluetoothDevice> foundScooters = await getSystemScooters();
    if (foundScooters.isNotEmpty) {
      return foundScooters.first;
    }
    BluetoothDevice found = await getNearbyScooters().first;
    flutterBluePlus.stopScan();
    return found;
  }

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await flutterBluePlus.systemDevices;
    List<BluetoothDevice> systemScooters = [];
    for (var device in systemDevices) {
      // criteria: it's named "unu Scooter" or it's the one we saved
      if (device.advName == "unu Scooter" ||
          device.remoteId.toString() == await getSavedScooter()) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters() async* {
    List<BluetoothDevice> foundScooterCache = [];
    String? savedScooterId = await getSavedScooter();
    if (savedScooterId != null) {
      flutterBluePlus.startScan(
        withRemoteIds: [savedScooterId], // look for OUR scooter
        timeout: const Duration(seconds: 30),
      );
    } else {
      flutterBluePlus.startScan(
        withNames: [
          "unu Scooter"
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
    log("Starting connection process...");
    _foundSth = false;
    // TODO: Turn on bluetooth if it's off, or prompt the user to do so on iOS
    // Cleanup in case this is a restart
    _connectedController.add(false);
    _stateController.add(ScooterState.disconnected);
    if (myScooter != null) {
      myScooter!.disconnect();
    }
    // First, see if the phone is already actively connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // TODO: this might return multiple scooters in super rare cases
      // get the first one, hook into its connection, and remember the ID for future reference
      await systemScooters.first.connect();
      myScooter = systemScooters.first;
      setSavedScooter(systemScooters.first.remoteId.toString());
      await setUpCharacteristics(systemScooters.first);
      // save this as the last known location
      _pollLocation();
      _connectedController.add(true);
      systemScooters.first.connectionState
          .listen((BluetoothConnectionState state) async {
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
          await foundScooter.connect(
              //autoConnect: true, // significantly slows down the connection process
              );
          // Set up this scooter as ours
          myScooter = foundScooter;
          setSavedScooter(foundScooter.remoteId.toString());
          await setUpCharacteristics(foundScooter);
          // save this as the last known location
          _pollLocation();
          // Let everybody know
          _connectedController.add(true);
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
        // TODO: we'll probably need some error handling here
        log("Error during search or connect!");
        log(e.toString());
      }
    }
    if (restart) {
      startAutoRestart();
    }
  }

  void startWithFoundDevice({required BluetoothDevice device}) async {
    try {
      await device.connect();
      myScooter = device;
      setSavedScooter(device.remoteId.toString());
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
    } else {
      //Auto-restart already on, ignoring to avoid duplicates
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
      await scooter.discoverServices();
      _commandCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590000-6e67-5d0d-aab9-ad9126b66f91",
          "9a590001-6e67-5d0d-aab9-ad9126b66f91");
      _hibernationCommandCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590000-6e67-5d0d-aab9-ad9126b66f91",
          "9a590002-6e67-5d0d-aab9-ad9126b66f91");
      _stateCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590021-6e67-5d0d-aab9-ad9126b66f91");
      _powerStateCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900a0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900a1-6e67-5d0d-aab9-ad9126b66f91");
      _seatCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590022-6e67-5d0d-aab9-ad9126b66f91");
      _handlebarCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590023-6e67-5d0d-aab9-ad9126b66f91");
      _auxSOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590040-6e67-5d0d-aab9-ad9126b66f91",
          "9a590044-6e67-5d0d-aab9-ad9126b66f91");
      //_cbbRemainingCapCharacteristic = _findCharacteristic(
      //     myScooter!,
      //     "9a590060-6e67-5d0d-aab9-ad9126b66f91",
      //     "9a590063-6e67-5d0d-aab9-ad9126b66f91");
      // _cbbFullCapCharacteristic = _findCharacteristic(
      //     myScooter!,
      //     "9a590060-6e67-5d0d-aab9-ad9126b66f91",
      //     "9a590064-6e67-5d0d-aab9-ad9126b66f91");
      _cbbSOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590060-6e67-5d0d-aab9-ad9126b66f91",
          "9a590061-6e67-5d0d-aab9-ad9126b66f91");
      _cbbChargingCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590060-6e67-5d0d-aab9-ad9126b66f91",
          "9a590072-6e67-5d0d-aab9-ad9126b66f91");
      _primaryCyclesCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900e6-6e67-5d0d-aab9-ad9126b66f91");
      _primarySOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900e9-6e67-5d0d-aab9-ad9126b66f91");
      _secondaryCyclesCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900f2-6e67-5d0d-aab9-ad9126b66f91");
      _secondarySOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900f5-6e67-5d0d-aab9-ad9126b66f91");
      // Set up the characteristics list
      _characteristics = [
        _commandCharacteristic!,
        _hibernationCommandCharacteristic!,
        _stateCharacteristic!,
        _powerStateCharacteristic!,
        _seatCharacteristic!,
        _handlebarCharacteristic!,
        _auxSOCCharacteristic!,
        // _cbbRemainingCapCharacteristic!,
        // _cbbFullCapCharacteristic!,
        _cbbSOCCharacteristic!,
        _cbbChargingCharacteristic!,
        _primaryCyclesCharacteristic!,
        _primarySOCCharacteristic!,
        _secondaryCyclesCharacteristic!,
        _secondarySOCCharacteristic!,
      ];
      // subscribe to a bunch of values
      // Subscribe to state
      _subscribeString(_stateCharacteristic!, "State", (String value) {
        _state = value;
        _updateScooterState();
      });
      // Subscribe to power state for correct hibernation
      _subscribeString(_powerStateCharacteristic!, "Power State",
          (String value) {
        _powerState = value;
        _updateScooterState();
      });
      // Subscribe to seat
      _subscribeString(_seatCharacteristic!, "Seat", (String seatState) {
        if (seatState == "open") {
          _seatClosedController.add(false);
        } else {
          _seatClosedController.add(true);
        }
      });
      // Subscribe to handlebars
      _subscribeString(_handlebarCharacteristic!, "Handlebars",
          (String handlebarState) {
        if (handlebarState == "unlocked") {
          _handlebarController.add(false);
        } else {
          _handlebarController.add(true);
        }
      });
      // Subscribe to aux battery SOC
      _auxSOCCharacteristic!.setNotifyValue(true);
      _auxSOCCharacteristic!.lastValueStream.listen((value) async {
        int? soc = _convertUint32ToInt(value);
        log("Aux SOC received: $soc");
        _auxSOCController.add(soc);
        if (soc != null) {
          ping();
          prefs ??= await SharedPreferences.getInstance();
          prefs!.setInt("auxSOC", soc);
        }
      });
      // // subscribe to CBB remaining capacity
      // _cbbRemainingCapCharacteristic!.setNotifyValue(true);
      // _cbbRemainingCapCharacteristic!.lastValueStream.listen((value) {
      //   int? remainingCap = _convertUint32ToInt(value);
      //   log("CBB remaining capacity received: $remainingCap");
      //   cbbRemainingCap = remainingCap;
      //   if (cbbRemainingCap != null && cbbFullCap != null) {
      //     _cbbHealthController.add(cbbRemainingCap! / cbbFullCap!);
      //   }
      // });
      // // subscribe to CBB full capacity
      // _cbbFullCapCharacteristic!.setNotifyValue(true);
      // _cbbFullCapCharacteristic!.lastValueStream.listen((value) {
      //   int? fullCap = _convertUint32ToInt(value);
      //   log("CBB full capacity received: $fullCap");
      //   cbbFullCap = fullCap;
      //   if (cbbRemainingCap != null && cbbFullCap != null) {
      //     _cbbHealthController.add(cbbRemainingCap! / cbbFullCap!);
      //   }
      // });
      // Subscribe to internal CBB SOC
      _cbbSOCCharacteristic!.setNotifyValue(true);
      _cbbSOCCharacteristic!.lastValueStream.listen((value) async {
        int? soc = value.firstOrNull;
        log("cbb SOC received: ${value.toString()}");
        _cbbSOCController.add(soc);
        if (soc != null) {
          ping();
          prefs ??= await SharedPreferences.getInstance();
          prefs!.setInt("cbbSOC", soc);
        }
      });
      // subscribe to CBB charging status
      _subscribeString(_cbbChargingCharacteristic!, "CBB charging",
          (String chargingState) {
        if (chargingState == "charging") {
          _cbbChargingController.add(true);
        } else if (chargingState == "not-charging") {
          _cbbChargingController.add(false);
        }
      });
      // Subscribe to primary battery charge cycles
      _primaryCyclesCharacteristic!.setNotifyValue(true);
      _primaryCyclesCharacteristic!.lastValueStream.listen((value) {
        int? cycles = _convertUint32ToInt(value);
        log("Primary battery cycles received: $cycles");
        _primaryCyclesController.add(cycles);
      });
      // Subscribe to primary SOC
      _primarySOCCharacteristic!.setNotifyValue(true);
      _primarySOCCharacteristic!.lastValueStream.listen((value) async {
        int? soc = _convertUint32ToInt(value);
        log("Primary SOC received: $soc");
        _primarySOCController.add(soc);
        if (soc != null) {
          ping();
          prefs ??= await SharedPreferences.getInstance();
          prefs!.setInt("primarySOC", soc);
        }
      });
      // Subscribe to secondary battery charge cycles
      _secondaryCyclesCharacteristic!.setNotifyValue(true);
      _secondaryCyclesCharacteristic!.lastValueStream.listen((value) {
        int? cycles = _convertUint32ToInt(value);
        log("Secondary battery cycles received: $cycles");
        _secondaryCyclesController.add(cycles);
      });
      // Subscribe to secondary SOC
      _secondarySOCCharacteristic!.setNotifyValue(true);
      _secondarySOCCharacteristic!.lastValueStream.listen((value) async {
        int? soc = _convertUint32ToInt(value);
        log("Secondary SOC received: $soc");
        _secondarySOCController.add(soc);
        if (soc != null) {
          ping();
          prefs ??= await SharedPreferences.getInstance();
          prefs!.setInt("secondarySOC", soc);
        }
      });
      // Read each value once to get the ball rolling
      _stateCharacteristic!.read();
      _powerStateCharacteristic!.read();
      _seatCharacteristic!.read();
      _handlebarCharacteristic!.read();
      _auxSOCCharacteristic!.read();
      _cbbSOCCharacteristic!.read();
      _cbbChargingCharacteristic!.read();
      _primaryCyclesCharacteristic!.read();
      _primarySOCCharacteristic!.read();
      _secondaryCyclesCharacteristic!.read();
      _secondarySOCCharacteristic!.read();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _updateScooterState() async {
    log("Update scooter state from state: '$_state' and power state: '$_powerState'");
    if (_state != null && _powerState != null) {
      ScooterPowerState powerState = ScooterPowerState.fromString(_powerState);
      ScooterState newState =
          ScooterState.fromStateAndPowerState(_state!, powerState);
      _stateController.add(newState);
    }
  }

  BluetoothCharacteristic? _findCharacteristic(
      BluetoothDevice device, String serviceUuid, String characteristicUuid) {
    log("Finding characteristic $characteristicUuid in service $serviceUuid...");
    return device.servicesList
        .firstWhere((service) => service.serviceUuid.toString() == serviceUuid)
        .characteristics
        .firstWhere(
            (char) => char.characteristicUuid.toString() == characteristicUuid);
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

  void lock() async {
    if (_seatClosedController.value == false) {
      log("Seat seems to be open, checking again...");
      // make really sure nothing has changed
      await _seatCharacteristic!.read();
      if (_seatClosedController.value == false) {
        log("Locking aborted, because seat is open!");
        throw "SEAT_OPEN";
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
    _sendCommand("wakeup", characteristic: _hibernationCommandCharacteristic);
  }

  Future<void> hibernate() async {
    _sendCommand("hibernate",
        characteristic: _hibernationCommandCharacteristic);
  }

  void ping() async {
    _lastPingController.add(DateTime.now());
    prefs ??= await SharedPreferences.getInstance();
    prefs!.setInt("lastPing", DateTime.now().microsecondsSinceEpoch);
  }

  void _pollLocation() async {
    // Test if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
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
    _lastLocationController.add(LatLng(position.latitude, position.longitude));
    if (prefs != null) {
      prefs!.setDouble("lastLat", position.latitude);
      prefs!.setDouble("lastLon", position.longitude);
    }
  }

  // HELPER FUNCTIONS

  void _subscribeString(
      BluetoothCharacteristic characteristic, String name, Function callback) {
    // Subscribe to value
    characteristic.setNotifyValue(true);
    characteristic.lastValueStream.listen((value) {
      log("$name received: ${ascii.decode(value)}");
      String state = _convertBytesToString(value);
      callback(state);
    });
  }

  String _convertBytesToString(List<int> value) {
    value.removeWhere((element) => element == 0);
    String state = ascii.decode(value).trim();
    return state;
  }

  void _sendCommand(String command, {BluetoothCharacteristic? characteristic}) {
    log("Sending command: $command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }

    var characteristicToSend = _commandCharacteristic;
    if (characteristic != null) {
      characteristicToSend = characteristic;
    }

    try {
      characteristicToSend!.write(ascii.encode(command));
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

  Future<String?> getSavedScooter() async {
    if (savedScooterId != null) {
      return savedScooterId;
    }
    prefs ??= await SharedPreferences.getInstance();
    return prefs!.getString("savedScooterId");
  }

  void forgetSavedScooter() async {
    stopAutoRestart();
    _connectedController.add(false);
    savedScooterId = null;
    prefs ??= await SharedPreferences.getInstance();
    prefs!.remove("savedScooterId");
    if (Platform.isAndroid) {
      myScooter?.removeBond();
    }
  }

  void setSavedScooter(String id) async {
    savedScooterId = id;
    prefs ??= await SharedPreferences.getInstance();
    prefs!.setString("savedScooterId", id);
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

  // thanks gemini advanced <3
  int? _convertUint32ToInt(List<int> uint32data) {
    log("Converting $uint32data to int.");
    if (uint32data.length != 4) {
      log("Received empty data for uint32 conversion. Ignoring.");
      return null;
    }

    // Little-endian to big-endian interpretation (important for proper UInt32 conversion)
    return (uint32data[3] << 24) +
        (uint32data[2] << 16) +
        (uint32data[1] << 8) +
        uint32data[0];
  }

  Future<void> _sleepSeconds(double seconds) async {
    await Future.delayed(Duration(milliseconds: (seconds * 1000).floor()));
  }
}
