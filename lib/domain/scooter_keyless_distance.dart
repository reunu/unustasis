import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

enum ScooterKeylessDistance {
  // Important: ensure all thresholds are equally spread
  close(-55, "auto_unlock_threshold_close"),
  regular(-65, "auto_unlock_threshold_regular"),
  far(-75, "auto_unlock_threshold_far"),
  veryFar(-85, "auto_unlock_threshold_very_far");

  const ScooterKeylessDistance(this.threshold, this._translationKey);

  final int threshold;
  final String _translationKey;

  static fromThreshold(int threshold) {
    return ScooterKeylessDistance.values
        .firstWhere((distance) => distance.threshold == threshold);
  }

  static getMinThresholdDistance() {
    return ScooterKeylessDistance.veryFar;
  }

  static getMaxThresholdDistance() {
    return ScooterKeylessDistance.close;
  }

  String getFormattedThreshold() {
    return "$threshold dBm";
  }

  String name(BuildContext context) {
    return FlutterI18n.translate(context, _translationKey);
  }
}