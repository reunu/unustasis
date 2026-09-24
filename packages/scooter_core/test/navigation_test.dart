import 'package:latlong2/latlong.dart';
import 'package:scooter_core/extended_response.dart';
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

  test('route plan commands fit the extended-command budget', () {
    expect(
        addNavStopCommand(NavigationDestination(
            location: const LatLng(52.51, 13.41), name: 'Home')),
        'nav:route:add 52.51,13.41,Home');
    // A long name is truncated so the command stays within the byte budget.
    final long = addNavStopCommand(NavigationDestination(
        location: const LatLng(52.51, 13.41), name: 'x' * 200));
    expect(long.length, lessThanOrEqualTo(100));
    expect(long, startsWith('nav:route:add 52.51,13.41,'));
    expect(removeNavStopCommand(2), 'nav:route:remove 2');
    expect(skipNavStopCommand, 'nav:route:skip');
    expect(listNavPlanCommand, 'nav:route:list');
  });

  test('route plan responses parse', () {
    expect(parseNavPlanCount('nav:route:count:3:1')!.count, 3);
    expect(parseNavPlanCount('nav:route:count:3:1')!.step, 1);
    expect(parseNavPlanCount('nav:route:0:1,2,Home'), isNull);
    expect(parseNavPlanStep('nav:route:count:3:1'), 1);
    expect(parseNavPlanStep('nav:route:count:0:0'), 0);
    expect(parseNavPlanStep('nav:route:0:1,2,Home'), isNull);
    expect(parseNavPlanStep('bad'), isNull);

    final stop = parseNavPlanStop('nav:route:1:52.51,13.41,Home, sweet home');
    expect(stop, isNotNull);
    expect(stop!.location.latitude, 52.51);
    expect(stop.location.longitude, 13.41);
    expect(stop.name, 'Home, sweet home');
    expect(stop.id, '1');
    expect(parseNavPlanStop('nav:route:1:52.51,13.41')!.name, isNull);
    for (final message in [
      'bad',
      'nav:route:1:52.51',
      'nav:route:1:x,13.41',
      'nav:route:count:3:1'
    ]) {
      expect(parseNavPlanStop(message), isNull);
    }
  });

  test('route plan model exposes the current stop and copies deeply', () {
    final plan = NavigationRoutePlan(
      stops: [
        NavigationDestination(
            location: const LatLng(1, 2), name: 'A', id: '0'),
        NavigationDestination(
            location: const LatLng(3, 4), name: 'B', id: '1'),
      ],
      currentStep: 1,
    );
    expect(plan.isEmpty, isFalse);
    expect(plan.currentStop!.id, '1');
    expect(NavigationRoutePlan(stops: const [], currentStep: 0).currentStop,
        isNull);
    expect(
        NavigationRoutePlan(stops: plan.stops, currentStep: 5).currentStop,
        isNull);

    final copy = plan.copy();
    copy.stops.first.name = 'changed';
    expect(plan.stops.first.name, 'A');
  });

  test('route plan list reader consumes the header and every stop', () async {
    final plan = await readNavigationRoutePlan(
      Stream.fromIterable([
        'nav:route:count:3:1',
        'nav:route:0:52.51,13.41,Home',
        'nav:route:1:52.52,13.42',
        'nav:route:2:52.53,13.43,Work',
        'nav:route:99:0,0,ignored',
      ]),
    );
    expect(plan.currentStep, 1);
    expect(plan.stops.map((stop) => stop.id), ['0', '1', '2']);
    expect(plan.stops[1].name, isNull);
    expect(plan.stops[2].name, 'Work');
  });

  test('route plan list reader handles an empty plan', () async {
    final plan = await readNavigationRoutePlan(
        Stream.fromIterable(['nav:route:count:0:0']));
    expect(plan.isEmpty, isTrue);
    expect(plan.currentStep, 0);
  });

  test('route plan list reader rejects a malformed header', () async {
    expect(
      () => readNavigationRoutePlan(Stream.fromIterable(['nav:route:0:1,2'])),
      throwsA(isA<ExtendedResponseFormatException>()),
    );
  });
}
