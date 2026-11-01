import 'dart:convert';

const batteryRegistrationConsentVersion = 'battery-registration-v1';

enum BatteryIdentitySource { ble, nfc }

String canonicalBatterySerial(String value) {
  final serial = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').replaceAll(RegExp(r'^ +| +$'), '');
  if (serial.isEmpty ||
      serial.length > 64 ||
      !RegExp(r'^[\x21-\x7e]+$').hasMatch(serial) ||
      !RegExp(r'[1-9a-zA-Z]').hasMatch(serial) ||
      const {'unknown', 'unbekannt', 'n/a', 'na', 'none', 'null', 'nil', 'undefined'}.contains(serial.toLowerCase())) {
    throw const FormatException('Invalid battery serial');
  }
  return RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(serial) ? serial.toUpperCase() : serial;
}

class BatteryIdentity {
  BatteryIdentity({
    required String serialNumber,
    required this.source,
    required this.checkedAt,
    this.slot,
  }) : serialNumber = canonicalBatterySerial(serialNumber);

  final String serialNumber;
  final BatteryIdentitySource source;
  // Time the phone checked the reported identity, not a pack telemetry timestamp.
  final DateTime checkedAt;
  final int? slot;

  Map<String, Object?> toJson() => {
        'serial_number': serialNumber,
        'source': source.name,
        'checked_at': checkedAt.toUtc().toIso8601String(),
        'slot': slot,
      };

  factory BatteryIdentity.fromJson(Map<String, dynamic> json) => BatteryIdentity(
        serialNumber: json['serial_number'] as String,
        source: BatteryIdentitySource.values.byName(json['source'] as String),
        checkedAt: DateTime.parse(json['checked_at'] as String),
        slot: json['slot'] as int?,
      );
}

BatteryIdentity? parseBatteryIdentityFields(List<String?> fields, int slot, DateTime checkedAt) {
  if (slot != 0 && slot != 1) throw ArgumentError.value(slot, 'slot');
  if (fields.length != 2 || (fields[0] != 'true' && fields[0] != 'false')) {
    throw const FormatException('Invalid battery presence');
  }
  if (fields[0] == 'false') return null;
  final serial = fields[1];
  if (serial == null) throw const FormatException('Missing battery serial');
  return BatteryIdentity(
    serialNumber: serial,
    source: BatteryIdentitySource.ble,
    checkedAt: checkedAt,
    slot: slot,
  );
}

/// Type 2 READ at pages 0xc4 and 0xc8 returns status memory at byte
/// addresses 0x0310 and 0x0320, matching the scooter-side battery reader.
String decodeNfcBatterySerial(List<int> status1, List<int> status2) {
  if (status1.length != 16 || status2.length != 16) {
    throw const FormatException('Incomplete battery identity');
  }
  final bytes = [...status1.sublist(4, 16), ...status2.sublist(0, 4)];
  if (bytes.any((value) => value < 0x20 || value > 0x7e)) {
    throw const FormatException('Invalid battery identity bytes');
  }
  return canonicalBatterySerial(ascii.decode(bytes));
}

const batteryTrackerHost = 'sunshine.rescoot.org';

Uri batteryTrackerJoinUri() => Uri.https(batteryTrackerHost, '/battery_tracker/join');
Uri batteryTrackerRegistrationsUri() => Uri.https(batteryTrackerHost, '/battery_tracker/registrations');
