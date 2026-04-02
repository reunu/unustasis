import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../domain/scooter_battery.dart';
import '../infrastructure/utils.dart';

final _log = Logger('ScooterSubscriptions');

// -- Parsing helpers --

String _bytesToString(List<int> value) {
  var withoutZeros = value.where((element) => element != 0).toList();
  return ascii.decode(withoutZeros).trim();
}

int? _bytesToUint32(List<int> data) {
  if (data.length != 4) return null;
  return (data[3] << 24) + (data[2] << 16) + (data[1] << 8) + data[0];
}

// -- String-based subscriptions --

/// Subscribes to a BLE characteristic that sends ASCII string values.
/// Calls [onChanged] with the decoded string whenever the value updates.
void subscribeToStringValue(
  BluetoothCharacteristic characteristic,
  String label,
  void Function(String value) onChanged,
) {
  subscribeCharacteristic(characteristic, (data) {
    String value = _bytesToString(data);
    _log.info("$label received: $value");
    onChanged(value);
  });
}

// -- Integer-based subscriptions --

/// Subscribes to a BLE characteristic that sends an integer value.
/// If [singleByte] is true, reads only the first byte; otherwise parses as uint32.
void subscribeToIntValue(
  BluetoothCharacteristic characteristic,
  String label,
  void Function(int value) onChanged, {
  bool singleByte = false,
}) {
  subscribeCharacteristic(characteristic, (data) {
    int? value;
    if (singleByte && data.isNotEmpty) {
      value = data[0];
    } else {
      value = _bytesToUint32(data);
    }
    if (value != null) {
      _log.info("$label received: $value");
      onChanged(value);
    }
  });
}

// -- Battery charging subscriptions --

/// Subscribes to a CBB charging characteristic.
/// Calls [onChanged] with true for "charging", false for "not-charging".
void subscribeToCbbCharging(
  BluetoothCharacteristic characteristic,
  void Function(bool charging) onChanged,
) {
  subscribeToStringValue(characteristic, "CBB charging", (value) {
    if (value == "charging") {
      onChanged(true);
    } else if (value == "not-charging") {
      onChanged(false);
    }
  });
}

/// Subscribes to an AUX charging characteristic.
/// Calls [onChanged] with the parsed [AUXChargingState].
void subscribeToAuxCharging(
  BluetoothCharacteristic characteristic,
  void Function(AUXChargingState charging) onChanged,
) {
  subscribeToStringValue(characteristic, "AUX charging", (value) {
    switch (value) {
      case "float-charge":
        onChanged(AUXChargingState.floatCharge);
      case "absorption-charge":
        onChanged(AUXChargingState.absorptionCharge);
      case "bulk-charge":
        onChanged(AUXChargingState.bulkCharge);
      case "not-charging":
        onChanged(AUXChargingState.none);
    }
  });
}

// -- NRF version (read-once) --

/// Reads the nRF firmware version once from the characteristic.
/// Calls [onRead] with the version string and whether it's a librescoot build.
Future<void> readNrfVersion(
  BluetoothCharacteristic characteristic,
  void Function(String version, bool isLibrescoot) onRead,
) async {
  try {
    List<int> value = await characteristic.read();
    String version = _bytesToString(value);
    _log.info("nRF version received: $version");
    onRead(version, version.contains("-ls"));
  } catch (e, stack) {
    _log.warning("Failed to read nRF version", e, stack);
  }
}
