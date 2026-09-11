import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation facade delegates state, firmware dispatch and invalidation', () {
    final source = File('lib/scooter_service.dart').readAsStringSync();
    for (final delegate in [
      'NavigationRuntime(',
      'runtime.initialize()',
      'service.navigation.bind(connection, repository)',
      'service.navigation.invalidate()',
      'service.navigation.firmwareIdentified(connection, firmware)',
      'service.navigation.navigationChanged(active)',
      'navigation.dispose()'
    ]) {
      expect(source, contains(delegate));
    }
    for (final algorithm in [
      '_pendingNavigation',
      '_activeNavigation',
      '_dispatchPendingNavigation',
      'jsonDecode(',
      'commands.navigateCommand('
    ]) {
      expect(source, isNot(contains(algorithm)));
    }
    expect(source, contains("getString('pendingNavigation')"));
    expect(source, contains("remove('pendingNavigation')"));
    expect(source, contains("setString('pendingNavigation', json)"));
  });
  test('navigation screen has no wire commands or characteristics', () {
    final source = File('lib/ui/screens/navigation_screen.dart').readAsStringSync();
    for (final escape in [
      'ble_commands.dart',
      'characteristicRepository',
      'navigateCommand(',
      'setActiveNavigation('
    ]) {
      expect(source, isNot(contains(escape)));
    }
    for (final method in [
      'listFavorites(',
      'navigate(',
      'saveFavorite(',
      'renameFavorite(',
      'deleteFavorite(',
      'cancel('
    ]) {
      expect(source, contains('service.navigation.$method'));
    }
    final commands = File('lib/service/ble_commands.dart').readAsStringSync();
    expect(commands, isNot(contains('nav:')));
    expect(commands, isNot(contains('withExtendedChannel(')));
  });
}
