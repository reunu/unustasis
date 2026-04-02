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
    final saved = await SharedPreferencesAsync().getString('savedLocale');
    final lang = saved ?? PlatformDispatcher.instance.locale.languageCode;
    _fallback = await _load('en');
    if (lang == 'en') {
      _translations = _fallback;
    } else {
      // Load the base language first, then overlay the specific variant.
      // e.g. for en_GB: load en, then merge en_GB on top.
      final parts = lang.split('_');
      if (parts.length > 1) {
        _translations = await _load(parts[0]);
        final specific = await _load(lang);
        _translations = {..._translations, ...specific};
      } else {
        _translations = await _load(lang);
      }
    }
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
