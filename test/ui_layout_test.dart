import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/app.dart' as app;
import 'package:unustasis/domain/icomoon.dart' as legacy_icons;
import 'package:unustasis/home_screen.dart' as legacy_home;
import 'package:unustasis/main.dart' as entrypoint;
import 'package:unustasis/ui/icons/icomoon.dart' as icons;
import 'package:unustasis/ui/screens/home_screen.dart' as home;
import 'package:unustasis/ui/theme/app_theme.dart' as theme;

// Legacy paths remain exports only, so callers share the canonical UI types.
const _relocated = <String, String>{
  'driving_screen.dart': 'ui/screens/driving_screen.dart',
  'home_screen.dart': 'ui/screens/home_screen.dart',
  'ls_keycard_screen.dart': 'ui/screens/ls_keycard_screen.dart',
  'ls_ota_screen.dart': 'ui/screens/ls_ota_screen.dart',
  'ls_scheduled_hibernation_screen.dart': 'ui/screens/ls_scheduled_hibernation_screen.dart',
  'ls_settings_screen.dart': 'ui/screens/ls_settings_screen.dart',
  'navigation_screen.dart': 'ui/screens/navigation_screen.dart',
  'onboarding_screen.dart': 'ui/screens/onboarding_screen.dart',
  'stats/battery_screen.dart': 'ui/screens/stats/battery_screen.dart',
  'stats/log_screen.dart': 'ui/screens/stats/log_screen.dart',
  'stats/scooter_screen.dart': 'ui/screens/stats/scooter_screen.dart',
  'stats/settings_screen.dart': 'ui/screens/stats/settings_screen.dart',
  'stats/support_screen.dart': 'ui/screens/stats/support_screen.dart',
  'control_sheet.dart': 'ui/sheets/control_sheet.dart',
  'hibernate_sheet.dart': 'ui/sheets/hibernate_sheet.dart',
  'handlebar_warning.dart': 'ui/dialogs/handlebar_warning.dart',
  'seat_warning.dart': 'ui/dialogs/seat_warning.dart',
  'keycard_add_dialog.dart': 'ui/dialogs/keycard_add_dialog.dart',
  'helper_widgets/clouds.dart': 'ui/widgets/clouds.dart',
  'helper_widgets/color_picker_dialog.dart': 'ui/dialogs/color_picker_dialog.dart',
  'helper_widgets/grassscape.dart': 'ui/widgets/grassscape.dart',
  'helper_widgets/header.dart': 'ui/widgets/header.dart',
  'helper_widgets/leaves.dart': 'ui/widgets/leaves.dart',
  'helper_widgets/onboarding_popups.dart': 'ui/dialogs/onboarding_popups.dart',
  'helper_widgets/scooter_action_button.dart': 'ui/widgets/scooter_action_button.dart',
  'helper_widgets/scooter_picker.dart': 'ui/widgets/scooter_picker.dart',
  'helper_widgets/snowfall.dart': 'ui/widgets/snowfall.dart',
  'scooter_visual.dart': 'ui/widgets/scooter_visual.dart',
  'domain/theme_helper.dart': 'ui/theme/theme_helper.dart',
  'domain/icomoon.dart': 'ui/icons/icomoon.dart',
};

Uri _resolveImport(File source, String path) {
  if (path.startsWith('package:unustasis/')) {
    return Directory('lib').absolute.uri.resolve(path.substring('package:unustasis/'.length));
  }
  return source.absolute.uri.resolve(path);
}

void main() {
  test('relocated presentation paths are export-only compatibility libraries', () {
    final export = RegExp(r"^export '([^']+)';$");
    for (final relocation in _relocated.entries) {
      final legacy = File('lib/${relocation.key}');
      final canonical = File('lib/${relocation.value}');
      expect(canonical.existsSync(), isTrue, reason: canonical.path);
      final match = export.firstMatch(legacy.readAsStringSync().trim());
      expect(match, isNotNull, reason: '${legacy.path} must be export-only');
      expect(_resolveImport(legacy, match![1]!), canonical.absolute.uri, reason: legacy.path);
    }
  });

  test('widget and painter implementations live in ui, apart from app composition', () {
    final presentationClass = RegExp(
      r'extends\s+(?:StatefulWidget|StatelessWidget|State<|CustomPainter)',
    );
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.startsWith('lib/ui/') || file.path == 'lib/app.dart') {
        continue;
      }
      expect(presentationClass.hasMatch(file.readAsStringSync()), isFalse, reason: file.path);
    }
  });

  test('ui imports canonical paths without depending on composition entrypoints', () {
    final imports = RegExp(r'''^\s*(?:import|export) ['"]([^'"]+)['"]''', multiLine: true);
    final forbidden = {
      for (final path in _relocated.keys) File('lib/$path').absolute.uri,
      for (final path in ['main.dart', 'app.dart', 'bootstrap.dart']) File('lib/$path').absolute.uri,
    };
    for (final file in Directory('lib/ui').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in imports.allMatches(file.readAsStringSync())) {
        final path = match[1]!;
        if (path.startsWith('dart:') || (path.startsWith('package:') && !path.startsWith('package:unustasis/'))) {
          continue;
        }
        final target = _resolveImport(file, path);
        expect(forbidden, isNot(contains(target)), reason: '${file.path}: $path');
        expect(File.fromUri(target).existsSync(), isTrue, reason: '${file.path}: $path');
      }
    }
  });

  test('main delegates startup and bootstrap retains the foreground Provider owner', () {
    final main = File('lib/main.dart').readAsStringSync();
    final bootstrap = File('lib/bootstrap.dart').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    expect(main, contains('Future<void> main() => bootstrap();'));
    expect(RegExp(r'\bScooterService\(').allMatches('$main\n$bootstrap\n$app'), hasLength(1));
    expect(bootstrap, contains('runApp(ChangeNotifierProvider('));
    expect(bootstrap, contains('create: (context) => ScooterService(FlutterBluePlusMockable())'));
    expect(app, contains('Provider.of<ScooterService>(context, listen: false)'));
  });

  test('legacy exports preserve UI type, navigator and theme helper identity', () {
    expect(legacy_home.HomeScreen, home.HomeScreen);
    expect(legacy_icons.Icomoon, icons.Icomoon);
    expect(entrypoint.MyApp, app.MyApp);
    expect(identical(entrypoint.navigatorKey, app.navigatorKey), isTrue);
    expect(entrypoint.createMaterialColor, theme.createMaterialColor);
  });
}
