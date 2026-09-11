import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:unustasis/service/location_polling.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  final calls = <String>[];
  Object? failure;

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('enabled');
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    calls.add('position');
    if (failure case final error?) throw error;
    return Position(
      latitude: 52.5,
      longitude: 13.4,
      timestamp: DateTime.utc(2026),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
  }
}

void main() {
  late GeolocatorPlatform previous;
  late _LocationPlatform platform;
  setUp(() {
    previous = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() => GeolocatorPlatform.instance = previous);

  test('disabled service avoids permission and position calls', () async {
    platform.enabled = false;
    expect(await pollLocation(), isNull);
    expect(platform.calls, ['enabled']);
  });

  for (final permission in [LocationPermission.whileInUse, LocationPermission.always]) {
    test('$permission returns coordinates without requesting permission', () async {
      platform.permission = permission;
      final position = await pollLocation();
      expect(position?.latitude, 52.5);
      expect(position?.longitude, 13.4);
      expect(platform.calls, ['enabled', 'permission', 'position']);
    });
  }

  test('denied permission is requested once and granted result is used', () async {
    platform.permission = LocationPermission.denied;
    expect(await pollLocation(), isNotNull);
    expect(platform.calls, ['enabled', 'permission', 'request', 'position']);
  });

  for (final permission in [LocationPermission.denied, LocationPermission.deniedForever]) {
    test('request returning $permission avoids position lookup', () async {
      platform.permission = LocationPermission.denied;
      platform.requestedPermission = permission;
      expect(await pollLocation(), isNull);
      expect(platform.calls, ['enabled', 'permission', 'request']);
    });
  }

  test('permanent denial does not request again', () async {
    platform.permission = LocationPermission.deniedForever;
    expect(await pollLocation(), isNull);
    expect(platform.calls, ['enabled', 'permission']);
  });

  test('platform lookup failures propagate unchanged', () async {
    final error = StateError('location unavailable');
    platform.failure = error;
    await expectLater(pollLocation(), throwsA(same(error)));
  });
}
