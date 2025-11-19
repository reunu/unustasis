import 'dart:convert';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_type.dart';

class SavedScooter {
  ScooterType _type;
  String _name;
  String _id;
  int _color;
  DateTime _lastPing;
  bool _autoConnect;
  int? _lastPrimarySOC;
  int? _lastSecondarySOC;
  int? _lastCbbSOC;
  int? _lastAuxSOC;
  LatLng? _lastLocation;
  bool? _handlebarsLocked;

  SavedScooter({
    required String id,
    ScooterType? type,
    String? name,
    int? color,
    DateTime? lastPing,
    bool? autoConnect,
    int? lastPrimarySOC,
    int? lastSecondarySOC,
    int? lastCbbSOC,
    int? lastAuxSOC,
    LatLng? lastLocation,
    bool? handlebarsLocked,
  })  : _type = type ?? ScooterType.unuPro,
        _name = name ?? "Scooter Pro",
        _id = id,
        _color = color ?? 1,
        _lastPing = lastPing ?? DateTime.now(),
        _autoConnect = autoConnect ?? true,
        _lastPrimarySOC = lastPrimarySOC,
        _lastSecondarySOC = lastSecondarySOC,
        _lastCbbSOC = lastCbbSOC,
        _lastAuxSOC = lastAuxSOC,
        _lastLocation = lastLocation,
        _handlebarsLocked = handlebarsLocked;

  set type(ScooterType type) {
    _type = type;
    updateSharedPreferences();
  }

  set name(String name) {
    _name = name;
    updateSharedPreferences();
  }

  set color(int color) {
    _color = color;
    updateSharedPreferences();
  }

  set lastPing(DateTime lastPing) {
    _lastPing = lastPing;
    updateSharedPreferences();
  }

  set autoConnect(bool autoConnect) {
    _autoConnect = autoConnect;
    updateSharedPreferences();
    FlutterBackgroundService().invoke("update", {"updateSavedScooters": true});
  }

  set lastPrimarySOC(int? lastPrimarySOC) {
    _lastPrimarySOC = lastPrimarySOC;
    updateSharedPreferences();
  }

  set lastSecondarySOC(int? lastSecondarySOC) {
    _lastSecondarySOC = lastSecondarySOC;
    updateSharedPreferences();
  }

  set lastCbbSOC(int? lastCbbSOC) {
    _lastCbbSOC = lastCbbSOC;
    updateSharedPreferences();
  }

  set lastAuxSOC(int? lastAuxSOC) {
    _lastAuxSOC = lastAuxSOC;
    updateSharedPreferences();
  }

  set lastLocation(LatLng? lastLocation) {
    _lastLocation = lastLocation;
    updateSharedPreferences();
  }

  set handlebarsLocked(bool? handlebarsLocked) {
    _handlebarsLocked = handlebarsLocked;
    updateSharedPreferences();
  }

  String get id => _id;
  ScooterType get type => _type;
  String get name => _name;
  int get color => _color;
  DateTime get lastPing => _lastPing;
  bool get autoConnect => _autoConnect;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;
  bool? get handlebarsLocked => _handlebarsLocked;

  BluetoothDevice get bluetoothDevice => BluetoothDevice.fromId(_id);

  Map<String, dynamic> toJson() => {
        'id': _id,
        'type': _type.name,
        'name': _name,
        'color': _color,
        'lastPing': _lastPing.microsecondsSinceEpoch,
        'autoConnect': _autoConnect,
        'lastPrimarySOC': _lastPrimarySOC,
        'lastSecondarySOC': _lastSecondarySOC,
        'lastCbbSOC': _lastCbbSOC,
        'lastAuxSOC': _lastAuxSOC,
        'lastLocation': _lastLocation?.toJson(),
        'handlebarsLocked': _handlebarsLocked,
      };

  factory SavedScooter.fromJson(
    String id,
    Map<String, dynamic> map,
  ) {
    return SavedScooter(
      id: id,
      type: ScooterType.values.byName(map['type']),
      name: map['name'],
      color: map['color'],
      lastPing: map.containsKey('lastPing') ? DateTime.fromMicrosecondsSinceEpoch(map['lastPing']) : DateTime.now(),
      autoConnect: map['autoConnect'],
      lastLocation: map['lastLocation'] != null ? LatLng.fromJson(map['lastLocation']) : null,
      lastPrimarySOC: map['lastPrimarySOC'],
      lastSecondarySOC: map['lastSecondarySOC'],
      lastCbbSOC: map['lastCbbSOC'],
      lastAuxSOC: map['lastAuxSOC'],
      handlebarsLocked: map['handlebarsLocked'],
    );
  }

  bool get dataIsOld {
    return _lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
  }

  void updateSharedPreferences() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    Map<String, dynamic> savedScooters =
        jsonDecode(await prefs.getString("savedScooters") ?? "{}") as Map<String, dynamic>;
    savedScooters[_id] = toJson();
    await prefs.setString("savedScooters", jsonEncode(savedScooters));
  }
}
