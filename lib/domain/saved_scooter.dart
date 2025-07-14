import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedScooter {
  String _name;
  String _id;
  int _color;
  String? _colorHex;
  String? _cloudImageUrl;
  DateTime _lastPing;
  bool _autoConnect;
  int? _lastPrimarySOC;
  int? _lastSecondarySOC;
  int? _lastCbbSOC;
  int? _lastAuxSOC;
  LatLng? _lastLocation;
  bool? _handlebarsLocked;
  int? _cloudScooterId;

  SavedScooter({
    required String id,
    String? name,
    int? color,
    String? colorHex,
    String? cloudImageUrl,
    DateTime? lastPing,
    bool? autoConnect,
    int? lastPrimarySOC,
    int? lastSecondarySOC,
    int? lastCbbSOC,
    int? lastAuxSOC,
    LatLng? lastLocation,
    bool? handlebarsLocked,
    int? cloudScooterId,
  })  : _name = name ?? "Scooter Pro",
        _id = id,
        _color = color ?? 1,
        _colorHex = colorHex,
        _cloudImageUrl = cloudImageUrl,
        _lastPing = lastPing ?? DateTime.now(),
        _autoConnect = autoConnect ?? true,
        _lastPrimarySOC = lastPrimarySOC,
        _lastSecondarySOC = lastSecondarySOC,
        _lastCbbSOC = lastCbbSOC,
        _lastAuxSOC = lastAuxSOC,
        _lastLocation = lastLocation,
        _handlebarsLocked = handlebarsLocked,
        _cloudScooterId = cloudScooterId;

  set name(String name) {
    _name = name;
    updateSharedPreferences();
  }

  set color(int color) {
    _color = color;
    _colorHex = null; // Clear hex color when setting predefined color
    updateSharedPreferences();
  }

  set colorHex(String? colorHex) {
    _colorHex = colorHex;
    updateSharedPreferences();
  }

  set cloudImageUrl(String? cloudImageUrl) {
    _cloudImageUrl = cloudImageUrl;
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

  set cloudScooterId(int? cloudScooterId) {
    _cloudScooterId = cloudScooterId;
    updateSharedPreferences();
  }

  String get name => _name;
  String get id => _id;
  int get color => _color;
  String? get colorHex => _colorHex;
  String? get cloudImageUrl => _cloudImageUrl;
  DateTime get lastPing => _lastPing;
  bool get autoConnect => _autoConnect;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;
  bool? get handlebarsLocked => _handlebarsLocked;
  int? get cloudScooterId => _cloudScooterId;

  /// Returns true if this scooter uses a custom hex color (from cloud)
  bool get hasCustomColor => _colorHex != null;

  /// Returns the effective color to display - either hex color or predefined color
  String get effectiveColorHex {
    if (_colorHex != null) return _colorHex!;
    return _getPredefinedColorHex(_color);
  }

  /// Maps predefined color indices to hex values
  String _getPredefinedColorHex(int colorIndex) {
    const colorMap = {
      0: '#000000', // black
      1: '#FFFFFF', // white
      2: '#1B5E20', // green
      3: '#9E9E9E', // gray
      4: '#FF5722', // orange
      5: '#F44336', // red
      6: '#2196F3', // blue
      7: '#424242', // eclipse
      8: '#4DB6AC', // idioteque
      9: '#03A9F4', // hover
    };
    return colorMap[colorIndex] ?? '#FFFFFF';
  }

  BluetoothDevice get bluetoothDevice => BluetoothDevice.fromId(_id);

  Map<String, dynamic> toJson() => {
        'id': _id,
        'name': _name,
        'color': _color,
        'colorHex': _colorHex,
        'cloudImageUrl': _cloudImageUrl,
        'lastPing': _lastPing.microsecondsSinceEpoch,
        'autoConnect': _autoConnect,
        'lastPrimarySOC': _lastPrimarySOC,
        'lastSecondarySOC': _lastSecondarySOC,
        'lastCbbSOC': _lastCbbSOC,
        'lastAuxSOC': _lastAuxSOC,
        'lastLocation': _lastLocation?.toJson(),
        'handlebarsLocked': _handlebarsLocked,
        'cloudScooterId': _cloudScooterId,
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
        cloudImageUrl: map['cloudImageUrl'],
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
        lastAuxSOC: map['lastAuxSOC'],
        handlebarsLocked: map['handlebarsLocked'],
        cloudScooterId: map['cloudScooterId']);
  }

  /// Updates scooter data from cloud data
  void updateFromCloudData(Map<String, dynamic> cloudData) {
    // Update name if provided
    if (cloudData['name'] != null) {
      _name = cloudData['name'];
    }
    
    // Handle color based on cloud 'color' field
    final cloudColor = cloudData['color'] as String?;
    if (cloudColor == 'custom') {
      // Use custom hex color
      if (cloudData['color_hex'] != null) {
        _colorHex = cloudData['color_hex'];
      }
      // Update cloud image URL for custom colors
      if (cloudData['images'] != null) {
        final images = cloudData['images'] as Map<String, dynamic>;
        _cloudImageUrl = images['right'] ?? images['left'];
      }
    } else {
      // Use predefined color_id
      if (cloudData['color_id'] != null) {
        _color = cloudData['color_id'];
        _colorHex = null; // Clear hex color when using predefined
        _cloudImageUrl = null; // Clear cloud image when using predefined
      }
    }
    
    updateSharedPreferences();
  }
  
  /// Gets the Flutter Color object for this scooter
  Color get effectiveColor {
    if (_colorHex != null) {
      // Parse hex color string
      final hexColor = _colorHex!.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    }
    return _getPredefinedColor(_color);
  }
  
  /// Maps predefined color indices to Flutter Colors
  Color _getPredefinedColor(int colorIndex) {
    const colorMap = {
      0: Colors.black,
      1: Colors.white,
      2: Colors.green,
      3: Colors.grey,
      4: Colors.deepOrange,
      5: Colors.red,
      6: Colors.blue,
      7: Colors.grey,
      8: Colors.teal,
      9: Colors.lightBlue,
    };
    return colorMap[colorIndex] ?? Colors.white;
  }

  void updateSharedPreferences() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    Map<String, dynamic> savedScooters =
        jsonDecode(await prefs.getString("savedScooters") ?? "{}") as Map<String, dynamic>;
    savedScooters[_id] = toJson();
    await prefs.setString("savedScooters", jsonEncode(savedScooters));
  }
}
