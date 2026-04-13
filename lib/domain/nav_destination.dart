import 'package:latlong2/latlong.dart';

import '../geo_helper.dart';

enum SpecialDestinationType {
  home,
  work,
  school,
}

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

class NavDestination {
  LatLng location;
  String? name;
  String? id;
  SpecialDestinationType? type;

  NavDestination({
    required this.location,
    this.name,
    this.id,
    this.type,
  }) {
    type ??= name != null ? inferTypeFromName(name!) : null;
  }

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

  Map<String, dynamic> toJson() => {
        'latitude': location.latitude,
        'longitude': location.longitude,
        'name': name,
        'id': id,
        'type': type?.name,
      };

  factory NavDestination.fromJson(Map<String, dynamic> map) {
    return NavDestination(
      location: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      name: map['name'],
      id: map['id'],
      type: map['type'] != null ? SpecialDestinationType.values.firstWhere((v) => v.name == map['type']) : null,
    );
  }

  Future<NavDestination> ensureNamed() async {
    if (name != null) return this;
    name = await GeoHelper.nameFromCoordinates(location);
    type ??= inferTypeFromName(name!);
    return this;
  }
}
