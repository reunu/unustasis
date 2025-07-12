enum CommandType {
  lock,
  unlock,
  wakeUp,
  hibernate,
  openSeat,
  blinkerLeft,
  blinkerRight,
  blinkerBoth,
  blinkerOff,
  honk,
  alarm,
}

abstract class CommandService {
  Future<bool> isAvailable(CommandType command);
  Future<bool> execute(CommandType command);
  Future<bool> needsConfirmation(CommandType command);
}