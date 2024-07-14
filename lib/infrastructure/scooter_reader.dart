import 'dart:developer';

import 'package:rxdart/rxdart.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/infrastructure/battery_reader.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/infrastructure/string_reader.dart';

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

  final void Function() ping;

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
      required void Function() pingFunc})
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
        ping = pingFunc;

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
    ping();
  }

  void _subscribeSeat() {
    StringReader("Seat", _characteristicRepository.seatCharacteristic)
        .readAndSubscribe((String seatState) {
      _seatClosedController.add(seatState != "open");
      ping();
    });
  }

  void _subscribeHandlebars() {
    StringReader(
            "Handlebars", _characteristicRepository.handlebarCharacteristic)
        .readAndSubscribe((String handlebarState) {
      _handlebarController.add(handlebarState != "unlocked");
      ping();
    });
  }

  void _subscribeBatteries() {
    var auxBatterReader = BatteryReader(ScooterBattery.aux, ping);
    auxBatterReader.readAndSubscribeSOC(
        _characteristicRepository.auxSOCCharacteristic, _auxSOCController);

    var cbbBatteryReader = BatteryReader(ScooterBattery.cbb, ping);
    cbbBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.cbbSOCCharacteristic, _cbbSOCController);
    cbbBatteryReader.readAndSubscribeCharging(
        _characteristicRepository.cbbChargingCharacteristic,
        _cbbChargingController);

    var primaryBatteryReader = BatteryReader(ScooterBattery.primary, ping);
    primaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.primarySOCCharacteristic,
        _primarySOCController);
    primaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.primaryCyclesCharacteristic,
        _primaryCyclesController);

    var secondaryBatteryReader = BatteryReader(ScooterBattery.secondary, ping);
    secondaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.secondarySOCCharacteristic,
        _secondarySOCController);
    secondaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.secondaryCyclesCharacteristic,
        _secondaryCyclesController);
  }
}
