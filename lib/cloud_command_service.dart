import 'package:logging/logging.dart';

import 'cloud_service.dart';
import 'command_service.dart';

class CloudCommandService implements CommandService {
  final CloudService cloudService;
  final int? cloudScooterId;
  final Logger log = Logger('CloudCommandService');

  CloudCommandService(this.cloudService, this.cloudScooterId);

  @override
  Future<bool> isAvailable(CommandType command) async {
    if (!await cloudService.isAuthenticated || cloudScooterId == null) {
      return false;
    }
    return true; // All commands available via cloud
  }

  @override
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      return false;
    }

    try {
      switch (command) {
        case CommandType.lock:
          return await cloudService.lock(cloudScooterId!);
        case CommandType.unlock:
          return await cloudService.unlock(cloudScooterId!);
        case CommandType.openSeat:
          return await cloudService.openSeatbox(cloudScooterId!);
        case CommandType.blinkerLeft:
          return await cloudService.blinkers(cloudScooterId!, "left");
        case CommandType.blinkerRight:
          return await cloudService.blinkers(cloudScooterId!, "right");
        case CommandType.blinkerBoth:
          return await cloudService.blinkers(cloudScooterId!, "both");
        case CommandType.blinkerOff:
          return await cloudService.blinkers(cloudScooterId!, "off");
        case CommandType.honk:
          return await cloudService.honk(cloudScooterId!);
        case CommandType.locate:
          return await cloudService.locate(cloudScooterId!);
        case CommandType.alarm:
          return await cloudService.alarm(cloudScooterId!);
        case CommandType.ping:
          return await cloudService.ping(cloudScooterId!);
        case CommandType.getState:
          return await cloudService.getState(cloudScooterId!);
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
