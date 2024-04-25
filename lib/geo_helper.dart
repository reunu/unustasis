import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:http/http.dart';

class GeoHelper {
  static Future<String?> getAddress(LatLng? position) async {
    if (position == null) {
      return null;
    }
    Response response = await get(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json'));
    if (response.statusCode != 200 || response.body.isEmpty) {
      return null;
    }
    Map<String, dynamic> json = jsonDecode(response.body);
    return "${json['address']['road']} ${json['address']['house_number'] ?? ""}, ${json['address']['city']}";
  }
}
