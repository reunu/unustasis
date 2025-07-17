import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'scooter_service.dart';

/// Cloud service for Sunshine scooter management with OAuth 2.0 + PKCE authentication
/// 
/// OAuth Client ID Configuration:
/// - Default: Uses hardcoded client ID for development
/// - Environment: Set OAUTH_CLIENT_ID environment variable
/// - Build time: flutter build apk --dart-define=OAUTH_CLIENT_ID=your_client_id
/// - Local development: Add oauth.clientId=your_client_id to local.properties
///
/// Security: Client secret has been removed and PKCE is used for secure authentication
class CloudService {
  static const String _baseUrl = 'https://sunshine.rescoot.org/api/v1';
  static const String _oauthUrl = 'https://sunshine.rescoot.org/oauth';
  static const String _clientId = String.fromEnvironment(
    'OAUTH_CLIENT_ID',
    defaultValue: 'Q20PF36dOaO1FDw0NEzkP1jNtPT12w_onMuwr5nS5I0',
  );
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
  Future<String?>? _refreshInProgress;

  CloudService(this.scooterService);

  /// Generates a cryptographically secure random string for PKCE code verifier
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Creates SHA256 code challenge from code verifier for PKCE
  String _createCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // OAuth Authentication with PKCE
  Future<void> initiateOAuth() async {
    final state = DateTime.now().millisecondsSinceEpoch.toString();
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _createCodeChallenge(codeVerifier);
    
    await _secureStorage.write(key: 'oauth_state', value: state);
    await _secureStorage.write(key: 'oauth_code_verifier', value: codeVerifier);

    final authUrl = Uri.parse('$_oauthUrl/authorize').replace(queryParameters: {
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'state': state,
      'scope': 'read write scooter_control',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
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
      await _secureStorage.delete(key: 'oauth_code_verifier');
      return true;
    } catch (e, stack) {
      log.severe('OAuth callback failed', e, stack);
      return false;
    }
  }

  Future<void> _exchangeCodeForTokens(String code) async {
    final codeVerifier = await _secureStorage.read(key: 'oauth_code_verifier');
    if (codeVerifier == null) {
      throw Exception('Missing PKCE code verifier');
    }

    final response = await http.post(
      Uri.parse('$_oauthUrl/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
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
    
    log.fine('Access token exists: ${accessToken != null}');
    log.fine('Expires at: $expiresAtStr');
    
    if (accessToken == null || expiresAtStr == null) {
      log.warning('Missing access token or expiry time');
      return null;
    }

    final expiresAt = DateTime.parse(expiresAtStr);
    final now = DateTime.now();
    log.fine('Token expires at: $expiresAt, now: $now');
    
    if (now.isAfter(expiresAt.subtract(const Duration(minutes: 5)))) {
      // Token is expired or expires soon, try to refresh
      log.info('Token expired or expires soon, refreshing...');
      
      // Check if refresh is already in progress
      if (_refreshInProgress != null) {
        log.info('Refresh already in progress, waiting for result...');
        return await _refreshInProgress!;
      }
      
      // Start refresh and store the future
      _refreshInProgress = _refreshAccessToken();
      final result = await _refreshInProgress!;
      _refreshInProgress = null;
      return result;
    }

    log.fine('Token is valid');
    return accessToken;
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = await _secureStorage.read(key: 'refresh_token');
    if (refreshToken == null) {
      log.warning('No refresh token available');
      return null;
    }

    try {
      log.info('Starting token refresh...');
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
        
        log.info('Token refresh successful');
        return tokenData['access_token'];
      } else {
        log.warning('Token refresh failed with status ${response.statusCode}: ${response.body}');
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
    _refreshInProgress = null;
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
      log.info('Getting cloud scooters from $_baseUrl/scooters');
      final headers = await _getAuthHeaders();
      log.info('Auth headers prepared: ${headers.keys}');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/scooters'),
        headers: headers,
      );

      log.info('Response status: ${response.statusCode}');
      log.info('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final scooters = List<Map<String, dynamic>>.from(data ?? []);
        log.info('Found ${scooters.length} cloud scooters');
        return scooters;
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else {
        throw Exception('Failed to fetch scooters: ${response.statusCode} ${response.body}');
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
        Uri.parse('$_baseUrl/scooters/$scooterId'),
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

  Future<bool> updateScooter(int scooterId, {String? name, String? color, String? customColor}) async {
    try {
      final headers = await _getAuthHeaders();
      final scooterData = <String, dynamic>{};
      
      if (name != null) scooterData['name'] = name;
      if (color != null) scooterData['color'] = color;
      if (customColor != null) scooterData['custom_color'] = customColor;
      
      if (scooterData.isEmpty) {
        log.warning('No data provided for scooter update');
        return false;
      }

      final body = {'scooter': scooterData};

      final response = await http.patch(
        Uri.parse('$_baseUrl/scooters/$scooterId'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        log.info('Cloud scooter $scooterId updated successfully');
        return true;
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else {
        log.warning('Failed to update cloud scooter $scooterId: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e, stack) {
      log.severe('Failed to update cloud scooter $scooterId', e, stack);
      return false;
    }
  }

  /// Check if a specific scooter is online in the cloud
  Future<bool> isScooterOnline(int scooterId) async {
    try {
      final scooterData = await getScooter(scooterId);
      if (scooterData == null) {
        return false;
      }
      
      // Check if the scooter has an 'online' field or determine based on last_seen
      if (scooterData.containsKey('online')) {
        return scooterData['online'] == true;
      }
      
      // If no explicit online field, check if last_seen is recent (within 5 minutes)
      if (scooterData.containsKey('last_seen') && scooterData['last_seen'] != null) {
        final lastSeen = DateTime.parse(scooterData['last_seen']);
        final now = DateTime.now();
        final difference = now.difference(lastSeen);
        return difference.inMinutes <= 5;
      }
      
      // If no online status info is available, assume offline
      return false;
    } catch (e, stack) {
      log.warning('Failed to check online status for scooter $scooterId', e, stack);
      return false;
    }
  }

  // Cloud Commands
  Future<bool> sendCommand(int scooterId, String command, {Map<String, dynamic>? parameters}) async {
    try {
      final headers = await _getAuthHeaders();
      
      // Build request body based on command type
      final body = <String, dynamic>{};
      if (parameters != null) {
        body.addAll(parameters);
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/scooters/$scooterId/$command'),
        headers: headers,
        body: body.isNotEmpty ? jsonEncode(body) : null,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['status'] == 'success') {
          log.info('Cloud command $command sent successfully to scooter $scooterId');
          return true;
        } else {
          log.warning('Cloud command failed: ${responseData['message']}');
          return false;
        }
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      } else if (response.statusCode == 422) {
        final responseData = jsonDecode(response.body);
        log.warning('Cloud command failed: ${responseData['message']}');
        return false;
      } else {
        log.warning('Cloud command failed with status ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e, stack) {
      log.severe('Failed to send cloud command $command to scooter $scooterId', e, stack);
      return false;
    }
  }

  // Scooter Assignment Management
  Future<void> assignScooterToDevice(int cloudScooterId, String deviceId, {String? cloudScooterName}) async {
    final scooter = scooterService.savedScooters[deviceId];
    if (scooter != null) {
      scooter.cloudScooterId = cloudScooterId;
      if (cloudScooterName != null) {
        scooter.cloudScooterName = cloudScooterName;
      }
      scooter.updateSharedPreferences();
    }
  }

  Future<void> unassignScooterFromDevice(String deviceId) async {
    final scooter = scooterService.savedScooters[deviceId];
    if (scooter != null) {
      scooter.cloudScooterId = null;
      scooter.cloudScooterName = null;
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
      // Use the scooters endpoint to check service availability
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/scooters'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Open cloud dashboard in browser
  Future<void> openCloudDashboard() async {
    final dashboardUrl = Uri.parse('https://sunshine.rescoot.org/dashboard');
    if (await canLaunchUrl(dashboardUrl)) {
      await launchUrl(dashboardUrl, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch dashboard URL');
    }
  }
}