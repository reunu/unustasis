import 'dart:developer';

import 'package:rxdart/rxdart.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/infrastructure/string_reader.dart';

import '../domain/scooter_power_state.dart';
import '../domain/scooter_state.dart';
import 'battery_reader.dart';

class ScooterReader {
  final CharacteristicRepository _characteristicRepository;
  String? _state, _powerState;

  final BehaviorSubject<ScooterState?> _stateController;
  final BehaviorSubject<bool?> _seatClosedController;
  final BehaviorSubject<bool?> _handlebarController;
  final BehaviorSubject<DateTime?> _lastPingController;
  final BehaviorSubject<int?> _auxSOCController;
  final BehaviorSubject<int?> _cbbSOCController;
  final BehaviorSubject<bool?> _cbbChargingController;
  final BehaviorSubject<int?> _primarySOCController;
  final BehaviorSubject<int?> _secondarySOCController;
  final BehaviorSubject<int?> _primaryCyclesController;
  final BehaviorSubject<int?> _secondaryCyclesController;

  ScooterReader(
      {required CharacteristicRepository characteristicRepository,
      required BehaviorSubject<ScooterState?> stateController,
      required BehaviorSubject<bool?> seatClosedController,
      required BehaviorSubject<bool?> handlebarController,
      required BehaviorSubject<DateTime?> lastPingController,
      required BehaviorSubject<int?> auxSOCController,
      required BehaviorSubject<int?> cbbSOCController,
      required BehaviorSubject<bool?> cbbChargingController,
      required BehaviorSubject<int?> primarySOCController,
      required BehaviorSubject<int?> secondarySOCController,
      required BehaviorSubject<int?> primaryCyclesController,
      required BehaviorSubject<int?> secondaryCyclesController})
      : _characteristicRepository = characteristicRepository,
        _stateController = stateController,
        _seatClosedController = seatClosedController,
        _handlebarController = handlebarController,
        _lastPingController = lastPingController,
        _auxSOCController = auxSOCController,
        _cbbSOCController = cbbSOCController,
        _cbbChargingController = cbbChargingController,
        _primarySOCController = primarySOCController,
        _secondarySOCController = secondarySOCController,
        _primaryCyclesController = primaryCyclesController,
        _secondaryCyclesController = secondaryCyclesController;

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
      _state = value;
      _updateScooterState();
    });
  }

  void _subscribePowerStateForHibernation() {
    StringReader(
            "Power State", _characteristicRepository.powerStateCharacteristic)
        .readAndSubscribe((String value) {
      _powerState = value;
      _updateScooterState();
    });
  }

  Future<void> _updateScooterState() async {
    log("Update scooter state from state: '$_state' and power state: '$_powerState'");
    if (_state != null && _powerState != null) {
      ScooterPowerState powerState = ScooterPowerState.fromString(_powerState);
      ScooterState newState =
          ScooterState.fromStateAndPowerState(_state!, powerState);
      _stateController.add(newState);
    }
  }

  void _subscribeSeat() {
    StringReader("Seat", _characteristicRepository.seatCharacteristic)
        .readAndSubscribe((String seatState) {
      _seatClosedController.add(seatState != "open");
    });
  }

  void _subscribeHandlebars() {
    StringReader(
            "Handlebars", _characteristicRepository.handlebarCharacteristic)
        .readAndSubscribe((String handlebarState) {
      _handlebarController.add(handlebarState != "unlocked");
    });
  }

  void _subscribeBatteries() {
    var auxBatterReader =
        BatteryReader(ScooterBattery.aux, _lastPingController);
    auxBatterReader.readAndSubscribeSOC(
        _characteristicRepository.auxSOCCharacteristic, _auxSOCController);

    var cbbBatterReader =
        BatteryReader(ScooterBattery.cbb, _lastPingController);
    cbbBatterReader.readAndSubscribeSOC(
        _characteristicRepository.cbbSOCCharacteristic, _cbbSOCController);
    cbbBatterReader.readAndSubscribeCharging(
        _characteristicRepository.cbbChargingCharacteristic,
        _cbbChargingController);

    var primaryBatteryReader =
        BatteryReader(ScooterBattery.primary, _lastPingController);
    primaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.primaryCyclesCharacteristic,
        _primarySOCController);
    primaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.primaryCyclesCharacteristic,
        _primaryCyclesController);

    var secondaryBatteryReader =
        BatteryReader(ScooterBattery.secondary, _lastPingController);
    secondaryBatteryReader.readAndSubscribeSOC(
        _characteristicRepository.secondaryCyclesCharacteristic,
        _secondarySOCController);
    secondaryBatteryReader.readAndSubscribeCycles(
        _characteristicRepository.secondaryCyclesCharacteristic,
        _secondaryCyclesController);
  }
}
