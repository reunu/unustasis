import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

/// Privacy policy for the online location services, published on the app's Pages site.
const privacyPolicyBaseUrl = 'https://reunu.github.io/unustasis';

Uri privacyPolicyUri({String? language}) {
  final path = language == 'de' ? '/de/privacy/mobile-app/' : '/privacy/mobile-app/';
  return Uri.parse('$privacyPolicyBaseUrl$path');
}

Uri privacyPolicyUriFor(BuildContext context) =>
    privacyPolicyUri(language: FlutterI18n.currentLocale(context)?.languageCode);
