import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Use the installed plugin's in-memory test backend without changing dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<SavedScooter> reload(SavedScooter scooter) async {
    // updateSharedPreferences is async void; drain its in-memory writes.
    await Future<void>.delayed(Duration.zero);
    final saved = jsonDecode((await SharedPreferencesAsync().getString('savedScooters'))!) as Map<String, dynamic>;
    return SavedScooter.fromJson(scooter.id, saved[scooter.id] as Map<String, dynamic>);
  }

  group('SavedScooter.updateFromCloudData images', () {
    const images = {
      'front': 'https://images.invalid/front.png',
      'right': 'https://images.invalid/right.png',
    };
    for (final color in ['custom', 'predefined', 'omitted']) {
      test('persists supplied images with $color color and restores them', () async {
        final scooter = SavedScooter(id: 'test-scooter');
        scooter.updateFromCloudData({
          if (color == 'custom') ...{'color': 'custom', 'color_hex': '#123456'},
          if (color == 'predefined') ...{'color': 'blue', 'color_id': 3},
          'images': images,
        });

        final restored = await reload(scooter);
        expect(scooter.cloudImages, images);
        expect(restored.cloudImages, images);
        expect(restored.cloudImageFront, images['front']);
        expect(restored.cloudImageSide, images['right']);
        expect(restored.hasCustomColor, color == 'custom');
        if (color == 'predefined') expect(restored.color, 3);
      });
    }

    test('custom to predefined sync uses the newly supplied images', () async {
      final scooter = SavedScooter(id: 'test-scooter', colorHex: '#123456', cloudImages: {'front': 'old.png'});
      scooter.updateFromCloudData({'color_id': 3, 'images': images});
      final restored = await reload(scooter);
      expect(restored.hasCustomColor, isFalse);
      expect(restored.color, 3);
      expect(restored.cloudImages, images);
    });

    test('predefined sync without images still clears obsolete custom images', () async {
      final scooter = SavedScooter(id: 'test-scooter', colorHex: '#123456', cloudImages: images);
      scooter.updateFromCloudData({'color_id': 3});
      final restored = await reload(scooter);
      expect(restored.cloudImages, isNull);
      expect(restored.cloudImageFront, isNull);
      expect(restored.color, 3);
    });

    test('empty image payload leaves no URL, enabling asset fallback', () async {
      final scooter = SavedScooter(id: 'test-scooter', cloudImages: images);
      scooter.updateFromCloudData({'color_id': 3, 'images': <String, String>{}});
      expect((await reload(scooter)).cloudImageFront, isNull);
    });

    test('missing images on a new custom scooter leaves no URL', () async {
      final scooter = SavedScooter(id: 'test-scooter');
      scooter.updateFromCloudData({'color': 'custom', 'color_hex': '#123456'});
      expect((await reload(scooter)).cloudImageFront, isNull);
    });
  });
}
