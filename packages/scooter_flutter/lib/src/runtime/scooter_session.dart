import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../ble/blue_plus_mockable.dart';
import '../ble/characteristic_repository.dart';

/// App-owned publications at ordered boundaries of the shared connection.
/// Implementations must use the supplied connection's freshness predicate for
/// asynchronous telemetry. No storage, widget identity or model lives here.
abstract interface class ScooterSessionEffects {
  void manualTargetChanged(String? id, {bool includeMetadata = false});
  void invalidateTelemetry();
  void linking(SessionConnection connection);
  void transportConnected(SessionConnection connection);
  Future<void> prepareIosWidget(SessionConnection connection);
  void wireTelemetry(
      SessionConnection connection, CharacteristicRepository repository);
  void readyMetadata(SessionConnection connection);
  void ready(SessionConnection connection);

  /// A null ID denotes preparation/failure rather than a live disconnect.
  void disconnected(String? id);
}

class _SupersededConnectionAttempt implements Exception {
  const _SupersededConnectionAttempt();
}

/// Per-call identity, never a BluetoothDevice wrapper identity. Remains usable
/// by late app reads after connect's finally has released the pending attempt.
class SessionConnection {
  SessionConnection._(
      this._owner, this.id, this.generation, this._acceptedIntent);
  int _acceptedIntent;
  final ScooterSession _owner;
  final String id;
  final int generation;
  BluetoothDevice? _device;
  bool _active = true;
  BluetoothDevice get device => _device!;
  bool get isCurrentAttempt =>
      !_owner._disposed && generation == _owner._attemptGeneration;
  bool get isCurrent =>
      _active &&
      isCurrentAttempt &&
      _owner.device?.remoteId.toString() == id &&
      // Linking publishes this token before its transport is assigned.
      _device?.isConnected == true;
}

/// The sole connection/intent/retry owner for one executing service isolate.
/// Construction has no side effects; start/connect and dispose are explicit.
class ScooterSession {
  ScooterSession({
    required this.flutterBluePlus,
    required this.effects,
    required this.onChanged,
    required this.findEligibleScooter,
    required this.isScanning,
    required this.onStart,
    BluetoothDevice Function(String)? deviceFromId,
    CharacteristicRepository Function(BluetoothDevice)? repositoryFactory,
    Future<void> Function(Duration)? delay,
    bool? isAndroid,
    bool? isIOS,
  })  : _delay = delay ?? Future<void>.delayed,
        _deviceFromId = deviceFromId ?? BluetoothDevice.fromId,
        repositoryFactory = repositoryFactory ?? CharacteristicRepository.new,
        isAndroid = isAndroid ?? Platform.isAndroid,
        isIOS = isIOS ?? Platform.isIOS;

  final log = Logger('ScooterSession');
  final FlutterBluePlusMockable flutterBluePlus;
  final ScooterSessionEffects effects;
  final void Function() onChanged;
  final Future<BluetoothDevice?> Function() findEligibleScooter;
  final bool Function() isScanning;
  final void Function() onStart;
  final BluetoothDevice Function(String) _deviceFromId;
  final CharacteristicRepository Function(BluetoothDevice) repositoryFactory;
  final bool isAndroid, isIOS;
  final Future<void> Function(Duration) _delay;
  bool get scanning => isScanning();
  bool _disposed = false;
  bool get isDisposed => _disposed;
  BluetoothDevice? device;
  SessionConnection? _connectionAttempt;

  /// True until the actual pending attempt exits, including ready publication.
  /// Destructive offline operations must defer rather than race that attempt.
  bool get hasPendingConnectionAttempt => _connectionAttempt != null;

  SessionConnection? _publishedConnectionAttempt;
  SessionConnection? get currentConnection => _publishedConnectionAttempt;
  String? _connectingScooterId;
  String? get connectingScooterId => _connectingScooterId;
  String? _manualTargetId;
  String? get manualTargetId => _manualTargetId;
  int _intentGeneration = 0;
  int get intentGeneration => _intentGeneration;
  int _attemptGeneration = 0;

