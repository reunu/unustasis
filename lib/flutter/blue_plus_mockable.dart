import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Wrapper for FlutterBluePlus in order to easily mock it
/// Wraps all static calls for testing purposes
/// from: https://github.com/boskokg/flutter_blue_plus/blob/master/MOCKING.md
class FlutterBluePlusMockable {
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
  }) {
    return FlutterBluePlus.startScan(
        withServices: withServices,
        withRemoteIds: withRemoteIds,
        withNames: withNames,
        withKeywords: withKeywords,
        withMsd: withMsd,
        withServiceData: withServiceData,
        timeout: timeout,
        removeIfGone: removeIfGone,
        continuousUpdates: continuousUpdates,
        continuousDivisor: continuousDivisor,
        oneByOne: oneByOne,
        androidScanMode: androidScanMode,
        androidUsesFineLocation: androidUsesFineLocation);
  }

  Stream<BluetoothAdapterState> get adapterState {
    return FlutterBluePlus.adapterState;
  }

  Stream<List<ScanResult>> get scanResults {
    return FlutterBluePlus.scanResults;
  }

  bool get isScanningNow {
    return FlutterBluePlus.isScanningNow;
  }

  Stream<bool> get isScanning {
    return FlutterBluePlus.isScanning;
  }

  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }

  Future<void> setLogLevel(LogLevel level, {color = true}) {
    return FlutterBluePlus.setLogLevel(level, color: color);
  }

  LogLevel get logLevel {
    return FlutterBluePlus.logLevel;
  }

  Future<bool> get isSupported {
    return FlutterBluePlus.isSupported;
  }

  Future<String> get adapterName {
    return FlutterBluePlus.adapterName;
  }

  Future<void> turnOn({int timeout = 60}) {
    return FlutterBluePlus.turnOn(timeout: timeout);
  }

  List<BluetoothDevice> get connectedDevices {
    return FlutterBluePlus.connectedDevices;
  }

  Future<List<BluetoothDevice>> Function(List<Guid> withServices) get systemDevices {
    return FlutterBluePlus.systemDevices;
  }

  Future<PhySupport> getPhySupport() {
    return FlutterBluePlus.getPhySupport();
  }

  Future<List<BluetoothDevice>> get bondedDevices {
    return FlutterBluePlus.bondedDevices;
  }

  Stream<List<ScanResult>> get onScanResults {
    return FlutterBluePlus.onScanResults;
  }

  BluetoothEvents get events {
    return FlutterBluePlus.events;
  }
}
