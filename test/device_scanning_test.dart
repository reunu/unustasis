import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unu_app/domain/scooter_state.dart';
import 'package:unu_app/scooter_service.dart';

import 'builder/bluetooth.dart';

final BluetoothBuilder flutterBlueBuilder = BluetoothBuilder();

void main() {
  group("Startup logic test", () {
    setUpAll(() {
      flutterBlueBuilder
          .withDevice('test:id', 'unu Scooter')
          .withServiceCharacteristics()
          .service("9a590000-6e67-5d0d-aab9-ad9126b66f91")
          .characteristic("9a590001-6e67-5d0d-aab9-ad9126b66f91")
          .service("9a590020-6e67-5d0d-aab9-ad9126b66f91")
          .characteristics([
            "9a590021-6e67-5d0d-aab9-ad9126b66f91",
            "9a590022-6e67-5d0d-aab9-ad9126b66f91",
            "9a590023-6e67-5d0d-aab9-ad9126b66f91"
          ])
          .service("9a590060-6e67-5d0d-aab9-ad9126b66f91")
          .characteristic("9a590061-6e67-5d0d-aab9-ad9126b66f91")
          .service("9a5900e0-6e67-5d0d-aab9-ad9126b66f91")
          .characteristics([
            "9a5900e9-6e67-5d0d-aab9-ad9126b66f91",
            "9a5900f2-6e67-5d0d-aab9-ad9126b66f91"
          ]);

      WidgetsFlutterBinding.ensureInitialized();
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'savedScooterId': '',
      });
    });

    test('expect service to be connected', () async {
      ScooterService service = ScooterService(flutterBlueBuilder.build());
      expect((await service.getSystemScooters()).isEmpty, false);
    });
  });
}
