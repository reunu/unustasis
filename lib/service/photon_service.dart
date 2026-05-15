import 'dart:convert';

import 'package:flutter_photon/flutter_photon.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const _userAgent = 'UnustasisApp (oss4unu@freal.de)';

/// Forward geocoding search using the Photon API with proper User-Agent.
Future<List<PhotonFeature>> photonForwardSearch(String query, {LatLng? ownLocation, int? limit}) async {
  final params = <String, String>{'q': query};
  if (ownLocation != null) {
    params['lat'] = '${ownLocation.latitude}';
    params['lon'] = '${ownLocation.longitude}';
  }
  if (limit != null) params['limit'] = '$limit';

  final uri = Uri.https('photon.komoot.io', '/api', params);
  final response = await http.get(uri, headers: {'User-Agent': _userAgent});
  return _parsePhotonResponse(response);
}

/// Reverse geocoding using the Photon API with proper User-Agent.
Future<List<PhotonFeature>> photonReverseSearch(double latitude, double longitude) async {
  final uri = Uri.https('photon.komoot.io', '/reverse', {
    'lat': '$latitude',
    'lon': '$longitude',
  });
  final response = await http.get(uri, headers: {'User-Agent': _userAgent});
  return _parsePhotonResponse(response);
}

List<PhotonFeature> _parsePhotonResponse(http.Response response) {
  if (response.statusCode != 200) {
    throw Exception('Photon API error: ${response.statusCode}');
  }
  final features = jsonDecode(response.body)['features'] as List<dynamic>;
  return features.map((f) => PhotonFeature.fromJson(f as Map<String, dynamic>)).toList();
}
