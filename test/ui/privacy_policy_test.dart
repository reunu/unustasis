import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/presentation/privacy_policy.dart';

void main() {
  test('privacy policy resolves to the rescoot policy per language', () {
    expect(
      privacyPolicyUri(language: 'en'),
      Uri.parse('https://rescoot.org/en/projects/stasis/privacy/'),
    );
    expect(
      privacyPolicyUri(language: 'de'),
      Uri.parse('https://rescoot.org/de/projekte/stasis/datenschutz/'),
    );
    expect(
      privacyPolicyUri(language: 'fr'),
      Uri.parse('https://rescoot.org/en/projects/stasis/privacy/'),
    );
    expect(privacyPolicyUri(), Uri.parse('https://rescoot.org/en/projects/stasis/privacy/'));
  });

  test('hosted policy pages name the online providers and contact', () {
    const pages = {
      'docs/privacy/mobile-app/index.html': ('27 September 2026', 'on by default'),
      'docs/de/privacy/mobile-app/index.html': ('27. September 2026', 'standardmäßig eingeschaltet'),
    };
    for (final page in pages.entries) {
      final html = File(page.key).readAsStringSync();
      expect(html, contains('nominatim'), reason: page.key);
      expect(html, contains('photon.komoot.io'), reason: page.key);
      expect(html, contains('oss4unu@freal.de'), reason: page.key);
      expect(html, contains(page.value.$1), reason: page.key);
      expect(html, contains(page.value.$2), reason: page.key);
    }
  });
}
