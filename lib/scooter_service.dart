import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScooterService {
  String? savedScooterId;
  BluetoothDevice? myScooter; // reserved for a connected scooter!

  ScooterService() {
    start();
  }

  // STATUS STREAMS

  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();
  Stream<bool> get connected => _connectedController.stream;

  Stream<bool> get scanning => FlutterBluePlus.isScanning;

  // MAIN FUNCTIONS

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.systemDevices;
    List<BluetoothDevice> systemScooters = [];
    for (var device in systemDevices) {
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

  Future<void> connectScooter(BluetoothDevice scooter) async {
    if (scooter.isConnected) {
      log("Already connected!");
      return;
    }
    await scooter.connect(
      timeout: const Duration(seconds: 20),
    );
    log("Connected to ${scooter.advName}!");
    return;
  }

  void start() async {
    _connectedController.add(false);
    // First, see if the phone is already connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // get the first one, hook into that and remember its ID
      connectScooter(systemScooters.first);
    } else {
      // If not, start scanning for nearby scooters
      getNearbyScooters().listen((scooter) async {
        // there's one! Attempt to connect to it
        try {
          await connectScooter(scooter);
          // We hava a scooter connected! Stop scanning.
          FlutterBluePlus.stopScan();
          // Set up this scooter as ours
          myScooter = scooter;
          setSavedScooter(scooter.remoteId.toString());
          await scooter.discoverServices();
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

  void unlock() {
    myScooter?.servicesList
        .firstWhere((service) {
          return service.serviceUuid.toString() ==
              "9a590000-6e67-5d0d-aab9-ad9126b66f91";
        })
        .characteristics
        .firstWhere((char) {
          return char.characteristicUuid.toString() ==
              "9a590001-6e67-5d0d-aab9-ad9126b66f91";
        })
        .write(ascii.encode("scooter:state unlock"));
  }

  void lock() {
    myScooter?.servicesList
        .firstWhere((service) {
          return service.serviceUuid.toString() ==
              "9a590000-6e67-5d0d-aab9-ad9126b66f91";
        })
        .characteristics
        .firstWhere((char) {
          return char.characteristicUuid.toString() ==
              "9a590001-6e67-5d0d-aab9-ad9126b66f91";
        })
        .write(ascii.encode("scooter:state lock"));
  }
}
