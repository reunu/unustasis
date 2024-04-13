The [device_scanning_test.dart](device_scanning_test.dart) contains a sample to test the bluetooth functionality of [scooter_service.dart](../lib/scooter_service.dart)

Before first usage, the appropriate mocks need to be generated.
```shell
flutter pub get
dart run build_runner build
```

After that, you can run 
```shell
flutter test test/
```
