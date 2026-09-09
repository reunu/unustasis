import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_flutter/update_controller.dart';

/// Unustasis uses the Librescoot firmware distribution. Asset URLs remain those supplied by its
/// release index (not rewritten to a different host or channel).
class AppUpdateReleaseProvider implements UpdateReleaseProvider {
  static const releasesBase = 'https://downloads.librescoot.org/releases';

  @override
  Future<List<FirmwareRelease>> fetchIndex(String channel) async {
    final response = await http.get(Uri.parse('$releasesBase/$channel.json')).timeout(const Duration(seconds: 15));
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
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(asset.url)));
      if (response.statusCode != 200) {
        throw UpdateHttpError(response.statusCode, index: false);
      }
      return UpdateBundleDownload(bytes: response.stream, length: response.contentLength, close: client.close);
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}
