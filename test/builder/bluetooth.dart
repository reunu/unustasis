import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:unu_app/flutter/blue_plus_mockable.dart';

import 'bluetooth.mocks.dart';
import 'device.dart';

@GenerateMocks([
  FlutterBluePlusMockable,
])
class BluetoothBuilder {
  final FlutterBluePlusMockable flutterBluePlus = MockFlutterBluePlusMockable();

  DeviceBuilder withDevice(String remoteId, String deviceName) {
    return DeviceBuilder(flutterBluePlus, remoteId, deviceName);
  }

  FlutterBluePlusMockable build() {
    when(flutterBluePlus.isScanning).thenAnswer((_) => Stream.value(true));
    return flutterBluePlus;
  }
}
