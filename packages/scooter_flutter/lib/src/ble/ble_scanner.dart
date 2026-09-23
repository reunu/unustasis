import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import 'scooter_candidate.dart';
import 'blue_plus_mockable.dart';

final _log = Logger('BleScanner');

class BleScanner {
  final FlutterBluePlusMockable _flutterBluePlus;

  BleScanner(this._flutterBluePlus);

  static final Guid scooterService =
      Guid("9a590000-6e67-5d0d-aab9-ad9126b66f91");

  /// The name a scooter advertises itself under.
  static const List<String> scooterAdvertisedNames = ["unu Scooter"];

  /// Every eligible scooter in range right now: system-connected ones plus
  /// whatever [settle] of scanning turns up. Callers that need to choose between
  /// scooters (auto-connect, the auto-unlock ambiguity guard) must use this
  /// rather than [findEligibleScooter], which cannot tell "one scooter" from
  /// "the first of several".
  Future<List<BluetoothDevice>> findEligibleScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect})
        getIds,
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
    List<String>? withRemoteIds,
    Duration settle = const Duration(seconds: 3),
  }) async {
    final Map<String, BluetoothDevice> found = {};

    void add(BluetoothDevice device) {
      final String id = device.remoteId.toString();
      if (excludedScooterIds.contains(id)) return;
      found[id] = device;
    }

    if (includeSystemScooters) {
      for (final BluetoothDevice device
          in await getSystemScooters(getIds: getIds)) {
        add(device);
      }
      // Nothing to gain from scanning when the OS already hands us a scooter it
      // is connected to, and it is not advertising anyway.
      if (found.isNotEmpty) {
        return found.values.toList();
      }
    }

    await _collect(
        getNearbyScooters(
          getIds: getIds,
          preferSavedScooters: excludedScooterIds.isEmpty,
          withRemoteIds: withRemoteIds,
        ),
        add,
        settle);
    _log.info("Found ${found.length} eligible scooter(s) in range");
    return found.values.toList();
  }

  /// Subscribes to [stream], feeding [add] until the scan ends or [settle]
  /// passes, whichever comes first. A fixed window alone would delay every
  /// connect by the full settle time even when the scan has nothing to do.
  Future<void> _collect(Stream<BluetoothDevice> stream,
      void Function(BluetoothDevice) add, Duration settle) async {
    final done = Completer<void>();
    final subscription = stream.listen(add, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    final timer = Timer(settle, () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    timer.cancel();
    // Not awaited: cancelling waits on the transport tearing the scan down, and
    // the first-hit path this replaces never waited for that either.
    unawaited(subscription.cancel());
  }

  /// Find the first eligible scooter — checks system-connected devices first,
  /// then falls back to a BLE scan.
  Future<BluetoothDevice?> findEligibleScooter({
    required Future<List<String>> Function({required bool onlyAutoConnect})
        getIds,
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    final scooters = await findEligibleScooters(
      getIds: getIds,
      excludedScooterIds: excludedScooterIds,
      includeSystemScooters: includeSystemScooters,
    );
    return scooters.isEmpty ? null : scooters.first;
  }

  /// Which of [ids] are reachable right now. Best effort: a failed scan yields
  /// whatever was seen before it gave up.
  Future<Set<String>> idsInRange(List<String> ids,
      {Duration settle = const Duration(seconds: 3)}) async {
    if (ids.isEmpty) return <String>{};
    final Set<String> found = {};
    await _collect(
      getNearbyScooters(
        getIds: ({required bool onlyAutoConnect}) async => ids,
        preferSavedScooters: true,
        withRemoteIds: ids,
      ),
      (device) {
        final String id = device.remoteId.toString();
        if (ids.contains(id)) found.add(id);
      },
      settle,
    );
    return found;
  }

  /// Checks for scooters already connected at the OS level.
  Future<List<BluetoothDevice>> getSystemScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect})
        getIds,
  }) async {
    List<BluetoothDevice> systemDevices = await _flutterBluePlus.systemDevices([
      scooterService,
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
  /// for those specific remote IDs. Otherwise scans for any scooter.
  Stream<BluetoothDevice> getNearbyScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect})
        getIds,
    bool preferSavedScooters = true,
    List<String>? withRemoteIds,
  }) {
    final foundScooterCache = <BluetoothDevice>{};
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;
    Timer? watchdog;
    bool ended = false;
    bool scanStarted = false;
    bool startRequested = false;
    Future<void>? cleanupFuture;
    late StreamController<BluetoothDevice> controller;

    Future<void> cleanup() {
      ended = true;
      return cleanupFuture ??= () async {
        watchdog?.cancel();
        watchdog?.cancel();
        await resultsSub?.cancel();
        await scanningSub?.cancel();
        if (startRequested && _flutterBluePlus.isScanningNow) {
          try {
            await _flutterBluePlus.stopScan();
          } catch (e, stack) {
            _log.warning("Couldn't stop the scan", e, stack);
          }
        }
      }();
    }

    Future<void> finish() async {
      await cleanup();
      // Never await close here: a cancelled or paused consumer need not
      // receive done. onCancel itself waits only for resource cleanup.
      if (!controller.isClosed) unawaited(controller.close());
    }

    Future<void> run() async {
      try {
        final ids = withRemoteIds ?? await getIds(onlyAutoConnect: true);
        if (ended) return;
        if (preferSavedScooters && ids.isEmpty) {
          _log.info("No saved scooters to auto-connect to, not scanning");
          await finish();
          return;
        }

        // Attach before startScan: adapters may synchronously emit results
        // or a complete start/stop sequence before its future resolves.
        resultsSub = _flutterBluePlus.onScanResults.listen((results) {
          if (ended || results.isEmpty) return;
          // Every device in the batch, not just the last: a batch is a snapshot
          // of what the adapter heard, and callers that need the full set of
          // scooters in range get their answers from these.
          for (final result in results) {
            if (foundScooterCache.add(result.device)) {
              controller.add(result.device);
            }
          }
        });
        scanningSub = _flutterBluePlus.isScanning.listen((active) {
          if (ended) return;
          if (active) {
            scanStarted = true;
          } else if (scanStarted) {
            unawaited(finish());
          }
        });

        startRequested = true;
        await _flutterBluePlus.startScan(
          withRemoteIds: preferSavedScooters ? ids : const [],
          withNames: preferSavedScooters ? const [] : scooterAdvertisedNames,
          timeout: const Duration(seconds: 30),
        );
        if (ended) {
          // Cancellation may have cleaned up while startup was pending.
          // A subsequently completed startup must not leave a scan running.
          if (_flutterBluePlus.isScanningNow) await _flutterBluePlus.stopScan();
          return;
        }
        scanStarted |= _flutterBluePlus.isScanningNow;
        watchdog = Timer(const Duration(seconds: 35), () {
          _log.warning(
              "Auto-connect scan didn't report that it stopped; closing it");
          unawaited(finish());
        });
      } catch (e, stack) {
        _log.severe("Failed to start scan", e, stack);
        await finish();
      }
    }

    // Explicit cancellation is needed: an async* generator waiting inside
    // await-for cannot run its finally block until that inner stream wakes.
    controller = StreamController<BluetoothDevice>(
      onListen: () => unawaited(run()),
      onCancel: cleanup,
    );
    return controller.stream;
  }

  /// Every scooter the user could pick right now, as a list that grows and
  /// re-sorts while the scan runs.
  ///
  /// A scan on its own cannot find a scooter that this phone has already
  /// bonded: Android reconnects a bonded peripheral within seconds of any
  /// disconnect, and a peripheral does not advertise while it is connected, so
  /// the scooter sits there linked to the phone and silent. Those are picked up
  /// from the bonded and system-connected lists instead, which is why this runs
  /// all three sources rather than just the scan.
  ///
  /// The stream closes when the scan window ends. Cancelling it stops the scan.
  Stream<List<ScooterCandidate>> discoverScooters({
    required Future<List<String>> Function({required bool onlyAutoConnect})
        getIds,
    List<String> excludedScooterIds = const [],
    Duration timeout = const Duration(seconds: 30),
    bool androidCheckLocationServices = true,
  }) {
    final Map<String, ScooterCandidate> candidates = {};
    final List<StreamSubscription<dynamic>> subscriptions = [];
    Timer? coalesceTimer;
    Timer? watchdog;
    bool cleanedUp = false;
    late StreamController<List<ScooterCandidate>> controller;

    void emit() {
      coalesceTimer?.cancel();
      coalesceTimer = null;
      if (!controller.isClosed) {
        // Old bonds that are neither advertising nor connected stay out of the
        // list. There is nothing to say they are anywhere near, and on a phone
        // that has paired with a lot of scooters they bury the ones that are.
        controller.add(ScooterCandidate.sorted(
            candidates.values.where((c) => c.isPresent)));
      }
    }

    // RSSI updates arrive with every advertisement, which is far more often
    // than a list needs to be rebuilt. New entries show up immediately, signal
    // strength catches up on the next tick.
    void scheduleEmit() {
      coalesceTimer ??= Timer(const Duration(milliseconds: 500), emit);
    }

    bool upsert(ScooterCandidate candidate) {
      if (excludedScooterIds.contains(candidate.id)) return false;
      final ScooterCandidate? existing = candidates[candidate.id];
      candidates[candidate.id] =
          existing == null ? candidate : existing.mergedWith(candidate);
      return existing == null;
    }

    Future<void> run() async {
      final List<String> savedIds = await getIds(onlyAutoConnect: false);

      for (final ScooterCandidate candidate
          in await findPairedScooters(savedIds)) {
        upsert(candidate);
      }
      emit();

      // Subscribe before starting the scan so nothing is missed in between.
      subscriptions.add(
        _flutterBluePlus.onScanResults.listen((List<ScanResult> results) {
          bool isNew = false;
          for (final ScanResult result in results) {
            isNew |= upsert(
              ScooterCandidate(
                device: result.device,
                name: result.advertisementData.advName.isNotEmpty
                    ? result.advertisementData.advName
                    : _platformName(result.device),
                rssi: result.rssi,
                saved: savedIds.contains(result.device.remoteId.toString()),
              ),
            );
          }
          if (isNew) {
            emit();
          } else {
            scheduleEmit();
          }
        }),
      );

      // The scan-stopped event does go missing, most reliably when the app is
      // suspended mid-scan. Without a backstop the caller waits on a stream
      // that never completes and the UI keeps claiming it is searching.
      watchdog = Timer(timeout + const Duration(seconds: 5), () {
        if (!controller.isClosed) {
          _log.warning(
              "Scan didn't report that it stopped, closing discovery anyway");
          emit();
          controller.close();
        }
      });

      try {
        // Filters are OR'ed, so a bonded scooter that reports an unexpected
        // name still shows up by remote ID once it starts advertising again.
        await _flutterBluePlus.startScan(
          withNames: scooterAdvertisedNames,
          withRemoteIds: candidates.keys.toList(),
          timeout: timeout,
          continuousUpdates: true,
          androidCheckLocationServices: androidCheckLocationServices,
        );
        if (cleanedUp || controller.isClosed) {
          if (_flutterBluePlus.isScanningNow) await _flutterBluePlus.stopScan();
          return;
        }
        // Ignore the false event emitted when startScan replaces an existing scan.
        subscriptions.add(
          _flutterBluePlus.isScanning.listen((bool isScanning) {
            if (!isScanning && !controller.isClosed) {
              emit();
              controller.close();
            }
          }),
        );
      } catch (e, stack) {
        _log.severe("Failed to start scan", e, stack);
        if (!controller.isClosed) {
          emit();
          controller.close();
        }
      }
    }

    Future<void> cleanUp() async {
      if (cleanedUp) return;
      cleanedUp = true;
      coalesceTimer?.cancel();
      watchdog?.cancel();
      for (final StreamSubscription<dynamic> subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      try {
        await _flutterBluePlus.stopScan();
      } catch (e, stack) {
        _log.warning("Couldn't stop the scan", e, stack);
      }
    }

    controller = StreamController<List<ScooterCandidate>>(
      onListen: () {
        run().catchError((Object e, StackTrace stack) {
          _log.severe("Discovery failed", e, stack);
          if (!controller.isClosed) controller.close();
        });
      },
      onCancel: cleanUp,
    );
    controller.done.then((_) => cleanUp());
    return controller.stream;
  }

  /// Scooters the OS already knows about: bonded to this phone, or holding a
  /// GATT link right now. Neither of these advertises, so neither can be found
  /// by scanning.
  Future<List<ScooterCandidate>> findPairedScooters(
      List<String> savedIds) async {
    final Map<String, ScooterCandidate> found = {};

    void add(BluetoothDevice device,
        {bool bonded = false, bool systemConnected = false}) {
      final String id = device.remoteId.toString();
      final String name = _platformName(device);
      if (!_looksLikeScooter(id: id, name: name, savedIds: savedIds)) return;
      final ScooterCandidate candidate = ScooterCandidate(
        device: device,
        name: name.isNotEmpty ? name : null,
        bonded: bonded,
        systemConnected: systemConnected,
        saved: savedIds.contains(id),
      );
      final ScooterCandidate? existing = found[id];
      found[id] = existing == null ? candidate : existing.mergedWith(candidate);
    }

    try {
      for (final BluetoothDevice device
          in await _flutterBluePlus.systemDevices([scooterService])) {
        add(device, systemConnected: true);
      }
    } catch (e, stack) {
      _log.warning("Couldn't read system devices", e, stack);
    }

    if (Platform.isAndroid) {
      try {
        for (final BluetoothDevice device
            in await _flutterBluePlus.bondedDevices) {
          add(device, bonded: true);
        }
      } catch (e, stack) {
        _log.warning("Couldn't read bonded devices", e, stack);
      }
    }

    _log.info("Found ${found.length} scooter(s) the OS already knows about"
        "${found.isEmpty ? "" : ": ${found.values.map((c) => c.toString()).join("; ")}"}");
    return found.values.toList();
  }

  String _platformName(BluetoothDevice device) {
    try {
      return device.platformName;
    } catch (_) {
      return "";
    }
  }

  /// The bonded and system device lists cover everything the phone has ever
  /// paired with or is talking to, headphones included, so they need filtering
  /// down to things that plausibly are a scooter. Neither list carries the
  /// advertised service UUIDs, which leaves the cached name and whatever the
  /// app already has saved.
  bool _looksLikeScooter(
      {required String id,
      required String name,
      required List<String> savedIds}) {
    if (savedIds.contains(id)) return true;
    final String lower = name.toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains("unu") || lower.contains("scooter");
  }
}
