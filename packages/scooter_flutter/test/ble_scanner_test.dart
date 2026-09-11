import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

const savedId = 'AA:BB:CC:DD:EE:01';
const otherId = 'AA:BB:CC:DD:EE:02';
const thirdId = 'AA:BB:CC:DD:EE:03';

class FakeBluePlus extends Fake implements FlutterBluePlusMockable {
  late final results = StreamController<List<ScanResult>>.broadcast(sync: true);
  late final scanning = StreamController<bool>.broadcast(sync: true);
  List<BluetoothDevice> system = [];
  List<List<Guid>> systemQueries = [];
  List<String>? remoteIds;
  List<String>? names;
  Duration? scanTimeout;
  int starts = 0;
  int stops = 0;
  bool active = false;
  bool? resultsAttachedAtStart;
  bool? scanningAttachedAtStart;
  Future<void> Function()? onStart;

  @override
  Stream<List<ScanResult>> get onScanResults => results.stream;

  @override
  Stream<bool> get isScanning => scanning.stream;

  @override
  bool get isScanningNow => active;

  @override
  Future<List<BluetoothDevice>> Function(List<Guid>) get systemDevices => (services) async {
        systemQueries.add(List.of(services));
        return system;
      };

  @override
  Future<void> startScan({
    List<Guid> withServices = const [],
    List<String> withRemoteIds = const [],
    List<String> withNames = const [],
    List<String> withKeywords = const [],
    List<MsdFilter> withMsd = const [],
    List<ServiceDataFilter> withServiceData = const [],
    Duration? timeout,
    Duration? removeIfGone,
    bool continuousUpdates = false,
    int continuousDivisor = 1,
    bool oneByOne = false,
    AndroidScanMode androidScanMode = AndroidScanMode.lowLatency,
    bool androidUsesFineLocation = false,
    bool androidCheckLocationServices = true,
  }) async {
    starts++;
    remoteIds = List.of(withRemoteIds);
    names = List.of(withNames);
    scanTimeout = timeout;
    resultsAttachedAtStart = results.hasListener;
    scanningAttachedAtStart = scanning.hasListener;
    if (onStart != null) {
      await onStart!();
    } else {
      setScanning(true);
    }
  }

  void setScanning(bool value) {
    active = value;
    scanning.add(value);
  }

  void emit(String id) => results.add([FakeScanResult(id)]);

  @override
  Future<void> stopScan() async {
    stops++;
    setScanning(false);
  }

  Future<void> dispose() async {
    await results.close();
    await scanning.close();
  }
}

class FakeScanResult extends Fake implements ScanResult {
  FakeScanResult(String id) : device = BluetoothDevice.fromId(id);

  @override
  final BluetoothDevice device;
}

void expectClean(FakeBluePlus blue) {
  expect(blue.results.hasListener, isFalse);
  expect(blue.scanning.hasListener, isFalse);
  expect(blue.active, isFalse);
}

// Stream cancellation can complete through SDK futures created outside the
// widget fake-clock zone. Drain both zones without advancing the scan clock.
Future<void> flushStreams(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() async {});
  }
  await tester.pump();
}

