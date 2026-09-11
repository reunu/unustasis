import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Configure before building any text styles; missing assets must never download.
void configureBundledFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/Nunito-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Kode Mono',
    ], await rootBundle.loadString('assets/fonts/KodeMono-OFL.txt'));
  });
}
