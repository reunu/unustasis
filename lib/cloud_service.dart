import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

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
      return false;
    }
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
    if (body != null) {
      log.fine('Body: $body');
    }

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
          throw Exception('Unsupported HTTP method: $method');
      }
    } catch (e, stack) {
      log.severe('HTTP request failed', e, stack);
      rethrow;
    }

    log.fine('Response status: ${response.statusCode}');
    log.fine('Response body: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(response.body);
      } catch (e, stack) {
        log.severe('Failed to decode JSON response', e, stack);
        throw Exception('Invalid JSON response: ${e.toString()}');
      }
    } else {
      final body = response.body;
      log.warning('API request failed with status ${response.statusCode}: $body');
      throw Exception('API request failed (${response.statusCode}): $body');
    }
  }

  // API Methods
  Future<List<Map<String, dynamic>>> getScooters() async {
    log.info('Fetching scooter list...');
    final response = await _authenticatedRequest('/scooters');
    
    try {
      if (response is! List) {
        throw Exception('Expected List response but got ${response.runtimeType}');
      }

      final List<Map<String, dynamic>> scooters = List<Map<String, dynamic>>.from(response);
      log.info('Successfully fetched ${scooters.length} scooters');
      return scooters;
    } catch (e, stack) {
      log.severe('Failed to parse scooters list', e, stack);
      rethrow;
    }
  }

  Future<Map<String, int>> getCurrentAssignments() async {
    final scooters = await getScooters();
    Map<String, int> assignments = {};
    
    for (var scooter in scooters) {
      final deviceIds = scooter['device_ids'] as Map<String, dynamic>?;
      if (deviceIds != null) {
        if (Platform.isAndroid && deviceIds['android'] != null) {
          assignments[deviceIds['android']] = scooter['id'] as int;
        } else if (Platform.isIOS && deviceIds['ios'] != null) {
          assignments[deviceIds['ios']] = scooter['id'] as int;
        }
      }
    }
    
    return assignments;
  }

  Future<void> assignScooter({required String bleId, required int cloudId}) async {
    // Format MAC address or keep UUID as is depending on platform
    final deviceId = Platform.isAndroid ? bleId.toLowerCase().replaceAllMapped(
      RegExp(r'([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})'),
      (match) => '${match[1]}:${match[2]}:${match[3]}:${match[4]}:${match[5]}:${match[6]}'
    ) : bleId;

    // Get current device_ids to preserve other platform assignments
    final scooters = await getScooters();
    final scooter = scooters.firstWhere((s) => s['id'] == cloudId);
    Map<String, dynamic> deviceIds = Map<String, dynamic>.from(scooter['device_ids'] ?? {});
    
    // Update the appropriate platform ID
    if (Platform.isAndroid) {
      deviceIds['android'] = deviceId;
    } else if (Platform.isIOS) {
      deviceIds['ios'] = deviceId;
    }

    await _authenticatedRequest(
      '/scooters/$cloudId',
      method: 'PUT',
      body: {
        'device_ids': deviceIds,
      },
    );
  }

  Future<void> removeAssignment(String bleId) async {
    final assignments = await getCurrentAssignments();
    final cloudId = assignments[bleId];
    
    if (cloudId != null) {
      // Get current device_ids to preserve other platform assignments
      final scooters = await getScooters();
      final scooter = scooters.firstWhere((s) => s['id'] == cloudId);
      Map<String, dynamic> deviceIds = Map<String, dynamic>.from(scooter['device_ids'] ?? {});

      // Remove the appropriate platform ID
      if (Platform.isAndroid) {
        deviceIds.remove('android');
      } else if (Platform.isIOS) {
        deviceIds.remove('ios');
      }

      await _authenticatedRequest(
        '/scooters/$cloudId',
        method: 'PUT',
        body: {
          'device_ids': deviceIds,
        },
      );
    }
  }

  // Command endpoints
  Future<void> lockScooter(int scooterId) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/lock',
      method: 'POST',
    );
  }

  Future<void> unlockScooter(int scooterId) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/unlock',
      method: 'POST',
    );
  }

  Future<void> blinkScooter(int scooterId, String state) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/blinkers',
      method: 'POST',
      body: {
        'state': state,
      },
    );
  }

  Future<void> honkScooter(int scooterId) async {
    await _authenticatedRequest(
      '/scooters/$scooterId/honk',
      method: 'POST',
    );
  }
}