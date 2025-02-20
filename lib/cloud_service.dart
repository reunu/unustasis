import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../scooter_service.dart';

class CloudService {
  final log = Logger('CloudService');
  final storage = const FlutterSecureStorage();
  final String baseUrl = 'https://sunshine.rescoot.org/api/v1';
  String? _token;

  // Singleton pattern
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  Future<void> init() async {
    _token = await storage.read(key: 'sunshine_token');
  }

  Future<bool> get isAuthenticated async {
    await init();
    if (_token == null) {
      log.info('No token found in storage');
      return false;
    }

    try {
      log.info('Validating token by fetching scooters...');
      // Test the token by making a simple API call
      final scooters = await getScooters();
      log.info('Successfully fetched ${scooters.length} scooters');
      return true;
    } catch (e, stack) {
      log.severe('Token validation failed', e, stack);
      // If the token is invalid, clear it
      // await logout();
      return false;
    }
  }

  Future<String?> findCloudScooterForBleId(BuildContext context) async {
    final scooter = context.read<ScooterService>().myScooter;
    if (scooter == null) {
      log.info('No scooter connected');
      return null;
    }

    final bleMAC = scooter.deviceId.toString().toLowerCase().replaceAllMapped(
        RegExp(
            r'([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})'),
        (match) =>
            '${match[1]}:${match[2]}:${match[3]}:${match[4]}:${match[5]}:${match[6]}');

    log.info('Looking for cloud scooter matching BLE MAC: $bleMAC');

    final scooters = await getScooters();

    log.info('Comparing against cloud scooters:');
    for (final scooter in scooters) {
      final cloudMac = scooter['ble_mac']?.toString();
      log.info(
          '  - Cloud scooter "${scooter['name']}" (ID: ${scooter['id']}) has BLE MAC: "$cloudMac"');

      if (cloudMac != null && cloudMac.isNotEmpty && bleMAC == cloudMac) {
        log.info('Found matching cloud scooter with ID: ${scooter['id']}');
        return scooter['id'].toString();
      }
    }

    log.info('No matching cloud scooter found for BLE MAC: $bleMAC');
    return null;
  }

  Future<void> setToken(String token) async {
    _token = token;
    await storage.write(key: 'sunshine_token', value: token);
  }

  Future<void> logout() async {
    _token = null;
    await storage.delete(key: 'sunshine_token');
  }

  Future<dynamic> _authenticatedRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (_token == null) {
      log.warning('Attempted API request without token');
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };

    log.info('Making $method request to $path');
    log.fine('Headers: $headers');

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw Exception('Unsupported HTTP method');
      }
    } catch (e, stack) {
      log.severe('HTTP request failed', e, stack);
      rethrow;
    }

    log.fine('Response status: ${response.statusCode}');
    log.fine('Response body: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return jsonDecode(response.body);
      } catch (e, stack) {
        log.severe('Failed to decode JSON response', e, stack);
        throw Exception('Invalid JSON response: ${e.toString()}');
      }
    } else {
      final body = response.body;
      log.warning(
          'API request failed with status ${response.statusCode}: $body');
      throw Exception('API request failed (${response.statusCode}): $body');
    }
  }

  // API Methods
  Future<List<Map<String, dynamic>>> getScooters() async {
    log.info('Fetching scooter list...');
    final dynamic response = await _authenticatedRequest('/scooters');
    log.fine('Response type: ${response.runtimeType}');

    try {
      if (response is! List) {
        throw Exception(
            'Expected List response but got ${response.runtimeType}');
      }

      final List<Map<String, dynamic>> scooters =
          List<Map<String, dynamic>>.from(response);
      log.info('Successfully fetched ${scooters.length} scooters');
      return scooters;
    } catch (e, stack) {
      log.severe('Failed to parse scooters list', e, stack);
      rethrow;
    }
  }

  Future<dynamic> createScooter({
    required String name,
    required String bleMac,
    String? color,
  }) async {
    return _authenticatedRequest(
      '/scooters',
      method: 'POST',
      body: {
        'name': name,
        'ble_mac': bleMac,
        if (color != null) 'color': color,
      },
    );
  }

  Future<void> lockScooter(String scooterId) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/lock',
      method: 'POST',
    );
  }

  Future<void> unlockScooter(String scooterId) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/unlock',
      method: 'POST',
    );
  }
}
