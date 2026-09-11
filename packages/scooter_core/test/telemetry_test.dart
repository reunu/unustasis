import 'package:scooter_core/telemetry.dart';
import 'package:test/test.dart';

void main() {
  test('USB enum spelling and order remain stable', () {
    expect(UsbMode.values.map((mode) => mode.name), ['normal', 'massStorage']);
  });
  test('alarm trigger keeps source with absent or invalid timestamp', () {
    expect(
        parseAlarmLastTrigger('motion'), (source: 'motion', timestamp: null));
    expect(parseAlarmLastTrigger('motion,invalid'),
        (source: 'motion', timestamp: null));
    expect(parseAlarmLastTrigger('motion,2026-01-02T03:04:05Z'),
        (source: 'motion', timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5)));
  });
  test('empty source is unknown; only first comma splits timestamp', () {
    expect(parseAlarmLastTrigger(''), isNull);
    expect(parseAlarmLastTrigger(',2026-01-02T03:04:05Z'), isNull);
    expect(parseAlarmLastTrigger('motion,2026-01-02T03:04:05Z,extra'),
        (source: 'motion', timestamp: null));
  });
  test('cache patch distinguishes known false and zero from absent values', () {
    const patch = TelemetryCachePatch(primarySOC: 0, supportsApnConfig: false);
    expect(patch.primarySOC, 0);
    expect(patch.supportsApnConfig, false);
    expect(patch.supportsHibernateFor, isNull);
  });
}
