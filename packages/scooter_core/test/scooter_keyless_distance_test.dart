import 'package:scooter_core/scooter_core.dart';
import 'package:test/test.dart';

void main() {
  test('keyless distances preserve names, order and evenly spaced thresholds',
      () {
    expect(ScooterKeylessDistance.values.map((value) => value.name), [
      'close',
      'regular',
      'far',
      'veryFar',
    ]);
    expect(ScooterKeylessDistance.values.map((value) => value.threshold), [
      -55,
      -65,
      -75,
      -85,
    ]);
    for (final value in ScooterKeylessDistance.values) {
      expect(
          ScooterKeylessDistance.fromThreshold(value.threshold), same(value));
    }
    expect(ScooterKeylessDistance.getMinThresholdDistance(),
        ScooterKeylessDistance.veryFar);
    expect(ScooterKeylessDistance.getMaxThresholdDistance(),
        ScooterKeylessDistance.close);
  });

  test('unknown thresholds still throw StateError', () {
    for (final threshold in [-100, -86, -80, -54, 0]) {
      expect(() => ScooterKeylessDistance.fromThreshold(threshold),
          throwsStateError);
    }
  });
}
