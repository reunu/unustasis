import 'package:scooter_flutter/scooter_flutter.dart' as shared;

import '../domain/saved_scooter.dart';

class ScooterStorage extends shared.ScooterStorage<SavedScooter> {
  ScooterStorage()
      : super(
          decode: SavedScooter.fromJson,
          create: SavedScooter.new,
          defaultName: 'Scooter Pro',
        );
}
