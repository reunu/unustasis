import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedScooter {
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

  SavedScooter({
    required String name,
    required String id,
    int? color,
    DateTime? lastPing,
    bool? autoConnect,
    int? lastPrimarySOC,
    int? lastSecondarySOC,
    int? lastCbbSOC,
    int? lastAuxSOC,
    LatLng? lastLocation,
  })  : _name = name,
        _id = id,
        _color = color ?? 1,
        _lastPing = lastPing ?? DateTime.now(),
        _autoConnect = autoConnect ?? true,
        _lastPrimarySOC = lastPrimarySOC,
        _lastSecondarySOC = lastSecondarySOC,
        _lastCbbSOC = lastCbbSOC,
        _lastAuxSOC = lastAuxSOC,
        _lastLocation = lastLocation;

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

  String get name => _name;
  String get id => _id;
  int get color => _color;
  DateTime get lastPing => _lastPing;
  bool get autoConnect => _autoConnect;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;

  Map<String, dynamic> toJson() => {
        'id': _id,
        'name': _name,
        'color': _color,
        'lastPing': _lastPing.microsecondsSinceEpoch,
        'autoConnect': _autoConnect,
        'lastPrimarySOC': _lastPrimarySOC,
        'lastSecondarySOC': _lastSecondarySOC,
        'lastCbbSOC': _lastCbbSOC,
        'lastAuxSOC': _lastAuxSOC,
        'lastLocation': _lastLocation?.toJson(),
      };

  factory SavedScooter.fromJson(
    String id,
    Map<String, dynamic> map,
  ) {
    return SavedScooter(
        id: id,
        name: map['name'],
        color: map['color'],
        lastPing: map.containsKey('lastPing')
            ? DateTime.fromMicrosecondsSinceEpoch(map['lastPing'])
            : DateTime.now(),
        autoConnect: map['autoConnect'],
        lastLocation: map['lastLocation'] != null
            ? LatLng.fromJson(map['lastLocation'])
            : null,
        lastPrimarySOC: map['lastPrimarySOC'],
        lastSecondarySOC: map['lastSecondarySOC'],
        lastCbbSOC: map['lastCbbSOC'],
        lastAuxSOC: map['lastAuxSOC']);
  }

  void updateSharedPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> savedScooters =
        jsonDecode(prefs.getString("savedScooters")!) as Map<String, dynamic>;
    savedScooters[_id] = toJson();
    prefs.setString("savedScooters", jsonEncode(savedScooters));
  }
}
