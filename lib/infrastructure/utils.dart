import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void subscribeCharacteristic(
    BluetoothCharacteristic characteristic, Function(List<int>) onData) async {
  characteristic.setNotifyValue(true);
  characteristic.lastValueStream.listen(onData);
  characteristic.read();
}
