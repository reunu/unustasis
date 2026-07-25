import 'package:logging/logging.dart';

import 'cloud_service.dart';
import 'command_service.dart';
import 'features.dart';

class CloudCommandService implements CommandService {
  final CloudService cloudService;
  final Future<int?> Function() getCurrentCloudScooterId;
  final bool Function() isCloudOnline;
  final log = Logger('CloudCommandService');

  CloudCommandService(this.cloudService, this.getCurrentCloudScooterId, this.isCloudOnline);

  @override
  Future<bool> isAvailable(CommandType command) async {
    // Guards are ordered cheapest first and short-circuit deliberately:
    // cloudService.isAuthenticated can trigger a token refresh, so it must not
    // run when the feature is off or the command has no cloud equivalent.
    if (!_isCommandSupportedInCloud(command)) {
      return false;
    }
    if (!await Features.isCloudConnectivityEnabled) {
      return false;
    }
    if (!await cloudService.isAuthenticated) {
      return false;
    }
    if (await getCurrentCloudScooterId() == null) {
      return false;
    }
    // Read the flag the 30s poll maintains rather than probing. Availability
    // gates the UI; the command's own response says whether it landed.
    return isCloudOnline();
  }

  @override
  Future<bool> execute(CommandType command) async {
    // Callers check isAvailable() first. Re-checking here bought nothing: the
    // confirmation dialog sits between the check and the send, so the answer is
    // stale by the time the request goes out either way.
    final cloudScooterId = await getCurrentCloudScooterId();
    if (cloudScooterId == null) {
      log.warning('No cloud scooter ID available for command $command');
      return false;
    }

    try {
      final commandString = _getCloudCommandString(command);
      final parameters = _getCloudCommandParameters(command);
      
      final success = await cloudService.sendCommand(
        cloudScooterId,
        commandString,
        parameters: parameters,
      );
      
      if (success) {
        log.info('Cloud command $command executed successfully');
      } else {
        log.warning('Cloud command $command failed');
      }
      
      return success;
    } catch (e, stack) {
      log.severe('Failed to execute cloud command $command', e, stack);
      return false;
    }
  }

  @override
  Future<bool> needsConfirmation(CommandType command) async {
    // Cloud commands need confirmation for security/safety reasons
    switch (command) {
      case CommandType.lock:
      case CommandType.unlock:
      case CommandType.wakeUp:
      case CommandType.openSeat:
      case CommandType.honk:
      case CommandType.alarm:
      case CommandType.locate:
        return true;
      // Disarming leaves the scooter unprotected, so it asks. Arming and
      // silencing a siren are both safe to do straight away.
      case CommandType.alarmDisarm:
        return true;
      case CommandType.alarmArm:
      case CommandType.alarmStop:
        return false;
      case CommandType.hibernate:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
      case CommandType.ping:
      case CommandType.getState:
        return false;
    }
  }

  String _getCloudCommandString(CommandType command) {
    switch (command) {
      case CommandType.lock:
        return 'lock';
      case CommandType.unlock:
        return 'unlock';
      case CommandType.wakeUp:
        throw UnsupportedError('WakeUp command is not supported in cloud');
      case CommandType.hibernate:
        return 'hibernate';
      case CommandType.openSeat:
        return 'open_seatbox';
      case CommandType.blinkerLeft:
        return 'blinkers';
      case CommandType.blinkerRight:
        return 'blinkers';
      case CommandType.blinkerBoth:
        return 'blinkers';
      case CommandType.blinkerOff:
        return 'blinkers';
      case CommandType.honk:
        return 'honk';
      case CommandType.alarm:
        return 'alarm';
      case CommandType.alarmArm:
        return 'alarm_arm';
      case CommandType.alarmDisarm:
        return 'alarm_disarm';
      case CommandType.alarmStop:
        return 'alarm_stop';
      case CommandType.locate:
        return 'locate';
      case CommandType.ping:
        return 'ping';
      case CommandType.getState:
        return 'get_state';
    }
  }

  Map<String, dynamic>? _getCloudCommandParameters(CommandType command) {
    switch (command) {
      case CommandType.blinkerLeft:
        return {'state': 'left'};
      case CommandType.blinkerRight:
        return {'state': 'right'};
      case CommandType.blinkerBoth:
        return {'state': 'both'};
      case CommandType.blinkerOff:
        return {'state': 'off'};
      case CommandType.alarm:
        return {'duration': '30s'};
      default:
        return null;
    }
  }

  bool _isCommandSupportedInCloud(CommandType command) {
    switch (command) {
      case CommandType.lock:
      case CommandType.unlock:
      case CommandType.hibernate:
      case CommandType.openSeat:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
      case CommandType.honk:
      case CommandType.alarm:
      case CommandType.alarmArm:
      case CommandType.alarmDisarm:
      case CommandType.alarmStop:
      case CommandType.locate:
      case CommandType.ping:
      case CommandType.getState:
        return true;
      case CommandType.wakeUp:
        return false; // Not supported in cloud API
    }
  }
}