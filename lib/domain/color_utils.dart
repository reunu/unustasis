import 'package:flutter/material.dart';

/// Utility class for scooter color management and parsing
class ColorUtils {
  ColorUtils._();

  /// Color ID to name mapping for scooters
  static const Map<int, String> colorNames = {
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

  /// Color ID to Flutter Color mapping for scooters
  static const Map<int, Color> colorValues = {
    0: Colors.black,
    1: Colors.white,
    2: Color(0xFF2E7D32), // Colors.green.shade900 equivalent
    3: Colors.grey,
    4: Color(0xFFFF7043), // Colors.deepOrange.shade400 equivalent
    5: Colors.red,
    6: Colors.blue,
    7: Color(0xFF424242), // Colors.grey.shade800 equivalent
    8: Color(0xFF4DB6AC), // Colors.teal.shade200 equivalent
    9: Colors.lightBlue,
  };

  /// Safely parses a hex color string to Flutter Color
  /// Handles various hex formats: "#RRGGBB", "RRGGBB", "#RGB", "RGB"
  static Color? parseHexColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) {
      return null;
    }

    // Remove # if present
    String cleanHex = hexColor.replaceAll('#', '');

    try {
      // Handle 3-character hex (e.g., "F0A" -> "FF00AA")
      if (cleanHex.length == 3) {
        cleanHex = cleanHex.split('').map((char) => char + char).join('');
      }

      // Ensure we have 6 characters for RGB
      if (cleanHex.length != 6) {
        return null;
      }

      // Parse with full alpha (FF prefix)
      return Color(int.parse('FF$cleanHex', radix: 16));
    } catch (e) {
      return null;
    }
  }

  /// Gets the color name for a given color ID
  static String getColorName(int colorId) {
    return colorNames[colorId] ?? 'Unknown';
  }

  /// Gets the Flutter Color for a given color ID
  static Color getColorValue(int colorId) {
    return colorValues[colorId] ?? Colors.grey;
  }

  /// Converts a Color to hex string (without # prefix)
  static String colorToHex(Color color) {
    return '${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}'
           '${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}'
           '${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}';
  }
}