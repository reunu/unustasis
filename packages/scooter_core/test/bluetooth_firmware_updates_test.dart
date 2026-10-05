import 'package:scooter_core/bluetooth_firmware_updates.dart';
import 'package:test/test.dart';

void main() {
  group('MDB Bluetooth firmware update eligibility', () {
    for (final version in [
      '1.2.0',
      'v1.2.0',
      ' v1.2.0+20260803123456 ',
      '1.2.0+build.01',
      '1.2.1',
      '1.2.1-rc.1',
      '1.3.0-beta',
      '2.0.0-alpha',
      '10.0.0',
      'nightly-20260803',
      'nightly-20260803T000000',
      'testing-20260803',
      'testing-20260803T235959',
      'nightly-20260804T000000',
      'testing-20280229T120000',
    ]) {
      test('$version qualifies',
          () => expect(supportsBluetoothFirmwareUpdates(version), isTrue));
    }
    for (final version in <String?>[
      null,
      '',
      ' ',
      'unknown',
      'demo',
      'custom',
      'v1.15.0-custom.01',
      '0.99.99',
      '1.1.99',
      '1.2.0-beta',
      'v1.2.0-rc.1+build',
      '1.3-beta',
      '1.2',
      '01.2.0',
      '1.02.0',
      '1.2.00',
      '1.2.1-01',
      'v1.2.0+',
      'v1.2.0+build..x',
      'v1.2.0junk',
      'release-v1.2.0',
      'nightly-20260802',
      'testing-20260802T235959',
      'nightly-20260229T000000',
      'testing-20260832',
      'nightly-20261301',
      'nightly-20260800',
      'testing-20260003',
      'nightly-20260803T240000',
      'testing-20260803T006000',
      'nightly-20260803T000060',
      'nightly-20260803T00000',
      'nightly-20260803junk',
      'custom-nightly-20260803',
      'testing-20260803t000000',
    ]) {
      test('$version stays hidden',
          () => expect(supportsBluetoothFirmwareUpdates(version), isFalse));
    }
  });
}
