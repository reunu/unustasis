import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final locales =
      Directory('assets/i18n')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('locale assets exist', () {
    expect(locales, isNotEmpty);
  });

  for (final locale in locales) {
    test('${locale.path} contains a valid JSON object', () {
      expect(
        jsonDecode(locale.readAsStringSync()),
        isA<Map<String, dynamic>>(),
      );
    });
  }
}
