import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:scooter_core/trip_expunge.dart';

import 'characteristic_repository.dart';
import 'firmware_queries.dart';

const lsKeyTripExpunge = 'trip.expunge';

/// Reads the atomic trip-history retention setting through the generic setting
/// transport. A null value means firmware does not expose this setting.
Future<TripExpunge?> getTripExpungePolicySetting(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
}) async {
  final value = await getLsSettingCommand(scooter, repo, lsKeyTripExpunge,
      isCurrent: isCurrent);
  return value == null ? null : TripExpunge.parse(value);
}

/// Writes one complete retention setting through the generic setting transport.
Future<void> setTripExpungePolicySetting(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  TripExpunge policy, {
  bool Function()? isCurrent,
}) =>
    setLsSettingCommand(scooter, repo, lsKeyTripExpunge, policy.wireValue,
        isCurrent: isCurrent);
