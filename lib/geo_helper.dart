import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/saved_scooter.dart';

class GeoHelper {
  static Future<String?> getAddress(SavedScooter scooter, BuildContext context) async {
    final log = Logger('HomeScreen');

    if (scooter.lastAddress != null) {
      log.info("Using cached address: ${scooter.lastAddress}");
      return scooter.lastAddress;
    }

    LatLng? position = scooter.lastLocation;
    if (position == null) {
      log.info("getAddress called with null position");
      return null;
    }

    // see if user hasn't disabled Nominatim
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (await prefs.getBool("osmConsent") == false) {
      log.info("User has disabled Nominatim");
      return null;
    }

    log.info("Fetching address from Nominatim for position: $position");
    // TODO: Set custom HTTP headers including User-Agent as per Nominatim usage policy
    // then, contact nominatim@openstreetmap.org to have ban lifted
    Response response = await get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json'),
        headers: {
          'User-Agent': 'UnustasisApp (unu@freal.de)',
        });
    if (response.statusCode != 200 || response.body.isEmpty) {
      log.info("Failed to fetch address from Nominatim: ${response.statusCode}");
      log.info("Message: ${response.body}");
      return null;
    }
    log.info("Successfully fetched address from Nominatim");
    Map<String, dynamic> json = jsonDecode(response.body);
    String? street = json['address']['road'];
    String? streetNumber = json['address']['house_number'];
    String? city = json['address']['city'];

    String? formattedAddress;

    if (street != null && streetNumber != null && city != null) {
      formattedAddress = '$street $streetNumber, $city';
    } else if (street != null && city != null) {
      formattedAddress = '$street, $city';
    } else if (street != null && streetNumber != null) {
      formattedAddress = '$street $streetNumber';
    } else if (street != null) {
      formattedAddress = street;
    } else if (city != null) {
      formattedAddress = city;
    } else {
      formattedAddress = null;
    }

    scooter.lastAddress = formattedAddress;
    return formattedAddress;
  }
}
