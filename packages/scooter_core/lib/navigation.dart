import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'actions.dart' show extendedCommandMaxBytes;
import 'extended_response.dart' show ExtendedResponseFormatException;

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

/// An ordered multi-hop route plan and the index of the stop being guided to.
class NavigationRoutePlan {
  const NavigationRoutePlan({required this.stops, required this.currentStep});

  final List<NavigationDestination> stops;
  final int currentStep;

  bool get isEmpty => stops.isEmpty;
  bool get isNotEmpty => stops.isNotEmpty;

  NavigationDestination? get currentStop =>
      currentStep >= 0 && currentStep < stops.length ? stops[currentStep] : null;

  NavigationRoutePlan copy() => NavigationRoutePlan(
      stops: stops.map((stop) => stop.copy()).toList(),
      currentStep: currentStep);
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

/// Appends a stop to the scooter's multi-hop plan. One stop per command: the
/// BLE extended command is capped at 100 bytes, so a whole plan cannot be sent
/// at once.
String addNavStopCommand(NavigationDestination stop) {
  final base =
      'nav:route:add ${stop.location.latitude},${stop.location.longitude}';
  final name = _truncateNavName(base, stop.name);
  return name != null ? '$base,$name' : base;
}

String removeNavStopCommand(int index) => 'nav:route:remove $index';
const String skipNavStopCommand = 'nav:route:skip';
const String listNavPlanCommand = 'nav:route:list';
const String clearNavPlanCommand = 'nav:route:clear';

/// The stop count and current step carried by a `nav:route:count:<n>:<step>`
/// response.
class NavPlanCount {
  const NavPlanCount(this.count, this.step);

  final int count;
  final int step;
}

NavPlanCount? parseNavPlanCount(String message) {
  final parts = message.split(':');
  if (parts.length < 5 ||
      parts[0] != 'nav' ||
      parts[1] != 'route' ||
      parts[2] != 'count') {
    return null;
  }
  final count = int.tryParse(parts[3]);
  final step = int.tryParse(parts[4]);
  if (count == null || step == null) return null;
  return NavPlanCount(count, step);
}

/// Reads the current step out of a `nav:route:count:<n>:<step>` response.
int? parseNavPlanStep(String message) => parseNavPlanCount(message)?.step;

/// Reads a full plan from a `nav:route:list` reply: a
/// `nav:route:count:<n>:<step>` header followed by n
/// `nav:route:<index>:<lat>,<lon>,<name>` entries.
Future<NavigationRoutePlan> readNavigationRoutePlan(Stream<String> stream) async {
  final stops = <NavigationDestination>[];
  int? expected;
  var step = 0;
  await for (final message in stream) {
    if (expected == null) {
      final header = parseNavPlanCount(message);
      if (header == null) {
        throw ExtendedResponseFormatException(
            "expected a route plan header, got '$message'");
      }
      expected = header.count;
      step = header.step;
      if (expected == 0) break;
      continue;
    }
    final stop = parseNavPlanStop(message);
    if (stop != null) stops.add(stop);
    if (stops.length >= expected) break;
  }
  return NavigationRoutePlan(stops: stops, currentStep: step);
}

/// Parses a `nav:route:<index>:<lat>,<lon>,<name>` plan list entry.
NavigationDestination? parseNavPlanStop(String message) {
  final parts = message.split(':');
  if (parts.length < 4 ||
      parts[0] != 'nav' ||
      parts[1] != 'route' ||
      parts[2] == 'count') {
    return null;
  }
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
