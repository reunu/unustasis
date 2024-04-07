import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/scooter_state.dart';

class ScooterService {
  String? savedScooterId;
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet

  // some useful characteristsics to save
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _stateCharacteristic;
  BluetoothCharacteristic? _seatCharacteristic;
  BluetoothCharacteristic? _handlebarCharacteristic;
  BluetoothCharacteristic? _internalCbbSOCCharacteristic;
  BluetoothCharacteristic? _primarySOCCharacteristic;
  BluetoothCharacteristic? _secondarySOCCharacteristic;

  ScooterService() {
    start();
    FlutterBluePlus.isScanning.listen((scanning) async {
      // retry if we stop scanning without having found anything
      if (!scanning && !_foundSth) {
        await Future.delayed(const Duration(seconds: 5));
        if (!_foundSth && !scanning) {
          // make sure nothing happened in these few seconds
          start();
        }
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

  // for debugging purposes
  final BehaviorSubject<String?> _stateRawController =
      BehaviorSubject<String?>();
  Stream<String?> get stateRaw => _stateRawController.stream;

  final BehaviorSubject<bool?> _seatController = BehaviorSubject<bool?>();
  Stream<bool?> get seatClosed => _seatController.stream;

  final BehaviorSubject<bool?> _handlebarController = BehaviorSubject<bool?>();
  Stream<bool?> get handlebarsLocked => _handlebarController.stream;

  final BehaviorSubject<int?> _internalCbbSOCController =
      BehaviorSubject<int?>();
  Stream<int?> get internalCbbSOC => _internalCbbSOCController.stream;

  final BehaviorSubject<int?> _primarySOCController = BehaviorSubject<int?>();
  Stream<int?> get primarySOC => _primarySOCController.stream;

  final BehaviorSubject<int?> _secondarySOCController = BehaviorSubject<int?>();
  Stream<int?> get secondarySOC => _secondarySOCController.stream;

  Stream<bool> get scanning => FlutterBluePlus.isScanning;

  // MAIN FUNCTIONS

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.systemDevices;
    List<BluetoothDevice> systemScooters = [];
    for (var device in systemDevices) {
      // criteria: it's named "unu Scooter" or it's the one we saved
      if (device.advName == "unu Scooter" ||
          device.remoteId.toString() == await _getSavedScooter()) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters() async* {
    List<BluetoothDevice> foundScooterCache = [];
    String? savedScooterId = await _getSavedScooter();
    if (savedScooterId != null) {
      FlutterBluePlus.startScan(
        withRemoteIds: [savedScooterId], // look for OUR scooter
        timeout: const Duration(seconds: 30),
      );
    } else {
      FlutterBluePlus.startScan(
        withNames: [
          "unu Scooter"
        ], // if we don't have a saved scooter, look for A scooter
        timeout: const Duration(seconds: 30),
      );
    }
    await for (var scanResult in FlutterBluePlus.onScanResults) {
      if (scanResult.isNotEmpty) {
        ScanResult r = scanResult.last; // the most recently found device
        if (!foundScooterCache.contains(r.device)) {
          foundScooterCache.add(r.device);
          yield r.device;
        }
      }
    }
  }

  void start() async {
    _foundSth = false;
    // TODO: Turn on bluetooth if it's off, or prompt the user to do so on iOS
    // First, see if the phone is already actively connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // TODO: this might return multiple scooters in super rare cases
      // get the first one, hook into its connection, and remember the ID for future reference
      await systemScooters.first.connect();
      myScooter = systemScooters.first;
      setSavedScooter(systemScooters.first.remoteId.toString());
      await setUpCharacteristics(systemScooters.first);
      _connectedController.add(true);
    } else {
      // If not, start scanning for nearby scooters
      getNearbyScooters().listen((foundScooter) async {
        // there's one! Attempt to connect to it
        _foundSth = true;
        _stateController.add(ScooterState.linking);
        try {
          // we could have some race conditions here if we find multiple scooters at once
          // so let's stop scanning immediately to avoid that
          FlutterBluePlus.stopScan();
          // attempt to connect to what we found
          await foundScooter.connect(
              //autoConnect: true, // significantly slows down the connection process
              );
          // Set up this scooter as ours
          myScooter = foundScooter;
          setSavedScooter(foundScooter.remoteId.toString());
          await setUpCharacteristics(foundScooter);
          // Let everybody know
          _connectedController.add(true);
        } catch (e) {
          // Guess this one is not happy with us
          // TODO: we'll probably need some error handling here
          log(e.toString());
        }
      });
    }
  }

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
      _stateCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590021-6e67-5d0d-aab9-ad9126b66f91");
      _seatCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590022-6e67-5d0d-aab9-ad9126b66f91");
      _handlebarCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590020-6e67-5d0d-aab9-ad9126b66f91",
          "9a590023-6e67-5d0d-aab9-ad9126b66f91");
      _internalCbbSOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a590060-6e67-5d0d-aab9-ad9126b66f91",
          "9a590061-6e67-5d0d-aab9-ad9126b66f91");
      _primarySOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900e9-6e67-5d0d-aab9-ad9126b66f91");
      _secondarySOCCharacteristic = _findCharacteristic(
          myScooter!,
          "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
          "9a5900f2-6e67-5d0d-aab9-ad9126b66f91");
      // subscribe to a bunch of values
      // Subscribe to state
      _stateCharacteristic!.setNotifyValue(true);
      _stateCharacteristic!.lastValueStream.listen(
        (value) {
          log("State received: ${ascii.decode(value)}");
          ScooterState newState = ScooterState.fromBytes(value);
          _stateController.add(newState);
          _stateRawController.add(ascii.decode(value));
        },
      );
      // Subscribe to seat
      _subscribeBoolean(_seatCharacteristic!, "Seat", (String seatState) {
        if (seatState == "open") {
          _seatController.add(false);
        } else {
          _seatController.add(true);
        }
      });
      // Subscribe to handlebars
      _subscribeBoolean(_handlebarCharacteristic!, "Handlebars",
          (String handlebarState) {
        if (handlebarState == "unlocked") {
          _handlebarController.add(false);
        } else {
          _handlebarController.add(true);
        }
      });
      // Subscribe to internal CBB SOC
      _internalCbbSOCCharacteristic!.setNotifyValue(true);
      _internalCbbSOCCharacteristic!.lastValueStream.listen((value) {
        if (value.isEmpty) return;
        print("### Internal CBB received: $value");
        _internalCbbSOCController.add(value.first);
      });
      // Subscribe to primary SOC
      _primarySOCCharacteristic!.setNotifyValue(true);
      _primarySOCCharacteristic!.lastValueStream.listen((value) {
        int? soc = _convertUint32ToInt(value);
        log("Primary SOC received: $soc");
        _primarySOCController.add(soc);
      });
      // Subscribe to secondary SOC
      _secondarySOCCharacteristic!.setNotifyValue(true);
      _secondarySOCCharacteristic!.lastValueStream.listen((value) {
        int? soc = _convertUint32ToInt(value);
        log("Secondary SOC received: $soc");
        _secondarySOCController.add(soc);
      });
      // Read each value once to get the ball rolling
      _stateCharacteristic!.read();
      _seatCharacteristic!.read();
      _handlebarCharacteristic!.read();
      _internalCbbSOCCharacteristic!.read();
      _primarySOCCharacteristic!.read();
      _secondarySOCCharacteristic!.read();
    } catch (e) {
      rethrow;
    }
  }

