import 'package:latlong2/latlong.dart';
import 'package:scooter_core/navigation.dart';
import 'package:test/test.dart';

void main() {
  test('destination schema, coordinate conversion, defaults and enum ordering',
      () {
    final destination =
        NavigationDestination.fromJson({'latitude': 1, 'longitude': -2});
    expect(destination.toJson(), {
      'latitude': 1.0,
      'longitude': -2.0,
      'name': null,
      'id': null,
      'type': null
    });
    expect(SpecialDestinationType.values.map((v) => v.name),
        ['home', 'work', 'school']);
    for (final type in SpecialDestinationType.values) {
      destination.type = type;
      destination.name = 'Home';
      destination.id = '7';
      expect(destination.copy().toJson(), destination.toJson());
    }
    // Core does not infer presentation labels.
    expect(
        NavigationDestination(location: const LatLng(0, 0), name: 'home').type,
        isNull);
  });
  test('invalid schema and enum remain errors', () {
    for (final json in [
      {'latitude': '1', 'longitude': 2},
      {'latitude': 1, 'longitude': 2, 'type': 'unknown'},
      {'latitude': 1, 'longitude': 2, 'name': 3},
      {'latitude': 1},
    ]) {
      expect(() => NavigationDestination.fromJson(json), throwsA(anything));
    }
  });
  test('coordinate wire commands preserve null and empty names', () {
    final d = NavigationDestination(location: const LatLng(1.25, -2.5));
    expect(navigateDestinationCommand(d), 'nav:dest 1.25,-2.5');
    d.name = '';
    expect(navigateDestinationCommand(d), 'nav:dest 1.25,-2.5');
    expect(() => saveFavoriteCommand(d),
        throwsA('Destination name cannot be empty when storing as favorite'));
    d.name = 'City, Center';
    expect(navigateDestinationCommand(d), 'nav:dest 1.25,-2.5,City, Center');
    expect(saveFavoriteCommand(d), 'nav:fav:add 1.25,-2.5,City, Center');
  });
  test(
      'truncation still counts Dart characters, including split surrogate pairs',
      () {
    final d =
        NavigationDestination(location: const LatLng(1, 2), name: 'é' * 120);
    const navPrefix = 'nav:dest 1.0,2.0,';
    const favPrefix = 'nav:fav:add 1.0,2.0,';
    expect(navigateDestinationCommand(d),
        navPrefix + 'é' * (100 - navPrefix.length));
    expect(saveFavoriteCommand(d), favPrefix + 'é' * (100 - favPrefix.length));
    d.name = 'x' + '😀' * 100;
    final command = saveFavoriteCommand(d);
    expect(command.length, 100);
    expect(command.codeUnitAt(99), 0xd83d);
  });
  test('favorite parser preserves permissive prefix, comma and colon semantics',
      () {
    final d =
        parseFavoriteDestination('nav:fav:abc:1.25,-2.5,Home, Place:ignored')!;
    expect(d.toJson(), {
      'latitude': 1.25,
      'longitude': -2.5,
      'name': 'Home, Place',
      'id': 'abc',
      'type': null
    });
    expect(parseFavoriteDestination('other:prefix:7:1,2')!.id, '7');
    expect(parseFavoriteDestination('nav:fav:7:1,2,')!.name, isNull);
    expect(parseFavoriteDestination('nav:fav:7:1,2')!.name, isNull);
    for (final message in [
      'bad',
      'nav:fav:7:1',
      'nav:fav:7:x,2',
      'nav:fav:7:1,x'
    ]) {
      expect(parseFavoriteDestination(message), isNull);
    }
  });
}
