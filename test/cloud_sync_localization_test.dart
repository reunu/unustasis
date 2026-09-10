import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = {
    'en': ['Local:', 'Cloud:'],
    'en_GB': ['Local:', 'Cloud:'],
    'de': ['Lokal:', 'Cloud:'],
    'fr': ['Local :', 'Cloud :'],
    'nl': ['Lokaal:', 'Cloud:'],
    'pi': ['Aboard:', 'In the clouds:'],
  };

  test('every shipped locale defines comparison labels with value placeholders', () {
    final locales = Directory('assets/i18n').listSync().whereType<File>().where((file) => file.path.endsWith('.json'));
    expect(locales.map((file) => file.uri.pathSegments.last.replaceAll('.json', '')), unorderedEquals(labels.keys));
    for (final file in locales) {
      final translations = {
        // Regional files intentionally override only a subset of their base locale.
        if (file.path.endsWith('en_GB.json'))
          ...jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>,
        ...jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      };
      for (final key in ['cloud_sync_local_value', 'cloud_sync_cloud_value']) {
        expect(translations[key], isA<String>(), reason: '${file.path}: $key');
        expect('{value}'.allMatches(translations[key] as String), hasLength(1));
      }
    }
  });

  test('ScooterScreen translates both name and color comparison rows', () {
    final source = File('lib/stats/scooter_screen.dart').readAsStringSync();
    for (final entry in {
      'localName': 'cloud_sync_local_value',
      'cloudName': 'cloud_sync_cloud_value',
      'localColorName': 'cloud_sync_local_value',
      'cloudColorName': 'cloud_sync_cloud_value',
    }.entries) {
      expect(source, contains('"${entry.value}", translationParams: {"value": ${entry.key}}'));
    }
    expect(source, isNot(contains("Text('Local:")));
    expect(source, isNot(contains("Text('Cloud:")));
  });

  for (final locale in labels.entries) {
    testWidgets('FlutterI18n interpolates comparison values in ${locale.key}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            forcedLocale: locale.key == 'en_GB' ? const Locale('en', 'GB') : Locale(locale.key),
            fallbackFile: null,
          )),
        ],
        home: Builder(
            builder: (context) => Column(children: [
                  for (final value in ['Scooter name', '#123456']) ...[
                    Text(FlutterI18n.translate(context, 'cloud_sync_local_value', translationParams: {'value': value})),
                    Text(FlutterI18n.translate(context, 'cloud_sync_cloud_value', translationParams: {'value': value})),
                  ],
                ])),
      ));
      await tester.pumpAndSettle();
      for (final value in ['Scooter name', '#123456']) {
        expect(find.text('${locale.value[0]} $value'), findsOneWidget);
        expect(find.text('${locale.value[1]} $value'), findsOneWidget);
      }
    });
  }
}
