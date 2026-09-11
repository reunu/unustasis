import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/domain/nav_destination.dart';

void main() {
  test('legacy constructor preserves app label inference and explicit type', () {
    for (final entry in {
      'My Home': SpecialDestinationType.home,
      'Office': SpecialDestinationType.work,
      'Universidad': SpecialDestinationType.school
    }.entries) {
      final d = NavDestination(location: const LatLng(1, 2), name: entry.key);
      expect(d.type, entry.value);
    }
    expect(NavDestination(location: const LatLng(1, 2), name: 'Home', type: SpecialDestinationType.work).type,
        SpecialDestinationType.work);
    expect(NavDestination(location: const LatLng(1, 2)).type, isNull);
  });
  test('legacy fromJson retains schema and inferred type when type is absent', () {
    final d = NavDestination.fromJson({'latitude': 1, 'longitude': 2, 'name': 'Home', 'id': '7'});
    expect(d.toJson(), {'latitude': 1.0, 'longitude': 2.0, 'name': 'Home', 'id': '7', 'type': 'home'});
    expect(NavDestination.fromJson(d.toJson()).toJson(), d.toJson());
  });
  test('legacy destination remains mutable and ensureNamed keeps supplied names', () async {
    final d = NavDestination(location: const LatLng(1, 2), name: 'Existing');
    expect(await d.ensureNamed(), same(d));
    d.location = const LatLng(3, 4);
    d.name = 'Other';
    d.id = '8';
    d.type = SpecialDestinationType.school;
    expect(d.toJson(), {'latitude': 3.0, 'longitude': 4.0, 'name': 'Other', 'id': '8', 'type': 'school'});
  });
}
