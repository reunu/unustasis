import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// A scooter the user could connect to, plus how we came to know about it.
///
/// Discovery has three sources and they do not overlap the way you would
/// expect. A BLE peripheral stops advertising while it has a connection, so a
/// scooter the phone has already bonded and silently reconnected is invisible
/// to a scan for as long as that link is up. Those only ever turn up through
/// the bonded and system-connected lists.
class ScooterCandidate {
  ScooterCandidate({
    required this.device,
    this.name,
    this.rssi,
    this.bonded = false,
    this.systemConnected = false,
    this.saved = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final BluetoothDevice device;

  /// Advertised or cached name, if the platform gave us one.
  final String? name;

  /// Signal strength of the most recent advertisement. Null when we have never
  /// heard this one advertise, which is normal for an already-connected scooter.
  final int? rssi;

  /// Paired with this phone at the OS level (Android bond).
  final bool bonded;

  /// Holds a GATT link to this phone right now, opened by us or by anything else.
  final bool systemConnected;

  /// Already in the app's list of saved scooters.
  final bool saved;

  final DateTime lastSeen;

  String get id => device.remoteId.toString();

  static final RegExp _macAddress = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  /// Android hands out the peripheral's MAC as its remote ID. iOS hands out an
  /// opaque per-app UUID that means nothing outside this install, so it should
  /// never be presented as if it were a hardware address.
  bool get idIsMacAddress => _macAddress.hasMatch(id);

  /// One-line label for the entry: the MAC where we have one, otherwise the
  /// tail of the identifier, which is enough to tell two entries apart.
  String get addressLabel {
    if (idIsMacAddress) return id.toUpperCase();
    if (id.length <= 8) return id;
    return "...${id.substring(id.length - 8)}";
  }

  /// Coarse signal strength, 0 to 4, for a bar indicator. Null when we have no
  /// RSSI to go on.
  int? get signalBars {
    final int? value = rssi;
    if (value == null || value == 0) return null;
    if (value >= -60) return 4;
    if (value >= -70) return 3;
    if (value >= -80) return 2;
    if (value >= -90) return 1;
    return 0;
  }

  /// Folds a fresh sighting into what we already knew about this scooter.
  /// Flags only ever go from false to true within a discovery run, so an entry
  /// that started as a scan result keeps its bond marker once we learn about it.
  ScooterCandidate mergedWith(ScooterCandidate other) {
    return ScooterCandidate(
      device: device,
      name: other.name ?? name,
      rssi: other.rssi ?? rssi,
      bonded: bonded || other.bonded,
      systemConnected: systemConnected || other.systemConnected,
      saved: saved || other.saved,
      lastSeen: other.lastSeen.isAfter(lastSeen) ? other.lastSeen : lastSeen,
    );
  }

  /// Scooters the phone has no bond with come first, since adding one of those
  /// is the point of this screen. Then whatever the phone is already talking
  /// to, then the back catalogue of old bonds, which gets long on a phone that
  /// has been paired with a lot of scooters over the years.
  int get _rank {
    if (!bonded && !systemConnected) return 0;
    if (systemConnected) return 1;
    return 2;
  }

  static List<ScooterCandidate> sorted(Iterable<ScooterCandidate> candidates) {
    final List<ScooterCandidate> list = candidates.toList();
    list.sort((a, b) {
      if (a._rank != b._rank) return a._rank.compareTo(b._rank);
      if (a.rssi != null && b.rssi != null && a.rssi != b.rssi) {
        return b.rssi!.compareTo(a.rssi!);
      }
      return a.id.compareTo(b.id);
    });
    return list;
  }

  @override
  String toString() {
    return "ScooterCandidate($id, name: $name, rssi: $rssi, bonded: $bonded, "
        "systemConnected: $systemConnected, saved: $saved)";
  }
}
