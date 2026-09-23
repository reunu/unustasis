import 'dart:async';
import 'dart:convert';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nav_destination.dart';

DateTime? _dateTimeFromMicros(Object? value) => value is int ? DateTime.fromMicrosecondsSinceEpoch(value) : null;

String? _normalizeCustomColor(Object? value) {
  if (value is! String) return null;
  final normalized = value.startsWith('#') ? value.substring(1) : value;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return '#${normalized.toUpperCase()}';
}

Map<String, dynamic> _tripCounterToJson(TripCounterSnapshot snapshot) => {
      'distanceMeters': snapshot.distanceMeters,
      'ridingSeconds': snapshot.ridingSeconds,
      'averageSpeedKph': snapshot.averageSpeedKph,
      'resetPolicy': snapshot.resetPolicy.name,
      'lastResetSeconds': snapshot.lastReset?.seconds,
      'lastResetReason': snapshot.lastResetReason.name,
      'generation': snapshot.generation,
      'status': snapshot.status.name,
    };

TripCounterSnapshot? _tripCounterFromJson(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  try {
    final lastReset = value['lastResetSeconds'];
    return TripCounterSnapshot(
      distanceMeters: value['distanceMeters'] as int,
      ridingSeconds: value['ridingSeconds'] as int,
      averageSpeedKph: value['averageSpeedKph'] as int,
      resetPolicy: TripResetPolicy.values.byName(value['resetPolicy'] as String),
      lastReset: lastReset is int ? TripTimestamp(lastReset) : null,
      lastResetReason: TripResetReason.values.byName(value['lastResetReason'] as String),
      generation: value['generation'] as int,
      status: TripCounterStatus.values.byName(value['status'] as String),
    );
  } catch (_) {
    return null;
  }
}

class SavedScooter implements SavedScooterRecord {
  String _name;
  String _id;
  int _color;
  String? _customColor;
  bool _customColorMatte;
  DateTime _lastPing;
  bool _autoConnect;
  bool _autoUnlock;
  bool _keylessPaused;
  bool _hazardLocking;
  bool _openSeatOnUnlock;
  int? _lastPrimarySOC;
  int? _lastSecondarySOC;
  int? _lastCbbSOC;
  int? _lastAuxSOC;
  LatLng? _lastLocation;
  String? _lastAddress;
  bool? _handlebarsLocked;
  bool? _isLibrescoot;
  bool? _supportsHibernateFor;
  bool? _supportsApnConfig;
  bool? _supportsAlarmControl;
  bool? _supportsTripCounter;
  bool? _supportsTripExpunge;
  bool? _supportsScheduledHibernation;
  bool? _supportsBatteryKeepActive;
  int? _cachedOdometerMeters;
  DateTime? _odometerUpdatedAt;
  TripCounterSnapshot? _cachedTripCounter;
  DateTime? _tripCounterUpdatedAt;
  List<NavDestination>? _cachedDestinations;

