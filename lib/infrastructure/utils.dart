import 'package:flutter_blue_plus/flutter_blue_plus.dart';

subscribeCharacteristic(
    BluetoothCharacteristic characteristic, Function(List<int>) callback) {
  characteristic.setNotifyValue(true);
  characteristic.lastValueStream.listen(callback);
  characteristic.read();
}
