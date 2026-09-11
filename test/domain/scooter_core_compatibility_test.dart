import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart' as core;
import 'package:unustasis/domain/alarm_wake_sources.dart' as legacy_alarm;
import 'package:unustasis/domain/go_duration.dart' as legacy_duration;
import 'package:unustasis/domain/hibernation_schedule.dart' as legacy_schedule;
import 'package:unustasis/domain/ota_protocol.dart' as legacy_ota;
import 'package:unustasis/domain/update_planner.dart' as legacy_planner;

void main() {
  test('legacy OTA exports share core types and wire behavior', () {
    final core.OtaStatusMessage message = legacy_ota.OtaStatusMessage.parse([
      core.OtaProtocol.opAck,
      0,
      42,
      0,
      0,
      0,
    ])!;
    final legacy_ota.OtaStatusMessage legacyMessage = message;
    expect(legacyMessage, isA<core.OtaAck>());
    expect((message as core.OtaAck).offset, 42);
    expect(legacy_ota.OtaProtocol.encodeComplete(), core.OtaProtocol.encodeComplete());
  });

  test('legacy planner exports share core plans and warning keys', () {
    final core.UpdatePlan plan = legacy_planner.UpdatePlanner.buildPlan(
      releases: const <core.FirmwareRelease>[],
      channel: 'stable',
      mdbVersion: null,
      dbcVersion: null,
    );
    final legacy_planner.UpdatePlan legacyPlan = plan;
    expect(identical(legacyPlan, plan), isTrue);
    expect(plan.warnings.first, isA<legacy_planner.PlanWarning>());
    expect(plan.warnings.first.key, 'ls_ota_warn_mdb_unknown');
    expect(legacy_planner.StepKind.delta, core.StepKind.delta);
  });

  test('legacy schedule and duration exports preserve core behavior', () {
    final core.HibernationSchedule schedule = legacy_schedule.HibernationSchedule.fromCron('30 22 * * 1,5')!;
    final legacy_schedule.HibernationSchedule legacySchedule = schedule;
    expect(legacySchedule.frequency, core.HibernationFrequency.weekly);
    expect(legacySchedule.toCron(), '30 22 * * 1,5');
    expect(legacy_duration.tryParseGoDuration('1h30m'), core.tryParseGoDuration('1h30m'));
    expect(legacy_duration.formatGoDuration(const Duration(minutes: 90)),
        core.formatGoDuration(const Duration(minutes: 90)));
  });

  test('legacy alarm exports share the core wake-source type', () {
    final core.AlarmWakeSources sources = legacy_alarm.AlarmWakeSources.fromBytes([1, 2, 60, 0, 0, 0])!;
    final legacy_alarm.AlarmWakeSources legacySources = sources;
    expect(identical(legacySources, sources), isTrue);
    expect(legacySources.wakeTimerDuration, const Duration(minutes: 1));
  });
}