  SavedScooter({
    required String id,
    String? name,
    int? color,
    String? customColor,
    bool? customColorMatte,
    DateTime? lastPing,
    bool? autoConnect,
    bool? autoUnlock,
    bool? keylessPaused,
    bool? hazardLocking,
    bool? openSeatOnUnlock,
    int? lastPrimarySOC,
    int? lastSecondarySOC,
    int? lastCbbSOC,
    int? lastAuxSOC,
    LatLng? lastLocation,
    String? lastAddress,
    bool? handlebarsLocked,
    bool? isLibrescoot,
    bool? supportsHibernateFor,
    bool? supportsApnConfig,
    bool? supportsAlarmControl,
    bool? supportsTripCounter,
    bool? supportsTripExpunge,
    bool? supportsScheduledHibernation,
    bool? supportsBatteryKeepActive,
    int? cachedOdometerMeters,
    DateTime? odometerUpdatedAt,
    TripCounterSnapshot? cachedTripCounter,
    DateTime? tripCounterUpdatedAt,
    List<NavDestination>? cachedDestinations,
  })  : _name = name ?? "Scooter Pro",
        _id = id,
        _color = color ?? 1,
        _customColor = _normalizeCustomColor(customColor),
        _customColorMatte = customColorMatte ?? true,
        _lastPing = lastPing ?? DateTime.now(),
        _autoConnect = autoConnect ?? true,
        _autoUnlock = autoUnlock ?? false,
        _keylessPaused = keylessPaused ?? false,
        _hazardLocking = hazardLocking ?? false,
        _openSeatOnUnlock = openSeatOnUnlock ?? false,
        _lastPrimarySOC = lastPrimarySOC,
        _lastSecondarySOC = lastSecondarySOC,
        _lastCbbSOC = lastCbbSOC,
        _lastAuxSOC = lastAuxSOC,
        _lastLocation = lastLocation,
        _lastAddress = lastAddress,
        _handlebarsLocked = handlebarsLocked,
        _isLibrescoot = isLibrescoot,
        _supportsHibernateFor = supportsHibernateFor,
        _supportsApnConfig = supportsApnConfig,
        _supportsAlarmControl = supportsAlarmControl,
        _supportsTripCounter = supportsTripCounter,
        _supportsTripExpunge = supportsTripExpunge,
        _supportsScheduledHibernation = supportsScheduledHibernation,
        _supportsBatteryKeepActive = supportsBatteryKeepActive,
        _cachedOdometerMeters = cachedOdometerMeters,
        _odometerUpdatedAt = odometerUpdatedAt,
        _cachedTripCounter = cachedTripCounter,
        _tripCounterUpdatedAt = tripCounterUpdatedAt,
        _cachedDestinations = cachedDestinations;

  @override
  set name(String name) {
    _name = name;
    updateSharedPreferences();
  }

  @override
  set color(int color) {
    _color = color;
    _customColor = null;
    updateSharedPreferences();
  }

  void setCustomColor(String color, {required bool matte}) {
    final normalized = _normalizeCustomColor(color);
    if (normalized == null) throw ArgumentError.value(color, 'color', 'Expected #RRGGBB');
    _customColor = normalized;
    _customColorMatte = matte;
    updateSharedPreferences();
  }

  @override
  set lastPing(DateTime lastPing) {
    _lastPing = lastPing;
    _scheduleTelemetryWrite();
  }

  @override
  set autoConnect(bool autoConnect) {
    _autoConnect = autoConnect;
    updateSharedPreferences();
    FlutterBackgroundService().invoke("update", {"updateSavedScooters": true});
  }

  @override
  set autoUnlock(bool autoUnlock) {
    _autoUnlock = autoUnlock;
    updateSharedPreferences();
    _notifyBackgroundService();
  }

  @override
  set keylessPaused(bool keylessPaused) {
    _keylessPaused = keylessPaused;
    updateSharedPreferences();
    _notifyBackgroundService();
  }

  @override
  set hazardLocking(bool hazardLocking) {
    _hazardLocking = hazardLocking;
    updateSharedPreferences();
    _notifyBackgroundService();
  }

  @override
  set openSeatOnUnlock(bool openSeatOnUnlock) {
    _openSeatOnUnlock = openSeatOnUnlock;
    updateSharedPreferences();
    _notifyBackgroundService();
  }

  set lastPrimarySOC(int? lastPrimarySOC) {
    _lastPrimarySOC = lastPrimarySOC;
    _scheduleTelemetryWrite();
  }

  set lastSecondarySOC(int? lastSecondarySOC) {
    _lastSecondarySOC = lastSecondarySOC;
    _scheduleTelemetryWrite();
  }

  set lastCbbSOC(int? lastCbbSOC) {
    _lastCbbSOC = lastCbbSOC;
    _scheduleTelemetryWrite();
  }

  set lastAuxSOC(int? lastAuxSOC) {
    _lastAuxSOC = lastAuxSOC;
    _scheduleTelemetryWrite();
  }

  set lastLocation(LatLng? lastLocation) {
    _lastLocation = lastLocation;
    _lastAddress = null;
    updateSharedPreferences();
  }

