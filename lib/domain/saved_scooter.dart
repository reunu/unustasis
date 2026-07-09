import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'color_utils.dart';
import 'nav_destination.dart';

class SavedScooter {
  String _name;
  String _id;
  int _color;
  String? _colorHex;
  Map<String, String>? _cloudImages;
  DateTime _lastPing;
  bool _autoConnect;
  int? _lastPrimarySOC;
  int? _lastSecondarySOC;
  int? _lastCbbSOC;
  int? _lastAuxSOC;
  LatLng? _lastLocation;
  String? _lastAddress;
  bool? _handlebarsLocked;
  bool? _isLibrescoot;
  List<NavDestination>? _cachedDestinations;
  int? _cloudScooterId;
  String? _cloudScooterName;

  SavedScooter({
    required String id,
    String? name,
    int? color,
    String? colorHex,
    Map<String, String>? cloudImages,
    DateTime? lastPing,
    bool? autoConnect,
    int? lastPrimarySOC,
    int? lastSecondarySOC,
    int? lastCbbSOC,
    int? lastAuxSOC,
    LatLng? lastLocation,
    String? lastAddress,
    bool? handlebarsLocked,
    bool? isLibrescoot,
    List<NavDestination>? cachedDestinations,
    int? cloudScooterId,
    String? cloudScooterName,
  })  : _name = name ?? "Scooter Pro",
        _id = id,
        _color = color ?? 1,
        _colorHex = colorHex,
        _cloudImages = cloudImages,
        _lastPing = lastPing ?? DateTime.now(),
        _autoConnect = autoConnect ?? true,
        _lastPrimarySOC = lastPrimarySOC,
        _lastSecondarySOC = lastSecondarySOC,
        _lastCbbSOC = lastCbbSOC,
        _lastAuxSOC = lastAuxSOC,
        _lastLocation = lastLocation,
        _lastAddress = lastAddress,
        _handlebarsLocked = handlebarsLocked,
        _isLibrescoot = isLibrescoot,
        _cachedDestinations = cachedDestinations,
        _cloudScooterId = cloudScooterId,
        _cloudScooterName = cloudScooterName;

  set name(String name) {
    _name = name;
    updateSharedPreferences();
  }

  set color(int color) {
    _color = color;
    _colorHex = null; // predefined color replaces any custom hex color
    updateSharedPreferences();
  }

  set colorHex(String? colorHex) {
    _colorHex = colorHex;
    updateSharedPreferences();
  }

  set cloudImages(Map<String, String>? cloudImages) {
    _cloudImages = cloudImages;
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
    _lastAddress = null;
    updateSharedPreferences();
  }

  set lastAddress(String? lastAddress) {
    _lastAddress = lastAddress;
    updateSharedPreferences();
  }

  set handlebarsLocked(bool? handlebarsLocked) {
    _handlebarsLocked = handlebarsLocked;
    updateSharedPreferences();
  }

  set isLibrescoot(bool? isLibrescoot) {
    _isLibrescoot = isLibrescoot;
    updateSharedPreferences();
  }

  set cachedDestinations(List<NavDestination>? cachedDestinations) {
    _cachedDestinations = cachedDestinations;
    updateSharedPreferences();
  }

  set cloudScooterId(int? cloudScooterId) {
    _cloudScooterId = cloudScooterId;
    updateSharedPreferences();
  }

  set cloudScooterName(String? cloudScooterName) {
    _cloudScooterName = cloudScooterName;
    updateSharedPreferences();
  }

  String get name => _name;
  String get id => _id;
  int get color => _color;
  String? get colorHex => _colorHex;
  Map<String, String>? get cloudImages => _cloudImages;

  /// Front view image URL, for the main scooter display.
  String? get cloudImageFront => _cloudImages?['front'];

  /// Side view image URL, for info lists.
  String? get cloudImageSide => _cloudImages?['right'] ?? _cloudImages?['side'];

  /// Any available cloud image URL, in order of preference.
  String? get cloudImageUrl => _cloudImages?['front'] ?? _cloudImages?['right'] ?? _cloudImages?['left'];
  DateTime get lastPing => _lastPing;
  bool get autoConnect => _autoConnect;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;
  String? get lastAddress => _lastAddress;
  bool? get handlebarsLocked => _handlebarsLocked;
  bool? get isLibrescoot => _isLibrescoot;
  List<NavDestination>? get cachedDestinations => _cachedDestinations;
  int? get cloudScooterId => _cloudScooterId;
  String? get cloudScooterName => _cloudScooterName;

