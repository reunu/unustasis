import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the bundled font licenses with Flutter's license registry.
/// The families themselves are declared in pubspec.yaml.
void configureBundledFonts() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/Nunito-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Kode Mono',
    ], await rootBundle.loadString('assets/fonts/KodeMono-OFL.txt'));
  });
}
