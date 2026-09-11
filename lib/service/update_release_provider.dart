import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_flutter/update_controller.dart';

import 'secure_http.dart';

/// Unustasis uses the Librescoot firmware distribution. Asset URLs remain those supplied by its
/// release index (not rewritten to a different host or channel).
class AppUpdateReleaseProvider implements UpdateReleaseProvider {
  static const releasesBase = 'https://downloads.librescoot.org/releases';

  final http.Client Function() _clientFactory;

  AppUpdateReleaseProvider({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  @override
  Future<List<FirmwareRelease>> fetchIndex(String channel) async {
    final response = await httpsGet(
      Uri.parse('$releasesBase/$channel.json'),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw UpdateHttpError(response.statusCode, index: true);
    }
    return [
      for (final entry in jsonDecode(response.body) as List<dynamic>)
        FirmwareRelease.fromJson(entry as Map<String, dynamic>)
    ];
  }

  @override
  Future<UpdateBundleDownload> fetchBundle(FirmwareAsset asset) async {
    final uri = Uri.parse(asset.url);
    if (uri.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(asset.url, 'asset.url', 'HTTPS is required');
    }

    final client = _clientFactory();
    try {
      var currentUri = uri;
      for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
        final request = http.Request('GET', currentUri)..followRedirects = false;
        final response = await client.send(request);
        final location = response.headers['location'];
        if (_isRedirectStatus(response.statusCode) && location != null) {
          await response.stream.drain<void>();
          final nextUri = currentUri.resolve(location);
          if (nextUri.scheme.toLowerCase() != 'https') {
            throw StateError('Firmware download redirected to a non-HTTPS URL');
          }
          currentUri = nextUri;
          continue;
        }
        if (response.statusCode != 200) {
          throw UpdateHttpError(response.statusCode, index: false);
        }
        return UpdateBundleDownload(
          bytes: response.stream,
          length: response.contentLength,
          close: client.close,
        );
      }
      throw StateError('Too many firmware download redirects');
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  bool _isRedirectStatus(int statusCode) =>
      statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;
}
