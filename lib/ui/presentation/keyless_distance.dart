import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';

extension KeylessDistanceExtension on ScooterKeylessDistance {
  String getFormattedThreshold() => '$threshold dBm';

  String name(BuildContext context) {
    final translationKey = switch (this) {
      ScooterKeylessDistance.close => 'auto_unlock_threshold_close',
      ScooterKeylessDistance.regular => 'auto_unlock_threshold_regular',
      ScooterKeylessDistance.far => 'auto_unlock_threshold_far',
      ScooterKeylessDistance.veryFar => 'auto_unlock_threshold_very_far',
    };
    return FlutterI18n.translate(context, translationKey);
  }
}