  /// Captures operation freshness without requiring a live/published link.
  /// Unlike SessionConnection, this remains usable after a failed attempt left
  /// an older publication behind. Any later intent/attempt or disposal expires
  /// it; a disconnect alone does not (bond forgetting expects that disconnect).
  /// BLE actions must still use their captured SessionConnection for link checks.
  bool Function() captureOperationFreshness() {
    final intent = _intentGeneration;
    final attempt = _attemptGeneration;
    return () =>
        !_disposed &&
        _intentGeneration == intent &&
        _attemptGeneration == attempt;
  }

  bool foundScooter = false;
  bool _autoRestarting = false;
  String? _targetScooterId;
  bool _connected = false;
  bool get connected => _connected;
  set connected(bool value) => setConnected(value);

  /// Compatibility publication for app-owned demo data; live transitions notify.
  void setConnected(bool value, {bool notify = true}) {
    _connected = value;
    if (!value) _publishedConnectionAttempt?._active = false;
    if (notify && !_disposed) onChanged();
  }

  /// Compatibility user-disconnect behavior: request native disconnect and
  /// immediately clear the retained device. Retry/intent choice stays explicit.
  void disconnectAndClearDevice() {
    device?.disconnect();
    device = null;
  }

  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  Future<void> connectToScooterId(
    String id, {
    bool automatic = false,
    int? expectedIntentGeneration,
  }) async {
    if (_disposed) return;
    final int requestedIntent;
    if (automatic) {
      requestedIntent = expectedIntentGeneration ?? intentGeneration;
      if (requestedIntent != intentGeneration) {
        log.info("Skipping obsolete automatic connection to $id");
        return;
      }
    } else {
      requestedIntent = ++_intentGeneration;
      stopAutoRestart(clearManualTarget: false);
      _manualTargetId = id;
      effects.manualTargetChanged(id, includeMetadata: true);
      if (_disposed || requestedIntent != intentGeneration) return;
    }

    if (connected && device?.remoteId.toString() == id && device!.isConnected) {
      // A listener can request this same link while its owner is still
      // publishing ready. Adopt only into that exact pending/published call;
      // treating the no-op as supersession would disconnect the retained link.
      final owner = _connectionAttempt;
      if (!automatic &&
          owner != null &&
          identical(owner, _publishedConnectionAttempt) &&
          owner.isCurrent &&
          identical(owner._device, device)) {
        owner._acceptedIntent = requestedIntent;
      }
      log.info("Already connected to requested scooter $id");
      return;
    }

    final attemptGeneration = ++_attemptGeneration;
    final attempt =
        SessionConnection._(this, id, attemptGeneration, requestedIntent);
    bool isCurrentAttempt() =>
        !_disposed &&
        attemptGeneration == _attemptGeneration &&
        attempt._acceptedIntent == intentGeneration;
    void ensureCurrentAttempt() {
      if (!isCurrentAttempt()) throw const _SupersededConnectionAttempt();
    }

    final previousAttempt = _connectionAttempt;
    _connectionAttempt = attempt;
    // Invalidate probes before yielding. Never await a mutable subscription
    // field that a newer request could replace underneath this call.
    effects.invalidateTelemetry();
    final previousSubscription = _connectionStateSubscription;
    _connectionStateSubscription = null;

    try {
      await previousSubscription?.cancel();
      ensureCurrentAttempt();

      log.info(
          "Connecting to scooter with ID: $id (intent $requestedIntent, attempt $attemptGeneration)");
      final BluetoothDevice? previousConnection = device;
      if (previousConnection != null &&
          previousConnection.remoteId.toString() != id) {
        device = null;
      }
      _connectingScooterId = id;
      foundScooter = true;
      connected = false;
      ensureCurrentAttempt();
      effects.linking(attempt);
      ensureCurrentAttempt();

      final attemptedScooter = _deviceFromId(id);
      attempt._device = attemptedScooter;
      if (!automatic) {
        await flutterBluePlus.stopScan();
        ensureCurrentAttempt();
      }
      final previousDevice = previousAttempt?._device;
      if (previousDevice != null &&
          previousDevice.remoteId != attemptedScooter.remoteId &&
          previousDevice.isConnected) {
        await previousDevice.disconnect();
        ensureCurrentAttempt();
      }
      if (previousConnection != null &&
          previousConnection.remoteId != attemptedScooter.remoteId &&
          previousConnection.isConnected) {
        await previousConnection.disconnect();
        ensureCurrentAttempt();
      }

      log.info("Connecting to ${attemptedScooter.remoteId}");
      await attemptedScooter.connect(timeout: const Duration(seconds: 30));
      ensureCurrentAttempt();

      if (isAndroid) {
        final BluetoothBondState bondState =
            await attemptedScooter.bondState.first;
        ensureCurrentAttempt();
        if (bondState == BluetoothBondState.bonded) {
          log.info(
              "Already bonded with ${attemptedScooter.remoteId}, no pairing request needed");
        } else {
          await attemptedScooter.createBond(timeout: 30);
          ensureCurrentAttempt();
          log.info("Bond established");
        }
        try {
          await attemptedScooter.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high,
          );
        } catch (e) {
          log.warning("Connection priority request failed (continuing): $e");
        }
        ensureCurrentAttempt();
      }

      log.info("Connected to ${attemptedScooter.remoteId}");
      device = attemptedScooter;
      _publishedConnectionAttempt = attempt;
      effects.transportConnected(attempt);
      ensureCurrentAttempt();

      if (isIOS) {
        await effects.prepareIosWidget(attempt);
        ensureCurrentAttempt();
      }

      if (attemptedScooter.isDisconnected) {
        throw "Scooter disconnected, can't set up characteristics!";
      }
      final repository = repositoryFactory(attemptedScooter);
      await repository.findAll(additionalLibrescootFeatures: true);
      ensureCurrentAttempt();
      effects.wireTelemetry(attempt, repository);
      ensureCurrentAttempt();
      if (repository.anyAreNull()) {
        log.warning("Some characteristics are null");
      }
      ensureCurrentAttempt();

      effects.readyMetadata(attempt);
      ensureCurrentAttempt();
      _connectingScooterId = null;
      connected = true;
      ensureCurrentAttempt();
      effects.ready(attempt);
      ensureCurrentAttempt();

      await _connectionStateSubscription?.cancel();
      ensureCurrentAttempt();
      final String listeningTo = id;
      final int listeningGeneration = attemptGeneration;
      _connectionStateSubscription = attemptedScooter.connectionState
          .listen((BluetoothConnectionState state) async {
        if (state == BluetoothConnectionState.disconnected &&
            listeningGeneration == _attemptGeneration) {
          foundScooter = false;
          connected = false;
          if (!attempt.isCurrentAttempt) return;
          effects.disconnected(listeningTo);
          if (!attempt.isCurrentAttempt) return;
          log.info(
              "Lost connection to scooter: ${attemptedScooter.disconnectReason ?? 'reason unavailable'}");
          if (_autoRestarting) {
            // We know exactly which live link was lost. Retry that device
            // directly instead of waiting for it to advertise and appear in a
            // scan; bonded scooters can remain connected at Android's system
            // level and therefore be invisible to scanning.
            _targetScooterId = listeningTo;
            unawaited(_attemptAutoRestart());
          }
        }
      });
    } on _SupersededConnectionAttempt {
      log.info("Connection attempt to $id was superseded");
      await _cleanUpSupersededAttempt(attempt);
    } catch (e, stack) {
      log.shout("Couldn't connect to scooter!", e, stack);
      if (isCurrentAttempt()) {
        foundScooter = false;
        _connectingScooterId = null;
        connected = false;
        if (isCurrentAttempt()) effects.disconnected(null);
        if (isCurrentAttempt() && identical(device, attempt._device)) {
          device = null;
        }
        if (_autoRestarting && _targetScooterId == id) {
          unawaited(_attemptAutoRestart());
        }
      }
      if (!identical(_connectionAttempt, attempt)) {
        await _cleanUpSupersededAttempt(attempt);
      }
      rethrow;
    } finally {
      if (identical(_connectionAttempt, attempt)) _connectionAttempt = null;
    }
  }

  Future<void> _cleanUpSupersededAttempt(SessionConnection attempt) async {
    final staleDevice = attempt._device;
    if (staleDevice == null) return;
    // Different wrappers can represent one physical link. Protect both a
    // pending newer request and a newer connection already past its finally.
    final current = _connectionAttempt;
    final published = _publishedConnectionAttempt;
    if ((current != null &&
            !identical(current, attempt) &&
            current.id == attempt.id) ||
        (published != null &&
            !identical(published, attempt) &&
            published.id == attempt.id &&
            device?.remoteId.toString() == attempt.id)) {
      return;
    }
    if (identical(device, staleDevice)) device = null;
    if (identical(_publishedConnectionAttempt, attempt)) {
      _publishedConnectionAttempt = null;
    }
    await _safeDisconnect(staleDevice);
  }

  /// Cleanup disconnect that must never mask the error being propagated.
  Future<void> _safeDisconnect(BluetoothDevice device) async {
    if (!device.isConnected) return;
    try {
      await device.disconnect();
    } catch (e) {
      log.warning("Cleanup disconnect failed (continuing): $e");
    }
  }

  bool _starting = false;

  // spins up the whole connection process, and connects/bonds with the nearest scooter
  void start({bool restart = true}) async {
    // A user-selected target always outranks generic auto-connect.
    if (_disposed) return;
    if (manualTargetId != null) {
      log.info(
          "START called while targeting $manualTargetId, keeping the explicit target");
      return;
    }
    // There are several entry points into this: startup, auto-restart, and
    // every app resume. Two overlapping runs used to fight each other, because
    // the second one tears down the link the first has just established.
    if (_starting) {
      log.info("START called while already starting, skipping the duplicate");
      return;
    }
    _starting = true;
    final requestedIntent = intentGeneration;
    log.info("START called on service for intent $intentGeneration");
    try {
      // GETTING READY
      // Remove the splash screen
      onStart();
      if (_disposed || requestedIntent != intentGeneration) return;

      // A working link is what this is trying to reach in the first place.
      // Dropping it here meant every spurious call cost a full
      // disconnect/scan/reconnect cycle. Both flags have to agree: the
      // platform's cached state alone can outlive a link that died while the
      // app was suspended, and the resume handler clears `connected` for
      // exactly that case before it gets here.
      if (connected && device != null && device!.isConnected) {
        log.info("Already connected to ${device!.remoteId}, keeping the link");
        foundScooter = true;
        if (restart) {
          startAutoRestart();
        }
        return;
      }

      // If Bluetooth is already on, don't wait for another "on" transition event.
      final BluetoothAdapterState adapterStateNow =
          await flutterBluePlus.adapterState.first;
      if (adapterStateNow != BluetoothAdapterState.on) {
        await flutterBluePlus.adapterState
            .where((val) => val == BluetoothAdapterState.on)
            .first;
      }
      if (requestedIntent != intentGeneration) return;

      // CLEANUP
      foundScooter = false;
      connected = false;
      if (_disposed || requestedIntent != intentGeneration) return;
      effects.disconnected(null);
      if (_disposed || requestedIntent != intentGeneration) return;
      if (device != null) {
        device!.disconnect();
      }

      // SCAN
      try {
        BluetoothDevice? eligibleScooter = await findEligibleScooter();
        if (requestedIntent != intentGeneration) {
          log.info("Discarding obsolete automatic scan result");
          return;
        }
        if (eligibleScooter != null) {
          await connectToScooterId(
            eligibleScooter.remoteId.toString(),
            automatic: true,
            expectedIntentGeneration: requestedIntent,
          );
        } else {
          log.info("No eligible scooters found during start()");
        }
      } catch (e, stack) {
        log.warning("Error during search or connect!", e, stack);
        // fail quietly, there can be benign reasons like race conditions for this
      }

      if (restart && requestedIntent == intentGeneration) {
        startAutoRestart();
      }
    } finally {
      _starting = false;
    }
  }

  StreamSubscription<bool>? _autoRestartSubscription;
  Object? _autoRestartListenerOwner;
  void startAutoRestart({String? targetScooterId}) async {
    if (_disposed) return;
    if (_autoRestarting) {
      log.info("Auto-restart already running, avoiding duplicate");
      if (targetScooterId != null) {
        _targetScooterId = targetScooterId;
        _manualTargetId = targetScooterId;
        if (!foundScooter) unawaited(_attemptAutoRestart());
      }
      return;
    }

    _autoRestarting = true;
    _targetScooterId = targetScooterId;
    if (targetScooterId != null) _manualTargetId = targetScooterId;
    log.info(
        "Starting auto-restart${targetScooterId != null ? " for scooter $targetScooterId" : ""}");

    // _autoRestarting flips back to false inside start(), by way of
    // findEligibleScooter calling stopAutoRestart, so this can be reached
    // again while a listener is still attached. Cancel it first: an orphaned
    // isScanning listener keeps firing _attemptAutoRestart forever, and
    // stopAutoRestart can only ever cancel the one it is holding.
    final listenerOwner = Object();
    _autoRestartListenerOwner = listenerOwner;
    final previousSubscription = _autoRestartSubscription;
    _autoRestartSubscription = null;
    await previousSubscription?.cancel();
    if (_disposed ||
        !_autoRestarting ||
        !identical(_autoRestartListenerOwner, listenerOwner)) {
      return;
    }
    _autoRestartSubscription = flutterBluePlus.isScanning.listen((
      scanState,
    ) async {
      // retry if we stop scanning without having found anything
      if (scanState == false && !foundScooter) {
        await _attemptAutoRestart();
      }
    });

    // If scan already ended before this listener was attached, trigger the same check.
    if (!foundScooter && !flutterBluePlus.isScanningNow) {
      await _attemptAutoRestart();
    }
  }

  bool _autoRestartAttemptPending = false;

  /// Retries the pinned target (or generic auto-connect) until something
  /// connects or the intent is superseded. Runs as a single loop so retry
  /// re-schedules can't stack up concurrent chains.
  Future<void> _attemptAutoRestart() async {
    if (_autoRestartAttemptPending) return;
    _autoRestartAttemptPending = true;
    try {
      while (_autoRestarting && !foundScooter && !scanning) {
        await _delay(const Duration(seconds: 3));
        // Things may have changed while we waited.
        if (!_autoRestarting || foundScooter || scanning) break;
        log.info(
            "Auto-restarting...${_targetScooterId != null ? " targeting $_targetScooterId" : ""}");
        final targetScooterId = _targetScooterId;
        if (targetScooterId != null) {
          // Keep retrying the specific scooter the user selected; generic
          // auto-connect must not take over this connection intent. Re-arm
          // the background gate each round: it expires on its own to stay
          // safe against a killed foreground, and this also survives a
          // background isolate restart.
          final requestedIntent = intentGeneration;
          if (manualTargetId != null) {
            effects.manualTargetChanged(targetScooterId);
          }
          if (!_autoRestarting || requestedIntent != intentGeneration) break;
          try {
            await connectToScooterId(
              targetScooterId,
              automatic: true,
              expectedIntentGeneration: requestedIntent,
            );
          } catch (e) {
            log.warning(
                "Failed to connect to target scooter $targetScooterId during auto-restart: $e");
          }
        } else {
          // Fall back to generic start() for auto-connect behavior
          start();
          break;
        }
      }
    } finally {
      _autoRestartAttemptPending = false;
    }
  }

  void stopAutoRestart({bool clearManualTarget = true}) {
    _autoRestarting = false;
    _targetScooterId = null;
    if (clearManualTarget && manualTargetId != null) {
      _manualTargetId = null;
      effects.manualTargetChanged(null);
    }
    _autoRestartListenerOwner = null;
    _autoRestartSubscription?.cancel();
    _autoRestartSubscription = null;
    log.fine("Auto-restart stopped.");
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _intentGeneration++;
    _attemptGeneration++;
    stopAutoRestart();
    effects.invalidateTelemetry();
    _connectionStateSubscription?.cancel();
    final devices = <String, BluetoothDevice>{};
    for (final transport in [
      device,
      _publishedConnectionAttempt?._device,
      _connectionAttempt?._device
    ]) {
      if (transport != null) {
        devices.putIfAbsent(transport.remoteId.toString(), () => transport);
      }
    }
    _connectionAttempt = null;
    _publishedConnectionAttempt = null;
    device = null;
    for (final transport in devices.values) {
      unawaited(_safeDisconnect(transport));
    }
  }
}