  set lastAddress(String? lastAddress) {
    _lastAddress = lastAddress;
    updateSharedPreferences();
  }

  set handlebarsLocked(bool? handlebarsLocked) {
    _handlebarsLocked = handlebarsLocked;
    _scheduleTelemetryWrite();
  }

  set isLibrescoot(bool? isLibrescoot) {
    _isLibrescoot = isLibrescoot;
    _scheduleTelemetryWrite();
  }

  set supportsHibernateFor(bool? supportsHibernateFor) {
    _supportsHibernateFor = supportsHibernateFor;
    _scheduleTelemetryWrite();
  }

  set supportsApnConfig(bool? supportsApnConfig) {
    _supportsApnConfig = supportsApnConfig;
    _scheduleTelemetryWrite();
  }

  set supportsAlarmControl(bool? supportsAlarmControl) {
    _supportsAlarmControl = supportsAlarmControl;
    _scheduleTelemetryWrite();
  }

  set supportsTripCounter(bool? supportsTripCounter) {
    _supportsTripCounter = supportsTripCounter;
    _scheduleTelemetryWrite();
  }

  set supportsTripExpunge(bool? supportsTripExpunge) {
    _supportsTripExpunge = supportsTripExpunge;
    _scheduleTelemetryWrite();
  }

  set supportsScheduledHibernation(bool? supportsScheduledHibernation) {
    _supportsScheduledHibernation = supportsScheduledHibernation;
    _scheduleTelemetryWrite();
  }

  set supportsBatteryKeepActive(bool? supportsBatteryKeepActive) {
    _supportsBatteryKeepActive = supportsBatteryKeepActive;
    _scheduleTelemetryWrite();
  }

  void cacheOdometer(int meters, {DateTime? updatedAt}) {
    _cachedOdometerMeters = meters;
    _odometerUpdatedAt = updatedAt ?? DateTime.now();
    _scheduleTelemetryWrite();
  }

  void cacheTripCounter(TripCounterSnapshot snapshot, {DateTime? updatedAt}) {
    _cachedTripCounter = snapshot;
    _tripCounterUpdatedAt = updatedAt ?? DateTime.now();
    _scheduleTelemetryWrite();
  }

  set cachedDestinations(List<NavDestination>? cachedDestinations) {
    _cachedDestinations = cachedDestinations;
    updateSharedPreferences();
  }

  @override
  String get name => _name;
  String get id => _id;
  @override
  int get color => _color;
  String? get customColor => _customColor;
  bool get customColorMatte => _customColorMatte;
  bool get hasCustomColor => _customColor != null;
  @override
  DateTime get lastPing => _lastPing;
  @override
  bool get autoConnect => _autoConnect;
  @override
  bool get autoUnlock => _autoUnlock;
  @override
  bool get keylessPaused => _keylessPaused;
  @override
  bool get hazardLocking => _hazardLocking;
  @override
  bool get openSeatOnUnlock => _openSeatOnUnlock;
  int? get lastPrimarySOC => _lastPrimarySOC;
  int? get lastSecondarySOC => _lastSecondarySOC;
  int? get lastCbbSOC => _lastCbbSOC;
  int? get lastAuxSOC => _lastAuxSOC;
  LatLng? get lastLocation => _lastLocation;
  String? get lastAddress => _lastAddress;
  bool? get handlebarsLocked => _handlebarsLocked;
  bool? get isLibrescoot => _isLibrescoot;
  bool? get supportsHibernateFor => _supportsHibernateFor;
  bool? get supportsApnConfig => _supportsApnConfig;
  bool? get supportsAlarmControl => _supportsAlarmControl;
  bool? get supportsTripCounter => _supportsTripCounter;
  bool? get supportsTripExpunge => _supportsTripExpunge;
  bool? get supportsScheduledHibernation => _supportsScheduledHibernation;
  bool? get supportsBatteryKeepActive => _supportsBatteryKeepActive;
  int? get cachedOdometerMeters => _cachedOdometerMeters;
  DateTime? get odometerUpdatedAt => _odometerUpdatedAt;
  TripCounterSnapshot? get cachedTripCounter => _cachedTripCounter;
  DateTime? get tripCounterUpdatedAt => _tripCounterUpdatedAt;
  List<NavDestination>? get cachedDestinations => _cachedDestinations;

