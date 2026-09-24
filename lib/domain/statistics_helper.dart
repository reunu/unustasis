import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';
import 'package:scooter_flutter/activity_store.dart';
export 'package:scooter_flutter/activity_store.dart' show LogEntry, EventType, EventSource;

class StatisticsHelper extends ActivityStore {
  StatisticsHelper._internal() : super(
    checkLocationPermission: () async {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    },
    readLocation: () async {
      final position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    },
    locationFailed: (error) => Logger('StatisticsHelper').warning("Couldn't add location to logged event: $error"),
  );
  static final StatisticsHelper _instance = StatisticsHelper._internal();
  factory StatisticsHelper() => _instance;

  // Unustasis has no logging preference: never read the LS-only setting.
  @override
  Future<bool> isEventLoggingEnabled() async => true;

  Future<void> addDemoLogs() async {
    await pendingWrites; // ensure previous writes are flushed
    logEvent(
      eventType: EventType.lock,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.app,
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      soc1: 80,
      soc2: 78,
      location: LatLng(40.7128, -74.0060),
    );
    logEvent(
      eventType: EventType.unlock,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.auto,
      timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 30)),
      soc1: 79,
      soc2: 77,
      location: LatLng(40.7138, -74.0050),
    );
    logEvent(
      eventType: EventType.openSeat,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.background,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      soc1: 78,
      soc2: 76,
      location: LatLng(40.7148, -74.0040),
    );
    logEvent(
      eventType: EventType.lock,
      scooterId: "F1:99:B2:59:94:21",
      source: EventSource.app,
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
      soc1: 85,
      soc2: 100,
      location: LatLng(40.7158, -74.0030),
    );
    await pendingWrites; // wait until all demo logs are written
  }
}
