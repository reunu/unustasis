import 'package:rxdart/rxdart.dart';

import '../scooter_service.dart';
import '../domain/scooter_battery.dart';
import '../domain/scooter_power_state.dart';
import '../domain/scooter_state.dart';
import '../infrastructure/battery_reader.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/string_reader.dart';

class ScooterReader {
  final CharacteristicRepository _characteristicRepository;
  ScooterState? _state;
  ScooterPowerState? _powerState;

  final BehaviorSubject<ScooterState?> _stateController;
  final BehaviorSubject<bool?> _seatClosedController;
  final BehaviorSubject<bool?> _handlebarController;
  final BehaviorSubject<int?> _auxSOCController;
  final BehaviorSubject<int?> _cbbSOCController;
  final BehaviorSubject<bool?> _cbbChargingController;
  final BehaviorSubject<int?> _primarySOCController;
  final BehaviorSubject<int?> _secondarySOCController;
  final BehaviorSubject<int?> _primaryCyclesController;
  final BehaviorSubject<int?> _secondaryCyclesController;

  final ScooterService _service;

  ScooterReader(
      {required CharacteristicRepository characteristicRepository,
      required BehaviorSubject<ScooterState?> stateController,
      required BehaviorSubject<bool?> seatClosedController,
      required BehaviorSubject<bool?> handlebarController,
      required BehaviorSubject<int?> auxSOCController,
      required BehaviorSubject<int?> cbbSOCController,
      required BehaviorSubject<bool?> cbbChargingController,
      required BehaviorSubject<int?> primarySOCController,
      required BehaviorSubject<int?> secondarySOCController,
      required BehaviorSubject<int?> primaryCyclesController,
      required BehaviorSubject<int?> secondaryCyclesController,
      required ScooterService service})
      : _characteristicRepository = characteristicRepository,
        _stateController = stateController,
        _seatClosedController = seatClosedController,
        _handlebarController = handlebarController,
        _auxSOCController = auxSOCController,
        _cbbSOCController = cbbSOCController,
        _cbbChargingController = cbbChargingController,
        _primarySOCController = primarySOCController,
        _secondarySOCController = secondarySOCController,
        _primaryCyclesController = primaryCyclesController,
        _secondaryCyclesController = secondaryCyclesController,
        _service = service;

  readAndSubscribe() {
    _subscribeState();
    _subscribePowerStateForHibernation();
    _subscribeSeat();
    _subscribeHandlebars();
    _subscribeBatteries();
  }

  void _subscribeState() {
    StringReader("State", _characteristicRepository.stateCharacteristic)
        .readAndSubscribe((String value) {
      _state = ScooterState.fromString(value);
      _updateScooterState();
    });
  }

  void _subscribePowerStateForHibernation() {
    StringReader(
            "Power State", _characteristicRepository.powerStateCharacteristic)
        .readAndSubscribe((String value) {
      _powerState = ScooterPowerState.fromString(value);
      _updateScooterState();
    });
  }

  Future<void> _updateScooterState() async {
    ScooterState? newState =
        ScooterState.fromStateAndPowerState(_state, _powerState);
    _stateController.add(newState);
    _service.ping();
  }

  void _subscribeSeat() {
    StringReader("Seat", _characteristicRepository.seatCharacteristic)
        .readAndSubscribe((String seatState) {
      _seatClosedController.add(seatState != "open");
      _service.ping();
    });
  }

  void _subscribeHandlebars() {
    StringReader(
            "Handlebars", _characteristicRepository.handlebarCharacteristic)
        .readAndSubscribe((String handlebarState) {
      _handlebarController.add(handlebarState != "unlocked");
      _service.ping();
    });
  }

  void _subscribeBatteries() {
    var auxBatterReader = BatteryReader(ScooterBattery.aux, _service);
    auxBatterReader.readAndSubscribeSOC(
        _characteristicRepository.auxSOCCharacteristic, _auxSOCController);

    var cbbBatteryReader = BatteryReader(ScooterBattery.cbb, _service);
    cbbBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.cbbSOCCharacteristic, _cbbSOCController);
    cbbBatteryReader.readAndSubscribeCharging(
        _characteristicRepository.cbbChargingCharacteristic,
        _cbbChargingController);

    var primaryBatteryReader = BatteryReader(ScooterBattery.primary, _service);
    primaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.primarySOCCharacteristic,
        _primarySOCController);
    primaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.primaryCyclesCharacteristic,
        _primaryCyclesController);

    var secondaryBatteryReader =
        BatteryReader(ScooterBattery.secondary, _service);
    secondaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.secondarySOCCharacteristic,
        _secondarySOCController);
    secondaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.secondaryCyclesCharacteristic,
        _secondaryCyclesController);
  }
}
