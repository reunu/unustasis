import 'bootstrap.dart';

export 'app.dart' show MyApp, navigatorKey;
export 'bootstrap.dart' show migrateSharedPrefs;
export 'ui/theme/app_theme.dart' show createMaterialColor;

Future<void> main() => bootstrap();
