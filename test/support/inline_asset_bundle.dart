import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_i18n/loaders/file_translation_loader.dart';

/// Decodes translation assets on the main isolate.
///
/// [AssetBundle.loadString] hands files of 50 KB or more to an isolate, whose
/// future never completes under the widget-test clock.
class InlineFileTranslationLoader extends FileTranslationLoader {
  InlineFileTranslationLoader({
    super.basePath = 'assets/flutter_i18n',
    super.fallbackFile = 'en',
    super.forcedLocale,
  }) {
    assetBundle = InlineStringBundle();
  }
}

class InlineStringBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final data = await load(key);
    return utf8.decode(Uint8List.sublistView(data));
  }
}
