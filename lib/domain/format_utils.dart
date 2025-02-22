import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:intl/intl.dart';

class FormatUtils {
  static String formatLastSeen(String lastSeenStr, {bool short = false}) {
    final lastSeen = DateTime.parse(lastSeenStr);
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (short) {
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d';
      } else {
        return '${(difference.inDays / 7).floor()}w';
      }
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM d, HH:mm').format(lastSeen);
    }
  }

  static String formatLocation(BuildContext context, Map<String, dynamic> location) {
    if (location['lat'] == null || location['lng'] == null) {
      return FlutterI18n.translate(context, "no_location");
    }
    final lat = double.parse(location['lat'].toString());
    final lng = double.parse(location['lng'].toString());
    if (lat == 0.0 && lng == 0.0) {
      return FlutterI18n.translate(context, "no_location");
    }
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }
}