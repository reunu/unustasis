import 'dart:convert';

import 'package:flutter_photon/flutter_photon.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/nav_destination.dart';
import '../service/photon_service.dart';

import '../domain/saved_scooter.dart';

class GeoHelper {
  static String sanitizeName(String name) {
    const replacements = {
      'ä': 'ae',
      'Ä': 'Ae',
      'ö': 'oe',
      'Ö': 'Oe',
      'ü': 'ue',
      'Ü': 'Ue',
      'ß': 'ss',
      ':': '',
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'æ': 'ae',
      'À': 'A',
      'Á': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Å': 'A',
      'Æ': 'Ae',
      'ç': 'c',
      'Ç': 'C',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'È': 'E',
      'É': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'Ì': 'I',
      'Í': 'I',
      'Î': 'I',
      'Ï': 'I',
      'ñ': 'n',
      'Ñ': 'N',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ø': 'o',
      'œ': 'oe',
      'Ò': 'O',
      'Ó': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ø': 'O',
      'Œ': 'Oe',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'Ù': 'U',
      'Ú': 'U',
      'Û': 'U',
      'ý': 'y',
      'ÿ': 'y',
      'Ý': 'Y',
      'š': 's',
      'Š': 'S',
      'ž': 'z',
      'Ž': 'Z',
      'ð': 'd',
      'Ð': 'D',
      'þ': 'th',
      'Þ': 'Th',
      'ł': 'l',
      'Ł': 'L',
      'ń': 'n',
      'Ń': 'N',
      'ř': 'r',
      'Ř': 'R',
      'ć': 'c',
      'Ć': 'C',
      'č': 'c',
      'Č': 'C',
      'ě': 'e',
      'Ě': 'E',
      'ď': 'd',
      'Ď': 'D',
      'ť': 't',
      'Ť': 'T',
      'ů': 'u',
      'Ů': 'U',
    };
    var result = name;
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    return result.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
  }

  static Future<String?> getScooterAddress(SavedScooter scooter) async {
    final log = Logger('GeoHelper');

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
      formattedAddress = sanitizeName('$street $streetNumber, $city');
    } else if (street != null && city != null) {
      formattedAddress = sanitizeName('$street, $city');
    } else if (street != null && streetNumber != null) {
      formattedAddress = sanitizeName('$street $streetNumber');
    } else if (street != null) {
      formattedAddress = sanitizeName(street);
    } else if (city != null) {
      formattedAddress = sanitizeName(city);
    } else {
      formattedAddress = null;
    }

    scooter.lastAddress = formattedAddress;
    return formattedAddress;
  }

  static String createNameFromPhotonFeature(PhotonFeature feature) {
    if (feature.name != null && feature.name != feature.street) {
      return sanitizeName(feature.name!);
    } else if (feature.street != null) {
      String street = feature.street!;
      if (feature.houseNumber != null) {
        street += " ${feature.houseNumber!}";
      }
      return sanitizeName(street);
    } else {
      return "${feature.coordinates.latitude}, ${feature.coordinates.longitude}";
    }
  }

  static Future<NavDestination> nameDestination(NavDestination destination) async {
    if (destination.name != null) {
      // this destination already has a name, use that!
      return destination;
    }

    LatLng location = destination.location;

    // see if we already have a name for this destination cached
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    String cacheKey = "address_${location.latitude}_${location.longitude}";
    String? cachedName = await prefs.getString(cacheKey);
    if (cachedName != null) {
      return destination..name = cachedName;
    }

    // see if user hasn't disabled geocoding services
    if (await prefs.getBool("osmConsent") == false) {
      return destination..name = "${location.latitude}, ${location.longitude}";
    }

    // use photon to get a name for this destination
    try {
      PhotonFeature feature = (await photonReverseSearch(location.latitude, location.longitude)).first;
      final named = createNameFromPhotonFeature(feature);
      await prefs.setString(cacheKey, named);
      return destination..name = named;
    } catch (e) {
      return destination..name = "${location.latitude}, ${location.longitude}";
    }
  }
}
