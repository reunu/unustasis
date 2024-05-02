enum ScooterKeylessDistance {
  // Important: ensure all thresholds are equally spread
  close(-55, "auto_unlock_threshold_close"),
  regular(-65, "auto_unlock_threshold_regular"),
  far(-75, "auto_unlock_threshold_far"),
  veryFar(-85, "auto_unlock_threshold_very_far");

  const ScooterKeylessDistance(this.threshold, this.translationKey);

  final int threshold;
  final String translationKey;

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
}