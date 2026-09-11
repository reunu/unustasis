import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart' as shared;
import 'package:unustasis/domain/scooter_candidate.dart' as legacy;
import 'package:unustasis/flutter/blue_plus_mockable.dart' as legacy_ble;
import 'package:unustasis/service/ble_scanner.dart' as legacy_scan;

void main() {
  test('legacy discovery exports preserve shared type identity', () {
    final candidate = legacy.ScooterCandidate(
      device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:01'),
      rssi: -65,
    );
    expect(candidate, isA<shared.ScooterCandidate>());
    expect(candidate.signalBars, 3);
    expect(candidate.id, 'AA:BB:CC:DD:EE:01');
    final scanner = legacy_scan.BleScanner(legacy_ble.FlutterBluePlusMockable());
    expect(scanner, isA<shared.BleScanner>());
    expect(legacy_scan.BleScanner.scooterService, shared.BleScanner.scooterService);
  });
}
