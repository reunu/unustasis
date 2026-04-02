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
    required bool hasSavedScooters,
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
      hasSavedScooters: hasSavedScooters,
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
    required bool hasSavedScooters,
    bool preferSavedScooters = true,
  }) async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> savedScooterIds = await getIds(onlyAutoConnect: true);

    if (savedScooterIds.isEmpty && hasSavedScooters) {
      _log.info(
        "We have saved scooters, but none with auto-connect enabled. Not scanning.",
      );
      return;
    }

    if (hasSavedScooters && preferSavedScooters) {
      _log.info("Looking for our scooters (saved IDs: $savedScooterIds)");
      try {
        _flutterBluePlus.startScan(
          withRemoteIds: savedScooterIds,
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

    await for (var scanResult in _flutterBluePlus.onScanResults) {
      if (scanResult.isNotEmpty) {
        ScanResult r = scanResult.last;
        if (!foundScooterCache.contains(r.device)) {
          foundScooterCache.add(r.device);
          yield r.device;
        }
      }
    }
  }
}
