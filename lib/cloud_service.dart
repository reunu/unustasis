import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import 'scooter_service.dart';

class CloudService {
  final log = Logger('CloudService');
  final storage = const FlutterSecureStorage();
  final String baseUrl = 'https://sunshine.rescoot.org/api/v1';
  final ScooterService scooterService;
  String? _token;
  List<Map<String, dynamic>>? _cachedScooters;

  // Singleton pattern
  static CloudService? _instance;
  factory CloudService(ScooterService scooterService) {
    _instance ??= CloudService._internal(scooterService);
    return _instance!;
  }
  CloudService._internal(this.scooterService);

  Future<void> init() async {
    _token = await storage.read(key: 'sunshine_token');
    if (_token != null) {
      try {
        // refresh scooters if needed
        await getScooters();
      } catch (e, stack) {
        log.warning('Failed to get scooters during init', e, stack);
        // Token might be invalid, clear it
        await logout();
      }
    }
  }

  Future<bool> get isAuthenticated async {
    await init();
    return _token != null && _cachedScooters != null;
  }

  Future<void> setToken(String token) async {
    _token = token;
    await storage.write(key: 'sunshine_token', value: token);
    // Validate token by refreshing scooters
    await _refreshScooters();
  }

  Future<void> logout() async {
    _token = null;
    _cachedScooters = null;
    await storage.delete(key: 'sunshine_token');
  }

  Future<List<Map<String, dynamic>>> getScooters() async {
    if (_cachedScooters == null) {
      await _refreshScooters();
    }
    return _cachedScooters ?? [];
  }

  Future<void> _refreshScooters() async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await _authenticatedRequest('/scooters');

    if (response is! List) {
      throw Exception('Expected List response but got ${response.runtimeType}');
    }

    _cachedScooters = List<Map<String, dynamic>>.from(response);
    log.info('Successfully cached ${_cachedScooters!.length} scooters');
  }

  Future<Map<String, int>> getCurrentAssignments() async {
    Map<String, int> assignments = {};

    for (var savedScooter in scooterService.savedScooters.values) {
      if (savedScooter.cloudScooterId != null) {
        assignments[savedScooter.id] = savedScooter.cloudScooterId!;
      }
    }

    return assignments;
  }

  Future<void> assignScooter({required String bleId, required int cloudId}) async {
    // Get the saved scooter object
    final savedScooter = scooterService.savedScooters[bleId];
    if (savedScooter == null) {
      throw Exception('Local scooter not found');
    }

    // Sync name and color
    final cloudScooter = (await getScooters()).firstWhere(
      (s) => s['id'] == cloudId,
      orElse: () => throw Exception('Cloud scooter not found'),
    );

    // Update local scooter if it has default values
    if (savedScooter.name == "Scooter Pro" && savedScooter.color == 1) {
      savedScooter.name = cloudScooter['name'];
      savedScooter.color = cloudScooter['color_id'] ?? 1;
    }

    // Get any existing assignment for this cloud scooter
    final assignments = await getCurrentAssignments();
    final existingAssignment =
        assignments.entries.firstWhere((entry) => entry.value == cloudId, orElse: () => MapEntry('', -1));

    if (existingAssignment.key.isNotEmpty) {
      // Remove the old assignment
      await removeAssignment(existingAssignment.key);
    }

    // Format device ID appropriately
    final deviceId = Platform.isAndroid
        ? bleId.toLowerCase().replaceAllMapped(
            RegExp(r'([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})'),
            (match) => '${match[1]}:${match[2]}:${match[3]}:${match[4]}:${match[5]}:${match[6]}')
        : bleId;

    // Update API and local data
    final Map<String, dynamic> deviceIds = {};
    if (Platform.isAndroid) {
      deviceIds['android'] = deviceId;
    } else if (Platform.isIOS) {
      deviceIds['ios'] = deviceId;
    }

    await _authenticatedRequest(
      '/scooters/$cloudId',
      method: 'PATCH',
      body: {
        'device_ids': deviceIds,
      },
    );

    // Update local saved scooter
    savedScooter.cloudScooterId = cloudId;
  }

  Future<void> removeAssignment(String bleId) async {
    final savedScooter = scooterService.savedScooters[bleId];
    if (savedScooter == null) {
      throw Exception('Local scooter not found');
    }

    final cloudId = savedScooter.cloudScooterId;
    if (cloudId != null) {
      final Map<String, dynamic> deviceIds = {};
      if (Platform.isAndroid) {
        deviceIds['android'] = null;
      } else if (Platform.isIOS) {
        deviceIds['ios'] = null;
      }

      await _authenticatedRequest(
        '/scooters/$cloudId',
        method: 'PUT',
        body: {
          'device_ids': deviceIds,
        },
      );

      // Clear local assignment
      savedScooter.cloudScooterId = null;
    }
  }

  Future<dynamic> _authenticatedRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (_token == null) {
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
        case 'PATCH':
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

  Future<bool> _executeCommand(String endpoint, int scooterId,
      {String method = 'POST', Map<String, dynamic>? body, String? logName // Optional custom name for logging
      }) async {
    final commandName = logName ?? endpoint.replaceAll('/', ' ').trim();
    log.info("Attempting $commandName for scooter $scooterId");

    try {
      final response = await _authenticatedRequest('/scooters/$scooterId/$endpoint', method: method, body: body);
      return response != null;
    } catch (e, stack) {
      log.severe('$commandName failed', e, stack);
      return false;
    }
  }

  Future<bool> lock(int scooterId) async {
    return _executeCommand('lock', scooterId);
  }

  Future<bool> unlock(int scooterId) async {
    return _executeCommand('unlock', scooterId);
  }

  Future<bool> openSeatbox(int scooterId) async {
    return _executeCommand('open_seatbox', scooterId);
  }

  Future<bool> blinkers(int scooterId, String state) async {
    return _executeCommand('blinkers', scooterId, body: {'state': state}, logName: 'blinkers $state');
  }

  Future<bool> honk(int scooterId) async {
    return _executeCommand('honk', scooterId);
  }

  Future<bool> locate(int scooterId) async {
    return _executeCommand('locate', scooterId);
  }

  Future<bool> alarm(int scooterId) async {
    return _executeCommand('alarm', scooterId);
  }

  Future<bool> ping(int scooterId) async {
    return _executeCommand('ping', scooterId);
  }

  Future<bool> getState(int scooterId) async {
    return _executeCommand('get_state', scooterId);
  }
}
