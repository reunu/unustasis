import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../service/photon_service.dart';

final _log = Logger('LocationUrlParser');

class ParsedLocation {
  final LatLng location;
  final String? name;

  const ParsedLocation({required this.location, this.name});
}

class LocationUrlParser {
  // Mobile UA for redirect following (gets 302s from short URL services).
  static const _mobileUA =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // Desktop UA for page fetching (Google returns og:image with coordinates
  // for desktop, but a JS-only "maps lite" page for mobile).
  static const _desktopUA =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Attempts to extract a location from shared text (URL or plain text).
  /// Returns null if no coordinates could be parsed.
  static Future<ParsedLocation?> parse(String text) async {
    text = text.trim();
    _log.fine('Parsing shared text: $text');

    // Extract all URLs and URI-like strings from the text
    final candidates = _extractCandidates(text);
    _log.fine('Extracted ${candidates.length} URL candidates');

    // Try each candidate against all parsers
    for (final candidate in candidates) {
      _log.fine('Trying candidate: $candidate');
      ParsedLocation? result;

      result = _parseGeoUri(candidate);
      if (result != null) return _enrichWithContext(result, text);

      result = _parseGoogleMapsUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      result = _parseAppleMapsUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      result = _parseOsmUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      result = _parseWazeUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      result = _parseHereUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      // Try following short URL redirects (e.g. maps.app.goo.gl)
      result = await _tryResolveShortUrl(candidate);
      if (result != null) return _enrichWithContext(result, text);

      // If it's a Google Maps URL with no coords, fetch the page and scrape
      final candidateUri = Uri.tryParse(candidate);
      if (candidateUri != null && candidateUri.host.contains('google.') && candidateUri.path.contains('/maps/')) {
        result = await _fetchAndScrapeGooglePage(candidate);
        if (result != null) return _enrichWithContext(result, text);
      }
    }

    // Last resort: look for raw coordinate patterns in the full text
    final result = _parseRawCoordinates(text);
    if (result != null) return result;

    // Final fallback: if the text contains a non-URL line (place name/address
    // that maps apps prepend), try geocoding it via Photon.
    final nameQuery = _extractNonUrlText(text);
    if (nameQuery != null) {
      _log.info('All URL parsing failed, trying to geocode text: "$nameQuery"');
      final geocoded = await _geocodeText(nameQuery);
      if (geocoded != null) return geocoded;
    }

    return null;
  }

  /// Extracts URLs and URI-like strings from shared text.
  /// Maps apps typically share "Place Name\nhttps://maps.app.goo.gl/..."
  static List<String> _extractCandidates(String text) {
    final candidates = <String>[];

    // Find all URLs (http, https, geo)
    final urlPattern = RegExp(r'(?:https?://|geo:)\S+', caseSensitive: false);
    for (final match in urlPattern.allMatches(text)) {
      var url = match.group(0)!;
      // Strip trailing punctuation that might be part of surrounding text
      url = url.replaceAll(RegExp(r'[.,;)\]}>]+$'), '');
      candidates.add(url);
    }

    // If no URLs found, try the whole text as a single candidate
    if (candidates.isEmpty) {
      candidates.add(text);
    }

    return candidates;
  }

  /// If the parsed result has no name, try to extract one from the
  /// surrounding text (e.g. the line before the URL).
  static ParsedLocation _enrichWithContext(ParsedLocation result, String fullText) {
    if (result.name != null) return result;

    // Try to use the first non-URL line as the name
    final lines = fullText.split(RegExp(r'[\n\r]+'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('http') || trimmed.startsWith('geo:')) continue;
      // Use this line as the place name
      return ParsedLocation(location: result.location, name: trimmed);
    }
    return result;
  }

  /// geo:lat,lng or geo:lat,lng?q=lat,lng(Label)
  static ParsedLocation? _parseGeoUri(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'geo') return null;

    final path = uri.path; // "lat,lng"
    String? name;

    // Check for ?q=lat,lng(Label) or ?q=Label
    final q = uri.queryParameters['q'];
    if (q != null) {
      final labelMatch = RegExp(r'\((.+)\)').firstMatch(q);
      if (labelMatch != null) {
        name = labelMatch.group(1);
      }
    }

