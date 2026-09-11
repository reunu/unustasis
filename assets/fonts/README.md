# Bundled Google Fonts

These unmodified static fonts are the exact files selected by `google_fonts`
6.3.3 (the version in `pubspec.lock`). Keep their filenames: the package matches
assets by family and variant, then registers them with Flutter's `FontLoader`.
They belong in `flutter.assets`, not `flutter.fonts`, to preserve the existing
Google Fonts family names and style behavior.

- Nunito Regular (400): used by both Material text themes.
- Kode Mono Regular (400): keycard identifiers and raw hibernation cron text.

The app passes unlocalized `ThemeData.textTheme` to `nunitoTextTheme`: its
weights are null, so all slots request Regular (400). Material's 400/500 weights
are applied later when the theme is localized. These inherited weights and
existing `copyWith` bold/italic styles continue to use Flutter's synthesis of the
regular face; they did not request separate Google Fonts downloads.
The icomoon icon font and platform monospace styling are unchanged.

## Sources and integrity

The URL for each file is `https://fonts.gstatic.com/s/a/<SHA-256>.ttf`, matching
its descriptor in `google_fonts` 6.3.3 (`part_n.g.dart` / `part_k.g.dart`).

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| Nunito-Regular.ttf | 125504 | 6f96017e762896b4cf3c2db345d41d7a72a3720a95698c3cd47020bf433db435 |
| KodeMono-Regular.ttf | 43452 | 6261ece2db7c0ce519f62a9cba501e50b3eed789c91436a955e4bc4a37ee3e3e |

Nunito reports version 3.602; Kode Mono reports version 1.206. Both are licensed
under the SIL Open Font License 1.1. The accompanying unmodified licenses match
the copyright notices embedded in the fonts and are registered in Flutter's
license registry at startup:

- [Nunito-OFL.txt](https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/nunito/OFL.txt)
- [KodeMono-OFL.txt](https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/kodemono/OFL.txt)

Runtime fetching is disabled in `lib/fonts.dart` before any UI is built. When
adding a new Google Fonts family or directly requesting another weight/style,
bundle that exact variant and its license and extend `test/assets/fonts_test.dart`.
