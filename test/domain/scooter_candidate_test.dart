import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/scooter_candidate.dart';

ScooterCandidate candidate(
  String id, {
  int? rssi,
  bool bonded = false,
  bool systemConnected = false,
  String? name,
}) {
  return ScooterCandidate(
    device: BluetoothDevice(remoteId: DeviceIdentifier(id)),
    name: name,
    rssi: rssi,
    bonded: bonded,
    systemConnected: systemConnected,
  );
}

void main() {
  group('addressLabel', () {
    test('shows an Android MAC in full', () {
      expect(candidate("aa:bb:cc:dd:ee:ff").idIsMacAddress, isTrue);
      expect(candidate("aa:bb:cc:dd:ee:ff").addressLabel, "AA:BB:CC:DD:EE:FF");
    });

    test('shortens an iOS identifier instead of passing it off as an address', () {
      final ScooterCandidate ios = candidate("A1B2C3D4-1234-5678-9ABC-DEF012345678");
      expect(ios.idIsMacAddress, isFalse);
      expect(ios.addressLabel, "...12345678");
    });
  });

  group('signalBars', () {
    test('has nothing to show without an RSSI', () {
      expect(candidate("aa:bb:cc:dd:ee:ff").signalBars, isNull);
    });

    test('maps signal strength onto four bars', () {
      expect(candidate("a", rssi: -45).signalBars, 4);
      expect(candidate("a", rssi: -65).signalBars, 3);
      expect(candidate("a", rssi: -75).signalBars, 2);
      expect(candidate("a", rssi: -85).signalBars, 1);
      expect(candidate("a", rssi: -100).signalBars, 0);
    });
  });

  group('mergedWith', () {
    test('keeps the bond marker when a scan result arrives later', () {
      final ScooterCandidate merged = candidate("aa:bb:cc:dd:ee:ff", bonded: true, name: "unu Scooter")
          .mergedWith(candidate("aa:bb:cc:dd:ee:ff", rssi: -60));
      expect(merged.bonded, isTrue);
      expect(merged.rssi, -60);
      expect(merged.name, "unu Scooter");
    });

    test('keeps the older RSSI when the newer sighting has none', () {
      final ScooterCandidate merged =
          candidate("a", rssi: -60).mergedWith(candidate("a", systemConnected: true));
      expect(merged.rssi, -60);
      expect(merged.systemConnected, isTrue);
    });
  });

  group('sorted', () {
    test('puts scooters we have no bond with first, then connected, then old bonds', () {
      final List<ScooterCandidate> sorted = ScooterCandidate.sorted([
        candidate("bonded-only", bonded: true),
        candidate("far", rssi: -90),
        candidate("near", rssi: -50),
        candidate("connected", bonded: true, systemConnected: true),
      ]);

      expect(sorted.map((c) => c.id).toList(), ["near", "far", "connected", "bonded-only"]);
    });

    test('orders old bonds that are answering above ones that are not', () {
      final List<ScooterCandidate> sorted = ScooterCandidate.sorted([
        candidate("silent", bonded: true),
        candidate("audible", bonded: true, rssi: -70),
      ]);

      expect(sorted.map((c) => c.id).toList(), ["audible", "silent"]);
    });
  });
}
