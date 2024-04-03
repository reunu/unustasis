import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/scooter_state.dart';

class ScooterService {
  String? savedScooterId;
  BluetoothDevice? myScooter; // reserved for a connected scooter!

  // some useful characteristsics to save
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _stateCharacteristic;
  BluetoothCharacteristic? _seatCharacteristic;
  BluetoothCharacteristic? _handlebarCharacteristic;

  ScooterService() {
    start();
  }

  // STATUS STREAMS

  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();
  Stream<bool> get connected => _connectedController.stream;

  final StreamController<ScooterState> _stateController =
      StreamController<ScooterState>.broadcast();
  Stream<ScooterState> get state => _stateController.stream;

  final StreamController<bool> _seatController =
      StreamController<bool>.broadcast();
  Stream<bool> get seatClosed => _seatController.stream;

  final StreamController<bool> _handlebarController =
      StreamController<bool>.broadcast();
  Stream<bool> get handlebarsLocked => _handlebarController.stream;

  Stream<bool> get scanning => FlutterBluePlus.isScanning;

  // MAIN FUNCTIONS

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.bondedDevices;
    List<BluetoothDevice> systemScooters = [];
    for (var device in systemDevices) {
      if (device.advName == "unu Scooter" || device.platformName == "unu Scooter" ||
          device.remoteId.toString() == await _getSavedScooter()) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters() async* {
    List<BluetoothDevice> foundScooterCache = [];
    FlutterBluePlus.startScan(
      withKeywords: ["unu"], // does this even work with no advertised name?
      // withServices: [
      //   Guid.fromString("9a590000-6e67-5d0d-aab9-ad9126b66f91")
      // ], // a service of unu Scooters, as backup
      timeout: const Duration(seconds: 30),
    );
    await for (var scanResult in FlutterBluePlus.onScanResults) {
      if (scanResult.isNotEmpty) {
        ScanResult r = scanResult.last; // the most recently found device
        if (r.advertisementData.advName == "unu Scooter" &&
            !foundScooterCache.contains(r.device)) {
          foundScooterCache.add(r.device);
          yield r.device;
        }
      }
    }
  }

  void start() async {
    _connectedController.add(false);
    _stateController.add(ScooterState.disconnected);
    _seatController.add(true);
    _handlebarController.add(true);
    // First, see if the phone is already connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // get the first one, hook into that and remember its ID
      await systemScooters.first.connect();
      setSavedScooter(systemScooters.first.remoteId.toString());
      myScooter = systemScooters.first;
      await setUpCharacteristics(systemScooters.first);
      _connectedController.add(true);
    } else {
      // If not, start scanning for nearby scooters
      getNearbyScooters().listen((foundScooter) async {
        // there's one! Attempt to connect to it
        try {
          await foundScooter.connect();
          // We hava a scooter connected! Stop scanning.
          FlutterBluePlus.stopScan();
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
      _commandCharacteristic = scooter.servicesList
          .firstWhere((service) {
            return service.serviceUuid.toString() ==
                "9a590000-6e67-5d0d-aab9-ad9126b66f91";
          })
          .characteristics
          .firstWhere((char) {
            return char.characteristicUuid.toString() ==
                "9a590001-6e67-5d0d-aab9-ad9126b66f91";
          });
      _stateCharacteristic = myScooter!.servicesList
          .firstWhere((service) {
            return service.serviceUuid.toString() ==
                "9a590020-6e67-5d0d-aab9-ad9126b66f91";
          })
          .characteristics
          .firstWhere((char) {
            return char.characteristicUuid.toString() ==
                "9a590021-6e67-5d0d-aab9-ad9126b66f91";
          });
      _seatCharacteristic = myScooter!.servicesList
          .firstWhere((service) {
            return service.serviceUuid.toString() ==
                "9a590020-6e67-5d0d-aab9-ad9126b66f91";
          })
          .characteristics
          .firstWhere((char) {
            return char.characteristicUuid.toString() ==
                "9a590022-6e67-5d0d-aab9-ad9126b66f91";
          });
      _handlebarCharacteristic = myScooter!.servicesList
          .firstWhere((service) {
            return service.serviceUuid.toString() ==
                "9a590020-6e67-5d0d-aab9-ad9126b66f91";
          })
          .characteristics
          .firstWhere((char) {
            return char.characteristicUuid.toString() ==
                "9a590023-6e67-5d0d-aab9-ad9126b66f91";
          });
      // subscribe to a bunch of values
      // Subscribe to state
      _stateCharacteristic!.setNotifyValue(true);
      _stateCharacteristic!.lastValueStream.listen(
        (value) {
          log("State received: ${ascii.decode(value)}");
          ScooterState newState = ScooterState.fromBytes(value);
          _stateController.add(newState);
        },
      );
      // Subscribe to seat
      _seatCharacteristic!.setNotifyValue(true);
      _seatCharacteristic!.lastValueStream.listen((value) {
        log("Seat received: ${ascii.decode(value)}");
        value.removeWhere((element) => element == 0);
        String seatState = ascii.decode(value).trim();
        if (seatState == "open") {
          _seatController.add(false);
        } else {
          _seatController.add(true);
        }
      });
      // Subscribe to handlebars
      _handlebarCharacteristic!.setNotifyValue(true);
      _handlebarCharacteristic!.lastValueStream.listen((value) {
        log("Handlebars received: ${ascii.decode(value)}");
        value.removeWhere((element) => element == 0);
        String handlebarState = ascii.decode(value).trim();
        if (handlebarState == "unlocked") {
          _handlebarController.add(false);
        } else {
          _handlebarController.add(true);
        }
      });
    } catch (e) {
      rethrow;
    }
  }

  // SCOOTER ACTIONS

  void unlock() {
    log("Sending unlock command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }
    try {
      _commandCharacteristic!.write(ascii.encode("scooter:state unlock"));
    } catch (e) {
      rethrow;
    }
  }

  void lock() async {
    log("Sending lock command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }
    if (await seatClosed.last) {
      throw "Seat is open!";
    }
    try {
      _commandCharacteristic!.write(ascii.encode("scooter:state lock"));
    } catch (e) {
      rethrow;
    }
  }

  void openSeat() {
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }
    try {
      _commandCharacteristic!.write(ascii.encode("scooter:seatbox open"));
    } catch (e) {
      rethrow;
    }
  }

  // HELPER FUNCTIONS

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
}
