import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/cycle_reader.dart';

import '../builder/service.mocks.dart';

@GenerateMocks([BluetoothCharacteristic])
void main() {
  group('CycleReader', () {
    test('converts bytes to number', () async {
      var uint32 = [40, 0, 0, 0];
      var mockCharacteristic = buildCharacterWithState(uint32);

      CycleReader stringReader = CycleReader(ScooterBattery.primary, mockCharacteristic);

      stringReader.readAndSubscribe((result) {
        expect(result, equals(40));
      });

      verify(await mockCharacteristic.setNotifyValue(true)).called(1);
      verify(await mockCharacteristic.read()).called(1);
    });
  });
}

MockBluetoothCharacteristic buildCharacterWithState(List<int> stateAsByteList) {
  MockBluetoothCharacteristic mockCharacteristic =
      MockBluetoothCharacteristic();
  when(mockCharacteristic.setNotifyValue(any))
      .thenAnswer((_) => Future.value(true));
  when(mockCharacteristic.read()).thenAnswer((_) => Future.value([0]));
  when(mockCharacteristic.lastValueStream).thenAnswer((_) {
    return Stream.fromIterable([stateAsByteList]);
  });

  return mockCharacteristic;
}
