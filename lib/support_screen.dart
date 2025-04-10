import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import '../stats/support_section.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          FlutterI18n.translate(context, "settings_support"),
        ),
      ),
      body: const SupportSection(),
    );
  }
}