void main() {
  late FakeBluePlus blue;
  late BleScanner scanner;
  late List<bool> idQueries;
  late List<String> savedIds;

  Future<List<String>> getIds({required bool onlyAutoConnect}) async {
    idQueries.add(onlyAutoConnect);
    return savedIds;
  }

  setUp(() {
    blue = FakeBluePlus();
    scanner = BleScanner(blue);
    idQueries = [];
    savedIds = [savedId];
  });

  tearDown(() async {
    await blue.dispose();
  });

  testWidgets('no saved IDs closes autoconnect without scanning', (tester) async {
    savedIds = [];
    List<BluetoothDevice>? found;
    scanner.getNearbyScooters(getIds: getIds).toList().then((v) => found = v);
    await tester.pump();
    expect(found, isEmpty);
    expect(idQueries, [true]);
    expect(blue.starts, 0);
    expect(blue.stops, 0);
    expectClean(blue);
  });

  testWidgets('find with no saved IDs returns null without scanning', (tester) async {
    savedIds = [];
    blue.system = [BluetoothDevice.fromId(otherId)];
    bool done = false;
    BluetoothDevice? found;
    scanner.findEligibleScooter(getIds: getIds).then((v) {
      found = v;
      done = true;
    });
    await tester.pump();
    expect(done, isTrue);
    expect(found, isNull);
    expect(idQueries, [true, true]);
    expect(blue.starts, 0);
    expectClean(blue);
  });

  testWidgets('returns first saved system device in system order without scan', (tester) async {
    savedIds = [thirdId, savedId];
    blue.system = [
      BluetoothDevice.fromId(otherId),
      BluetoothDevice.fromId(savedId),
      BluetoothDevice.fromId(thirdId),
    ];
    BluetoothDevice? found;
    scanner.findEligibleScooter(getIds: getIds).then((v) => found = v);
    await tester.pump();
    expect(found, same(blue.system[1]));
    expect(blue.systemQueries, [
      [BleScanner.scooterService]
    ]);
    expect(idQueries, [true]);
    expect(blue.starts, 0);
    expect(blue.stops, 0);
    expectClean(blue);
  });

  testWidgets('skips excluded system device in favor of next saved device', (tester) async {
    savedIds = [savedId, otherId];
    blue.system = [BluetoothDevice.fromId(savedId), BluetoothDevice.fromId(otherId)];
    BluetoothDevice? found;
    scanner.findEligibleScooter(
      getIds: getIds,
      excludedScooterIds: [savedId],
    ).then((v) => found = v);
    await tester.pump();
    expect(found, same(blue.system[1]));
    expect(blue.starts, 0);
    expectClean(blue);
  });

  testWidgets('excluded system device falls back to name scan and skips excluded results', (tester) async {
    blue.system = [BluetoothDevice.fromId(savedId)];
    bool done = false;
    BluetoothDevice? found;
    scanner.findEligibleScooter(
      getIds: getIds,
      excludedScooterIds: [savedId],
    ).then((v) {
      found = v;
      done = true;
    });
    await tester.pump();
    expect(blue.starts, 1);
    expect(blue.remoteIds, isEmpty);
    expect(blue.names, ['unu Scooter']);
    blue.emit(savedId);
    await tester.pump();
    expect(done, isFalse);
    blue.emit(otherId);
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    expect(done, isTrue);
    expect(found?.remoteId.toString(), otherId);
    expect(blue.stops, 1);
    expectClean(blue);
  });

  testWidgets('listeners capture immediate results and true-to-false scan events', (tester) async {
    blue.onStart = () async {
      blue.setScanning(false); // An initial idle value must not close the stream.
      blue.setScanning(true);
      blue.emit(savedId);
      blue.setScanning(false);
    };
    List<BluetoothDevice>? found;
    scanner.getNearbyScooters(getIds: getIds).toList().then((v) => found = v);
    await tester.pump();
    expect(blue.resultsAttachedAtStart, isTrue);
    expect(blue.scanningAttachedAtStart, isTrue);
    expect(blue.remoteIds, [savedId]);
    expect(blue.names, isEmpty);
    expect(blue.scanTimeout, const Duration(seconds: 30));
    await tester.runAsync(() async {});
    await tester.pump();
    expect(found?.map((d) => d.remoteId.toString()), [savedId]);
    expect(blue.stops, 0);
    expectClean(blue);
  });

  testWidgets('manual discovery with no saved IDs uses name filter and closes on stop', (tester) async {
    savedIds = [];
    List<BluetoothDevice>? found;
    scanner.getNearbyScooters(getIds: getIds, preferSavedScooters: false).toList().then((v) => found = v);
    await tester.pump();
    expect(found, isNull);
    expect(blue.names, ['unu Scooter']);
    expect(blue.remoteIds, isEmpty);
    expect(blue.scanTimeout, const Duration(seconds: 30));
    expect(idQueries, [true]);
    blue.emit(otherId);
    await tester.pump();
    blue.setScanning(false);
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    expect(found?.map((d) => d.remoteId.toString()), [otherId]);
    expect(blue.stops, 0);
    expectClean(blue);
  });

  testWidgets('asynchronous start rejection closes stream and cleans listeners', (tester) async {
    final start = Completer<void>();
    blue.onStart = () => start.future;
    List<BluetoothDevice>? found;
    scanner.getNearbyScooters(getIds: getIds).toList().then((v) => found = v);
    await tester.pump();
    expect(blue.results.hasListener, isTrue);
    expect(blue.scanning.hasListener, isTrue);
    expect(found, isNull);
    start.completeError(StateError('scan unavailable'));
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    await flushStreams(tester);
    expectClean(blue);
    expect(found, isNotNull, reason: 'startScan rejection must complete the output stream');
    expect(found, isEmpty);
    expect(blue.stops, 0);
    expectClean(blue);
  });

  testWidgets('consumer cancellation after result stops active scan and removes listeners', (tester) async {
    final found = <BluetoothDevice>[];
    final subscription = scanner.getNearbyScooters(getIds: getIds).listen(found.add);
    await tester.pump();
    blue.emit(savedId);
    await tester.pump();
    expect(found.map((d) => d.remoteId.toString()), [savedId]);
    expect(blue.active, isTrue);
    bool cancelled = false;
    subscription.cancel().then((_) => cancelled = true);
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    await flushStreams(tester);
    expect(cancelled, isTrue, reason: 'Cancellation after delivery must not wait for another BLE event');
    expect(blue.stops, 1);
    expectClean(blue);
    blue.emit(otherId);
    await tester.pump(const Duration(seconds: 36));
    expect(found, hasLength(1));
    expect(blue.stops, 1);
  });

  testWidgets('cancelling inside result callback cleans listeners and stops scan', (tester) async {
    bool cancelled = false;
    final found = <BluetoothDevice>[];
    late StreamSubscription<BluetoothDevice> subscription;
    subscription = scanner.getNearbyScooters(getIds: getIds).listen((device) {
      found.add(device);
      subscription.cancel().then((_) => cancelled = true);
    });
    await tester.pump();
    blue.emit(savedId);
    await flushStreams(tester);
    expect(found.map((d) => d.remoteId.toString()), [savedId]);
    expect(cancelled, isTrue);
    expect(blue.stops, 1);
    expectClean(blue);
    await tester.pump(const Duration(seconds: 36));
    expect(blue.stops, 1);
  });

  testWidgets('cancellation before ID lookup completes never starts scan', (tester) async {
    final ids = Completer<List<String>>();
    final subscription = scanner.getNearbyScooters(
      getIds: ({required bool onlyAutoConnect}) => ids.future,
    ).listen((_) {});
    await tester.pump();
    bool cancelled = false;
    subscription.cancel().then((_) => cancelled = true);
    await flushStreams(tester);
    expect(cancelled, isTrue);
    ids.complete([savedId]);
    await flushStreams(tester);
    expect(blue.starts, 0);
    expectClean(blue);
  });

  testWidgets('startup completing after cancellation stops its late scan', (tester) async {
    final start = Completer<void>();
    blue.onStart = () async {
      await start.future;
      blue.setScanning(true);
    };
    final subscription = scanner.getNearbyScooters(getIds: getIds).listen((_) {});
    await tester.pump();
    bool cancelled = false;
    subscription.cancel().then((_) => cancelled = true);
    await flushStreams(tester);
    expect(cancelled, isTrue);
    expectClean(blue);
    start.complete();
    await flushStreams(tester);
    expect(blue.stops, 1);
    expectClean(blue);
    await tester.pump(const Duration(seconds: 36));
    expect(blue.stops, 1);
  });

  testWidgets('watchdog closes at 35 seconds when stopped event is omitted', (tester) async {
    List<BluetoothDevice>? found;
    scanner.getNearbyScooters(getIds: getIds).toList().then((v) => found = v);
    await tester.pump();
    await tester.pump(const Duration(seconds: 34));
    expect(found, isNull);
    expect(blue.results.hasListener, isTrue);
    expect(blue.scanning.hasListener, isTrue);
    expect(blue.stops, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {});
    await tester.pump();
    expect(found, isEmpty);
    expect(blue.stops, 1);
    expectClean(blue);
  });
}
