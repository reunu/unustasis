import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OTA UI renders one service controller, no transfer/cache/planner runtime', () {
    final screen = File('lib/ui/screens/ls_ota_screen.dart').readAsStringSync();
    for (final forbidden in [
      'http.',
      'dart:io',
      'ble_commands.dart',
      'getInstalledVersionCommand',
      '.transfer(',
      'syncFromScooter(',
      '_pruneDownloads',
      'getApplicationSupportDirectory',
      'characteristicRepository',
      'myScooter',
      'UpdatePlanner.buildPlan',
      '_downloadBundle',
      '_verifyBundle',
      'OtaTransferService.shared',
      'static UpdatePlan'
    ]) {
      expect(screen, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(screen, contains('context.read<ScooterService>().updateController'));
    expect(screen, contains('_updates.removeListener(_onTransferChanged)'));
    expect(screen, isNot(contains('_updates.dispose()')));
    expect(File('lib/service/ota_transfer_service.dart').readAsStringSync().trim(),
        "export 'package:scooter_flutter/ota_transfer_service.dart';");
  });
  test('app supplies distribution and composes OTA on the existing session', () {
    final service = File('lib/scooter_service.dart').readAsStringSync();
    expect(service, contains('UpdateController(session: _session'));
    expect(service, contains('service.updateController.bind(connection, repository)'));
    expect(service, contains('service.updateController.invalidate()'));
    expect(service, contains('service.updateController.sessionReady()'));
    expect(service, contains('updateController.dispose()'));
    expect(service, contains("onTargetCaptured: (id) => updateTargetName = savedScooters[id]?.name ?? id"));
    final provider = File('lib/service/update_release_provider.dart').readAsStringSync();
    expect(provider, contains('https://downloads.librescoot.org/releases'));
    expect(provider, contains('Uri.parse(asset.url)'));
    expect(provider, contains('Duration(seconds: 15)'));
    expect(provider, contains('close: client.close'));
  });
}
