import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('U activity policy and navigation presentation remain app effects', () {
    final activity = File('lib/domain/statistics_helper.dart').readAsStringSync();
    expect(activity, contains('Future<bool> isEventLoggingEnabled() async => true;'));
    expect(activity, isNot(contains('setBool(')));
    expect(activity, contains('Geolocator.checkPermission()'));
    expect(activity, contains('Geolocator.getCurrentPosition()'));
    final screen = File('lib/ui/screens/navigation_screen.dart').readAsStringSync();
    expect(screen, contains('vehicle.navigationActive'));
    expect(screen, isNot(contains('service.activeNavigation')));
    expect(screen, isNot(contains('service.navigation.active')));
  });
  test('UI has no raw BLE transport or legacy command escape hatches', () {
    for (final file in Directory('lib/ui').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final escape in [
        'characteristicRepository',
        'myScooter',
        'ble_commands.dart',
        'characteristic_repository.dart',
        "package:flutter_blue_plus/",
        '.readRssi(',
        '.setNotifyValue(',
        'BluetoothCharacteristic',
      ]) {
        expect(source, isNot(contains(escape)), reason: '${file.path}: $escape');
      }
    }
  });
  test('app and background widget publication consume only the shared ID view', () {
    for (final path in ['lib/app.dart', 'lib/background/bg_service.dart']) {
      final source = File(path).readAsStringSync();
      expect(source, contains('currentScooterId'));
      expect(source, isNot(contains('myScooter')));
      expect(source, isNot(contains('characteristicRepository')));
    }
    final facade = File('lib/scooter_service.dart').readAsStringSync();
    expect(facade, isNot(contains('late CharacteristicRepository characteristicRepository')));
    expect(facade, contains('@visibleForTesting\n  BluetoothDevice? get myScooter'));
  });
  test('Provider metadata effects cannot own asynchronous store workflows', () {
    final facade = File('lib/scooter_service.dart').readAsStringSync();
    // The explicit reconnect-only widget route exposes one synchronous ID view.
    // It must not reintroduce asynchronous metadata selection/publication here.
    const widgetTargetView = 'String? get mostRecentSavedScooterId => store.getMostRecent()?.id;';
    expect(widgetTargetView.allMatches(facade), hasLength(1));
    final source = facade.replaceFirst(widgetTargetView, '');
    for (final operation in ['rename', 'recolor', 'load', 'remove', 'add', 'getMostRecent']) {
      expect(source, isNot(matches(RegExp(r'store\s*\.\s*' + operation + r'\s*\('))), reason: operation);
    }
    expect(source, isNot(matches(RegExp(r'await\s+(?:runtime\.)?getMostRecentScooter\s*\('))));
    for (final operation in ['rename', 'recolor']) {
      expect(source, contains('=> runtime.${operation}SavedScooter('));
    }
    // The only direct store operations left are compatibility map/ID views,
    // ping's concrete model effect and demo persistence; none select/publish
    // a saved-metadata workflow after an await.
    expect(RegExp(r'\bstore\s*\.\s*(\w+)').allMatches(source).map((match) => match[1]).toSet(),
        {'scooters', 'updatePing', 'save', 'getIds'});
  });
  test('Provider composes shared runtime rather than wire polling or cache loops', () {
    final source = File('lib/scooter_service.dart').readAsStringSync();
    for (final escape in [
      'Timer.periodic',
      'readRssi(',
      '.isScanning.listen(',
      'await store.load()',
      'await store.remove(',
      'await store.add(',
      'await device.',
      '.removeBond(',
      'jsonDecode(',
      'jsonEncode(',
      '_expireManualConnectionTarget(',
      'Duration(milliseconds: 500)',
      'Duration(seconds: 20)',
      'Duration(seconds: 60)',
      'while (',
      'withExtendedChannel(',
    ]) {
      expect(source, isNot(contains(escape)), reason: escape);
    }
    for (final delegate in [
      'ScooterRuntime<SavedScooter>(',
      'runtime.initialize()',
      'runtime.dispose()',
      'runtime.didChangeAppLifecycleState(state)',
      'runtime.refetchSavedScooters()',
      'runtime.pollLocation()',
      'runtime.prepareExplicitAction(EventType.unlock)'
    ]) {
      expect(source, contains(delegate));
    }
    final activity = File('lib/domain/statistics_helper.dart').readAsStringSync();
    for (final algorithm in ['_writeQueue', 'jsonEncode(', 'getStringList(', 'setStringList(']) {
      expect(activity, isNot(contains(algorithm)));
    }
    expect(activity, contains('extends ActivityStore'));
    expect(activity, contains('addDemoLogs()'));
  });
}
