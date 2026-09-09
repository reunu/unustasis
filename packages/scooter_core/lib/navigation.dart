import 'package:latlong2/latlong.dart';
import 'actions.dart' show extendedCommandMaxBytes;

enum SpecialDestinationType {
  home,
  work,
  school,
}

/// Wire/storage value only. Name inference and geocoding belong to app adapters.
class NavigationDestination {
  LatLng location;
  String? name;
  String? id;
  SpecialDestinationType? type;

  NavigationDestination(
      {required this.location, this.name, this.id, this.type});

  Map<String, dynamic> toJson() => {
        'latitude': location.latitude,
        'longitude': location.longitude,
        'name': name,
        'id': id,
        'type': type?.name,
      };

  factory NavigationDestination.fromJson(Map<String, dynamic> map) {
    return NavigationDestination(
      location: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      name: map['name'] as String?,
      id: map['id'] as String?,
      type: map['type'] != null
          ? SpecialDestinationType.values
              .firstWhere((v) => v.name == map['type'])
          : null,
    );
  }

  NavigationDestination copy() => NavigationDestination.fromJson(toJson());
}

// Preserve legacy Dart string-length truncation (not UTF-8 byte counting).
String? _truncateNavName(String prefix, String? name) {
  if (name == null || name.isEmpty) return null;
  final available = extendedCommandMaxBytes - prefix.length - 1;
  if (available <= 0) return null;
  return name.length > available ? name.substring(0, available) : name;
}

String navigateDestinationCommand(NavigationDestination destination) {
  final base =
      'nav:dest ${destination.location.latitude},${destination.location.longitude}';
  final name = _truncateNavName(base, destination.name);
  return name != null ? '$base,$name' : base;
}

String saveFavoriteCommand(NavigationDestination destination) {
  if (destination.name == null || destination.name!.isEmpty) {
    throw 'Destination name cannot be empty when storing as favorite';
  }
  final base =
      'nav:fav:add ${destination.location.latitude},${destination.location.longitude}';
  final name = _truncateNavName(base, destination.name) ?? destination.name!;
  return '$base,$name';
}

NavigationDestination? parseFavoriteDestination(String message) {
  final parts = message.split(':');
  if (parts.length < 4) return null;
  final coords = parts[3].split(',');
  if (coords.length < 2) return null;
  final lat = double.tryParse(coords[0]);
  final lon = double.tryParse(coords[1]);
  if (lat == null || lon == null) return null;
  final name = coords.length >= 3 ? coords.sublist(2).join(',') : null;
  return NavigationDestination(
      location: LatLng(lat, lon),
      name: name?.isNotEmpty == true ? name : null,
      id: parts[2]);
}
