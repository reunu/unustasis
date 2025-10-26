import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'color_utils.dart';

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
  bool? _handlebarsLocked;
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
    bool? handlebarsLocked,
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
        _handlebarsLocked = handlebarsLocked,
        _cloudScooterId = cloudScooterId,
        _cloudScooterName = cloudScooterName;

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

  set cloudScooterName(String? cloudScooterName) {
    _cloudScooterName = cloudScooterName;
    updateSharedPreferences();
  }

  String get name => _name;
  String get id => _id;
  int get color => _color;
  String? get colorHex => _colorHex;
  Map<String, String>? get cloudImages => _cloudImages;
  
  /// Gets the front view image URL for main page display
  String? get cloudImageFront => _cloudImages?['front'];
  
  /// Gets the side view image URL for info list display  
  String? get cloudImageSide => _cloudImages?['right'] ?? _cloudImages?['side'];
  
  /// Gets any available cloud image URL as fallback
  String? get cloudImageUrl => _cloudImages?['front'] ?? _cloudImages?['right'] ?? _cloudImages?['left'];
  DateTime get lastPing => _lastPing;
  bool get autoConnect => _autoConnect;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;
  bool? get handlebarsLocked => _handlebarsLocked;
  int? get cloudScooterId => _cloudScooterId;
  String? get cloudScooterName => _cloudScooterName;

  /// Returns true if this scooter uses a custom hex color (from cloud)
  bool get hasCustomColor => _colorHex != null;

  /// Returns the effective color to display - either hex color or predefined color
  String get effectiveColorHex {
    if (_colorHex != null) return _colorHex!;
    return getPredefinedColorHex(_color);
  }

  /// Maps predefined color indices to hex values
  static String getPredefinedColorHex(int colorIndex) {
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

  /// Maps predefined color indices to Flutter Colors
  static Color getPredefinedColor(int colorIndex) {
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

  /// Maps predefined color indices to human-readable names
  static String getColorName(int colorIndex) {
    const colorNames = {
      0: 'Black',
      1: 'White', 
      2: 'Green',
      3: 'Gray',
      4: 'Orange',
      5: 'Red',
      6: 'Blue',
      7: 'Eclipse',
      8: 'Idioteque',
      9: 'Hover',
    };
    return colorNames[colorIndex] ?? 'Unknown';
  }

  /// Converts hex color string to Flutter Color
  static Color hexToColor(String hexColor) {
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  /// Gets the effective color (hex or predefined) for a given color setup
  static Color getEffectiveColor({String? colorHex, int? colorIndex}) {
    if (colorHex != null) {
      return hexToColor(colorHex);
    }
    return getPredefinedColor(colorIndex ?? 1);
  }

  /// Gets the effective color hex (custom hex or predefined) for a given color setup
  static String getEffectiveColorHex({String? colorHex, int? colorIndex}) {
    if (colorHex != null) return colorHex;
    return getPredefinedColorHex(colorIndex ?? 1);
  }

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
        'handlebarsLocked': _handlebarsLocked,
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
        cloudImages: map['cloudImages'] != null 
            ? Map<String, String>.from(map['cloudImages']) 
            : null,
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
        cloudScooterId: map['cloudScooterId'],
        cloudScooterName: map['cloudScooterName']);
  }

  /// Updates scooter data from cloud data
  void updateFromCloudData(Map<String, dynamic> cloudData) {
    // Update name if provided
    if (cloudData['name'] != null) {
      _name = cloudData['name'];
      _cloudScooterName = cloudData['name']; // Also cache cloud name
    }
    
    // Update cloud scooter ID if provided
    if (cloudData['id'] != null) {
      _cloudScooterId = cloudData['id'];
    }
    
    // Handle color based on cloud 'color' field
    final cloudColor = cloudData['color'] as String?;
    if (cloudColor == 'custom') {
      // Use custom hex color
      if (cloudData['color_hex'] != null) {
        _colorHex = cloudData['color_hex'];
        // When using custom color, clear the predefined color to avoid conflicts
        _color = 1; // Default to white as fallback
      }
      // Save entire images hash for custom colors
      if (cloudData['images'] != null) {
        final images = cloudData['images'] as Map<String, dynamic>;
        _cloudImages = Map<String, String>.from(images);
      }
    } else {
      // Use predefined color_id
      if (cloudData['color_id'] != null) {
        _color = cloudData['color_id'];
        _colorHex = null; // Clear hex color when using predefined
        _cloudImages = null; // Clear cloud images when using predefined
      }
    }
    
    updateSharedPreferences();
  }
  
  /// Gets the Flutter Color object for this scooter
  Color get effectiveColor {
    return getEffectiveColor(colorHex: _colorHex, colorIndex: _color);
  }

  void updateSharedPreferences() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    Map<String, dynamic> savedScooters =
        jsonDecode(await prefs.getString("savedScooters") ?? "{}") as Map<String, dynamic>;
    savedScooters[_id] = toJson();
    await prefs.setString("savedScooters", jsonEncode(savedScooters));
  }
}
