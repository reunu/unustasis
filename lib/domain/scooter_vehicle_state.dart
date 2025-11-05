import 'package:logging/logging.dart';

enum ScooterVehicleState {
  standby,
  off,
  parked,
  shuttingDown,
  ready,
  waitingSeatbox,
  updating,
  waitingHibernation,
  waitingHibernationAdvanced,
  waitingHibernationSeatbox,
  waitingHibernationConfirm,
  unknown;

  static ScooterVehicleState? fromString(String? state) {
    final log = Logger("ScooterVehicleState.fromString");
    switch (state) {
      case "stand-by":
        return ScooterVehicleState.standby;
      case "off":
        return ScooterVehicleState.off;
      case "parked":
        return ScooterVehicleState.parked;
      case "shutting-down":
        return ScooterVehicleState.shuttingDown;
      case "ready-to-drive":
        return ScooterVehicleState.ready;
      case "waiting-seatbox":
        return ScooterVehicleState.waitingSeatbox;
      case "updating":
        return ScooterVehicleState.updating;
      case "waiting-hibernation":
        return ScooterVehicleState.waitingHibernation;
      case "waiting-hibernation-advanced":
        return ScooterVehicleState.waitingHibernationAdvanced;
      case "waiting-hibernation-seatbox":
        return ScooterVehicleState.waitingHibernationSeatbox;
      case "waiting-hibernation-confirm":
        return ScooterVehicleState.waitingHibernationConfirm;
      case "":
        // this is sometimes sent during standby, off or hibernating...
        return ScooterVehicleState.unknown;
      case null:
        return null;
      default:
        log.warning("Unknown vehicle state: $state");
        return ScooterVehicleState.unknown;
    }
  }
}
