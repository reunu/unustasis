import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart' as core;
import 'package:unustasis/domain/scooter_keyless_distance.dart';

void main() {
  test('legacy export forwards the core enum and formatting extension', () {
    expect(identical(ScooterKeylessDistance.values, core.ScooterKeylessDistance.values), isTrue);
    expect(ScooterKeylessDistance.values.map((distance) => distance.getFormattedThreshold()), [
      '-55 dBm',
      '-65 dBm',
      '-75 dBm',
      '-85 dBm',
    ]);
    expect(ScooterKeylessDistance.fromThreshold(-65), core.ScooterKeylessDistance.regular);
  });

  testWidgets('legacy name(context) maps every distance to its existing localization', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(translationLoader: FileTranslationLoader(basePath: 'assets/i18n', fallbackFile: 'en')),
      ],
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();
    const keys = [
      'auto_unlock_threshold_close',
      'auto_unlock_threshold_regular',
      'auto_unlock_threshold_far',
      'auto_unlock_threshold_very_far',
    ];
    for (var index = 0; index < keys.length; index++) {
      final distance = ScooterKeylessDistance.values[index];
      final translated = FlutterI18n.translate(context, keys[index]);
      expect(translated, isNot(keys[index]));
      expect(distance.name(context), translated);
      expect(KeylessDistanceExtension(distance).name(context), translated);
    }
  });
}
