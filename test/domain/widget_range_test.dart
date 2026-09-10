import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/widget_range.dart';

void main() {
  test('missing readings are unavailable, not an empty battery', () {
    expect(estimatedWidgetRangeKm(null, null), isNull);
    expect(estimatedWidgetRangeKm(-1, null), isNull);
  });
  test('matches the app estimate for one and two batteries', () {
    expect(estimatedWidgetRangeKm(100, null), 45);
    expect(estimatedWidgetRangeKm(100, 100), 90);
    expect(estimatedWidgetRangeKm(87, 100), 84);
    expect(estimatedWidgetRangeKm(50, 0), 23);
    expect(estimatedWidgetRangeKm(null, 100), 45);
  });
  test('real zero stays zero and invalid SOC cannot overfill the gauge', () {
    expect(estimatedWidgetRangeKm(0, 0), 0);
    expect(estimatedWidgetRangeKm(120, 100), 90);
    expect(estimatedWidgetRangeKm(-1, 50), 23);
  });
}