    final coords = _parseCommaSeparatedCoords(path);
    if (coords != null) {
      return ParsedLocation(location: coords, name: name);
    }
    return null;
  }

  /// Google Maps URLs:
  /// - /maps/place/Name/@lat,lng,...
  /// - /maps/@lat,lng,...
  /// - /maps?q=lat,lng
  /// - /maps/search/lat,lng
  /// - data=...!3dlat!4dlng (expanded short URL format)
  /// - center=lat,lng (query parameter)
  static ParsedLocation? _parseGoogleMapsUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    if (!host.contains('google.')) return null;

    final fullUrl = uri.toString();
    String? name;

    // Extract place name from /maps/place/Name/... (with or without @coords)
    final placeNameMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(fullUrl);
    if (placeNameMatch != null) {
      name = _extractGooglePlaceName(placeNameMatch.group(1)!);
    }

    // Try /maps/place/Name/@lat,lng
    final placeMatch = RegExp(r'/maps/place/([^/]+)/@(-?[\d.]+),(-?[\d.]+)').firstMatch(fullUrl);
    if (placeMatch != null) {
      final lat = double.tryParse(placeMatch.group(2)!);
      final lng = double.tryParse(placeMatch.group(3)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng), name: name);
      }
    }

    // Try /maps/@lat,lng
    final atMatch = RegExp(r'/maps/@(-?[\d.]+),(-?[\d.]+)').firstMatch(fullUrl);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng), name: name);
      }
    }

    // Try ?q=lat,lng
    final q = uri.queryParameters['q'];
    if (q != null) {
      final coords = _parseCommaSeparatedCoords(q);
      if (coords != null) return ParsedLocation(location: coords, name: name);
    }

    // Try ?center=lat,lng
    final center = uri.queryParameters['center'];
    if (center != null) {
      final coords = _parseCommaSeparatedCoords(center);
      if (coords != null) return ParsedLocation(location: coords, name: name);
    }

    // Try /maps/search/lat,lng
    final searchMatch = RegExp(r'/maps/search/(-?[\d.]+),(-?[\d.]+)').firstMatch(fullUrl);
    if (searchMatch != null) {
      final lat = double.tryParse(searchMatch.group(1)!);
      final lng = double.tryParse(searchMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng), name: name);
      }
    }

    // Try Google Maps data parameter: !3dlat!4dlng
    final dataMatch = RegExp(r'!3d(-?[\d.]+)!4d(-?[\d.]+)').firstMatch(fullUrl);
    if (dataMatch != null) {
      final lat = double.tryParse(dataMatch.group(1)!);
      final lng = double.tryParse(dataMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng), name: name);
      }
    }

    return null;
  }

  /// Apple Maps: https://maps.apple.com/?ll=lat,lng&q=Name
  static ParsedLocation? _parseAppleMapsUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.host.contains('maps.apple.com')) return null;

    final ll = uri.queryParameters['ll'];
    final name = uri.queryParameters['q'];

    if (ll != null) {
      final coords = _parseCommaSeparatedCoords(ll);
      if (coords != null) return ParsedLocation(location: coords, name: name);
    }

    // Also check for 'sll' (source location) or address
    final sll = uri.queryParameters['sll'];
    if (sll != null) {
      final coords = _parseCommaSeparatedCoords(sll);
      if (coords != null) return ParsedLocation(location: coords, name: name);
    }

    return null;
  }

  /// OpenStreetMap: https://www.openstreetmap.org/#map=zoom/lat/lng
  static ParsedLocation? _parseOsmUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (!uri.host.contains('openstreetmap.org')) return null;

    // Fragment: #map=zoom/lat/lng
    final fragment = uri.fragment;
    final match = RegExp(r'map=\d+/(-?[\d.]+)/(-?[\d.]+)').firstMatch(fragment);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng));
      }
    }

    // Also try ?mlat=...&mlon=... (marker)
    final mlat = uri.queryParameters['mlat'];
    final mlon = uri.queryParameters['mlon'];
    if (mlat != null && mlon != null) {
      final lat = double.tryParse(mlat);
      final lng = double.tryParse(mlon);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng));
      }
    }

    return null;
  }

  /// Waze: https://waze.com/ul?ll=lat,lng
  static ParsedLocation? _parseWazeUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.host.contains('waze.com')) return null;

    final ll = uri.queryParameters['ll'];
    if (ll != null) {
      final coords = _parseCommaSeparatedCoords(ll);
      if (coords != null) return ParsedLocation(location: coords);
    }
    return null;
  }

  /// HERE WeGo: https://share.here.com/l/lat,lng
  static ParsedLocation? _parseHereUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (!uri.host.contains('here.com')) return null;

    final match = RegExp(r'/l/(-?[\d.]+),(-?[\d.]+)').firstMatch(uri.path);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng));
      }
    }
    return null;
  }

  /// Resolve short URLs (maps.app.goo.gl, goo.gl) by following redirects.
  static Future<ParsedLocation?> _tryResolveShortUrl(String text) async {
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;

    final host = uri.host.toLowerCase();
    final isShortUrl = host.contains('goo.gl') ||
        host.contains('bit.ly') ||
        host.contains('t.co') ||
        host.contains('ow.ly') ||
        host.contains('maps.app');

    if (!isShortUrl) return null;

    _log.info('Resolving short URL: $text');

    try {
      // Follow redirects manually to capture intermediate URLs
      var currentUri = uri;
      for (var i = 0; i < 5; i++) {
        final request = http.Request('GET', currentUri)
          ..followRedirects = false
          ..headers['User-Agent'] = _mobileUA
          ..headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
          ..headers['Accept-Language'] = 'en-US,en;q=0.9';
        final client = http.Client();
        try {
          final response = await client.send(request).timeout(const Duration(seconds: 10));
          final location = response.headers['location'];
          _log.info('Redirect $i: ${response.statusCode} → $location');

          if (location == null) {
            // No more redirects — try URL first, then scan response body
            final finalUrl = currentUri.toString();
            final fromUrl = _parseGoogleMapsUrl(finalUrl) ??
                _parseAppleMapsUrl(finalUrl) ??
                _parseOsmUrl(finalUrl) ??
                _parseWazeUrl(finalUrl) ??
                _parseHereUrl(finalUrl) ??
                _parseRawCoordinates(finalUrl);
            if (fromUrl != null) {
              client.close();
              return fromUrl;
            }

            // Read the page body BEFORE closing the client
            final body = await response.stream.bytesToString();
            client.close();

            if (response.statusCode >= 400) {
              _log.info(
                  'Got ${response.statusCode} on hop $i, body preview: ${body.substring(0, body.length < 500 ? body.length : 500)}');
            }

            final fromBody = _scrapeCoordinatesFromHtml(body);
            if (fromBody != null) {
              // Try to extract the place name from the URL
              String? name;
              final placeMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(finalUrl);
              if (placeMatch != null) {
                name = _extractGooglePlaceName(placeMatch.group(1)!);
              }
              return ParsedLocation(location: fromBody, name: name);
            }
            // Don't return here — fall through to the auto-redirect fallback
            break;
          }

          client.close();

          // Try parsing each intermediate redirect URL
          final resolved = _parseGoogleMapsUrl(location) ??
              _parseAppleMapsUrl(location) ??
              _parseOsmUrl(location) ??
              _parseWazeUrl(location) ??
              _parseHereUrl(location) ??
              _parseRawCoordinates(location);
          if (resolved != null) return resolved;

          // If this is a maps URL with no coords in the URL, fetch the page
          // directly and scrape coordinates from the body (avoids consent redirect)
          final locUri = Uri.tryParse(location);
          if (locUri != null && locUri.host.contains('google.') && locUri.path.contains('/maps/')) {
            _log.info('Google Maps URL has no coords in URL, fetching page body');
            final pageResult = await _fetchAndScrapeGooglePage(location);
            if (pageResult != null) return pageResult;
          }

          // Continue following redirects
          final nextUri = Uri.tryParse(location);
          if (nextUri == null) break;
          currentUri = nextUri.hasScheme ? nextUri : currentUri.resolve(location);
        } catch (e) {
          client.close();
          rethrow;
        }
      }

      // Fallback: if manual redirect following didn't yield coordinates,
      // try http.get() which auto-follows all redirects (handles 404 on
      // first hop that some devices see with manual following).
      // Retry up to 2 times: first with original URL, then stripped of query
      // params (Firebase Dynamic Links deprecation can cause flaky 404s).
      final urlsToTry = [
        uri,
        if (uri.hasQuery) uri.replace(query: ''),
      ];
      for (final tryUri in urlsToTry) {
        _log.info('Auto-redirect fallback trying: $tryUri');
        final fallbackResponse = await http.get(tryUri, headers: {
          'User-Agent': _desktopUA,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        }).timeout(const Duration(seconds: 10));

        if (fallbackResponse.statusCode == 200) {
          _log.info('Auto-redirect fallback got 200, body ${fallbackResponse.body.length} chars');

          // Try to extract coordinates from the final page body
          final coords = _scrapeCoordinatesFromHtml(fallbackResponse.body);
          if (coords != null) {
            // Try to extract a place name from the body or URL
            String? name;
            final placeMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(fallbackResponse.body);
            if (placeMatch != null) {
              name = _extractGooglePlaceName(placeMatch.group(1)!);
            }
            return ParsedLocation(location: coords, name: name);
          }
          _log.info(
              'Auto-redirect fallback: no coords in body, preview: ${fallbackResponse.body.substring(0, fallbackResponse.body.length < 500 ? fallbackResponse.body.length : 500)}');
        } else {
          _log.info(
              'Auto-redirect fallback got ${fallbackResponse.statusCode}, body: ${fallbackResponse.body.substring(0, fallbackResponse.body.length < 500 ? fallbackResponse.body.length : 500)}');
        }
      }
    } catch (e) {
      _log.warning('Failed to resolve short URL: $e');
    }
    return null;
  }

  /// Fetch a Google Maps page directly and scrape coordinates from the body.
  /// A direct http.get auto-handles consent redirects and returns a smaller
  /// page that reliably contains og:image/staticmap meta tags with coords.
  /// Falls back to geocoding the place name from the URL if scraping fails
  /// (Google Maps pages with only a place ID don't include destination coords
  /// in the server-rendered HTML).
  static Future<ParsedLocation?> _fetchAndScrapeGooglePage(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': _desktopUA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final coords = _scrapeCoordinatesFromHtml(response.body);
      if (coords != null) {
        String? name;
        final placeMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(url);
        if (placeMatch != null) {
          name = _extractGooglePlaceName(placeMatch.group(1)!);
        }
        return ParsedLocation(location: coords, name: name);
      }

      // Scraping failed — Google Maps pages with only a place ID (/data=)
      // don't include destination coordinates in the HTML (only the viewer's
      // viewport center). Fall back to geocoding the place name from the URL.
      final placeMatch = RegExp(r'/maps/place/([^/@?]+)').firstMatch(url);
      if (placeMatch != null) {
        final rawSegment = Uri.decodeComponent(placeMatch.group(1)!).replaceAll('+', ' ');
        final shortName = _extractGooglePlaceName(placeMatch.group(1)!);
        _log.info('Scraping found no coords, geocoding place name from URL: "$rawSegment"');
        final geocoded = await _geocodeText(rawSegment);
        if (geocoded != null) {
          return ParsedLocation(location: geocoded.location, name: shortName);
        }
      }
    } catch (e) {
      _log.warning('Failed to fetch Google Maps page: $e');
    }
    return null;
  }

  /// Scrape lat/lng from a Google Maps HTML page body.
  /// Google embeds coordinates in several places: meta tags, JS data, etc.
  static LatLng? _scrapeCoordinatesFromHtml(String body) {
    // 1. Look for /@lat,lng pattern (canonical URL in meta or body)
    final atPattern = RegExp(r'/@(-?\d{1,3}\.\d{3,8}),(-?\d{1,3}\.\d{3,8})');
    final atMatch = atPattern.firstMatch(body);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        _log.info('Found coordinates from @pattern in page body');
        return LatLng(lat, lng);
      }
    }

    // 2. Look for !3dlat!4dlng (Google Maps data parameter in body)
    final dataPattern = RegExp(r'!3d(-?\d{1,3}\.\d{3,8})!4d(-?\d{1,3}\.\d{3,8})');
    final dataMatch = dataPattern.firstMatch(body);
    if (dataMatch != null) {
      final lat = double.tryParse(dataMatch.group(1)!);
      final lng = double.tryParse(dataMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        _log.info('Found coordinates from !3d/!4d pattern in page body');
        return LatLng(lat, lng);
      }
    }

    // 4. Look for [null,null,lat,lng] pattern (protobuf-style in JS)
    final protoPattern = RegExp(r'\[null,null,(-?\d{1,3}\.\d{4,8}),(-?\d{1,3}\.\d{4,8})\]');
    final protoMatch = protoPattern.firstMatch(body);
    if (protoMatch != null) {
      final lat = double.tryParse(protoMatch.group(1)!);
      final lng = double.tryParse(protoMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        _log.info('Found coordinates from proto pattern in page body');
        return LatLng(lat, lng);
      }
    }

    // 5. Look for markers= in staticmap/og:image URLs (the marker IS the place;
    //    center= is the viewport center which can be the user's location).
    final markersPattern = RegExp(r'markers=[^"&]*?(-?\d{1,3}\.\d{3,8})%2C(-?\d{1,3}\.\d{3,8})');
    final markersMatch = markersPattern.firstMatch(body);
    if (markersMatch != null) {
      final lat = double.tryParse(markersMatch.group(1)!);
      final lng = double.tryParse(markersMatch.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        _log.info('Found coordinates from staticmap markers parameter');
        return LatLng(lat, lng);
      }
    }

    // NOTE: Patterns for center= (og:image) and [number,lng,lat] JS arrays
    // were removed because they return the VIEWER's IP-based location, not the
    // destination's coordinates, on Google Maps pages with only a place ID
    // (/data=!...!1s0x...) and no @lat,lng in the URL.

    _log.info('No coordinates found in page body (${body.length} chars)');
    return null;
  }

  /// Last resort: find "lat, lng" coordinate patterns in the text.
  static ParsedLocation? _parseRawCoordinates(String text) {
    // Match patterns like "52.5200, 13.4050" or "52.5200,13.4050"
    final match = RegExp(r'(-?\d{1,3}\.\d{3,8})\s*[,\s]\s*(-?\d{1,3}\.\d{3,8})').firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
        return ParsedLocation(location: LatLng(lat, lng));
      }
    }
    return null;
  }

  // --- Helpers ---

  /// Decode a Google Maps /place/Name/ URL segment into a short place name.
  /// Google encodes names like "Gustav+Café+%26+Bar+-+Stuttgart,+Schwabstraße+47,+70197+Stuttgart".
  /// This extracts just the meaningful part (e.g. "Gustav Café & Bar").
  static String _extractGooglePlaceName(String raw) {
    var name = Uri.decodeComponent(raw).replaceAll('+', ' ');
    // Strip city/address suffix after " - " (Google format: "Name - City, Address")
    final dashIndex = name.indexOf(' - ');
    if (dashIndex > 0) name = name.substring(0, dashIndex);
    // Strip address parts after first comma
    final commaIndex = name.indexOf(',');
    if (commaIndex > 0) name = name.substring(0, commaIndex);
    return name.trim();
  }

  static LatLng? _parseCommaSeparatedCoords(String s) {
    final parts = s.split(',');
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    if (!_isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  /// Extract non-URL text lines from shared text (e.g. place name that maps
  /// apps prepend before the URL). Returns null if no such text found.
  static String? _extractNonUrlText(String text) {
    final lines = text.split(RegExp(r'[\n\r]+'));
    final parts = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('http') || trimmed.startsWith('geo:')) continue;
      parts.add(trimmed);
    }
    final joined = parts.join(', ').trim();
    return joined.isNotEmpty ? joined : null;
  }

  /// Try to geocode a text query (place name or address) via Photon.
  static Future<ParsedLocation?> _geocodeText(String query) async {
    try {
      final results = await photonForwardSearch(query, limit: 1);
      if (results.isNotEmpty) {
        final feature = results.first;
        _log.info('Geocoded "$query" → ${feature.coordinates.latitude}, ${feature.coordinates.longitude}');
        return ParsedLocation(
          location: LatLng(feature.coordinates.latitude.toDouble(), feature.coordinates.longitude.toDouble()),
          name: feature.name ?? query,
        );
      }
      _log.info('Geocoding "$query" returned no results');
    } catch (e) {
      _log.warning('Geocoding failed for "$query": $e');
    }
    return null;
  }
}
