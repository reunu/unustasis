import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:scooter_flutter/scooter_flutter.dart' as shared;
import 'package:shared_preferences/shared_preferences.dart';

class UserSettings extends shared.UserSettings {
  UserSettings({bool isInBackgroundService = false})
      : _isInBackgroundService = isInBackgroundService,
        super(onUpdate: isInBackgroundService ? null : (data) => FlutterBackgroundService().invoke('update', data));

  final bool _isInBackgroundService;
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  bool autoUnlock = false;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;

  @override
  Future<void> restore() async {
    await super.restore();
    autoUnlock = legacyAutoUnlock;
    openSeatOnUnlock = legacyOpenSeatOnUnlock;
    hazardLocking = legacyHazardLocking;
  }

  Future<void> setAutoUnlock(bool enabled) async {
    autoUnlock = enabled;
    await _prefs.setBool('autoUnlock', enabled);
    _notifyBackground({'autoUnlock': enabled});
  }

  Future<void> setOpenSeatOnUnlock(bool enabled) async {
    openSeatOnUnlock = enabled;
    await _prefs.setBool('openSeatOnUnlock', enabled);
    _notifyBackground({'openSeatOnUnlock': enabled});
  }

  Future<void> setHazardLocking(bool enabled) async {
    hazardLocking = enabled;
    await _prefs.setBool('hazardLocking', enabled);
    _notifyBackground({'hazardLocking': enabled});
  }

  void _notifyBackground(Map<String, dynamic> data) {
    if (!_isInBackgroundService) FlutterBackgroundService().invoke('update', data);
  }
}
