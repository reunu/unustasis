import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// Intentionally characterize the locked plugin's real Dart implementation
// without adding/changing dependencies or invoking a native/device platform.
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/src/ble/protection_subscription.dart';

final class _Platform extends FlutterBluePlusPlatform {
  final received = StreamController<BmCharacteristicData>.broadcast(sync: true);
  final written = StreamController<BmCharacteristicData>.broadcast(sync: true);
  final descriptorReads =
      StreamController<BmDescriptorData>.broadcast(sync: true);
  final connections =
      StreamController<BmConnectionStateResponse>.broadcast(sync: true);
  final adapters =
      StreamController<BmBluetoothAdapterState>.broadcast(sync: true);
  final descriptors = StreamController<BmDescriptorData>.broadcast(sync: true);
  final reads = <BmReadCharacteristicRequest>[];

  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived => received.stream;
  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten => written.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorRead => descriptorReads.stream;
  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      connections.stream;
  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => adapters.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorWritten => descriptors.stream;
  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
          BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);

  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async {
    descriptors.add(BmDescriptorData(
        remoteId: request.remoteId,
        primaryServiceUuid: request.primaryServiceUuid,
        serviceUuid: request.serviceUuid,
        characteristicUuid: request.characteristicUuid,
        instanceId: request.instanceId,
        descriptorUuid: Guid('2902'),
        value: [1, 0],
        success: true,
        errorCode: 0,
        errorString: ''));
    return true;
  }

  @override
  Future<bool> readCharacteristic(BmReadCharacteristicRequest request) async {
    reads.add(request);
    // Native response deliberately remains pending; notifications travel over
    // the same public event type and can complete the real FBP read Future.
    return true;
  }

  void connection(BluetoothCharacteristic c, bool connected) {
    connections.add(BmConnectionStateResponse(
        remoteId: c.remoteId,
        connectionState: connected
            ? BmConnectionStateEnum.connected
            : BmConnectionStateEnum.disconnected,
        disconnectReasonCode: null,
        disconnectReasonString: null));
  }

  void event(BluetoothCharacteristic c, String value) {
    received.add(BmCharacteristicData(
        remoteId: c.remoteId,
        primaryServiceUuid: c.primaryServiceUuid,
        serviceUuid: c.serviceUuid,
        characteristicUuid: c.characteristicUuid,
        instanceId: c.instanceId,
        value: value.codeUnits,
        success: true,
        errorCode: 0,
        errorString: ''));
  }
}

BluetoothCharacteristic _characteristic(String id) => BluetoothCharacteristic(
    remoteId: DeviceIdentifier(id),
    serviceUuid: Guid('1800'),
    characteristicUuid: Guid('2a00'));
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'real FBP: no cache replay, but notification completes read and delayed '
      'same-identity native delivery remains ambiguous', () async {
    final platform = _Platform();
    FlutterBluePlusPlatform.instance = platform;
    await FlutterBluePlus.isSupported; // initializes real FBP global listeners
    await _flush();
    platform.adapters
        .add(BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on));
    final a = _characteristic('A');
    platform.connection(a, true);
    platform.event(a, 'locked');
    await _flush();
    expect(a.lastValue, 'locked'.codeUnits);
    expect(await a.lastValueStream.first, 'locked'.codeUnits);

    var active = true;
    final values = <String>[];
    final subscription = subscribeProtectionCharacteristic(
        a, (bytes) => values.add(String.fromCharCodes(bytes)),
        isCurrent: () => active);
    await _flush();
    expect(values, isEmpty, reason: 'Protection must not replay FBP cache');
    expect(platform.reads.length, 1);
    platform.event(a, 'unlocked'); // notification, not pending native response
    await _flush();
    expect(values, ['unlocked']);

    // A second real read reaching the platform proves the first read released
    // FBP's global mutex on that notification, not on its native read response.
    final read = a.read();
    await _flush();
    expect(platform.reads.length, 2);
    platform.event(a, 'unlocked');
    expect(await read, 'unlocked'.codeUnits);
    active = false;
    await subscription.cancel();
    platform.connection(a, false);
    platform.connection(a, true);
    final replacement = _characteristic('A');
    final replacementValues = <String>[];
    var replacementActive = true;
    final replacementSubscription = subscribeProtectionCharacteristic(
        replacement,
        (bytes) => replacementValues.add(String.fromCharCodes(bytes)),
        isCurrent: () => replacementActive);
    await _flush();
    expect(replacementValues, isEmpty);
    expect(platform.reads.length, 3);
    platform.event(_characteristic('B'), 'locked');
    await _flush();
    expect(replacementValues, isEmpty, reason: 'Distinct device is isolated');
    // Synthetic retired-source response: native payload has only identity,
    // not a read/notification marker, operation ID, or connection generation.
    platform.event(a, 'locked');
    await _flush();
    expect(replacementValues, ['locked'],
        reason: 'Accepted residual limitation, NOT a freshness assertion');
    replacementActive = false;
    await replacementSubscription.cancel();
    await platform.received.close();
    await platform.written.close();
    await platform.descriptorReads.close();
    await platform.connections.close();
    await platform.adapters.close();
    await platform.descriptors.close();
  });
}
