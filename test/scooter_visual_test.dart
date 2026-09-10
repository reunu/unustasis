import 'dart:async';
import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Use the installed plugin's platform fake without changing dependencies.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_visual.dart';
import 'package:unustasis/services/image_cache_service.dart';

class _TestPathProvider extends PathProviderPlatform {
  final String path;
  _TestPathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheRoot = await Directory.systemTemp.createTemp('scooter-visual-test-');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(cacheRoot.path);
    await ImageCacheService().initialize();
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PathProviderPlatform.instance = originalPathProvider;
    await cacheRoot.delete(recursive: true);
  });

  Widget visual({String? url, bool custom = false}) => EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          home: ScooterVisual(
            state: ScooterState.parked,
            scanning: false,
            blinkerLeft: false,
            blinkerRight: false,
            color: 3,
            cloudImageUrl: url,
            hasCustomColor: custom,
          ),
        ),
      );

  final asset = find.byWidgetPredicate((widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'images/scooter/base_3.webp');
  final fileImage = find.byWidgetPredicate((widget) => widget is Image && widget.image is FileImage);
  final cloudFuture = find.byWidgetPredicate((widget) => widget is FutureBuilder<File?>);

  Future<void> finishCloudLoad(WidgetTester tester) async {
    final future = tester.widget<FutureBuilder<File?>>(cloudFuture).future!;
    await future;
    await tester.pumpAndSettle();
  }

  for (final custom in [false, true]) {
    testWidgets('renders supplied cloud image with custom color = $custom', (tester) async {
      const url = 'https://images.invalid/scooter.webp';
      // Seed the real disk cache using a bundled image and an in-memory HTTP response.
      await tester.runAsync(() async {
        final bytes = await rootBundle.load('images/scooter/base_1.webp');
        await http.runWithClient(
          () => ImageCacheService().downloadAndCache(url),
          () => MockClient((_) async => http.Response.bytes(bytes.buffer.asUint8List(), 200)),
        );
      });
      await tester.runAsync(() => http.runWithClient(() async {
            await tester.pumpWidget(visual(url: url, custom: custom));
            await tester.pump();
            await finishCloudLoad(tester);
            final provider = tester.widget<Image>(fileImage).image;
            await precacheImage(provider, tester.element(fileImage));
            await tester.pumpAndSettle();
            expect(fileImage, findsOneWidget);
            expect(asset, findsNothing);
            expect(tester.takeException(), isNull);
          }, () => MockClient((_) async => throw StateError('Cached image must not download again'))));
    });
  }

  for (final url in [null, '', '   ']) {
    testWidgets('uses the predefined asset for absent/blank URL: "$url"', (tester) async {
      await tester.pumpWidget(visual(url: url));
      await tester.pumpAndSettle();
      expect(asset, findsOneWidget);
      expect(cloudFuture, findsNothing);
      expect(fileImage, findsNothing);
    });
  }

  testWidgets('uses asset while loading and after a failed download', (tester) async {
    var requests = 0;
    await tester.runAsync(() async {
      final response = Completer<http.Response>();
      await http.runWithClient(() async {
        await tester.pumpWidget(visual(url: 'https://images.invalid/missing.webp'));
        await tester.pump();
        expect(asset, findsOneWidget);
        response.complete(http.Response('not found', 404));
        await finishCloudLoad(tester);
        expect(requests, 1);
        expect(asset, findsOneWidget);
        expect(fileImage, findsNothing);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((_) {
                requests++;
                return response.future;
              }));
    });
  });

  testWidgets('uses asset for an invalid image URL', (tester) async {
    await tester.runAsync(() => http.runWithClient(() async {
          await tester.pumpWidget(visual(url: 'http://['));
          await tester.pump();
          await expectLater(tester.widget<FutureBuilder<File?>>(cloudFuture).future!, throwsFormatException);
          await tester.pumpAndSettle();
          expect(asset, findsOneWidget);
          expect(tester.takeException(), isNull);
        }, () => MockClient((_) async => throw StateError('Invalid URL must not make a request'))));
  });

  testWidgets('uses asset when downloaded bytes cannot decode as an image', (tester) async {
    await tester.runAsync(() => http.runWithClient(() async {
          await tester.pumpWidget(visual(url: 'https://images.invalid/broken.webp'));
          await tester.pump();
          await finishCloudLoad(tester);
          final provider = tester.widget<Image>(fileImage).image;
          await precacheImage(provider, tester.element(fileImage), onError: (_, __) {});
          await tester.pumpAndSettle();
          expect(asset, findsOneWidget);
          expect(tester.takeException(), isNull);
        }, () => MockClient((_) async => http.Response('not an image', 200))));
  });
}
