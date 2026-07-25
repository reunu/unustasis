import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/nav_channel.dart';

void main() {
  group('navChannelFor', () {
    test('BLE wins when it is ready', () {
      expect(
        navChannelFor(bleReady: true, cloudLinked: true, cloudOnline: true),
        NavChannel.ble,
      );
      expect(
        navChannelFor(bleReady: true, cloudLinked: false, cloudOnline: false),
        NavChannel.ble,
      );
    });

    test('cloud takes over when BLE is not ready', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: true, cloudOnline: true),
        NavChannel.cloud,
      );
    });

    test('a linked but offline scooter falls through to pending', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: true, cloudOnline: false),
        NavChannel.pending,
      );
    });

    test('an unlinked scooter falls through to pending', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: false, cloudOnline: true),
        NavChannel.pending,
      );
      expect(
        navChannelFor(bleReady: false, cloudLinked: false, cloudOnline: false),
        NavChannel.pending,
      );
    });
  });
}
