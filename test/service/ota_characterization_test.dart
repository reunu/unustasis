import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/service/ota_transfer_service.dart';

void main() {
  test('Unustasis retains the configured English fallback', () {
    expect(File('lib/app.dart').readAsStringSync(), contains("fallbackFile: 'en'"));
  });
  test('Unustasis release distribution, index deadline and cache path policy remain app-owned', () {
    final provider = File('lib/service/update_release_provider.dart');
    final source = provider.existsSync() ? provider.readAsStringSync() : File('lib/ui/screens/ls_ota_screen.dart').readAsStringSync();
    expect(source, contains('https://downloads.librescoot.org/releases'));
    expect(source, contains('Duration(seconds: 15)'));
    expect(source, contains('Uri.parse(asset.url)'));
    final app = File('lib/scooter_service.dart').readAsStringSync() + File('lib/ui/screens/ls_ota_screen.dart').readAsStringSync();
    expect(app, contains('getApplicationSupportDirectory()'));
    expect(app, contains('.path}/ota'));
  });
  test('settled reboot outcome remains busy but not active and resettable', () {
    final transfer = OtaTransferService();
    transfer.state = OtaTransferState.pendingReboot;
    expect(transfer.busy, true);
    expect(transfer.active, false);
    transfer.reset();
    expect(transfer.state, OtaTransferState.idle);
    transfer.dispose();
  });
}