  BluetoothDevice get bluetoothDevice => BluetoothDevice.fromId(_id);

  @override
  Map<String, dynamic> toJson() => {
        'id': _id,
        'name': _name,
        'color': _color,
        'customColor': _customColor,
        'customColorMatte': _customColorMatte,
        'lastPing': _lastPing.microsecondsSinceEpoch,
        'autoConnect': _autoConnect,
        'autoUnlock': _autoUnlock,
        'keylessPaused': _keylessPaused,
        'hazardLocking': _hazardLocking,
        'openSeatOnUnlock': _openSeatOnUnlock,
        'lastPrimarySOC': _lastPrimarySOC,
        'lastSecondarySOC': _lastSecondarySOC,
        'lastCbbSOC': _lastCbbSOC,
        'lastAuxSOC': _lastAuxSOC,
        'lastLocation': _lastLocation?.toJson(),
        'lastAddress': _lastAddress,
        'handlebarsLocked': _handlebarsLocked,
        'isLibrescoot': _isLibrescoot,
        'supportsHibernateFor': _supportsHibernateFor,
        'supportsApnConfig': _supportsApnConfig,
        'supportsAlarmControl': _supportsAlarmControl,
        'supportsTripCounter': _supportsTripCounter,
        'supportsTripExpunge': _supportsTripExpunge,
        'supportsScheduledHibernation': _supportsScheduledHibernation,
        'supportsBatteryKeepActive': _supportsBatteryKeepActive,
        'cachedOdometerMeters': _cachedOdometerMeters,
        'odometerUpdatedAt': _odometerUpdatedAt?.microsecondsSinceEpoch,
        'cachedTripCounter': _cachedTripCounter == null ? null : _tripCounterToJson(_cachedTripCounter!),
        'tripCounterUpdatedAt': _tripCounterUpdatedAt?.microsecondsSinceEpoch,
        'cachedDestinations': _cachedDestinations?.map((d) => d.toJson()).toList(),
      };

