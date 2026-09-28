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
}
