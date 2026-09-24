import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/service/ble_commands.dart';

import '../support/command_transport_fakes.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  final names = <String, String>{};
  final reads = <String>[];
  bool? consent;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    reads.add(key);
    return names[key];
  }

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    reads.add(key);
    return consent;
  }
}

// Run against 17d2e9f before adapting the facade. These app distinctions must
// survive shared navigation: telemetry-based UI, naming, consent and wire codec.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences prefs;
  setUp(() {
    prefs = _Preferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
  });

  test('Unustasis cached name precedes consent and uses six-decimal key', () async {
    prefs.consent = false;
    prefs.names['address_1.123457_2.000000'] = 'My Home';
    final destination = NavDestination(location: const LatLng(1.1234567, 2));
    expect(await destination.ensureNamed(), same(destination));
    expect(destination.name, 'My Home');
    expect(destination.type, SpecialDestinationType.home);
    expect(prefs.reads, ['address_1.123457_2.000000']);
  });

  test('Unustasis denied consent uses coordinates without reverse geocoding', () async {
    prefs.consent = false;
    final destination = NavDestination(location: const LatLng(1, 2));
    await destination.ensureNamed();
    expect(destination.name, '1.0, 2.0');
    expect(destination.type, isNull);
    expect(prefs.reads, ['address_1.000000_2.000000', 'osmConsent']);
  });

  test('Unustasis absent consent keeps reverse geocoding local', () async {
    expect(await GeoHelper.nameFromCoordinates(const LatLng(1, 2)), '1.0, 2.0');
    expect(prefs.reads, ['address_1.000000_2.000000', 'osmConsent']);
  });

  test('absent consent does not send saved scooter coordinates to Nominatim', () async {
    final scooter = SavedScooter(id: 'A', lastLocation: const LatLng(1, 2));
    expect(await GeoHelper.getScooterAddress(scooter), isNull);
    expect(prefs.reads, ['osmConsent']);
  });

  test('Unustasis privacy wiring retains app endpoints and removes saved-record export', () {
    final settings = File('lib/ui/screens/stats/settings_screen.dart').readAsStringSync();
    expect(settings, contains('bool osmConsent = false'));
    expect(settings, contains('prefs.getBool("osmConsent") ?? false'));
    final report = File('lib/domain/log_helper.dart').readAsStringSync();
    expect(report, contains('Saved scooter count:'));
    expect(report, isNot(contains('prefs.getString("savedScooters")')));
    expect(report, contains('oss4unu@freal.de'));
    expect(File('lib/service/sharing_handler.dart').readAsStringSync(),
        contains('prefs.getBool("osmConsent") == true'));
    expect(File('lib/ui/screens/stats/support_screen.dart').readAsStringSync(),
        contains("httpsGet(Uri.parse('https://reunu.github.io/unustasis-data/garages.json'))"));
    expect(File('lib/ui/dialogs/onboarding_popups.dart').readAsStringSync(),
        contains('httpsGet(Uri.parse("https://reunu.github.io/unustasis/notifications.json"))'));
  });

  test('Unustasis sanitization and name inference retain app policy', () {
    expect(GeoHelper.sanitizeName('Büro: Äß é 東京'), 'Buero Aess e ');
    expect(NavDestination(location: const LatLng(1, 2), name: 'home office').type,
        SpecialDestinationType.home);
    expect(NavDestination(location: const LatLng(1, 2), name: '').type, isNull);
    expect(() => NavDestination.fromJson({'latitude': 1, 'longitude': 2, 'type': 'unknown'}), throwsStateError);
  });

  test('favorite wire decoding retains permissive parsing and app inference', () async {
    final device = TransportTestDevice();
    final wire = TransportTestCharacteristic();
    final repo = CharacteristicRepository(device)
      ..extendedCommandCharacteristic = wire
      ..extendedResponseCharacteristic = wire;
    wire.onWrite = (_) async {
      wire.reply('nav:fav:count:3');
      wire.reply('nav:fav:bad:no,coordinates');
      wire.reply('nav:fav:7:1,2,My Home');
      wire.reply('nav:fav:8:3,4,Office, rear');
      wire.reply('nav:fav:9:5,6,');

    };
    final favorites = await listFavDestinationsCommand(device, repo);
    expect(favorites.map((d) => d.name), ['My Home', 'Office, rear', null]);
    expect(favorites.map((d) => d.type), [SpecialDestinationType.home, SpecialDestinationType.work, null]);
    expect(wire.writes.single.command, 'nav:fav:list');
    expect(wire.listeners, 0);
  });

  test('Unustasis navigation uses telemetry plus upstream active destination and opt-in consent', () {
    final source = File('lib/ui/screens/navigation_screen.dart').readAsStringSync();
    expect(source, contains('isNavigating: s.vehicle.navigationActive == true'));
    expect(source, contains('context.watch<ScooterService>().vehicle.navigationActive != true'));
    expect(source, contains('nav_status_active_subtitle'));
    expect(source, contains('activeName: s.activeNavigation?.name'));
    expect(source, contains('service.setPendingNavigation(null)'));
    expect(source, contains('final consent = await prefs.getBool("osmConsent")'));
    expect(source, contains('_osmConsent = consent ?? false'));
    expect(source, contains('if (km <= 100) return true'));
    expect(source, contains('Geolocator.getLastKnownPosition()'));
    expect(source, contains('savedScooter?.cachedDestinations = named'));
    expect(source, contains('on TimeoutException'));
    expect(source, contains('name.contains(\':\')'));
  });
}