  factory SavedScooter.fromJson(
    String id,
    Map<String, dynamic> map,
  ) {
    return SavedScooter(
      id: id,
      name: map['name'],
      color: map['color'],
      customColor: map['customColor'],
      customColorMatte: map['customColorMatte'],
      lastPing: map.containsKey('lastPing') ? DateTime.fromMicrosecondsSinceEpoch(map['lastPing']) : DateTime.now(),
      autoConnect: map['autoConnect'],
      autoUnlock: map['autoUnlock'] ?? false,
      keylessPaused: map['keylessPaused'] ?? false,
      hazardLocking: map['hazardLocking'] ?? false,
      openSeatOnUnlock: map['openSeatOnUnlock'] ?? false,
      lastLocation: map['lastLocation'] != null ? LatLng.fromJson(map['lastLocation']) : null,
      lastAddress: map['lastAddress'],
      lastPrimarySOC: map['lastPrimarySOC'],
      lastSecondarySOC: map['lastSecondarySOC'],
      lastCbbSOC: map['lastCbbSOC'],
      lastAuxSOC: map['lastAuxSOC'],
      handlebarsLocked: map['handlebarsLocked'],
      isLibrescoot: map['isLibrescoot'],
      supportsHibernateFor: map['supportsHibernateFor'],
      supportsApnConfig: map['supportsApnConfig'],
      supportsAlarmControl: map['supportsAlarmControl'],
      supportsTripCounter: map['supportsTripCounter'],
      supportsTripExpunge: map['supportsTripExpunge'],
      supportsScheduledHibernation: map['supportsScheduledHibernation'],
      supportsBatteryKeepActive: map['supportsBatteryKeepActive'],
      cachedOdometerMeters: map['cachedOdometerMeters'],
      odometerUpdatedAt: _dateTimeFromMicros(map['odometerUpdatedAt']),
      cachedTripCounter: _tripCounterFromJson(map['cachedTripCounter']),
      tripCounterUpdatedAt: _dateTimeFromMicros(map['tripCounterUpdatedAt']),
      cachedDestinations: (map['cachedDestinations'] as List<dynamic>?)
          ?.map((e) => NavDestination.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The background isolate holds its own copies of the saved scooters and
  /// decides auto-unlock, so it has to hear about these.
  void _notifyBackgroundService() => FlutterBackgroundService().invoke("update", {"updateSavedScooters": true});

  bool get dataIsOld {
    return _lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
  }

  /// Whole-map write, used by deliberate user edits and one-off state that
  /// other processes read back promptly.
  void updateSharedPreferences() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    Map<String, dynamic> savedScooters =
        jsonDecode(await prefs.getString("savedScooters") ?? "{}") as Map<String, dynamic>;
    // A forgotten scooter must not write itself back. Instances outlive the
    // removal: the background isolate holds its own copy and keeps setting
    // lastPing, which resurrected the entry moments after the user forgot it.
    // Adding goes through ScooterStorage.save(), which writes the whole map, so
    // a genuinely new scooter is never lost to this check.
    if (!savedScooters.containsKey(_id)) return;
    savedScooters[_id] = toJson();
    await prefs.setString("savedScooters", jsonEncode(savedScooters));
  }

  void _scheduleTelemetryWrite() => _telemetryWrites.schedule(this);

  /// Writes every scooter with outstanding telemetry. Call this when the app
  /// is leaving the foreground or a session ends, so the coalescing window
  /// cannot swallow the last update.
  static Future<void> flushPendingWrites() => _telemetryWrites.flush();
}

final _TelemetryWriteCoalescer _telemetryWrites = _TelemetryWriteCoalescer();

/// At most one map rewrite per window, however many setters ran.
///
/// Telemetry used to rewrite the whole saved-scooter map on every update, and
/// a single battery packet sets several fields while `ping()` sets `lastPing`
/// on nearly every notification. That put multiple read/decode/encode/write
/// passes of the entire blob on the UI isolate per second while riding. This
/// defers everything inside the window and lets the next telemetry event,
/// [SavedScooter.flushPendingWrites] or app departure carry it out.
///
/// Deliberately not a timer: a debounce would keep widget tests from settling
/// and would leave a window running in the background isolate forever.
class _TelemetryWriteCoalescer {
  static const Duration _window = Duration(seconds: 1);

  final Set<SavedScooter> _dirty = <SavedScooter>{};
  DateTime? _lastWrite;
  Future<void>? _pending;

  void schedule(SavedScooter scooter) {
    _dirty.add(scooter);
    final last = _lastWrite;
    if (last == null || DateTime.now().difference(last) >= _window) {
      unawaited(flush());
    }
  }

  Future<void> flush() async {
    // Serialise read-modify-write cycles; concurrent ones could drop a field.
    await _pending;
    if (_dirty.isEmpty) return;
    final batch = Set<SavedScooter>.of(_dirty);
    _dirty.clear();
    _lastWrite = DateTime.now();
    _pending = _writeTelemetryBatch(batch);
    try {
      await _pending;
    } finally {
      _pending = null;
    }
  }
}

Future<void> _writeTelemetryBatch(Set<SavedScooter> scooters) async {
  final prefs = SharedPreferencesAsync();
  final raw = await prefs.getString("savedScooters");
  if (raw == null) return;
  final stored = jsonDecode(raw) as Map<String, dynamic>;
  var changed = false;
  for (final scooter in scooters) {
    // Same forgotten-scooter guard as the immediate write above.
    if (!stored.containsKey(scooter.id)) continue;
    stored[scooter.id] = scooter.toJson();
    changed = true;
  }
  if (changed) await prefs.setString("savedScooters", jsonEncode(stored));
}
