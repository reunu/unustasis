import 'dart:async';

import 'package:scooter_flutter/scooter_flutter.dart' show HashReadException;

// Only fixed reason codes leave the read path. Exception messages may contain
// NFC or Bluetooth payloads and must not be logged or shown verbatim.
String batteryReadFailureReason(Object error) => switch (error) {
      TimeoutException() => 'timeout',
      UnsupportedError() => 'unsupported',
      HashReadException(code: 'redis') => 'hash_redis',
      HashReadException(code: 'busy') => 'hash_busy',
      HashReadException(code: 'session') => 'hash_session',
      HashReadException() => 'hash_protocol',
      FormatException(message: 'Invalid battery presence') => 'presence',
      FormatException(message: 'Missing battery serial') => 'missing_serial',
      FormatException(message: 'Invalid battery serial') => 'invalid_serial',
      FormatException(message: 'Invalid hash notification') => 'hash_frame',
      FormatException(message: 'Invalid hash snapshot header') => 'hash_header',
      FormatException(message: 'Invalid hash snapshot length') => 'hash_length',
      FormatException(message: 'Invalid hash base36 number') => 'hash_number',
      FormatException(message: 'Invalid hash chunk') => 'hash_chunk',
      FormatException(message: 'Invalid hash chunk bytes') => 'hash_chunk_bytes',
      FormatException(message: 'Invalid hash EOF') => 'hash_eof',
      FormatException(message: 'Invalid hash field array') => 'hash_array',
      FormatException(message: 'Invalid hash field value') => 'hash_value',
      FormatException(message: 'Invalid hash error') => 'hash_error',
      FormatException() => 'invalid_data',
      StateError() => 'connection',
      _ => 'unavailable',
    };

String batteryReadFailureMessage(String reason, {required bool nfc}) {
  if (nfc) return 'error';
  return switch (reason) {
    'timeout' => 'error_timeout',
    'connection' || 'hash_session' => 'error_connection',
    'presence' || 'missing_serial' || 'invalid_serial' => 'error_identity',
    'unsupported' => 'ble_unsupported',
    'hash_busy' || 'hash_redis' => 'error_unavailable',
    _ => 'error',
  };
}
