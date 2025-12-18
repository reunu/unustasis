import 'package:flutter/widgets.dart';

class GlobalNavigator {
  GlobalNavigator._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;
}
