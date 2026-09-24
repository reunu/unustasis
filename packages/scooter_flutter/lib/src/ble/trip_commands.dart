import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:scooter_core/actions.dart' show extendedCommandMaxBytes;
import 'package:scooter_core/trip_counter.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';
import 'firmware_queries.dart' show getLsSettingCommand, setLsSettingCommand;

/// The service may spend up to 15 seconds completing a reset. Do not release
/// the response listener before it has sent the terminal acknowledgement.
const tripResetResponseTimeout = Duration(seconds: 20);

enum TripResetFailure { busy, invalid, unavailable, internal, timeout }

class TripCounterUnavailableException implements Exception {
  const TripCounterUnavailableException();

  @override
  String toString() => 'Trip counter is unavailable';
}

class TripResetException implements Exception {
  const TripResetException(this.failure);
  final TripResetFailure failure;
  @override
  String toString() => 'Trip reset failed: ${failure.name}';
}

void _checkLength(String command) {
  if (utf8.encode(command).length > extendedCommandMaxBytes) {
    throw ArgumentError.value(command, 'command',
        'Trip command exceeds $extendedCommandMaxBytes bytes');
  }
}

/// Reads the currently active trip counter. Malformed scooter data is rejected
/// rather than being shown as a zero-distance trip.
Future<TripCounterSnapshot?> getTripCounterCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
}) async {
  const command = 'trip:get';
  _checkLength(command);
  final response =
      await sendLsExtendedCommand(scooter, repo, command, isCurrent: isCurrent);
  if (response == null) {
    throw TimeoutException('Trip counter request timed out');
  }
  checkCommandCurrent(isCurrent);
  if (response == 'trip:data:error:unavailable') {
    throw const TripCounterUnavailableException();
  }
  return TripCounterSnapshot.parse(response);
}

/// Resets only the scooter's current aggregate trip counter.
Future<void> resetTripCounterCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
  Duration responseTimeout = tripResetResponseTimeout,
}) async {
  const command = 'trip:reset';
  _checkLength(command);
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    command,
    isCurrent: isCurrent,
    responseTimeout: responseTimeout,
  );
  checkCommandCurrent(isCurrent);
  if (response == null) {
    throw const TripResetException(TripResetFailure.timeout);
  }
  const prefix = 'trip:reset:error:';
  if (response != 'trip:reset:ok') {
    final code =
        response.startsWith(prefix) ? response.substring(prefix.length) : null;
    TripResetFailure? failure;
    for (final candidate in TripResetFailure.values) {
      if (candidate.name == code) failure = candidate;
    }
    if (failure != null) throw TripResetException(failure);
    throw StateError('Trip reset failed: $response');
  }
}

Future<TripResetPolicy?> getTripCounterResetPolicyCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
}) async {
  final value = await getLsSettingCommand(scooter, repo, 'trip.counter-reset',
      isCurrent: isCurrent);
  if (value == null) return null;
  final policy = TripResetPolicyWire.parse(value);
  if (policy == null) {
    throw FormatException('Unknown trip reset policy: $value');
  }
  return policy;
}

Future<void> setTripCounterResetPolicyCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  TripResetPolicy policy, {
  bool Function()? isCurrent,
}) async {
  final command = 'set:trip.counter-reset:${policy.wireName}';
  _checkLength(command);
  await setLsSettingCommand(
      scooter, repo, 'trip.counter-reset', policy.wireName,
      isCurrent: isCurrent);
  checkCommandCurrent(isCurrent);
}
