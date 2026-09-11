/// Mutable persistence contract; implementations own their setter side effects.
abstract interface class SavedScooterRecord {
  String get name;
  set name(String name);

  int get color;
  set color(int color);

  DateTime get lastPing;
  set lastPing(DateTime lastPing);

  bool get autoConnect;
  set autoConnect(bool autoConnect);

  Map<String, dynamic> toJson();
}
