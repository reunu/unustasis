import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../flutter/blue_plus_mockable.dart';

final _log = Logger('BleScanner');

class BleScanner {
  final FlutterBluePlusMockable _flutterBluePlus;

  BleScanner(this._flutterBluePlus);

  /// Finds the first eligible scooter — checks system-connected devices first,
  /// then falls back to a BLE scan.
  Future<BluetoothDevice?> findEligibleScooter({
    required Future<List<String>> Function({required bool onlyAutoConnect}) getIds,
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    if (includeSystemScooters) {
      _log.fine("Searching system devices");
      List<BluetoothDevice> foundScooters = await getSystemScooters(
        getIds: getIds,
      );
      if (foundScooters.isNotEmpty) {
        _log.fine("Found system scooter");
        foundScooters = foundScooters.where((foundScooter) {
          return !excludedScooterIds.contains(foundScooter.remoteId.toString());
        }).toList();
        if (foundScooters.isNotEmpty) {
          _log.fine("System scooter is not excluded from search, returning!");
          return foundScooters.first;
        }
      }
    }
    _log.info("Searching nearby devices");
    await for (BluetoothDevice foundScooter in getNearbyScooters(
      getIds: getIds,
      preferSavedScooters: excludedScooterIds.isEmpty,
    )) {
      _log.fine("Found scooter: ${foundScooter.remoteId.toString()}");
      if (!excludedScooterIds.contains(foundScooter.remoteId.toString())) {
        _log.fine("Scooter's ID is not excluded, stopping scan and returning!");
        _flutterBluePlus.stopScan();
        return foundScooter;
      }
    }
    _log.info("Scan over, nothing found");
    return null;
  }

  /// Checks for scooters already connected at the OS level.
  Future<List<BluetoothDevice>> getSystemScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect}) getIds,
  }) async {
    List<BluetoothDevice> systemDevices = await _flutterBluePlus.systemDevices([
      Guid("9a590000-6e67-5d0d-aab9-ad9126b66f91"),
    ]);
    List<BluetoothDevice> systemScooters = [];
    List<String> savedScooterIds = await getIds(onlyAutoConnect: true);
    for (var device in systemDevices) {
      if (savedScooterIds.contains(device.remoteId.toString())) {
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  /// Scans for nearby scooters over BLE.
  /// If we have saved scooters and [preferSavedScooters] is true, scans only
  /// for those specific remote IDs. Otherwise scans for any "unu Scooter".
  Stream<BluetoothDevice> getNearbyScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect}) getIds,
    bool preferSavedScooters = true,
  }) async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> autoConnectScooterIds = await getIds(onlyAutoConnect: true);

    // Don't early-return here. Even if no scooters have autoConnect enabled,
    // the user might still want to search for new scooters. The logic below
    // will handle scanning appropriately based on preferSavedScooters.

    if (autoConnectScooterIds.isNotEmpty && preferSavedScooters) {
      _log.info("Looking for our scooters (saved IDs: $autoConnectScooterIds)");
      try {
        _flutterBluePlus.startScan(
          withRemoteIds: autoConnectScooterIds,
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        _log.severe("Failed to start scan", e, stack);
      }
    } else {
      _log.info("Looking for any scooter, since we have no saved scooters");
      try {
        _flutterBluePlus.startScan(
          withNames: ["unu Scooter"],
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        _log.severe("Failed to start scan", e, stack);
      }
    }

    // onScanResults is a broadcast stream that never closes, so we wrap it in
    // a StreamController that closes when isScanning goes false. Without this,
    // the await-for loop hangs forever when no scooter is found, and start()
    // never reaches startAutoRestart().
    final scanResultsController = StreamController<List<ScanResult>>();

    final resultsSub = _flutterBluePlus.onScanResults.listen(
      (r) {
        if (!scanResultsController.isClosed) scanResultsController.add(r);
      },
    );

    // isScanning emits the current value immediately on listen. Skip the initial
    // value and only close when it transitions from true→false.
    final isScanSub = _flutterBluePlus.isScanning.skip(1).listen((isScanning) {
      if (!isScanning && !scanResultsController.isClosed) {
        scanResultsController.close();
      }
    });

    try {
      await for (var scanResult in scanResultsController.stream) {
        if (scanResult.isNotEmpty) {
          ScanResult r = scanResult.last;
          if (!foundScooterCache.contains(r.device)) {
            foundScooterCache.add(r.device);
            yield r.device;
          }
        }
      }
    } finally {
      resultsSub.cancel();
      isScanSub.cancel();
      if (!scanResultsController.isClosed) scanResultsController.close();
    }
  }
}
