import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundI18n {
  static final BackgroundI18n _instance = BackgroundI18n._();
  static BackgroundI18n get instance => _instance;
  BackgroundI18n._();

  Map<String, dynamic> _translations = {};
  Map<String, dynamic> _fallback = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    String lang = (await SharedPreferencesAsync().getString('savedLocale')) ??
        PlatformDispatcher.instance.locale.languageCode;
    _fallback = await _load('en');
    _translations = (lang == 'en') ? _fallback : await _load(lang);
    _initialized = true;
  }

  Future<Map<String, dynamic>> _load(String lang) async {
    try {
      return jsonDecode(await rootBundle.loadString('assets/i18n/$lang.json'));
    } catch (_) {
      return {};
    }
  }

  String translate(String key) => (_translations[key] ?? _fallback[key] ?? key) as String;
}
