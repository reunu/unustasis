import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

class CharacteristicRepository {
  final log = Logger("CharacteristicRepository");
  BluetoothDevice scooter;
  late BluetoothCharacteristic? commandCharacteristic;
  late BluetoothCharacteristic? hibernationCommandCharacteristic;
  late BluetoothCharacteristic? stateCharacteristic;
  late BluetoothCharacteristic? powerStateCharacteristic;
  late BluetoothCharacteristic? seatCharacteristic;
  late BluetoothCharacteristic? handlebarCharacteristic;
  late BluetoothCharacteristic? auxSOCCharacteristic;
  late BluetoothCharacteristic? auxVoltageCharacteristic;
  late BluetoothCharacteristic? auxChargingCharacteristic;
  late BluetoothCharacteristic? cbbSOCCharacteristic;
  late BluetoothCharacteristic? cbbVoltageCharacteristic;
  late BluetoothCharacteristic? cbbCapacityCharacteristic;
  late BluetoothCharacteristic? cbbChargingCharacteristic;
  late BluetoothCharacteristic? cbbFullCapacityCharacteristic;
  late BluetoothCharacteristic? primaryStateCharacteristic;
  late BluetoothCharacteristic? primaryPresentCharacteristic;
  late BluetoothCharacteristic? primaryCyclesCharacteristic;
  late BluetoothCharacteristic? primarySOCCharacteristic;
  late BluetoothCharacteristic? secondaryCyclesCharacteristic;
  late BluetoothCharacteristic? secondarySOCCharacteristic;
  late BluetoothCharacteristic? nrfVersionCharacteristic;

  // librescoot-specific characteristics
  late BluetoothCharacteristic? imxVersionCharacteristic;
  late BluetoothCharacteristic? odometerCharacteristic;
  late BluetoothCharacteristic? systemTimeCharacteristic;
  late BluetoothCharacteristic? navigationActiveCharacteristic;
  late BluetoothCharacteristic? umsStatusCharacteristic;
  late BluetoothCharacteristic? extendedCommandCharacteristic;
  late BluetoothCharacteristic? extendedResponseCharacteristic;

  // OTA firmware transfer (librescoot firmware with the 0x0500 service only);
  // non-late so they are simply null on firmware without OTA support
  BluetoothCharacteristic? otaDataCharacteristic;
  BluetoothCharacteristic? otaControlCharacteristic;
  BluetoothCharacteristic? otaStatusCharacteristic;

  // Alarm state (librescoot firmware with the 0x0220 service only)
  BluetoothCharacteristic? alarmStatusCharacteristic;
  BluetoothCharacteristic? alarmLastTriggerCharacteristic;
  BluetoothCharacteristic? alarmWakeSourcesCharacteristic;

  /// What discovery asked for and did not find, in discovery order.
  final List<String> missingCharacteristics = <String>[];

  /// Set when the local stack refused an operation with a code that means its
  /// cached GATT table is wrong. See [isGattTableMismatch].
  bool gattTableMismatch = false;

  bool extendedNotifyVerified = false;

  /// Extended commands written with no answer at all, and whether any answer
  /// ever arrived. Firmware rejects unknown commands, so silence is not the same
  /// as an unsupported command.
  int silentExtendedCommands = 0;
  bool extendedResponseSeen = false;

  /// Silent extended commands since the last answer, if any. Unlike
  /// [extendedChannelSilent] this is not a verdict about the phone's table, so
  /// it is safe to use it to stop waiting on a channel mid-session.
  int consecutiveSilentCommands = 0;

