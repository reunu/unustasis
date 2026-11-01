import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart' show HashReadException;
import 'package:unustasis/service/battery_read_failure.dart';

void main() {
  test('failure diagnostics contain fixed reasons, never serials or payloads', () {
    final cases = <Object, String>{
      TimeoutException('private serial'): 'timeout',
      UnsupportedError('private serial'): 'unsupported',
      const HashReadException('redis'): 'hash_redis',
      const HashReadException('busy'): 'hash_busy',
      const HashReadException('session'): 'hash_session',
      const HashReadException('private serial'): 'hash_protocol',
      const FormatException('Invalid battery presence'): 'presence',
      const FormatException('Missing battery serial'): 'missing_serial',
      const FormatException('Invalid battery serial'): 'invalid_serial',
      const FormatException('Invalid hash notification'): 'hash_frame',
      const FormatException('Invalid hash snapshot header'): 'hash_header',
      const FormatException('Invalid hash snapshot length'): 'hash_length',
      const FormatException('Invalid hash base36 number'): 'hash_number',
      const FormatException('Invalid hash chunk'): 'hash_chunk',
      const FormatException('Invalid hash chunk bytes'): 'hash_chunk_bytes',
      const FormatException('Invalid hash EOF'): 'hash_eof',
      const FormatException('Invalid hash field array'): 'hash_array',
      const FormatException('Invalid hash field value'): 'hash_value',
      const FormatException('Invalid hash error'): 'hash_error',
      const FormatException('private serial'): 'invalid_data',
      StateError('private serial'): 'connection',
      PlatformException(code: 'private serial', message: 'private serial'): 'unavailable',
    };
    for (final entry in cases.entries) {
      expect(batteryReadFailureReason(entry.key), entry.value);
      expect(batteryReadFailureReason(entry.key), isNot(contains('private serial')));
    }
  });
  test('BLE recovery hints distinguish connection, timeout and reported data', () {
    expect(batteryReadFailureMessage('timeout', nfc: false), 'error_timeout');
    expect(batteryReadFailureMessage('connection', nfc: false), 'error_connection');
    expect(batteryReadFailureMessage('hash_session', nfc: false), 'error_connection');
    expect(batteryReadFailureMessage('presence', nfc: false), 'error_identity');
    expect(batteryReadFailureMessage('missing_serial', nfc: false), 'error_identity');
    expect(batteryReadFailureMessage('invalid_serial', nfc: false), 'error_identity');
    expect(batteryReadFailureMessage('unsupported', nfc: false), 'ble_unsupported');
    expect(batteryReadFailureMessage('hash_redis', nfc: false), 'error_unavailable');
    expect(batteryReadFailureMessage('hash_busy', nfc: false), 'error_unavailable');
    expect(batteryReadFailureMessage('invalid_data', nfc: false), 'error');
    expect(batteryReadFailureMessage('connection', nfc: true), 'error');
  });
}
