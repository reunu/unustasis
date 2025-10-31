import '../scooter_service.dart';
import '../domain/scooter_battery.dart';
import '../domain/scooter_power_state.dart';
import '../domain/scooter_state.dart';
import '../infrastructure/battery_reader.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/string_reader.dart';
import '../infrastructure/version_reader.dart';

class ScooterReader {
  final CharacteristicRepository _characteristicRepository;
  ScooterState? _state;
  ScooterPowerState? _powerState;

  final ScooterService _service;

  ScooterReader({required ScooterService service, required CharacteristicRepository characteristicRepository})
      : _characteristicRepository = characteristicRepository,
        _service = service;

  readAndSubscribe() {
    _subscribeState();
    _subscribePowerStateForHibernation();
    _subscribeSeat();
    _subscribeHandlebars();
    _subscribeBatteries();
    _readNrfVersion();
  }

  // some of these characteristics are only available in more recent software versions
  // for those, we need to check if the characteristic is available, and ignore them gently otherwise
  // for all others, we can assume they're not null!

  void _subscribeState() {
    StringReader("State", _characteristicRepository.stateCharacteristic!).readAndSubscribe((String value) {
      _state = ScooterState.fromString(value);
      _updateScooterState();
    });
  }

  void _subscribePowerStateForHibernation() {
    if (_characteristicRepository.powerStateCharacteristic != null) {
      StringReader("Power State", _characteristicRepository.powerStateCharacteristic!).readAndSubscribe((String value) {
        _powerState = ScooterPowerState.fromString(value);
        _updateScooterState();
      });
    }
  }

  Future<void> _updateScooterState() async {
    ScooterState? oldState = _service.state;
    ScooterState? newState = ScooterState.fromStateAndPowerState(_state, _powerState);
    _service.state = newState;
    _service.ping();

    // if someone just locked the scooter with their keycard, stop keyless from unlocking again
    // this might (will) cause the cooldown to run even on app locks, but that's okay
    if (oldState?.isOn == true && newState?.isOn == false) {
      _service.autoUnlockCooldown();
    }
  }

  void _subscribeSeat() {
    StringReader("Seat", _characteristicRepository.seatCharacteristic!).readAndSubscribe((String seatState) {
      _service.seatClosed = seatState != "open";
      _service.ping();
    });
  }

  void _subscribeHandlebars() {
    StringReader("Handlebars", _characteristicRepository.handlebarCharacteristic!)
        .readAndSubscribe((String handlebarState) {
      _service.handlebarsLocked = handlebarState != "unlocked";
      _service.ping();
    });
  }

  void _subscribeBatteries() {
    var auxBatteryReader = BatteryReader(ScooterBatteryType.aux, _service);
    auxBatteryReader.readAndSubscribeSOC(_characteristicRepository.auxSOCCharacteristic!);
    auxBatteryReader.readAndSubscribeCharging(_characteristicRepository.auxChargingCharacteristic!);
    auxBatteryReader.readAndSubscribeVoltage(_characteristicRepository.auxVoltageCharacteristic!);

    var cbbBatteryReader = BatteryReader(ScooterBatteryType.cbb, _service);
    cbbBatteryReader.readAndSubscribeSOC(_characteristicRepository.cbbSOCCharacteristic!);
    cbbBatteryReader.readAndSubscribeCharging(_characteristicRepository.cbbChargingCharacteristic!);
    cbbBatteryReader.readAndSubscribeVoltage(_characteristicRepository.cbbVoltageCharacteristic!);
    cbbBatteryReader.readAndSubscribeCapacity(_characteristicRepository.cbbCapacityCharacteristic!);

    var primaryBatteryReader = BatteryReader(ScooterBatteryType.primary, _service);
    primaryBatteryReader.readAndSubscribeSOC(
      _characteristicRepository.primarySOCCharacteristic!,
    );
    primaryBatteryReader.readAndSubscribeCycles(
      _characteristicRepository.primaryCyclesCharacteristic!,
    );

    var secondaryBatteryReader = BatteryReader(ScooterBatteryType.secondary, _service);
    secondaryBatteryReader.readAndSubscribeSOC(
      _characteristicRepository.secondarySOCCharacteristic!,
    );
    secondaryBatteryReader.readAndSubscribeCycles(
      _characteristicRepository.secondaryCyclesCharacteristic!,
    );
  }

  void _readNrfVersion() {
    if (_characteristicRepository.nrfVersionCharacteristic != null) {
      VersionReader(
        _characteristicRepository.nrfVersionCharacteristic!,
        _service,
      ).readOnce();
    }
  }
}
