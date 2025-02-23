enum CommandType {
  lock,
  unlock,
  openSeat,
  blinkerLeft,
  blinkerRight,
  blinkerBoth,
  blinkerOff,
  hibernate,
  wakeUp,
  honk,
  locate,
  alarm,
  ping,
  getState
}

abstract class CommandService {
  Future<bool> isAvailable(CommandType command);
  Future<bool> execute(CommandType command);
  Future<bool> needsConfirmation(CommandType command);
}
