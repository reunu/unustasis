import 'package:flutter/material.dart';

class Analytics extends InheritedWidget {
  const Analytics({
    super.key,
    required super.child,
  });

  static _AnalyticsWidgetState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<Analytics>()!;
  }

  @override
  bool updateShouldNotify(EasyDynamicTheme old) {
    return this != old;
  }
}
