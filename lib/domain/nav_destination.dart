import 'package:latlong2/latlong.dart';

class NavDestination {
  LatLng location;
  String? name;
  String? id;

  // TODO: Make sure destination titles contain only characters that the scooter and API can handle (e.g. ascii only, no colons, etc.)

  NavDestination({
    required this.location,
    this.name,
    this.id,
  });

  Map<String, dynamic> toJson() => {
        'latitude': location.latitude,
        'longitude': location.longitude,
        'name': name,
        'id': id,
      };

  factory NavDestination.fromJson(Map<String, dynamic> map) {
    return NavDestination(
      location: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      name: map['name'],
      id: map['id'],
    );
  }
}
