
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';

import 'device.mocks.dart';
import 'service.dart';

@GenerateMocks([
  AdvertisementData,
  BluetoothDevice,
])

class DeviceBuilder {
  final FlutterBluePlusMockable flutterBluePlus;
  final String remoteId;
  final String advName;
  final BluetoothDevice bluetoothDevice = MockBluetoothDevice();

  DeviceBuilder(this.flutterBluePlus, this.remoteId, this.advName) {
    DeviceIdentifier deviceIdentifier = DeviceIdentifier(remoteId);
    when(bluetoothDevice.remoteId).thenReturn(deviceIdentifier);
    when(bluetoothDevice.advName).thenReturn(advName);
    when(bluetoothDevice.isDisconnected).thenReturn(false);
    // nothing to do here, just empty
    when(bluetoothDevice.discoverServices())
        .thenAnswer((_) => Future.value(<BluetoothService>[]));

    when(flutterBluePlus.systemDevices)
        .thenAnswer((_) => Future.value([bluetoothDevice]));

    AdvertisementData advertisementDataMock = MockAdvertisementData();
    when(flutterBluePlus.onScanResults).thenAnswer((_) {
      return Stream.value([
        ScanResult(
            device: bluetoothDevice,
            advertisementData: advertisementDataMock,
            rssi: 0,
            timeStamp: DateTime.now())
      ]);
    });
  }

  ServiceCharacteristicsBuilder withServiceCharacteristics() {
    return ServiceCharacteristicsBuilder(bluetoothDevice);
  }
}

