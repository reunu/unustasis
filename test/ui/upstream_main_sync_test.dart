import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// The app's geolocator dependency supplies this platform contract.
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/ui/screens/stats/support_screen.dart';

class _Location extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.deniedForever;
  int checks = 0;
  @override
  Future<bool> isLocationServiceEnabled() async {
    checks++;
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
}

class _Garages extends GarageWidget {
  const _Garages(this.garages);
  final List<Garage> garages;
  @override
  Future<List<Garage>> getGarages() async => garages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform previous;
  late _Location location;
  setUp(() {
    previous = GeolocatorPlatform.instance;
    location = _Location();
    GeolocatorPlatform.instance = location;
  });
  tearDown(() => GeolocatorPlatform.instance = previous);

  for (final unavailable in ['disabled', 'denied', 'deniedForever']) {
    test('workshops remain visible when location is $unavailable', () async {
      location.enabled = unavailable != 'disabled';
      location.permission = unavailable == 'denied' ? LocationPermission.denied : LocationPermission.deniedForever;
      final garages = List.generate(
          6,
          (i) => Garage(
                name: 'Garage $i',
                phone: '',
                street: '',
                city: '',
                country: '',
                countryCode: '',
                zipCode: '',
                location: const LatLng(52, 13),
              ));
      final result = await _Garages(garages).getClosestGarages();
      expect(result.map((garage) => garage.name), List.generate(5, (i) => 'Garage $i'));
      expect(result.every((garage) => garage.distance == null), isTrue);
    });
  }
  test('empty workshop result does not request location', () async {
    expect(await _Garages([]).getClosestGarages(), isEmpty);
    expect(location.checks, 0);
  });

  test('upstream UI changes use the refactored owners, not restored legacy transports', () {
    final navigation = File('lib/ui/screens/navigation_screen.dart').readAsStringSync();
    expect(navigation, contains('activeName: s.activeNavigation?.name'));
    expect(navigation, contains('nav_stop_button'));
    expect(navigation, contains('service.navigation.cancel()'));
    expect(navigation, isNot(contains('cancelNavigationCommand')));
    final alarms = File('lib/ui/screens/ls_settings_screen.dart').readAsStringSync();
    expect(alarms, contains('service.alarmAvailable'));
    expect(alarms, contains('service.getAlarmEnabled()'));
    expect(alarms, contains('supportsAlarmControl'));
    expect(alarms, isNot(contains('characteristicRepository')));
    expect(File('lib/navigation_screen.dart').readAsStringSync().trim(), "export 'ui/screens/navigation_screen.dart';");
    expect(
        File('lib/ls_settings_screen.dart').readAsStringSync().trim(), "export 'ui/screens/ls_settings_screen.dart';");
  });
}
