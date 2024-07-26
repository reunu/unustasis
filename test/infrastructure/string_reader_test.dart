import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:unu_app/infrastructure/string_reader.dart';

import '../builder/service.mocks.dart';

@GenerateMocks([BluetoothCharacteristic])
void main() {
  group('StringReader', () {
    test('converts bytes to string', () async {
      var stateAsByteList = [115, 116, 97, 110, 100, 45, 98, 121];
      var mockCharacteristic = buildCharacterWithState(stateAsByteList);

      StringReader stringReader = StringReader('Test', mockCharacteristic);

      stringReader.readAndSubscribe((result) {
        expect(result, equals('stand-by'));
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
