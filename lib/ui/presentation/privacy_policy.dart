import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

/// Privacy policy for the online location services, hosted on the rescoot site.
const privacyPolicyBaseUrl = 'https://rescoot.org';

Uri privacyPolicyUri({String? language}) {
  final path = language == 'de' ? '/de/projekte/stasis/datenschutz/' : '/en/projects/stasis/privacy/';
  return Uri.parse('$privacyPolicyBaseUrl$path');
}

Uri privacyPolicyUriFor(BuildContext context) =>
    privacyPolicyUri(language: FlutterI18n.currentLocale(context)?.languageCode);