  CharacteristicRepository(this.scooter);

  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {
    log.info("findAll running");
    missingCharacteristics.clear();
    await scooter.discoverServices();
    commandCharacteristic = _expect(
        'command',
        "9a590000-6e67-5d0d-aab9-ad9126b66f91",
        "9a590001-6e67-5d0d-aab9-ad9126b66f91");
    hibernationCommandCharacteristic = _expect(
        'hibernation-command',
        "9a590000-6e67-5d0d-aab9-ad9126b66f91",
        "9a590002-6e67-5d0d-aab9-ad9126b66f91");
    stateCharacteristic = _expect(
        'state',
        "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590021-6e67-5d0d-aab9-ad9126b66f91");
    powerStateCharacteristic = _expect(
        'power-state',
        "9a5900a0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900a1-6e67-5d0d-aab9-ad9126b66f91");
    seatCharacteristic = _expect('seat', "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590022-6e67-5d0d-aab9-ad9126b66f91");
    handlebarCharacteristic = _expect(
        'handlebar',
        "9a590020-6e67-5d0d-aab9-ad9126b66f91",
        "9a590023-6e67-5d0d-aab9-ad9126b66f91");
    auxSOCCharacteristic = _expect(
        'aux-soc',
        "9a590040-6e67-5d0d-aab9-ad9126b66f91",
        "9a590044-6e67-5d0d-aab9-ad9126b66f91");
    auxVoltageCharacteristic = _expect(
        'aux-voltage',
        "9a590040-6e67-5d0d-aab9-ad9126b66f91",
        "9a590041-6e67-5d0d-aab9-ad9126b66f91");
    auxChargingCharacteristic = _expect(
        'aux-charging',
        "9a590040-6e67-5d0d-aab9-ad9126b66f91",
        "9a590043-6e67-5d0d-aab9-ad9126b66f91");
    cbbSOCCharacteristic = _expect(
        'cbb-soc',
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590061-6e67-5d0d-aab9-ad9126b66f91");
    cbbVoltageCharacteristic = _expect(
        'cbb-voltage',
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590065-6e67-5d0d-aab9-ad9126b66f91");
    cbbCapacityCharacteristic = _expect(
        'cbb-capacity',
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590063-6e67-5d0d-aab9-ad9126b66f91");
    cbbChargingCharacteristic = _expect(
        'cbb-charging',
        "9a590060-6e67-5d0d-aab9-ad9126b66f91",
        "9a590072-6e67-5d0d-aab9-ad9126b66f91");
    primaryCyclesCharacteristic = _expect(
        'primary-cycles',
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900e6-6e67-5d0d-aab9-ad9126b66f91");
    primarySOCCharacteristic = _expect(
        'primary-soc',
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900e9-6e67-5d0d-aab9-ad9126b66f91");
    secondaryCyclesCharacteristic = _expect(
        'secondary-cycles',
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900f2-6e67-5d0d-aab9-ad9126b66f91");
    secondarySOCCharacteristic = _expect(
        'secondary-soc',
        "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
        "9a5900f5-6e67-5d0d-aab9-ad9126b66f91");
    nrfVersionCharacteristic = _expect(
        'nrf-version',
        "9a59a000-6e67-5d0d-aab9-ad9126b66f91",
        "9a59a001-6e67-5d0d-aab9-ad9126b66f91");

    if (additionalLibrescootFeatures) {
      imxVersionCharacteristic = _expect(
          'imx-version',
          "9a59a040-6e67-5d0d-aab9-ad9126b66f91",
          "9a59a041-6e67-5d0d-aab9-ad9126b66f91");
      odometerCharacteristic = _expect(
          'odometer',
          "9a59a040-6e67-5d0d-aab9-ad9126b66f91",
          "9a59a042-6e67-5d0d-aab9-ad9126b66f91");
      systemTimeCharacteristic = _expect(
          'system-time',
          "9a59a040-6e67-5d0d-aab9-ad9126b66f91",
          "9a59a043-6e67-5d0d-aab9-ad9126b66f91");
      navigationActiveCharacteristic = _expect(
          'navigation-active',
          "9a59a040-6e67-5d0d-aab9-ad9126b66f91",
          "9a59a044-6e67-5d0d-aab9-ad9126b66f91");
      umsStatusCharacteristic = _expect(
          'ums-status',
          "9a59a040-6e67-5d0d-aab9-ad9126b66f91",
          "9a59a045-6e67-5d0d-aab9-ad9126b66f91");
      extendedCommandCharacteristic = _expect(
          'extended-command',
          "9a590400-6e67-5d0d-aab9-ad9126b66f91",
          "9a590401-6e67-5d0d-aab9-ad9126b66f91");
      extendedResponseCharacteristic = _expect(
          'extended-response',
          "9a590400-6e67-5d0d-aab9-ad9126b66f91",
          "9a590402-6e67-5d0d-aab9-ad9126b66f91");
      otaDataCharacteristic = _expect(
          'ota-data',
          "9a590500-6e67-5d0d-aab9-ad9126b66f91",
          "9a590501-6e67-5d0d-aab9-ad9126b66f91");
      otaControlCharacteristic = _expect(
          'ota-control',
          "9a590500-6e67-5d0d-aab9-ad9126b66f91",
          "9a590502-6e67-5d0d-aab9-ad9126b66f91");
      otaStatusCharacteristic = _expect(
          'ota-status',
          "9a590500-6e67-5d0d-aab9-ad9126b66f91",
          "9a590503-6e67-5d0d-aab9-ad9126b66f91");
      alarmStatusCharacteristic = _expect(
          'alarm-status',
          "9a590220-6e67-5d0d-aab9-ad9126b66f91",
          "9a590221-6e67-5d0d-aab9-ad9126b66f91");
      alarmLastTriggerCharacteristic = _expect(
          'alarm-last-trigger',
          "9a590220-6e67-5d0d-aab9-ad9126b66f91",
          "9a590222-6e67-5d0d-aab9-ad9126b66f91");
      alarmWakeSourcesCharacteristic = _expect(
          'alarm-wake-sources',
          "9a590220-6e67-5d0d-aab9-ad9126b66f91",
          "9a590223-6e67-5d0d-aab9-ad9126b66f91");
    }
    return;
  }

  /// Whether the connected firmware exposes the OTA transfer service.
  bool get otaAvailable =>
      otaDataCharacteristic != null &&
      otaControlCharacteristic != null &&
      otaStatusCharacteristic != null;

  /// Whether the connected firmware exposes the alarm state service.
  bool get alarmAvailable =>
      alarmStatusCharacteristic != null &&
      alarmLastTriggerCharacteristic != null &&
      alarmWakeSourcesCharacteristic != null;

  /// Whether the extended command channel is missing from the discovered table.
  /// Every librescoot firmware exposes it, so a miss is not an old firmware.
  bool get extendedChannelMissing =>
      extendedCommandCharacteristic == null ||
      extendedResponseCharacteristic == null;

  /// Whether every extended command written so far went unanswered.
  bool get extendedChannelSilent =>
      silentExtendedCommands >= 2 && !extendedResponseSeen;

  /// Whether recent extended commands went unanswered, whether or not the
  /// channel answered at some earlier point.
  bool get extendedChannelUnresponsive => consecutiveSilentCommands >= 2;

  bool anyAreNull() {
    return stateCharacteristic == null ||
        powerStateCharacteristic == null ||
        seatCharacteristic == null ||
        handlebarCharacteristic == null ||
        auxSOCCharacteristic == null ||
        cbbSOCCharacteristic == null ||
        cbbChargingCharacteristic == null ||
        primaryCyclesCharacteristic == null ||
        primarySOCCharacteristic == null ||
        secondaryCyclesCharacteristic == null ||
        secondarySOCCharacteristic == null;
  }

  /// Returns why this table is unsafe, or null when its available structure is
  /// usable. The exact CCCD probe detects the known Android handle collision;
  /// it cannot prove freshness for every self-consistent cache. Stock firmware
  /// has no extended channel, so absence of the whole channel is allowed.
  Future<String?> validateGattTable({required bool isAndroid}) async {
    if (anyAreNull()) return 'mandatory characteristics are missing';
    final hasExtendedCommand = extendedCommandCharacteristic != null;
    final hasExtendedResponse = extendedResponseCharacteristic != null;
    if (hasExtendedCommand != hasExtendedResponse) {
      return 'the extended command and response characteristics are incomplete';
    }
    if (!hasExtendedResponse || !isAndroid) return null;

    final response = extendedResponseCharacteristic!;
    final cccd = _cccdOf(response);
    if (cccd == null) {
      return 'the extended response characteristic has no CCCD';
    }
    try {
      final value = await cccd.read();
      if (!_isValidCccdValue(value, response.properties)) {
        return 'the extended response CCCD has an invalid shape or value';
      }
    } catch (e) {
      return 'the extended response CCCD could not be read: $e';
    }
    return null;
  }

  /// Confirms the LE bond on iOS by touching an encrypted characteristic.
  ///
  /// iOS starts pairing only when the app accesses a characteristic whose
  /// permissions need encryption, or when the peripheral sends an SMP Security
  /// Request. The scooter stopped sending that request, so the prompt would
  /// otherwise arrive whenever the fire-and-forget telemetry reads happen to
  /// land, long after the session is announced as ready. Reading a mandatory
  /// encrypted characteristic here makes the prompt part of the connect.
  /// Android has [BluetoothDevice.createBond] and does not use this.
  Future<void> confirmPairing({
    bool Function()? isCurrent,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final characteristic = stateCharacteristic;
    if (characteristic == null) {
      throw StateError('the state characteristic is missing, cannot pair');
    }
    if (isCurrent != null && !isCurrent()) return;
    log.info(
        'Waiting for the system pairing prompt on the state characteristic');
    await characteristic.read(timeout: timeout.inSeconds);
    if (isCurrent != null && !isCurrent()) return;
    log.info('Pairing confirmed');
  }

  void noteStaleGattTable(String detail) {
    if (gattTableMismatch) return;
    log.warning(
        "This phone's Bluetooth table does not match the scooter: $detail");
    gattTableMismatch = true;
  }

  void noteGattRejection(Object error, String operation) {
    if (!isGattTableMismatch(error)) return;
    if (!gattTableMismatch) {
      log.warning(
          "$operation rejected by the local Bluetooth stack, which suggests its cached "
          "attribute table is stale: $error");
    }
    gattTableMismatch = true;
  }

  void noteSilentExtendedCommand() {
    silentExtendedCommands++;
    consecutiveSilentCommands++;
  }

  void noteExtendedResponse() {
    extendedResponseSeen = true;
    consecutiveSilentCommands = 0;
  }

  BluetoothCharacteristic? _expect(
      String label, String serviceUuid, String characteristicUuid) {
    final characteristic =
        findCharacteristic(scooter, serviceUuid, characteristicUuid);
    if (characteristic == null) missingCharacteristics.add(label);
    return characteristic;
  }

  static BluetoothCharacteristic? findCharacteristic(
      BluetoothDevice device, String serviceUuid, String characteristicUuid) {
    try {
      return device.servicesList
          .firstWhere(
              (service) => service.serviceUuid.toString() == serviceUuid)
          .characteristics
          .firstWhere((char) =>
              char.characteristicUuid.toString() == characteristicUuid);
    } catch (e) {
      Logger("findCharacteristic")
          .severe("Characteristic $characteristicUuid not found!");
      return null;
    }
  }
}

final Guid _cccdUuid = Guid('00002902-0000-1000-8000-00805f9b34fb');

BluetoothDescriptor? _cccdOf(BluetoothCharacteristic characteristic) {
  for (final descriptor in characteristic.descriptors) {
    if (descriptor.descriptorUuid == _cccdUuid) return descriptor;
  }
  return null;
}

bool _isValidCccdValue(List<int> value, CharacteristicProperties properties) {
  if (value.length != 2 || value[1] != 0 || (value[0] & ~0x03) != 0) {
    return false;
  }
  if ((value[0] & 0x01) != 0 && !properties.notify) return false;
  if ((value[0] & 0x02) != 0 && !properties.indicate) return false;
  return true;
}

/// Whether a BLE failure means the local stack's cached GATT table is wrong
/// (3 = not permitted, 13 = invalid length).
bool isGattTableMismatch(Object error) {
  if (error is! FlutterBluePlusException) return false;
  if (error.platform != ErrorPlatform.android) return false;
  return error.code == 3 || error.code == 13;
}
