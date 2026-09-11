import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Reset the package's in-memory cache and intercept its HTTP client for this test.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_loader;
import 'package:http/testing.dart';
import 'package:unustasis/fonts.dart';

const _fontHashes = {
  'assets/fonts/Nunito-Regular.ttf': '6f96017e762896b4cf3c2db345d41d7a72a3720a95698c3cd47020bf433db435',
  'assets/fonts/KodeMono-Regular.ttf': '6261ece2db7c0ce519f62a9cba501e50b3eed789c91436a955e4bc4a37ee3e3e',
};

List<TextStyle> _styles(TextTheme theme) => [
      theme.displayLarge!,
      theme.displayMedium!,
      theme.displaySmall!,
      theme.headlineLarge!,
      theme.headlineMedium!,
      theme.headlineSmall!,
      theme.titleLarge!,
      theme.titleMedium!,
      theme.titleSmall!,
      theme.bodyLarge!,
      theme.bodyMedium!,
      theme.bodySmall!,
      theme.labelLarge!,
      theme.labelMedium!,
      theme.labelSmall!,
    ];

double _textWidth(TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'stasis Wi 0123', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('main configures bundled fonts before asynchronous startup or UI', () {
    final source = File('lib/main.dart').readAsStringSync();
    final configure = source.indexOf('  configureBundledFonts();');
    expect(configure, greaterThan(source.indexOf('void main()')));
    expect(configure, lessThan(source.indexOf('  await ')));
    expect(configure, lessThan(source.indexOf('  runApp(')));
  });

  test('font request sites stay covered by the offline rendering test', () {
    final requests = <String, List<String>>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final calls =
          RegExp(r'GoogleFonts\.(\w+)\(').allMatches(file.readAsStringSync()).map((match) => match.group(1)!).toList();
      if (calls.isNotEmpty) requests[file.path] = calls;
    }
    expect(requests, {
      'lib/main.dart': ['nunitoTextTheme', 'nunitoTextTheme'],
      'lib/ls_keycard_screen.dart': ['kodeMono'],
      'lib/ls_scheduled_hibernation_screen.dart': ['kodeMono'],
    });
    final main = File('lib/main.dart').readAsStringSync();
    for (final brightness in ['light', 'dark']) {
      expect(
          main,
          contains('GoogleFonts.nunitoTextTheme('
              'ThemeData(brightness: Brightness.$brightness).textTheme)'));
    }
    expect(File('lib/ls_keycard_screen.dart').readAsStringSync(),
        contains(RegExp(r'GoogleFonts\.kodeMono\(\s*color: Colors.white,\s*fontSize: 28,\s*\)')));
    expect(File('lib/ls_scheduled_hibernation_screen.dart').readAsStringSync(), contains('GoogleFonts.kodeMono()'));
  });

  testWidgets(
    'bundled fonts render light/dark typography without network or cache',
    (tester) async {
      final previousClient = font_loader.httpClient;
      final previousFetching = GoogleFonts.config.allowRuntimeFetching;
      var networkRequests = 0;
      var cacheRequests = 0;
      font_loader.clearCache();
      font_loader.assetManifest = null;
      font_loader.httpClient = MockClient((request) async {
        networkRequests++;
        throw StateError('Offline: unexpected font request ${request.url}');
      });
      // No device cache is available, even if a developer has downloaded fonts.
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        (call) async {
          cacheRequests++;
          throw StateError(
            'Font loading must use assets, not the device cache',
          );
        },
      );
      addTearDown(() {
        font_loader.httpClient = previousClient;
        font_loader.clearCache();
        font_loader.assetManifest = null;
        GoogleFonts.config.allowRuntimeFetching = previousFetching;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProvider,
          null,
        );
      });

      configureBundledFonts();
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final entry in _fontHashes.entries) {
        expect(manifest.listAssets(), contains(entry.key));
        final bytes = await rootBundle.load(entry.key);
        expect(
          sha256.convert(bytes.buffer.asUint8List()).toString(),
          entry.value,
        );
      }
      // The existing icon font must remain registered independently.
      final fonts = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
      expect(
        fonts,
        contains(equals({
          'family': 'icomoon',
          'fonts': [
            {'asset': 'assets/fonts/icomoon.ttf'},
          ],
        })),
      );

      final licenses = await LicenseRegistry.licenses.toList();
      for (final family in ['Nunito', 'Kode Mono']) {
        final license = licenses.singleWhere(
          (entry) => entry.packages.contains(family),
        );
        final text = license.paragraphs.map((p) => p.text).join('\n');
        expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
        expect(text, contains('The $family Project Authors'));
      }

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final brightness in Brightness.values) {
        // Match the app's two theme calls and both Kode Mono call sites exactly.
        final textTheme = GoogleFonts.nunitoTextTheme(
          ThemeData(brightness: brightness).textTheme,
        );
        // ThemeData's unlocalized slots have no weights yet: every request is
        // Regular, even though Material later supplies 400/500 geometry.
        expect(_styles(textTheme).map((s) => s.fontWeight).toSet(), {null});
        expect(_styles(textTheme).map((s) => s.fontFamily).toSet(), {
          'Nunito_regular',
        });
        final theme = ThemeData(brightness: brightness, textTheme: textTheme);
        final localizedTextTheme = ThemeData.localize(
          theme,
          theme.typography.englishLike,
        ).textTheme;
        final styles = _styles(localizedTextTheme);
        expect(styles.map((s) => s.fontWeight).toSet(), {
          FontWeight.w400,
          FontWeight.w500,
        });
        final keycard = GoogleFonts.kodeMono(color: Colors.white, fontSize: 28);
        final cron = GoogleFonts.kodeMono();
        expect(keycard.fontFamily, 'KodeMono_regular');
        expect(cron.fontFamily, 'KodeMono_regular');
        // copyWith does not request new variants; preserve existing synthesis.
        styles.addAll([
          localizedTextTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w900),
          localizedTextTheme.bodyMedium!.copyWith(fontStyle: FontStyle.italic),
          keycard,
          cron,
        ]);
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        for (final style in styles) {
          expect(
            _textWidth(style),
            isNot(
              _textWidth(
                style.copyWith(
                  fontFamily: 'Ahem',
                  fontFamilyFallback: const [],
                ),
              ),
            ),
            reason: '${style.fontFamily} must render a loaded font, not fallback',
          );
        }

        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final style in styles) Text('stasis Wi 0123 • äöü é', style: style),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixels, isNotNull);
          expect(pixels!.lengthInBytes, 1000 * 1400 * 4);
          // A rendered frame must contain more than its solid background color.
          expect(pixels.buffer.asUint32List().toSet().length, greaterThan(2));
          image.dispose();
        });
      }
      expect(networkRequests, 0);
      expect(cacheRequests, 0);
      expect(font_loader.pendingFontFutures, isEmpty);
    },
  );
}
