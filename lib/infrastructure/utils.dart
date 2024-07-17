import 'package:flutter_blue_plus/flutter_blue_plus.dart';

Future<void> subscribeCharacteristic(
    BluetoothCharacteristic characteristic, Function(List<int>) onData) async {
  await characteristic.setNotifyValue(true);
  characteristic.lastValueStream.listen(onData);
  await characteristic.read();
}
