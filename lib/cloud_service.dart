import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'scooter_service.dart';

class CloudService {
  static const String _baseUrl = 'https://api.sunray.rescoot.org';
  static const String _oauthUrl = 'https://sunray.rescoot.org/oauth';
  static const String _clientId = 'unustasis-mobile';
  static const String _redirectUri = 'unustasis://oauth/callback';

  final ScooterService scooterService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final log = Logger('CloudService');

  CloudService(this.scooterService);

  // OAuth Authentication
  Future<void> initiateOAuth() async {
    final state = DateTime.now().millisecondsSinceEpoch.toString();
    await _secureStorage.write(key: 'oauth_state', value: state);

    final authUrl = Uri.parse('$_oauthUrl/authorize').replace(queryParameters: {
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'state': state,
      'scope': 'scooter:read scooter:control',
    });

    try {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      log.severe('Failed to launch OAuth URL: $authUrl', e);
      throw Exception('Could not launch OAuth URL: $e');
    }
  }

  Future<bool> handleOAuthCallback(Uri callbackUri) async {
    try {
      final code = callbackUri.queryParameters['code'];
      final state = callbackUri.queryParameters['state'];
      final storedState = await _secureStorage.read(key: 'oauth_state');

      if (code == null || state != storedState) {
        throw Exception('Invalid OAuth callback');
      }

      await _exchangeCodeForTokens(code);
      await _secureStorage.delete(key: 'oauth_state');
      return true;
    } catch (e, stack) {
      log.severe('OAuth callback failed', e, stack);
      return false;
    }
  }

  Future<void> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse('$_oauthUrl/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'redirect_uri': _redirectUri,
      },
    );

    if (response.statusCode == 200) {
      final tokenData = jsonDecode(response.body);
      await _secureStorage.write(key: 'access_token', value: tokenData['access_token']);
      await _secureStorage.write(key: 'refresh_token', value: tokenData['refresh_token']);
      
      final expiresIn = tokenData['expires_in'] as int;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await _secureStorage.write(key: 'token_expires_at', value: expiresAt.toIso8601String());
    } else {
      throw Exception('Failed to exchange code for tokens: ${response.body}');
    }
  }

  Future<String?> _getValidAccessToken() async {
    final accessToken = await _secureStorage.read(key: 'access_token');
    final expiresAtStr = await _secureStorage.read(key: 'token_expires_at');
    
    if (accessToken == null || expiresAtStr == null) {
      return null;
    }

    final expiresAt = DateTime.parse(expiresAtStr);
    if (DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)))) {
      // Token is expired or expires soon, try to refresh
      return await _refreshAccessToken();
    }

    return accessToken;
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = await _secureStorage.read(key: 'refresh_token');
    if (refreshToken == null) {
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_oauthUrl/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': _clientId,
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);
        await _secureStorage.write(key: 'access_token', value: tokenData['access_token']);
        
        if (tokenData['refresh_token'] != null) {
          await _secureStorage.write(key: 'refresh_token', value: tokenData['refresh_token']);
        }
        
        final expiresIn = tokenData['expires_in'] as int;
        final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
        await _secureStorage.write(key: 'token_expires_at', value: expiresAt.toIso8601String());
        
        return tokenData['access_token'];
      } else {
        log.warning('Token refresh failed: ${response.body}');
        await logout();
        return null;
      }
    } catch (e, stack) {
      log.severe('Token refresh error', e, stack);
      return null;
    }
  }

  Future<bool> get isAuthenticated async {
    final token = await _getValidAccessToken();
    return token != null;
  }

  Future<void> logout() async {
    await _secureStorage.deleteAll();
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _getValidAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // Cloud Scooter Management
  Future<List<Map<String, dynamic>>> getScooters() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/scooters'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['scooters'] ?? []);
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else {
        throw Exception('Failed to fetch scooters: ${response.body}');
      }
    } catch (e, stack) {
      log.severe('Failed to get cloud scooters', e, stack);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getScooter(int scooterId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/scooters/$scooterId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to fetch scooter: ${response.body}');
      }
    } catch (e, stack) {
      log.severe('Failed to get cloud scooter $scooterId', e, stack);
      rethrow;
    }
  }

  // Cloud Commands
  Future<bool> sendCommand(int scooterId, String command, {Map<String, dynamic>? parameters}) async {
    try {
      final headers = await _getAuthHeaders();
      final body = {
        'command': command,
        if (parameters != null) 'parameters': parameters,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/v1/scooters/$scooterId/commands'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        log.info('Cloud command $command sent successfully to scooter $scooterId');
        return true;
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else {
        log.warning('Cloud command failed: ${response.body}');
        return false;
      }
    } catch (e, stack) {
      log.severe('Failed to send cloud command $command to scooter $scooterId', e, stack);
      return false;
    }
  }

  // Scooter Assignment Management
  Future<void> assignScooterToDevice(int cloudScooterId, String deviceId) async {
    final scooter = scooterService.savedScooters[deviceId];
    if (scooter != null) {
      scooter.cloudScooterId = cloudScooterId;
      scooter.updateSharedPreferences();
    }
  }

  Future<void> unassignScooterFromDevice(String deviceId) async {
    final scooter = scooterService.savedScooters[deviceId];
    if (scooter != null) {
      scooter.cloudScooterId = null;
      scooter.updateSharedPreferences();
    }
  }

  Future<int?> getAssignedCloudScooterId(String deviceId) async {
    final scooter = scooterService.savedScooters[deviceId];
    return scooter?.cloudScooterId;
  }

  // Check if cloud service is available
  Future<bool> isServiceAvailable() async {
    if (!await isAuthenticated) {
      return false;
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/health'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Open cloud dashboard in browser
  Future<void> openCloudDashboard() async {
    final dashboardUrl = Uri.parse('https://sunray.rescoot.org/dashboard');
    if (await canLaunchUrl(dashboardUrl)) {
      await launchUrl(dashboardUrl, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch dashboard URL');
    }
  }
}