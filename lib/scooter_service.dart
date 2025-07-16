import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
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
import '../domain/connection_status.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';
import 'ble_command_service.dart';
import 'cloud_command_service.dart';
import 'cloud_service.dart';
import 'command_service.dart';
import 'services/ble_connection_service.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;
const handlebarCheckSeconds = 5;

class ScooterService with ChangeNotifier {
  final log = Logger('ScooterService');
  Map<String, SavedScooter> savedScooters = {};
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet
  bool _autoRestarting = false;
  bool _autoUnlock = false;
  int _autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool _openSeatOnUnlock = false;
  bool _hazardLocking = false;
  bool _warnOfUnlockedHandlebars = true;
  bool _autoUnlockCooldown = false;
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
  
  // New architecture: current scooter and connection service
  SavedScooter? _currentScooter;
  BLEConnectionService? _bleConnectionService;
  Timer? _availabilityTimer;
  
  // Cloud services
  CloudService? _cloudService;
  BLECommandService? _bleCommandService;
  CloudCommandService? _cloudCommandService;
  bool _cloudServicesInitialized = false;
  
  // Command availability cache
  Map<CommandType, bool> _commandAvailabilityCache = {};
  
  // Cloud connectivity cache
  bool _isCloudOnline = false;
  
  // Cloud scooter data cache
  Map<int, Map<String, dynamic>> _cloudScooterCache = {};

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
        "Loaded ${savedScooters.length} saved scooters from SharedPreferences");
    await seedStreamsWithCache();
    log.info("Seeded streams with cached values");
    restoreCachedSettings();
    log.info("Restored cached settings");
    
    // Cloud cache will be refreshed only when user logs in or links scooters
  }

  // On initialization...
  ScooterService(this.flutterBluePlus, {this.isInBackgroundService = false}) {
    loadCachedData();
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
        // only refresh state and seatbox, for now
        log.info("Auto-refresh...");
        characteristicRepository.stateCharacteristic!.read();
        characteristicRepository.seatCharacteristic!.read();
      }
    });
  }

  void _ensureCloudServicesInitialized() {
    if (_cloudServicesInitialized) return;
    
    _cloudService = CloudService(this);
    _cloudServicesInitialized = true;
  }
  
  void _ensureBLECommandServiceInitialized() {
    // Only initialize if BLE connection service is available
    if (_bleCommandService == null && _bleConnectionService != null) {
      _bleCommandService = BLECommandService(_bleConnectionService!);
    }
  }
  
  void _ensureCloudCommandServiceInitialized() {
    if (_cloudCommandService == null && _cloudService != null) {
      _cloudCommandService = CloudCommandService(_cloudService!, _getCurrentCloudScooterId);
    }
  }

  Future<int?> _getCurrentCloudScooterId() async {
    // Use current scooter for cloud commands
    return _currentScooter?.cloudScooterId;
  }

  CloudService get cloudService {
    _ensureCloudServicesInitialized();
    return _cloudService!;
  }

  /// Execute a command using BLE first, then cloud as fallback
  Future<bool> _executeCommand(CommandType command, {BuildContext? context}) async {
    // Ensure services are initialized
    _ensureCloudServicesInitialized();
    _ensureBLECommandServiceInitialized();
    _ensureCloudCommandServiceInitialized();
    
    // Try BLE first
    if (await _bleCommandService!.isAvailable(command)) {
      log.info('Executing BLE command: $command');
      return await _bleCommandService!.execute(command);
    }
    
    // Fall back to cloud if BLE is not available
    if (await _cloudCommandService!.isAvailable(command)) {
      log.info('Executing cloud command: $command');
      
      // Check if confirmation is needed for cloud commands
      if (await _cloudCommandService!.needsConfirmation(command)) {
        if (context != null && context.mounted) {
          bool confirmed = await _showCloudCommandConfirmation(context, command);
          if (!confirmed) {
            log.info('Cloud command $command cancelled by user');
            return false;
          }
        } else {
          log.warning('Cloud command $command requires confirmation but no context provided');
          return false;
        }
      }
      
      return await _cloudCommandService!.execute(command);
    }
    
    log.warning('Command $command not available via BLE or cloud');
    return false;
  }

  Future<bool> _showCloudCommandConfirmation(BuildContext context, CommandType command) async {
    String commandName = _getCommandDisplayName(context, command);
    String title = FlutterI18n.translate(context, "cloud_command_confirm_title");
    String message = FlutterI18n.translate(context, "cloud_command_confirm_message", 
        translationParams: {"command": commandName});
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(FlutterI18n.translate(context, "cancel")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(FlutterI18n.translate(context, "confirm")),
            ),
          ],
        );
      },
    ) ?? false;
  }

  String _getCommandDisplayName(BuildContext context, CommandType command) {
    switch (command) {
      case CommandType.lock:
        return FlutterI18n.translate(context, "controls_lock");
      case CommandType.unlock:
        return FlutterI18n.translate(context, "controls_unlock");
      case CommandType.wakeUp:
        return FlutterI18n.translate(context, "controls_wake_up");
      case CommandType.hibernate:
        return FlutterI18n.translate(context, "controls_hibernate");
      case CommandType.openSeat:
        return FlutterI18n.translate(context, "home_seat_button_closed");
      case CommandType.honk:
        return FlutterI18n.translate(context, "cloud_command_honk");
      case CommandType.alarm:
        return FlutterI18n.translate(context, "cloud_command_alarm");
      case CommandType.blinkerLeft:
        return FlutterI18n.translate(context, "controls_blink_left");
      case CommandType.blinkerRight:
        return FlutterI18n.translate(context, "controls_blink_right");
      case CommandType.blinkerBoth:
        return FlutterI18n.translate(context, "controls_blink_hazard");
      case CommandType.blinkerOff:
        return FlutterI18n.translate(context, "controls_blink_off");
    }
  }

  Future<void> restoreCachedSettings() async {
    _autoUnlock = await prefs.getBool("autoUnlock") ?? false;
    _autoUnlockThreshold = await prefs.getInt("autoUnlockThreshold") ??
        ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(await prefs.getBool("biometrics") ?? false);
    _openSeatOnUnlock = await prefs.getBool("openSeatOnUnlock") ?? false;
    _hazardLocking = await prefs.getBool("hazardLocking") ?? false;
    _warnOfUnlockedHandlebars =
        await prefs.getBool("unlockedHandlebarsWarning") ?? true;
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
            "we'll reenable autoconnect for this scooter, since it's the only one available");
        savedScooters.values.first.autoConnect = true;
        updateBackgroundService({"updateSavedScooters": true});
      }
      return savedScooters.values.first;
    } else {
      List<SavedScooter> autoConnectScooters =
          filterAutoConnectScooters(savedScooters).values.toList();
      // get the saved scooter with the most recent ping
      for (var scooter in autoConnectScooters) {
        if (mostRecentScooter == null ||
            scooter.lastPing.isAfter(mostRecentScooter.lastPing)) {
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
    _targetScooter = mostRecentScooter;
    _lastLocation = mostRecentScooter?.lastLocation;
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
    _targetScooter = SavedScooter(id: "12345", name: "Demo Scooter");

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

  // Target scooter system - unified source of scooter data
  SavedScooter? _targetScooter;
  bool _isTargetingSpecificScooter = false;

  String? get scooterName => _currentScooter?.name;
  set scooterName(String? scooterName) {
    if (_currentScooter != null) {
      _currentScooter!.name = scooterName ?? "Scooter Pro";
    }
    notifyListeners();
  }

  DateTime? _lastPing;
  DateTime? get lastPing => _lastPing;
  set lastPing(DateTime? lastPing) {
    _lastPing = lastPing;
    notifyListeners();
  }

  int? get scooterColor => _currentScooter?.color;
  set scooterColor(int? scooterColor) {
    if (_currentScooter != null) {
      _currentScooter!.color = scooterColor ?? 1;
    }
    notifyListeners();
    updateBackgroundService({"scooterColor": scooterColor});
  }

  /// Gets the current scooter's custom hex color, if any
  String? get scooterColorHex => _currentScooter?.colorHex;

  /// Gets the current scooter's cloud image URL for main display (front view)
  String? get scooterCloudImageUrl => _targetScooter?.cloudImageFront;

  /// Returns true if the current scooter uses a custom color
  bool get scooterHasCustomColor => _targetScooter?.hasCustomColor ?? false;

  /// Gets the current scooter object
  SavedScooter? getCurrentScooter() {
    if (myScooter != null) {
      return savedScooters[myScooter!.remoteId.toString()];
    }
    return null;
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
        foundScooters = foundScooters.where(
          (foundScooter) {
            return !excludedScooterIds
                .contains(foundScooter.remoteId.toString());
          },
        ).toList();
        if (foundScooters.isNotEmpty) {
          log.fine("System scooter is not excluded from search, returning!");
          return foundScooters.first;
        }
      }
    }
    log.info("Searching nearby devices");
    await for (BluetoothDevice foundScooter
        in getNearbyScooters(preferSavedScooters: excludedScooterIds.isEmpty)) {
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
    List<BluetoothDevice> systemDevices = await flutterBluePlus
        .systemDevices([Guid("9a590000-6e67-5d0d-aab9-ad9126b66f91")]);
    List<BluetoothDevice> systemScooters = [];
    List<String> savedScooterIds =
        await getSavedScooterIds(onlyAutoConnect: true);
    for (var device in systemDevices) {
      // see if this is a scooter we saved and want to (auto-)connect to
      if (savedScooterIds.contains(device.remoteId.toString())) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters(
      {bool preferSavedScooters = true}) async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> savedScooterIds =
        await getSavedScooterIds(onlyAutoConnect: true);
    if (savedScooterIds.isEmpty && savedScooters.isNotEmpty) {
      log.info(
          "We have ${savedScooters.length} saved scooters, but getSavedScooterIds returned an empty list. Probably no auto-connect enabled scooters, so we're not even scanning.");
      return;
    }
    if (savedScooters.isNotEmpty && preferSavedScooters) {
      log.info(
          "Looking for our scooters, since we have ${savedScooters.length} saved scooters");
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
    
    // Set target scooter and connection state for legacy compatibility
    _targetScooter = savedScooters[id];
    _isTargetingSpecificScooter = true;
    state = ScooterState.connectingSpecific;
    addSavedScooter(id);
    
    // Set current scooter using the new architecture - this handles both BLE and cloud connections
    // The connection state will be updated automatically when connections complete
    await setCurrentScooter(savedScooters[id]);
    
    log.info("Connection attempts initiated for scooter: $id");
  }

  // spins up the whole connection process, and connects/bonds with the nearest scooter
  void start({bool restart = true}) async {
    log.info("START called on service");
    // GETTING READY
    // Remove the splash screen
    Future.delayed(const Duration(milliseconds: 1500), () {
      FlutterNativeSplash.remove();
    });
    
    // Initialize BLE connection service
    _bleConnectionService = BLEConnectionService();
    
    // Initialize command availability cache (but don't refresh yet)
    // refreshCommandAvailabilityCache();
    
    // Try to turn on Bluetooth (Android-Only)
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    // TODO: prompt users to turn on bluetooth manually

    // CLEANUP
    _foundSth = false;
    connected = false;
    _isTargetingSpecificScooter = false;
    _targetScooter = null;
    state = ScooterState.connectingAuto;
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
  void startAutoRestart() async {
    if (!_autoRestarting) {
      _autoRestarting = true;
      _autoRestartSubscription =
          flutterBluePlus.isScanning.listen((scanState) async {
        // retry if we stop scanning without having found anything
        if (scanState == false && !_foundSth) {
          await Future.delayed(const Duration(seconds: 3));
          if (!_foundSth && !scanning && _autoRestarting) {
            // make sure nothing happened in these few seconds
            log.info("Auto-restarting...");
            start();
          }
        }
      });
    } else {
      log.info("Auto-restart already running, avoiding duplicate");
    }
  }

  void stopAutoRestart() {
    _autoRestarting = false;
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
          "Found all characteristics! StateCharacteristic is: ${characteristicRepository.stateCharacteristic}");
      _scooterReader = ScooterReader(
        characteristicRepository: characteristicRepository,
        service: this,
      );
      _scooterReader.readAndSubscribe();

      // check if any of the characteristics are null, and if so, throw an error
      if (characteristicRepository.anyAreNull()) {
        log.warning(
            "Some characteristics are null, throwing exception to warn further up the chain!");
        throw UnavailableCharacteristicsException();
      }
    } catch (e) {
      rethrow;
    }
  }

  // SCOOTER ACTIONS

  Future<void> unlock({bool checkHandlebars = true, BuildContext? context}) async {
    // Try cloud command if BLE is not available
    if (!await _executeCommand(CommandType.unlock, context: context)) {
      throw Exception("Failed to unlock scooter");
    }
    HapticFeedback.heavyImpact();

    if (_openSeatOnUnlock) {
      await Future.delayed(const Duration(seconds: 1), () async {
        await openSeat(context: context);
      });
    }

    if (_hazardLocking) {
      await Future.delayed(const Duration(seconds: 2), () async {
        await hazard(times: 2, context: context);
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
        ScooterState.standby, const Duration(seconds: bootingTimeSeconds + 5));

    if (_state == ScooterState.standby) {
      unlock();
    }
  }

  Future<void> lock({bool checkHandlebars = true, BuildContext? context}) async {
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

    // Try cloud command if BLE is not available
    if (!await _executeCommand(CommandType.lock, context: context)) {
      throw Exception("Failed to lock scooter");
    }
    HapticFeedback.heavyImpact();

    if (_hazardLocking) {
      Future.delayed(const Duration(seconds: 1), () async {
        await hazard(times: 1, context: context);
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

  Future<void> openSeat({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.openSeat, context: context)) {
      throw Exception("Failed to open seat");
    }
  }

  Future<void> blink({required bool left, required bool right, BuildContext? context}) async {
    CommandType commandType;
    if (left && !right) {
      commandType = CommandType.blinkerLeft;
    } else if (!left && right) {
      commandType = CommandType.blinkerRight;
    } else if (left && right) {
      commandType = CommandType.blinkerBoth;
    } else {
      commandType = CommandType.blinkerOff;
    }
    
    await _executeCommand(commandType, context: context);
  }

  Future<void> hazard({int times = 1, BuildContext? context}) async {
    await blink(left: true, right: true, context: context);
    await _sleepSeconds((0.6) * times);
    await blink(left: false, right: false, context: context);
  }

  Future<void> wakeUp({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.wakeUp, context: context)) {
      throw Exception("Failed to wake up scooter");
    }
  }

  Future<void> hibernate({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.hibernate, context: context)) {
      throw Exception("Failed to hibernate scooter");
    }
  }

  Future<void> honk({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.honk, context: context)) {
      throw Exception("Failed to honk");
    }
  }

  Future<void> alarm({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.alarm, context: context)) {
      throw Exception("Failed to activate alarm");
    }
  }

  /// Check if a command is available via BLE or cloud
  Future<bool> isCommandAvailable(CommandType command) async {
    // Ensure services are initialized
    _ensureCloudServicesInitialized();
    _ensureBLECommandServiceInitialized();
    _ensureCloudCommandServiceInitialized();
    
    // Check if available via BLE
    if (_bleCommandService != null && await _bleCommandService!.isAvailable(command)) {
      return true;
    }
    
    // Check if available via cloud
    if (_cloudCommandService != null && await _cloudCommandService!.isAvailable(command)) {
      return true;
    }
    
    return false;
  }

  /// Get detailed availability status for a command
  Future<Map<String, dynamic>> getCommandAvailabilityStatus(CommandType command) async {
    // Ensure services are initialized
    _ensureCloudServicesInitialized();
    _ensureBLECommandServiceInitialized();
    _ensureCloudCommandServiceInitialized();
    
    bool bleAvailable = _bleCommandService != null && await _bleCommandService!.isAvailable(command);
    bool cloudAvailable = _cloudCommandService != null && await _cloudCommandService!.isAvailable(command);
    
    return {
      'available': bleAvailable || cloudAvailable,
      'bleAvailable': bleAvailable,
      'cloudAvailable': cloudAvailable,
      'preferredMethod': bleAvailable ? 'ble' : (cloudAvailable ? 'cloud' : 'none'),
    };
  }

  /// Get cached command availability (synchronous)
  bool isCommandAvailableCached(CommandType command) {
    return _commandAvailabilityCache[command] ?? false;
  }
  
  /// Cache cloud scooter data
  void _cacheCloudScooterData(int cloudScooterId, Map<String, dynamic> data) {
    _cloudScooterCache[cloudScooterId] = data;
  }
  
  /// Get cached cloud scooter data
  Map<String, dynamic>? getCachedCloudScooterData(int cloudScooterId) {
    return _cloudScooterCache[cloudScooterId];
  }
  
  /// Refresh cloud scooter cache for all linked scooters
  Future<void> refreshCloudScooterCache() async {
    if (!await _isCloudServiceAvailable()) {
      return;
    }
    
    try {
      _ensureCloudServicesInitialized();
      final cloudScooters = await _cloudService!.getScooters();
      
      // Cache each cloud scooter
      for (final scooterData in cloudScooters) {
        if (scooterData.containsKey('id')) {
          final cloudScooterId = scooterData['id'] as int;
          _cacheCloudScooterData(cloudScooterId, scooterData);
        }
      }
      
      log.info("Refreshed cloud scooter cache for ${cloudScooters.length} scooters");
      notifyListeners();
    } catch (e) {
      log.warning("Failed to refresh cloud scooter cache", e);
    }
  }
  
  /// Check if cloud service is available
  Future<bool> _isCloudServiceAvailable() async {
    try {
      _ensureCloudServicesInitialized();
      return await _cloudService!.isServiceAvailable();
    } catch (e) {
      return false;
    }
  }

  /// Refresh command availability cache (legacy method - use _refreshCommandAvailabilityFromConnectionState instead)
  Future<void> refreshCommandAvailabilityCache() async {
    log.warning("Using legacy refreshCommandAvailabilityCache - should use _refreshCommandAvailabilityFromConnectionState");
    _refreshCommandAvailabilityFromConnectionState();
  }

  /// Get current scooter
  SavedScooter? get currentScooter => _currentScooter;

  /// Set current scooter and start connection attempts
  Future<void> setCurrentScooter(SavedScooter? scooter) async {
    if (_currentScooter == scooter) return;
    
    _currentScooter = scooter;
    log.info("Current scooter set to: ${scooter?.name ?? 'none'}");
    
    // Initialize BLE connection service if not already done
    _bleConnectionService ??= BLEConnectionService();
    
    if (scooter != null) {
      // Immediately update UI to show scooter info
      notifyListeners();
      
      // Set up listeners for connection changes
      _setupConnectionListeners();
      
      // Start both connection attempts in parallel and update UI as soon as each completes
      final bleConnectionFuture = _bleConnectionService!.attemptConnection(scooter.id).then((bleSuccess) {
        log.info("BLE connection result: $bleSuccess");
        _refreshCommandAvailabilityFromConnectionState();
      });
      
      final cloudStatusFuture = _refreshCloudOnlineStatus().then((_) {
        log.info("Cloud status check completed, isOnline: $_isCloudOnline");
        _refreshCommandAvailabilityFromConnectionState();
      });
      
      // Don't wait for both - let them complete independently
      bleConnectionFuture.catchError((e) => log.warning("BLE connection failed: $e"));
      cloudStatusFuture.catchError((e) => log.warning("Cloud status check failed: $e"));
      
      log.info("Connection attempts started for ${scooter.name}");
    } else {
      _isCloudOnline = false;
      _commandAvailabilityCache.clear();
    }
    
    notifyListeners();
  }
  
  /// Set up listeners for connection state changes
  void _setupConnectionListeners() {
    if (_bleConnectionService != null) {
      _bleConnectionService!.connectionStream.listen((scooterId) {
        log.info("BLE connection state changed: $scooterId");
        // Only refresh command availability when BLE connection changes
        // Don't re-check cloud status - we already did that once
        _refreshCommandAvailabilityFromConnectionState();
      });
    }
  }
  
  /// Refresh command availability based on current connection state (without re-checking cloud)
  void _refreshCommandAvailabilityFromConnectionState() {
    if (_currentScooter == null) {
      log.info("_refreshCommandAvailabilityFromConnectionState: No current scooter");
      _commandAvailabilityCache.clear();
      connected = false;
      state = ScooterState.disconnected;
      notifyListeners();
      return;
    }
    
    // Simple logic: if BLE is connected, enable BLE commands
    // If cloud is available (from our one-time check), enable cloud commands
    bool bleConnected = _bleConnectionService?.isConnectedTo(_currentScooter!.id) ?? false;
    bool cloudAvailable = _currentScooter!.cloudScooterId != null && _isCloudOnline;
    
    log.info("_refreshCommandAvailabilityFromConnectionState: BLE connected: $bleConnected, Cloud available: $cloudAvailable");
    log.info("_refreshCommandAvailabilityFromConnectionState: Current scooter cloudScooterId: ${_currentScooter!.cloudScooterId}, _isCloudOnline: $_isCloudOnline");
    
    // Update legacy connection state
    if (bleConnected || cloudAvailable) {
      connected = true;
      _foundSth = true;
      
      // Only update state if we don't have a cloud state already
      if (!cloudAvailable) {
        state = ScooterState.unknown; // BLE-only connection
      }
      // For cloud connections, state is already updated in _refreshCloudOnlineStatus
      
      // Set up old architecture compatibility if BLE is connected
      if (bleConnected && _bleConnectionService?.connectedDevice != null) {
        myScooter = _bleConnectionService!.connectedDevice!;
      }
      
      // Update background service
      updateBackgroundService({
        "scooterName": scooterName,
        "scooterColor": scooterColor,
        "lastPingInt": DateTime.now().millisecondsSinceEpoch,
      });
      
      log.info("_refreshCommandAvailabilityFromConnectionState: Setting connected = true");
    } else {
      connected = false;
      state = ScooterState.disconnected;
      _foundSth = false;
      log.info("_refreshCommandAvailabilityFromConnectionState: Setting connected = false");
    }
    
    for (CommandType command in CommandType.values) {
      bool available = false;
      
      if (bleConnected) {
        // All commands available via BLE
        available = true;
      } else if (cloudAvailable) {
        // Only cloud-supported commands available
        available = _isCommandSupportedInCloud(command);
      }
      
      _commandAvailabilityCache[command] = available;
    }
    
    log.info("_refreshCommandAvailabilityFromConnectionState: Command availability cache updated: $_commandAvailabilityCache");
    notifyListeners();
  }
  
  /// Check if command is supported in cloud (copied from CloudCommandService)
  bool _isCommandSupportedInCloud(CommandType command) {
    switch (command) {
      case CommandType.lock:
      case CommandType.unlock:
      case CommandType.hibernate:
      case CommandType.openSeat:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
      case CommandType.honk:
      case CommandType.alarm:
        return true;
      case CommandType.wakeUp:
        return false; // Not supported in cloud API
    }
  }
  
  /// Refresh cloud online status for current scooter
  Future<void> _refreshCloudOnlineStatus() async {
    if (_currentScooter?.cloudScooterId == null) {
      _isCloudOnline = false;
      return;
    }
    
    try {
      _ensureCloudServicesInitialized();
      final scooterData = await _cloudService!.getScooter(_currentScooter!.cloudScooterId!);
      
      if (scooterData != null) {
        // Cache the cloud scooter data
        _cacheCloudScooterData(_currentScooter!.cloudScooterId!, scooterData);
        
        // Check if scooter is online
        _isCloudOnline = scooterData.containsKey('online') && scooterData['online'] == true;
        
        // Update scooter state from cloud if available
        if (_isCloudOnline && scooterData.containsKey('state')) {
          state = _convertCloudStateToScooterState(scooterData['state']);
          log.info("Updated scooter state from cloud: ${scooterData['state']} -> $state");
        }
        
        // Update seatbox status from cloud
        if (scooterData.containsKey('seatbox')) {
          seatClosed = scooterData['seatbox'] == 'closed';
          log.info("Updated seatbox status from cloud: ${scooterData['seatbox']} -> seatClosed=$seatClosed");
        }
        
        // Update battery levels from cloud if available
        if (scooterData.containsKey('batteries')) {
          final batteries = scooterData['batteries'];
          if (batteries is Map) {
            if (batteries.containsKey('battery0') && batteries['battery0']['present'] == true) {
              final level = batteries['battery0']['level'];
              if (level != null) {
                primarySOC = int.tryParse(level.toString().split('.')[0]) ?? primarySOC;
                log.info("Updated primary battery from cloud: ${level}% -> $primarySOC%");
              }
            }
            if (batteries.containsKey('battery1') && batteries['battery1']['present'] == true) {
              final level = batteries['battery1']['level'];
              if (level != null) {
                secondarySOC = int.tryParse(level.toString().split('.')[0]) ?? secondarySOC;
                log.info("Updated secondary battery from cloud: ${level}% -> $secondarySOC%");
              }
            }
            
            // Update auxiliary battery
            if (batteries.containsKey('aux')) {
              final aux = batteries['aux'];
              if (aux is Map && aux.containsKey('level')) {
                final level = aux['level'];
                if (level != null) {
                  auxSOC = int.tryParse(level.toString().split('.')[0]) ?? auxSOC;
                  log.info("Updated auxiliary battery from cloud: ${level}% -> $auxSOC%");
                }
              }
            }
            
            // Update CBB battery
            if (batteries.containsKey('cbb')) {
              final cbb = batteries['cbb'];
              if (cbb is Map && cbb.containsKey('level')) {
                final level = cbb['level'];
                if (level != null) {
                  cbbSOC = int.tryParse(level.toString().split('.')[0]) ?? cbbSOC;
                  log.info("Updated CBB battery from cloud: ${level}% -> $cbbSOC%");
                }
              }
            }
          }
        }
        
        // Update last seen timestamp
        if (scooterData.containsKey('last_seen_at')) {
          final lastSeenStr = scooterData['last_seen_at'];
          if (lastSeenStr != null) {
            try {
              lastPing = DateTime.parse(lastSeenStr.toString());
              log.info("Updated last seen from cloud: $lastSeenStr");
            } catch (e) {
              log.warning("Failed to parse last_seen_at: $lastSeenStr");
            }
          }
        }
        
        // Update location from cloud if available
        if (scooterData.containsKey('location')) {
          final location = scooterData['location'];
          if (location is Map && location.containsKey('lat') && location.containsKey('lng')) {
            final lat = location['lat'];
            final lng = location['lng'];
            if (lat != null && lng != null) {
              try {
                final latDouble = double.parse(lat.toString());
                final lngDouble = double.parse(lng.toString());
                if (_currentScooter != null) {
                  _currentScooter!.lastLocation = LatLng(latDouble, lngDouble);
                  log.info("Updated location from cloud: $latDouble, $lngDouble");
                }
              } catch (e) {
                log.warning("Failed to parse location: lat=$lat, lng=$lng");
              }
            }
          }
        }
      } else {
        _isCloudOnline = false;
      }
    } catch (e) {
      log.warning("Failed to check cloud online status", e);
      _isCloudOnline = false;
    }
  }
  
  /// Convert cloud state string to ScooterState enum
  ScooterState _convertCloudStateToScooterState(String cloudState) {
    switch (cloudState) {
      case 'stand-by':
        return ScooterState.standby;
      case 'parked':
        return ScooterState.parked;
      case 'ready-to-drive':
        return ScooterState.ready;
      case 'shutting-down':
        return ScooterState.shuttingDown;
      case 'updating':
        return ScooterState.booting; // Closest equivalent
      case 'waiting-hibernation-confirm':
        return ScooterState.hibernatingImminent;
      case 'waiting-hibernation':
        return ScooterState.hibernating;
      default:
        log.warning("Unknown cloud state: $cloudState");
        return ScooterState.cloudConnected; // Fallback
    }
  }

  /// Check if current scooter is online in the cloud
  Future<bool> _isCurrentScooterOnlineInCloud() async {
    if (_currentScooter?.cloudScooterId == null) return false;
    
    try {
      _ensureCloudServicesInitialized();
      return await _cloudService!.isScooterOnline(_currentScooter!.cloudScooterId!);
    } catch (e) {
      log.warning("Failed to check cloud online status", e);
      return false;
    }
  }

  /// Get connection status for current scooter
  ConnectionStatus get connectionStatus {
    if (_currentScooter == null) return ConnectionStatus.none;
    
    bool bleConnected = _bleConnectionService?.isConnectedTo(_currentScooter!.id) ?? false;
    bool cloudAvailable = _currentScooter!.cloudScooterId != null && _isCloudOnline;
    
    if (bleConnected && cloudAvailable) {
      return ConnectionStatus.both;
    } else if (bleConnected) {
      return ConnectionStatus.ble;
    } else if (cloudAvailable) {
      return ConnectionStatus.cloud;
    } else {
      return ConnectionStatus.offline;
    }
  }

  /// Get status text for current connection
  String getStatusText(BuildContext context) {
    return connectionStatus.name(context);
  }
  
  /// Manually trigger connection attempts for current scooter
  Future<void> connectToCurrentScooter() async {
    if (_currentScooter == null) return;
    
    log.info("Manually connecting to current scooter: ${_currentScooter!.name}");
    
    // Start both connection attempts in parallel
    final bleConnectionFuture = _bleConnectionService?.attemptConnection(_currentScooter!.id);
    final cloudStatusFuture = _refreshCloudOnlineStatus();
    
    // Wait for both to complete, then refresh command availability
    if (bleConnectionFuture != null) {
      await Future.wait([bleConnectionFuture, cloudStatusFuture]);
    } else {
      await cloudStatusFuture;
    }
    
    _refreshCommandAvailabilityFromConnectionState();
    log.info("Manual connection attempts completed");
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
    savedScooters[myScooter!.remoteId.toString()]!.lastLocation =
        LatLng(position.latitude, position.longitude);
  }

  // HELPER FUNCTIONS


  static Future<void> sendStaticPowerCommand(String id, String command) async {
    BluetoothDevice scooter = BluetoothDevice.fromId(id);
    if (scooter.isDisconnected) {
      await scooter.connect();
    }
    await scooter.discoverServices();
    BluetoothCharacteristic? commandCharacteristic =
        CharacteristicRepository.findCharacteristic(
            scooter,
            "9a590000-6e67-5d0d-aab9-ad9126b66f91",
            "9a590001-6e67-5d0d-aab9-ad9126b66f91");
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
      ScooterState expectedScooterState, Duration limit) async {
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
          jsonDecode((await prefs.getString("savedScooters"))!)
              as Map<String, dynamic>;
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
      Map<String, SavedScooter> scooters) {
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
        _targetScooter = mostRecentScooter;
        _lastLocation = mostRecentScooter.lastLocation;
      } else {
        // no saved scooters, reset streams
        _lastPing = null;
        _primarySOC = null;
        _secondarySOC = null;
        _cbbSOC = null;
        _auxSOC = null;
        _targetScooter = null;
        _lastLocation = null;
      }
    }
    notifyListeners();
  }

  Future<List<String>> getSavedScooterIds(
      {bool onlyAutoConnect = false}) async {
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
            "No saved scooters found in SharedPreferences, returning empty list");
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
          "Attempted to rename scooter, but no ID was given and we're not connected to anything!");
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

    updateBackgroundService({"updateSavedScooters": true});
    if ((await getMostRecentScooter())?.id == id) {
      // if we're renaming the most recent scooter, update the name immediately
      scooterName = name;
      updateBackgroundService({"scooterName": name});
    }
    // let the background service know too right away
    notifyListeners();
  }

  void recolorSavedScooter({String? id, required int color}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
          "Attempted to recolor scooter, but no ID was given and we're not connected to anything!");
      return;
    }
    if (savedScooters[id] == null) {
      savedScooters[id] = SavedScooter(
        color: color,
        id: id,
      );
    } else {
      savedScooters[id]!.color = color;
    }

    updateBackgroundService({"updateSavedScooters": true});
    if ((await getMostRecentScooter())?.id == id) {
      // if we're recoloring the most recent scooter, update the color immediately
      scooterColor = color;
      updateBackgroundService({"scooterColor": color});
    }
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
    super.dispose();
  }

  Future<void> _sleepSeconds(double seconds) {
    return Future.delayed(Duration(milliseconds: (seconds * 1000).floor()));
  }
}

class SeatOpenException {}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}