  BluetoothCharacteristic? _findCharacteristic(
      BluetoothDevice device, String serviceUuid, String characteristicUuid) {
    return device.servicesList
        .firstWhere((service) => service.serviceUuid.toString() == serviceUuid)
        .characteristics
        .firstWhere(
            (char) => char.characteristicUuid.toString() == characteristicUuid);
  }

  // SCOOTER ACTIONS

  void unlock() {
    _sendCommand("scooter:state unlock");
  }

  void lock() {
    // double check for open seat, maybe?
    _sendCommand("scooter:state lock");
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

  // HELPER FUNCTIONS

  void _subscribeBoolean(
      BluetoothCharacteristic characteristic, String name, Function callback) {
    // Subscribe to seat
    characteristic.setNotifyValue(true);
    characteristic.lastValueStream.listen((value) {
      log("$name received: ${ascii.decode(value)}");
      value.removeWhere((element) => element == 0);
      String state = ascii.decode(value).trim();
      callback(state);
    });
  }

  void _sendCommand(String command) {
    log("Sending command: $command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }
    try {
      _commandCharacteristic!.write(ascii.encode(command));
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> _getSavedScooter() async {
    if (savedScooterId != null) {
      return savedScooterId;
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("savedScooterId");
  }

  void setSavedScooter(String id) async {
    savedScooterId = id;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("savedScooterId", id);
  }

  void dispose() {
    _connectedController.close();
    _stateController.close();
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
}
