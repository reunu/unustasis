/// What the alarm can still notice while everything else is asleep. While the
/// scooter is running the mask predicts what would apply if it hibernated right
/// now; once it is hibernating the same mask is live.
class AlarmWakeSources {
  static const int _motionBit = 0x01;
  static const int _wakeTimerBit = 0x02;
  static const int _brakeBit = 0x04;
  static const int _bleBit = 0x08;
  static const int _lowCbbBit = 0x10;

  final bool hibernating;
  final bool motionWouldWake;
  final bool wakeTimerArmed;
  final bool brakeWouldWake;
  final bool bleWouldWake;
  final bool lowCbbWouldWake;
  final Duration? wakeTimerDuration;

  const AlarmWakeSources({
    required this.hibernating,
    required this.motionWouldWake,
    required this.wakeTimerArmed,
    required this.brakeWouldWake,
    required this.bleWouldWake,
    required this.lowCbbWouldWake,
    required this.wakeTimerDuration,
  });

  /// Parses phase, mask and a little-endian uint32 of wake-timer seconds.
  /// Returns null on anything but the expected 6 bytes.
  static AlarmWakeSources? fromBytes(List<int> data) {
    if (data.length != 6) return null;
    final int mask = data[1];
    final bool wakeTimerArmed = mask & _wakeTimerBit != 0;
    final int seconds = data[2] + (data[3] << 8) + (data[4] << 16) + (data[5] << 24);
    return AlarmWakeSources(
      hibernating: data[0] == 1,
      motionWouldWake: mask & _motionBit != 0,
      wakeTimerArmed: wakeTimerArmed,
      brakeWouldWake: mask & _brakeBit != 0,
      bleWouldWake: mask & _bleBit != 0,
      lowCbbWouldWake: mask & _lowCbbBit != 0,
      wakeTimerDuration: wakeTimerArmed && seconds > 0 ? Duration(seconds: seconds) : null,
    );
  }
}
