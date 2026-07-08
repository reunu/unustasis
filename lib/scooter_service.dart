import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../domain/connection_status.dart';
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
import 'cloud_command_service.dart';
import 'cloud_service.dart';
import 'command_service.dart';
import 'features.dart';

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

  // Cloud connectivity (all lazily initialized, only matters once a scooter is cloud-linked)
  CloudService? _cloudService;
  CloudCommandService? _cloudCommandService;
  bool _cloudServicesInitialized = false;
  bool _isCloudOnline = false;
  bool _isCloudConnecting = false;
  Timer? _cloudStatusTimer;
  SavedScooter? _cachedMostRecentScooter;

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
    _cachedMostRecentScooter = mostRecentScooter;
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
    battery.cbbVoltage = 3700;
    battery.cbbCapacity = 3000;
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
      await commands.navigateCommand(
        myScooter!,
        characteristicRepository,
        _pendingNavigation!,
      );

      log.info('Pending navigation dispatched to ${_pendingNavigation!.name}');
      await setPendingNavigation(null);
    } catch (e) {
      log.warning('Pending navigation dispatch failed: $e');
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

  // CLOUD CONNECTIVITY

  /// The scooter we're currently interacting with: the connected BLE device if
  /// there is one, otherwise the most recently used saved scooter. Used to
  /// resolve cloud commands even when there's no active BLE connection.
  SavedScooter? get currentScooter {
    if (myScooter != null) {
      return savedScooters[myScooter!.remoteId.toString()] ?? _cachedMostRecentScooter;
    }
    return _cachedMostRecentScooter;
  }

  void _ensureCloudServicesInitialized() {
    if (_cloudServicesInitialized) return;
    _cloudService = CloudService(this);
    _cloudCommandService = CloudCommandService(_cloudService!, () async => currentScooter?.cloudScooterId);
    _cloudServicesInitialized = true;
  }

  CloudService get cloudService {
    _ensureCloudServicesInitialized();
    return _cloudService!;
  }

  /// Combined BLE + cloud connection status for the current scooter.
  ConnectionStatus get connectionStatus {
    final scooter = currentScooter;
    if (scooter == null) return ConnectionStatus.none;
    bool bleConnected = connected && myScooter?.remoteId.toString() == scooter.id;
    bool cloudAvailable = scooter.cloudScooterId != null && _isCloudOnline;
    if (bleConnected && cloudAvailable) return ConnectionStatus.both;
    if (bleConnected) return ConnectionStatus.ble;
    if (cloudAvailable) return ConnectionStatus.cloud;
    return ConnectionStatus.offline;
  }

  bool get isCloudOnline => _isCloudOnline;
  bool get isCloudConnecting => _isCloudConnecting;

  bool _bleSupportsCommand(CommandType command) {
    switch (command) {
      case CommandType.honk:
      case CommandType.alarm:
      case CommandType.locate:
      case CommandType.ping:
      case CommandType.getState:
        return false; // no BLE equivalent, cloud-only
      default:
        return true;
    }
  }

  bool _isCommandSupportedInCloud(CommandType command) {
    switch (command) {
      case CommandType.wakeUp:
        return false; // not supported by the cloud API
      default:
        return true;
    }
  }

  /// Whether [command] can currently be sent, via BLE or cloud.
  bool isCommandAvailableCached(CommandType command) {
    bool bleAvailable = _bleSupportsCommand(command) && _bleReady;
    final scooter = currentScooter;
    bool cloudAvailable = scooter?.cloudScooterId != null && _isCloudOnline && _isCommandSupportedInCloud(command);
    return bleAvailable || cloudAvailable;
  }

  /// Executes [command] via the cloud. Used both as a fallback when BLE is
  /// unavailable, and directly for cloud-only commands that have no BLE
  /// equivalent (honk, alarm, locate, ping, getState).
  Future<bool> _executeCommand(CommandType command, {BuildContext? context}) async {
    _ensureCloudServicesInitialized();

    if (!await _cloudCommandService!.isAvailable(command)) {
      log.warning("Command $command not available via cloud");
      return false;
    }

    if (await _cloudCommandService!.needsConfirmation(command)) {
      if (context == null || !context.mounted) {
        log.warning("Cloud command $command requires confirmation but no context was provided");
        return false;
      }
      bool confirmed = await _showCloudCommandConfirmation(context, command);
      if (!confirmed) {
        log.info("Cloud command $command cancelled by user");
        return false;
      }
    }

    return await _cloudCommandService!.execute(command);
  }

  Future<bool> _showCloudCommandConfirmation(BuildContext context, CommandType command) async {
    String commandName = _getCommandDisplayName(context, command);
    String title = FlutterI18n.translate(context, "cloud_command_confirm_title");
    String message = FlutterI18n.translate(
      context,
      "cloud_command_confirm_message",
      translationParams: {"command": commandName},
    );

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
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
        ) ??
        false;
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
      case CommandType.locate:
        return FlutterI18n.translate(context, "controls_locate");
      case CommandType.ping:
        return FlutterI18n.translate(context, "controls_ping");
      case CommandType.getState:
        return FlutterI18n.translate(context, "controls_get_state");
    }
  }

  /// Refreshes whether the current scooter is reachable in the cloud, and if
  /// so, folds its reported state into our own streams. Cloud data is only
  /// allowed to drive visible state while there's no live BLE connection, so
  /// it never fights with fresher BLE telemetry.
  Future<void> _refreshCloudOnlineStatus() async {
    final scooter = currentScooter;
    if (scooter?.cloudScooterId == null) {
      _isCloudOnline = false;
      _isCloudConnecting = false;
      return;
    }

    try {
      _isCloudConnecting = true;
      notifyListeners();
      _ensureCloudServicesInitialized();
      final data = await _cloudService!.getScooter(scooter!.cloudScooterId!);
      if (data == null) {
        _isCloudOnline = false;
        return;
      }

      _isCloudOnline = data['online'] == true;

      if (_isCloudOnline && !connected) {
        if (data['state'] != null) {
          state = _convertCloudStateToScooterState(data['state']);
        }
        if (data['seatbox'] != null) {
          vehicle.seatClosed = data['seatbox'] == 'closed';
        }
        _applyCloudBatteryData(data['batteries'], scooter);
        if (data['last_seen_at'] != null) {
          try {
            identity.lastPing = DateTime.parse(data['last_seen_at'].toString());
            scooter.lastPing = identity.lastPing!;
          } catch (_) {
            // ignore unparseable timestamps
          }
        }
      }
    } catch (e, stack) {
      log.warning("Failed to refresh cloud online status", e, stack);
      _isCloudOnline = false;
    } finally {
      _isCloudConnecting = false;
      notifyListeners();
    }
  }

  void _applyCloudBatteryData(dynamic batteries, SavedScooter scooter) {
    if (batteries is! Map) return;

    int? parseLevel(dynamic level) {
      if (level == null) return null;
      return int.tryParse(level.toString().split('.').first);
    }

    final battery0 = batteries['battery0'];
    if (battery0 is Map && battery0['present'] == true) {
      final level = parseLevel(battery0['level']);
      if (level != null) {
        battery.primarySOC = level;
        scooter.lastPrimarySOC = level;
      }
    }

    final battery1 = batteries['battery1'];
    if (battery1 is Map) {
      if (battery1['present'] == true) {
        final level = parseLevel(battery1['level']);
        if (level != null) {
          battery.secondarySOC = level;
          scooter.lastSecondarySOC = level;
        }
      } else {
        battery.secondarySOC = -1;
        scooter.lastSecondarySOC = -1;
      }
    }

    final aux = batteries['aux'];
    if (aux is Map) {
      final level = parseLevel(aux['level']);
      if (level != null) {
        battery.auxSOC = level;
        scooter.lastAuxSOC = level;
      }
    }

    final cbb = batteries['cbb'];
    if (cbb is Map) {
      final level = parseLevel(cbb['level']);
      if (level != null) {
        battery.cbbSOC = level;
        scooter.lastCbbSOC = level;
      }
    }
  }

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
        return ScooterState.updating;
      case 'waiting-hibernation-confirm':
        return ScooterState.waitingHibernationConfirm;
      case 'waiting-hibernation':
        return ScooterState.waitingHibernation;
      case 'hibernating':
        return ScooterState.hibernating;
      default:
        log.warning("Unknown cloud state: $cloudState");
        return ScooterState.cloudConnected;
    }
  }

  /// Kicks off a cloud status check for the current scooter, if it's cloud-linked.
  /// Fire-and-forget: runs alongside the BLE connection attempt, never blocks it.
  void _maybeRefreshCloudStatus() {
    if (!_cloudServicesInitialized && currentScooter?.cloudScooterId == null) return;
    Features.isCloudConnectivityEnabled.then((enabled) {
      if (enabled && currentScooter?.cloudScooterId != null) {
        _ensureCloudServicesInitialized();
        _refreshCloudOnlineStatus();
        _cloudStatusTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
          if (currentScooter?.cloudScooterId != null) {
            _refreshCloudOnlineStatus();
          }
        });
      }
    });
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
      identity.resetLsCapabilities();
      _lsProbeGeneration++;
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

    // If Bluetooth is already on, don't wait for another "on" transition event.
    final BluetoothAdapterState adapterStateNow = await flutterBluePlus.adapterState.first;
    if (adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
    }

    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // Check cloud reachability for cloud-linked scooters alongside the BLE scan below,
    // never blocking on it.
    _maybeRefreshCloudStatus();

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
          await _attemptAutoRestart();
        }
      });

      // If scan already ended before this listener was attached, trigger the same check.
      if (!_foundSth && !flutterBluePlus.isScanningNow) {
        await _attemptAutoRestart();
      }
    } else {
      log.info("Auto-restart already running, avoiding duplicate");
      if (targetScooterId != null) {
        _targetScooterId = targetScooterId;
      }
    }
  }

  Future<void> _attemptAutoRestart() async {
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
      onUsbModeChanged: () {
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
        if (identity.isLibrescoot == true) {
          _probeLsCapabilities();
        } else {
          identity.supportsHibernateFor = false;
          identity.supportsScheduledHibernation = false;
        }
        notifyListeners();
      },
    );
  }

  // bumped on each (re)connect so a stale in-flight probe from a previous
  // connection can't apply its results to the current one
  int _lsProbeGeneration = 0;

  /// Probes which of the newer librescoot features this scooter supports.
  /// Fire-and-forget; flags stay null until the probe resolves.
  Future<void> _probeLsCapabilities() async {
    final generation = _lsProbeGeneration;
    bool? supportsHibernateFor;
    try {
      final caps = await commands.getPmCapabilitiesCommand(myScooter, characteristicRepository);
      supportsHibernateFor = caps.contains("hibernate-for");
    } catch (e, stack) {
      log.warning("pm capability probe failed", e, stack);
      supportsHibernateFor = false;
    }
    if (generation != _lsProbeGeneration) return;
    identity.supportsHibernateFor = supportsHibernateFor;
    notifyListeners();

    bool? supportsScheduledHibernation;
    try {
      final value = await commands.getLsSettingCommand(
        myScooter,
        characteristicRepository,
        commands.lsKeyScheduledHibernateEnabled,
      );
      supportsScheduledHibernation = value != null;
    } catch (e, stack) {
      log.warning("scheduled hibernation probe failed", e, stack);
      supportsScheduledHibernation = false;
    }
    if (generation != _lsProbeGeneration) return;
    identity.supportsScheduledHibernation = supportsScheduledHibernation;
    notifyListeners();
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

  // Real BLE connections report isConnected==true; demo mode's fake
  // BluetoothDevice never does, so fall back to our own _connected flag
  // (which addDemoData sets directly) to keep demo mode working.
  bool get _bleReady => myScooter != null && (myScooter!.isConnected || _connected);

  Future<void> unlock({
    bool checkHandlebars = true,
    EventSource source = EventSource.app,
    BuildContext? context,
  }) async {
    bool viaBLE = _bleReady;
    if (viaBLE) {
      await commands.unlockScooter(
        myScooter,
        characteristicRepository,
        primarySOC: battery.primarySOC,
        secondarySOC: battery.secondarySOC,
        source: source,
      );
    } else if (!await _executeCommand(CommandType.unlock, context: context)) {
      throw Exception("Failed to unlock scooter");
    }

    if (settings.openSeatOnUnlock) {
      await Future.delayed(const Duration(seconds: 1), () {
        if (context != null && !context.mounted) return;
        openSeat(source: EventSource.auto, context: context);
      });
    }

    if (settings.hazardLocking) {
      await Future.delayed(const Duration(seconds: 2), () {
        if (context != null && !context.mounted) return;
        hazard(times: 2, context: context);
      });
    }

    if (checkHandlebars && viaBLE) {
      await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
        if (vehicle.handlebarsLocked == true) {
          log.warning("Handlebars didn't unlock, sending warning");
          throw HandlebarLockException();
        }
      });
    }
  }

  Future<void> wakeUpAndUnlock({EventSource? source, BuildContext? context}) async {
    wakeUp(context: context);

    await _waitForScooterState(
      ScooterState.standby,
      const Duration(seconds: bootingTimeSeconds + 5),
    );

    if (context != null && !context.mounted) return;
    if (_state == ScooterState.standby) {
      unlock(context: context);
    }
  }

  Future<void> lock({
    bool checkHandlebars = true,
    EventSource source = EventSource.app,
    BuildContext? context,
  }) async {
    if (vehicle.seatClosed == false) {
      log.warning("Locking with open seatbox!");
    }

    bool viaBLE = _bleReady;
    if (viaBLE) {
      await commands.lockScooter(
        myScooter,
        characteristicRepository,
        primarySOC: battery.primarySOC,
        secondarySOC: battery.secondarySOC,
        source: source,
        lastLocation: lastLocation,
      );
    } else if (!await _executeCommand(CommandType.lock, context: context)) {
      throw Exception("Failed to lock scooter");
    }

    if (settings.hazardLocking) {
      Future.delayed(const Duration(seconds: 1), () {
        if (context != null && !context.mounted) return;
        hazard(times: 1, context: context);
      });
    }

    if (checkHandlebars && viaBLE) {
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

  Future<void> openSeat({EventSource source = EventSource.app, BuildContext? context}) async {
    if (_bleReady) {
      await commands.openSeatCommand(
        myScooter,
        characteristicRepository,
        primarySOC: battery.primarySOC,
        secondarySOC: battery.secondarySOC,
        source: source,
      );
    } else if (!await _executeCommand(CommandType.openSeat, context: context)) {
      throw Exception("Failed to open seat");
    }
  }

  Future<void> blink({required bool left, required bool right, BuildContext? context}) async {
    if (_bleReady) {
      await commands.blinkCommand(myScooter, characteristicRepository, left: left, right: right);
      return;
    }
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
    await Future.delayed(Duration(milliseconds: (600 * times)));
    if (context != null && !context.mounted) return;
    await blink(left: false, right: false, context: context);
  }

  Future<void> wakeUp({BuildContext? context}) async {
    if (_bleReady) {
      await commands.wakeUpCommand(myScooter, characteristicRepository);
    } else if (!await _executeCommand(CommandType.wakeUp, context: context)) {
      throw Exception("Failed to wake up scooter");
    }
  }

  Future<void> hibernate({BuildContext? context}) async {
    if (_bleReady) {
      await commands.hibernateCommand(myScooter, characteristicRepository);
    } else if (!await _executeCommand(CommandType.hibernate, context: context)) {
      throw Exception("Failed to hibernate scooter");
    }
  }

  // Cloud-only actions: no BLE equivalent exists for these.
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

  Future<void> locate({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.locate, context: context)) {
      throw Exception("Failed to locate scooter");
    }
  }

  Future<void> pingScooter({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.ping, context: context)) {
      throw Exception("Failed to ping scooter");
    }
  }

  Future<void> getState({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.getState, context: context)) {
      throw Exception("Failed to get scooter state");
    }
  }

  /// Hibernates the scooter with a wake timer (librescoot pm capability).
  Future<void> hibernateFor(Duration wakeAfter) async {
    await commands.hibernateForCommand(myScooter, characteristicRepository, wakeAfter);
  }

  Future<void> reboot() async {
    await commands.rebootCommand(myScooter, characteristicRepository);
  }

  Future<void> hardReboot() async {
    await commands.hardRebootCommand(myScooter, characteristicRepository);
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
      _maybeRefreshCloudStatus();
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
      _cachedMostRecentScooter = mostRecentScooter;
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
    _cloudStatusTimer?.cancel();

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
