/// Librescoot settings keys for scheduled hibernation.
const String lsKeyScheduledHibernateCron = "pm.scheduled-hibernate-cron";
const String lsKeyScheduledHibernateDuration =
    "pm.scheduled-hibernate-duration";

/// Librescoot settings keys used by the scooter settings screen.
const String lsKeyAutoStandbySeconds = "scooter.auto-standby-seconds";
const String lsKeyHibernateTimer = "pm.hibernation-timer";
const String lsKeyCellularApn = "cellular.apn";

/// Librescoot settings key for the alarm as a whole. Off means the scooter
/// never arms, whatever the vehicle is doing.
const String lsKeyAlarmEnabled = "alarm.enabled";

/// Librescoot settings key that adds the horn to the alarm's siren.
const String lsKeyAlarmHonk = "alarm.honk";

// Maximum payload for the extended command characteristic. The basic command
// characteristic is limited to 20 bytes (default BLE MTU minus ATT overhead),
// but the extended characteristic uses allowLongWrite so it can carry more.
// Keep this well under typical negotiated MTUs (185–512 bytes) and the
// scooter's own command-buffer size.
const int extendedCommandMaxBytes = 100;

/// Why a user-entered APN can't be sent to the scooter.
enum ApnProblem { empty, invalidCharacters, tooLong }

const String apnCommandPrefix = "config:apn ";

/// Longest APN that still fits into a single extended command.
const int maxApnLength = extendedCommandMaxBytes - apnCommandPrefix.length;

// APNs are DNS-style labels, so anything outside printable ASCII (a space
// included) would be rejected by the modem anyway, and the command
// characteristic only carries ASCII.
final RegExp _apnAllowedChars = RegExp(r'^[\x21-\x7E]+$');

/// Checks an already-trimmed APN against what the command channel and the
/// modem accept. Returns null when [apn] is usable.
ApnProblem? checkApn(String apn) {
  if (apn.isEmpty) return ApnProblem.empty;
  if (!_apnAllowedChars.hasMatch(apn)) return ApnProblem.invalidCharacters;
  if (apn.length > maxApnLength) return ApnProblem.tooLong;
  return null;
}

enum EventType { lock, unlock, openSeat, hibernate, wakeUp, unknown }

enum EventSource { app, background, auto, unknown }

class ActionLocation {
  const ActionLocation(this.latitude, this.longitude);
  final double latitude, longitude;
}

class ActionEvent {
  const ActionEvent(
      {required this.scooterId,
      required this.generation,
      required this.kind,
      required this.source,
      this.primarySOC,
      this.secondarySOC,
      this.location});
  final String scooterId;
  final int generation;
  final EventType kind;
  final EventSource source;
  final int? primarySOC, secondarySOC;
  final ActionLocation? location;
}

class ActionSettings {
  const ActionSettings(
      {this.openSeatOnUnlock = false,
      this.hazardLocking = false,
      this.warnOfUnlockedHandlebars = true,
      this.autoUnlock = false,
      this.autoUnlockThreshold = -65,
      this.optionalAuth = false});
  final bool openSeatOnUnlock, hazardLocking, warnOfUnlockedHandlebars;
  final bool autoUnlock, optionalAuth;
  final int autoUnlockThreshold;
}

class HandlebarWarning {
  const HandlebarWarning(this.action);
  final ActionEvent action;
  bool get didNotUnlock => action.kind == EventType.unlock;
}

const keylessCooldownSeconds = 60;
const handlebarCheckSeconds = 5;
const wakeAndUnlockTimeout = Duration(seconds: 45);
const unlockCommand = 'scooter:state unlock';
const lockCommand = 'scooter:state lock';
const seatCommand = 'scooter:seatbox open';
String blinkerCommand(bool left, bool right) =>
    'scooter:blinker ${left ? (right ? "both" : "left") : (right ? "right" : "off")}';

const wakeCommand = 'wakeup';
const hibernatePowerCommand = 'hibernate';
const rebootPowerCommand = 'reboot';
const hardRebootPowerCommand = 'hard-reboot';
const usbUmsCommand = 'usb:ums';
const usbNormalCommand = 'usb:normal';
const usbAcknowledgement = 'usb:ok';
const keycardCountCommand = 'keycard:count';
const keycardListCommand = 'keycard:list';
const keycardAcknowledgement = 'keycard:ok';
const hibernateCancelPowerCommand = 'pm:hibernate-cancel';
const pmAcknowledgement = 'pm:ok';
const apnAcknowledgement = 'config:ok';
const bondForgetCommand = 'ble:forget';
const bondForgetAcknowledgement = 'ble:forget:ok';
String addKeycardPayload(String uid) => 'keycard:add:$uid';
String deleteKeycardPayload(String uid) => 'keycard:remove:$uid';
String clockPayload(DateTime time) =>
    'time:set ${time.millisecondsSinceEpoch ~/ 1000}';
String hibernateForPayload(Duration wakeAfter) {
  if (wakeAfter <= Duration.zero) throw 'Hibernate wake timer must be positive';
  return 'pm:hibernate-for ${wakeAfter.inSeconds}s';
}

String autoStandbyValue(Duration time) {
  final seconds = time.inSeconds;
  if (seconds < 0) throw 'Auto-standby time cannot be negative';
  if (seconds > 3600) throw 'Auto-standby time cannot be greater than 1 hour';
  return seconds.toString();
}
