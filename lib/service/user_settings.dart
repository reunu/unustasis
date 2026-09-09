import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:scooter_flutter/scooter_flutter.dart' as shared;

class UserSettings extends shared.UserSettings {
  UserSettings({bool isInBackgroundService = false})
      : super(
          onUpdate: isInBackgroundService ? null : (data) => FlutterBackgroundService().invoke('update', data),
        );
}
