import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeoHelper {
  static Future<String?> getAddress(LatLng? position, BuildContext context) async {
    if (position == null) {
      return null;
    }

    // see if user hasn't disabled Nominatim
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (await prefs.getBool("osmConsent") == false) {
      return null;
    }

    Response response = await get(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json'));
    if (response.statusCode != 200 || response.body.isEmpty) {
      return null;
    }
    Map<String, dynamic> json = jsonDecode(response.body);
    String? street = json['address']['road'];
    String? streetNumber = json['address']['house_number'];
    String? city = json['address']['city'];

    if (street != null && streetNumber != null && city != null) {
      return '$street $streetNumber, $city';
    } else if (street != null && city != null) {
      return '$street, $city';
    } else if (street != null && streetNumber != null) {
      return '$street $streetNumber';
    } else if (street != null) {
      return street;
    } else if (city != null) {
      return city;
    } else {
      return null;
    }
  }
}
