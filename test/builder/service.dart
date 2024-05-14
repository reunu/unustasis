import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'service.mocks.dart';

@GenerateMocks([
  Stream,
  StreamSubscription,
  BluetoothService,
  BluetoothCharacteristic,
])
class StreamMock extends Stream<List<int>> {
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return MockStreamSubscription();
  }
}

class CharacteristicBuilder {
  final BluetoothService bluetoothService;
  final BluetoothDevice bluetoothDevice;
  final ServiceCharacteristicsBuilder serviceCharacteristicsBuilder;
  final String serviceId;

  CharacteristicBuilder(this.bluetoothService, this.bluetoothDevice,
      this.serviceCharacteristicsBuilder, this.serviceId);

  ServiceCharacteristicsBuilder characteristic(String characteristicsId) {
    var characteristics = [bcm(characteristicsId)];
    when(bluetoothService.characteristics).thenReturn(characteristics);
    return serviceCharacteristicsBuilder;
  }

  ServiceCharacteristicsBuilder characteristics(
      List<String> characteristicsId) {
    var characteristics = characteristicsId.map((c) => bcm(c)).toList();
    when(bluetoothService.characteristics).thenReturn(characteristics);
    return serviceCharacteristicsBuilder;
  }

  BluetoothCharacteristic bcm(String characteristicsId) {
    BluetoothCharacteristic bc = MockBluetoothCharacteristic();
    when(bc.remoteId).thenReturn(bluetoothDevice.remoteId);
    when(bc.serviceUuid).thenReturn(Guid(serviceId));
    when(bc.characteristicUuid).thenReturn(Guid(characteristicsId));
    when(bc.device).thenReturn(bluetoothDevice);
    when(bc.setNotifyValue(true)).thenAnswer((_) => Future.value(true));
    when(bc.lastValueStream).thenAnswer((_) => StreamMock());
    when(bc.read()).thenAnswer((_) => Future.value([0]));
    return bc;
  }
}

class ServiceCharacteristicsBuilder {
  final BluetoothDevice bluetoothDevice;
  final List<BluetoothService> bluetoothServiceList = [];

  ServiceCharacteristicsBuilder(this.bluetoothDevice) {
    when(bluetoothDevice.servicesList).thenAnswer((_) => bluetoothServiceList);
  }

  CharacteristicBuilder service(String serviceId) {
    BluetoothService bluetoothService = MockBluetoothService();
    when(bluetoothService.serviceUuid).thenReturn(Guid(serviceId));
    bluetoothServiceList.add(bluetoothService);

    return CharacteristicBuilder(
        bluetoothService, bluetoothDevice, this, serviceId);
  }
}
