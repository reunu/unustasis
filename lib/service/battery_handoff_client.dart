import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:scooter_core/battery_identity.dart';

class BatteryHandoff {
  const BatteryHandoff({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;
}

enum BatteryHandoffFailure { unavailable, rateLimited, invalidResponse, cancelled }

class BatteryHandoffException implements Exception {
  const BatteryHandoffException(this.reason, {this.statusCode});

  final BatteryHandoffFailure reason;
  final int? statusCode;

  @override
  String toString() => 'Battery handoff failed: ${reason.name}';
}

class _PendingClaim {
  const _PendingClaim(this.battery, this.challenge, this.expiresAt);

  final BatteryIdentity battery;
  final String challenge;
  final DateTime expiresAt;
}

class BatteryHandoffClient {
  BatteryHandoffClient({http.Client Function()? clientFactory, this.timeout = const Duration(seconds: 30)})
      : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  final Duration timeout;
  http.Client? _active;
  _PendingClaim? _pending;

  void cancel() {
    final client = _active;
    _active = null;
    _pending = null;
    client?.close();
  }

  Future<BatteryHandoff> prepare(BatteryIdentity battery) async {
    if (_active != null) throw const BatteryHandoffException(BatteryHandoffFailure.unavailable);
    final client = _active = _clientFactory();
    try {
      return await _prepare(client, battery).timeout(timeout);
    } on BatteryHandoffException {
      rethrow;
    } catch (_) {
      // HTTP and decoding errors may contain the request URL or response data.
      throw const BatteryHandoffException(BatteryHandoffFailure.unavailable);
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }
  }

  void _checkActive(http.Client client) {
    if (!identical(_active, client)) throw const BatteryHandoffException(BatteryHandoffFailure.cancelled);
  }

  Future<BatteryHandoff> _prepare(http.Client client, BatteryIdentity battery) async {
    var pending = _pending;
    if (pending == null ||
        pending.battery.serialNumber != battery.serialNumber ||
        pending.battery.source != battery.source ||
        !pending.expiresAt.isAfter(DateTime.now())) {
      final challenge = await _post(client, '/api/v1/battery_tracker/challenges', {});
      pending = _PendingClaim(battery, _token(challenge['challenge']), _expiry(challenge));
      _checkActive(client);
      _pending = pending;
    }
    try {
      // Keep the nonce after an ambiguous POST failure so a deliberate retry
      // recovers the same immutable claim instead of creating another one.
      final claim = await _post(
          client,
          '/api/v1/battery_tracker/claims',
          {
            'challenge': pending.challenge,
            'serial_number': battery.serialNumber,
            'source': battery.source.name,
          },
          allowExisting: true);
      final code = _token(claim['code']);
      final handoff = BatteryHandoff(
        uri: Uri.https(batteryTrackerHost, '/battery_tracker/handoff').replace(fragment: 'code=$code'),
        expiresAt: _expiry(claim),
      );
      if (identical(_pending, pending)) _pending = null;
      return handoff;
    } on BatteryHandoffException catch (error) {
      if ({400, 404, 409, 410, 413, 415, 422}.contains(error.statusCode) && identical(_pending, pending)) {
        _pending = null;
      }
      rethrow;
    }
  }

  String _token(Object? value) {
    if (value is! String || value.length != 43 || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
      throw const BatteryHandoffException(BatteryHandoffFailure.invalidResponse);
    }
    return value;
  }

  DateTime _expiry(Map<String, dynamic> data) {
    final raw = data['expires_at'];
    final expiry = raw is String ? DateTime.tryParse(raw) : null;
    final now = DateTime.now();
    if (expiry == null || !expiry.isAfter(now) || expiry.isAfter(now.add(const Duration(minutes: 15)))) {
      throw const BatteryHandoffException(BatteryHandoffFailure.invalidResponse);
    }
    return expiry;
  }

  Future<Map<String, dynamic>> _post(http.Client client, String path, Map<String, dynamic> body,
      {bool allowExisting = false}) async {
    _checkActive(client);
    final request = http.Request('POST', Uri.https(batteryTrackerHost, path))
      ..followRedirects = false
      ..headers.addAll({'accept': 'application/json', 'content-type': 'application/json'})
      ..body = jsonEncode(body);
    final response = await client.send(request);
    _checkActive(client);
    if (response.statusCode == 429) {
      throw const BatteryHandoffException(BatteryHandoffFailure.rateLimited, statusCode: 429);
    }
    if (response.statusCode != 201 && !(allowExisting && response.statusCode == 200)) {
      throw BatteryHandoffException(BatteryHandoffFailure.unavailable, statusCode: response.statusCode);
    }
    if ((response.contentLength ?? 0) > 4096 ||
        response.headers['content-type']?.split(';').first.trim().toLowerCase() != 'application/json') {
      throw const BatteryHandoffException(BatteryHandoffFailure.invalidResponse);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      _checkActive(client);
      if (bytes.length + chunk.length > 4096) {
        throw const BatteryHandoffException(BatteryHandoffFailure.invalidResponse);
      }
      bytes.addAll(chunk);
    }
    _checkActive(client);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) throw const BatteryHandoffException(BatteryHandoffFailure.invalidResponse);
    return decoded;
  }
}
