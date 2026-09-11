enum ScooterKeylessDistance {
  // Important: ensure all thresholds are equally spread.
  close(-55),
  regular(-65),
  far(-75),
  veryFar(-85);

  const ScooterKeylessDistance(this.threshold);

  final int threshold;

  static ScooterKeylessDistance fromThreshold(int threshold) {
    return values.firstWhere((distance) => distance.threshold == threshold);
  }

  static ScooterKeylessDistance getMinThresholdDistance() {
    return ScooterKeylessDistance.veryFar;
  }

  static ScooterKeylessDistance getMaxThresholdDistance() {
    return ScooterKeylessDistance.close;
  }
}
