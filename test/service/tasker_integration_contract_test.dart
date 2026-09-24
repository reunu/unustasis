import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only signed Tasker configurations reach the exported action service', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"\n            android:exported="false"'));
    final editor = File('android/app/src/main/kotlin/de/freal/unustasis/tasker/TaskerActionEditActivity.kt').readAsStringSync();
    final receiver = File('android/app/src/main/kotlin/de/freal/unustasis/tasker/TaskerActionReceiver.kt').readAsStringSync();
    final authorization = File('android/app/src/main/kotlin/de/freal/unustasis/tasker/TaskerActionAuthorization.kt')
        .readAsStringSync();
    expect(editor.indexOf('TaskerActionAuthorization.isTrustedEditorCaller(callingPackage)'),
        lessThan(editor.indexOf('setContentView(')));
    expect(editor, contains('TaskerActionAuthorization.sign(this, action)'));
    expect(editor, contains('putString(TaskerActionAuthorization.BUNDLE_KEY_SIGNATURE, signature)'));
    expect(receiver.indexOf('TaskerActionAuthorization.accepts(context, action, settings)'),
        lessThan(receiver.indexOf('TaskerActionService.start(')));
    expect(authorization, contains('Mac.getInstance("HmacSHA256")'));
    expect(authorization, contains('MessageDigest.isEqual('));
  });

  test('native Tasker scan guidance reads the setting mirrored from DataStore', () {
    final settings = File('lib/ui/screens/stats/settings_screen.dart').readAsStringSync();
    final background = File('lib/background/bg_service.dart').readAsStringSync();
    final mirror = File('lib/service/tasker_settings_mirror.dart').readAsStringSync();
    final editor = File('android/app/src/main/kotlin/de/freal/unustasis/tasker/TaskerActionEditActivity.kt')
        .readAsStringSync();
    expect(settings.indexOf('await mirrorTaskerBackgroundScan(value)'),
        greaterThan(settings.indexOf('await prefs.setBool("backgroundScan", value)')));
    expect(background, contains('await mirrorTaskerBackgroundScan(backgroundScanEnabled)'));
    expect(mirror, contains("setBool('taskerBackgroundScan', enabled)"));
    expect(editor, contains('getBoolean("flutter.taskerBackgroundScan", false)'));
    expect(editor, isNot(contains('getBoolean("flutter.backgroundScan"')));
  });

  test('notification quick actions still persist the widget slot before direct dispatch', () {
    final notification = File('lib/background/notification_handler.dart').readAsStringSync();
    final background = File('lib/background/bg_service.dart').readAsStringSync();
    expect(notification.indexOf('await prefs.setBool("pendingWidgetAction", true)'),
        lessThan(notification.indexOf('FlutterBackgroundService().invoke(action)')));
    for (final action in ['lock', 'unlock', 'openseat']) {
      expect(background, contains('service.on("$action").listen((data) async => executeWidgetAction("$action"))'));
    }
  });
}
