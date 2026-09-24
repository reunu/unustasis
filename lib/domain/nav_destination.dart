import 'package:scooter_core/navigation.dart';
export 'package:scooter_core/navigation.dart' show SpecialDestinationType;

import '../geo_helper.dart';

List<String> homeNames = [
  'home',
  'zuhause',
  'nach hause',
  'heim',
  'casa',
  'domicile',
  'maison',
  'hem',
  'hjem',
  'hogar'
];
List<String> workNames = [
  'work',
  'arbeit',
  'zur arbeit',
  'buero',
  'office',
  'travail',
  'werk',
  'jobb',
  'trabajo',
  'oficina',
  'ufficio'
];
List<String> schoolNames = [
  'school',
  'schule',
  'zur schule',
  'uni',
  'university',
  'hochschule',
  'universitaet',
  'schule',
  'school',
  'ecole',
  'skola',
  'escuela',
  'scuola',
  'universidad'
];

class NavDestination extends NavigationDestination {
  NavDestination({required super.location, super.name, super.id, super.type}) {
    type ??= name != null ? inferTypeFromName(name!) : null;
  }

  factory NavDestination.fromDestination(NavigationDestination destination) => NavDestination(
      location: destination.location, name: destination.name, id: destination.id, type: destination.type);

  SpecialDestinationType? inferTypeFromName(String name) {
    if (homeNames.any((keyword) => name.toLowerCase().contains(keyword))) {
      return SpecialDestinationType.home;
    } else if (workNames.any((keyword) => name.toLowerCase().contains(keyword))) {
      return SpecialDestinationType.work;
    } else if (schoolNames.any((keyword) => name.toLowerCase().contains(keyword))) {
      return SpecialDestinationType.school;
    }
    return null;
  }

  factory NavDestination.fromJson(Map<String, dynamic> map) =>
      NavDestination.fromDestination(NavigationDestination.fromJson(map));

  Future<NavDestination> ensureNamed() async {
    if (name != null) return this;
    name = await GeoHelper.nameFromCoordinates(location);
    type ??= inferTypeFromName(name!);
    return this;
  }
}
