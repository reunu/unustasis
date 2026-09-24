import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scooter_core/scooter_core.dart';

final _log = Logger('ScooterStorage');

class ScooterStorage<T extends SavedScooterRecord> {
  final SharedPreferencesAsync _prefs;
  final T Function(String, Map<String, dynamic>) decode;
  final T Function({required String id, String? name, int? color, DateTime? lastPing}) create;
  final String defaultName;

  ScooterStorage({
    required this.decode,
    required this.create,
    required this.defaultName,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync();

  Map<String, T> scooters = {};

  Future<void> load() async {
    _log.info("Fetching saved scooters from SharedPreferences");
    Map<String, T> loaded = {};
    try {
      final saved = await _prefs.getString("savedScooters");
      if (saved == null) {
        _log.info("No saved scooters found");
        return;
      }
      Map<String, dynamic> data = jsonDecode(saved) as Map<String, dynamic>;
      _log.info("Found ${data.length} saved scooters");
      for (String id in data.keys) {
        if (data[id] is Map<String, dynamic>) {
          loaded[id] = decode(id, data[id]);
        }
      }
      _log.info("Successfully fetched saved scooters: $loaded");
    } catch (e, stack) {
      _log.severe("Error fetching saved scooters", e, stack);
    }
    scooters = loaded;
  }

  Future<void> save() async {
    await _prefs.setString("savedScooters", jsonEncode(scooters));
  }

  Map<String, T> filterAutoConnect(
    Map<String, T> input,
  ) {
    if (input.length == 1) {
      return Map.from(input);
    }
    Map<String, T> filtered = Map.from(input);
    filtered.removeWhere((key, value) => !value.autoConnect);
    return filtered;
  }

  T? getMostRecent() {
    _log.info("Getting most recent scooter from savedScooters");
    if (scooters.isEmpty) {
      _log.info("No saved scooters found, returning null");
      return null;
    }
    if (scooters.length == 1) {
      _log.info("Only one saved scooter found, returning it one way or another");
      if (scooters.values.first.autoConnect == false) {
        _log.info(
          "we'll reenable autoconnect for this scooter, since it's the only one available",
        );
        scooters.values.first.autoConnect = true;
      }
      return scooters.values.first;
    }

    List<T> autoConnectScooters = filterAutoConnect(scooters).values.toList();
    T? mostRecentScooter;
    for (var scooter in autoConnectScooters) {
      if (mostRecentScooter == null || scooter.lastPing.isAfter(mostRecentScooter.lastPing)) {
        mostRecentScooter = scooter;
      }
    }
    _log.info("Most recent scooter: $mostRecentScooter");
    return mostRecentScooter;
  }

  Future<List<String>> getIds({bool onlyAutoConnect = false}) async {
    if (scooters.isNotEmpty) {
      _log.info("Getting ids of already fetched scooters");
      if (onlyAutoConnect) {
        return filterAutoConnect(scooters).keys.toList();
      }
      return scooters.keys.toList();
    }
    // nothing saved locally yet, check prefs
    _log.info("No saved scooters, checking SharedPreferences");
    if (await _prefs.containsKey("savedScooters")) {
      _log.info("Found saved scooters in SharedPreferences, fetching...");
      await load();
      if (onlyAutoConnect) {
        return filterAutoConnect(scooters).keys.toList();
      }
      return scooters.keys.toList();
    }
    _log.info(
      "No saved scooters found in SharedPreferences, returning empty list",
    );
    return [];
  }

  /// Adds a new scooter if it doesn't already exist.
  /// Returns true if a new scooter was added, false if it already existed.
  Future<bool> add(String id) async {
    if (scooters.containsKey(id)) {
      return false;
    }
    scooters[id] = create(
      name: defaultName,
      id: id,
      color: 0,
      lastPing: DateTime.now(),
    );
    await save();
    return true;
  }

  Future<void> remove(String id) async {
    scooters.remove(id);
    await save();
  }

  Future<void> rename(String id, String name) async {
    if (scooters[id] == null) {
      scooters[id] = create(name: name, id: id);
    } else {
      scooters[id]!.name = name;
    }
    await save();
  }

  Future<void> recolor(String id, int color) async {
    if (scooters[id] == null) {
      scooters[id] = create(color: color, id: id);
    } else {
      scooters[id]!.color = color;
    }
  }

  void updatePing(String id) {
    if (scooters.containsKey(id)) {
      scooters[id]!.lastPing = DateTime.now();
    }
  }
}
