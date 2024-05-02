enum ScooterKeylessDistance {
  // Important: ensure all thresholds are equally spread
  hard(-55, "auto_unlock_threshold_hard"),
  regular(-65, "auto_unlock_threshold_regular"),
  easy(-75, "auto_unlock_threshold_easy"),
  veryEasy(-85, "auto_unlock_threshold_very_easy");

  const ScooterKeylessDistance(this.threshold, this.translationKey);

  final int threshold;
  final String translationKey;

  static fromThreshold(int threshold) {
    return ScooterKeylessDistance.values
        .firstWhere((distance) => distance.threshold == threshold);
  }

  static getMinDistance() {
    return ScooterKeylessDistance.veryEasy;
  }

  static getMaxDistance() {
    return ScooterKeylessDistance.hard;
  }

  String getFormattedThreshold() {
    return "$threshold dBm";
  }
}