  /// Whether this scooter uses a custom hex color (set from the cloud) instead of a predefined one.
  bool get hasCustomColor => _colorHex != null;

  /// The hex color to display: the custom one if set, otherwise the predefined color's hex.
  String get effectiveColorHex => _colorHex ?? '#${ColorUtils.colorToHex(ColorUtils.getColorValue(_color))}';

  /// The Flutter Color to display: the custom hex color if set, otherwise the predefined color.
  Color get effectiveColor =>
      (_colorHex != null ? ColorUtils.parseHexColor(_colorHex) : null) ?? ColorUtils.getColorValue(_color);

  BluetoothDevice get bluetoothDevice => BluetoothDevice.fromId(_id);

  Map<String, dynamic> toJson() => {
        'id': _id,
        'name': _name,
        'color': _color,
        'colorHex': _colorHex,
        'cloudImages': _cloudImages,
        'lastPing': _lastPing.microsecondsSinceEpoch,
        'autoConnect': _autoConnect,
        'lastPrimarySOC': _lastPrimarySOC,
        'lastSecondarySOC': _lastSecondarySOC,
        'lastCbbSOC': _lastCbbSOC,
        'lastAuxSOC': _lastAuxSOC,
        'lastLocation': _lastLocation?.toJson(),
        'lastAddress': _lastAddress,
        'handlebarsLocked': _handlebarsLocked,
        'isLibrescoot': _isLibrescoot,
        'cachedDestinations': _cachedDestinations?.map((d) => d.toJson()).toList(),
        'cloudScooterId': _cloudScooterId,
        'cloudScooterName': _cloudScooterName,
      };

  factory SavedScooter.fromJson(
    String id,
    Map<String, dynamic> map,
  ) {
    return SavedScooter(
      id: id,
      name: map['name'],
      color: map['color'],
      colorHex: map['colorHex'],
      cloudImages: map['cloudImages'] != null ? Map<String, String>.from(map['cloudImages']) : null,
      lastPing: map.containsKey('lastPing') ? DateTime.fromMicrosecondsSinceEpoch(map['lastPing']) : DateTime.now(),
      autoConnect: map['autoConnect'],
      lastLocation: map['lastLocation'] != null ? LatLng.fromJson(map['lastLocation']) : null,
      lastAddress: map['lastAddress'],
      lastPrimarySOC: map['lastPrimarySOC'],
      lastSecondarySOC: map['lastSecondarySOC'],
      lastCbbSOC: map['lastCbbSOC'],
      lastAuxSOC: map['lastAuxSOC'],
      handlebarsLocked: map['handlebarsLocked'],
      isLibrescoot: map['isLibrescoot'],
      cachedDestinations: (map['cachedDestinations'] as List<dynamic>?)
          ?.map((e) => NavDestination.fromJson(e as Map<String, dynamic>))
          .toList(),
      cloudScooterId: map['cloudScooterId'],
      cloudScooterName: map['cloudScooterName'],
    );
  }

  /// Applies scooter data fetched from the cloud API, syncing name and color.
  void updateFromCloudData(Map<String, dynamic> cloudData) {
    if (cloudData['name'] != null) {
      _name = cloudData['name'];
      _cloudScooterName = cloudData['name'];
    }

    if (cloudData['id'] != null) {
      _cloudScooterId = cloudData['id'];
    }

    final cloudColor = cloudData['color'] as String?;
    if (cloudColor == 'custom') {
      if (cloudData['color_hex'] != null) {
        _colorHex = cloudData['color_hex'];
        _color = 1; // fallback for anything that still reads the predefined index
      }
      if (cloudData['images'] != null) {
        _cloudImages = Map<String, String>.from(cloudData['images'] as Map<String, dynamic>);
      }
    } else if (cloudData['color_id'] != null) {
      _color = cloudData['color_id'];
      _colorHex = null;
      _cloudImages = null;
    }

    updateSharedPreferences();
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
