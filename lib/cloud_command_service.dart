import 'package:logging/logging.dart';

import 'cloud_service.dart';
import 'command_service.dart';

class CloudCommandService implements CommandService {
  final CloudService cloudService;
  final int? Function() getCloudScooterId;
  final Logger log = Logger('CloudCommandService');

  CloudCommandService(this.cloudService, this.getCloudScooterId);

  @override
  Future<bool> isAvailable(CommandType command) async {
    log.info([
      "CloudCommandService.isAvailable",
      await cloudService.isAuthenticated,
      getCloudScooterId()
    ]);
    if (!await cloudService.isAuthenticated || getCloudScooterId() == null) {
      return false;
    }
    return true; // All commands available via cloud
  }

  @override
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      return false;
    }

    final currentId = getCloudScooterId();
    if (currentId == null) {
      return false;
    }

    log.info(["executing command", command]);

    try {
      switch (command) {
        case CommandType.lock:
          return await cloudService.lock(currentId);
        case CommandType.unlock:
          return await cloudService.unlock(currentId);
        case CommandType.openSeat:
          return await cloudService.openSeatbox(currentId);
        case CommandType.blinkerLeft:
          return await cloudService.blinkers(currentId, "left");
        case CommandType.blinkerRight:
          return await cloudService.blinkers(currentId, "right");
        case CommandType.blinkerBoth:
          return await cloudService.blinkers(currentId, "both");
        case CommandType.blinkerOff:
          return await cloudService.blinkers(currentId, "off");
        case CommandType.honk:
          return await cloudService.honk(currentId);
        case CommandType.locate:
          return await cloudService.locate(currentId);
        case CommandType.alarm:
          return await cloudService.alarm(currentId);
        case CommandType.ping:
          return await cloudService.ping(currentId);
        case CommandType.getState:
          return await cloudService.getState(currentId);
        // case CommandType.hibernate:
        // case CommandType.wakeUp:
        //   return false; // These commands are BLE-only
        default:
          return false;
      }
    } catch (e, stack) {
      log.severe("Cloud command failed", e, stack);
      return false;
    }
  }

  @override
  Future<bool> needsConfirmation(CommandType command) async {
    // Only certain commands need confirmation when using cloud
    return command == CommandType.unlock || command == CommandType.openSeat;
  }
}
