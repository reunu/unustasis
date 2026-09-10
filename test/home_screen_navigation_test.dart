import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/navigation_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/battery_state.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/state/vehicle_status.dart';

// No ScooterService constructor, Bluetooth, storage, or background tasks run.
class _NavigationService extends ChangeNotifier implements ScooterService {
  @override
  final identity = ScooterIdentity()..isLibrescoot = true;
  @override
  final vehicle = VehicleStatus();
  @override
  final battery = BatteryState();
  @override
  bool get connected => false;
  @override
  bool get scanning => false;
  @override
  NavDestination? pendingNavigation;
  @override
  Future<SavedScooter?> getMostRecentScooter() async => null;

  void updateNavigation({bool? active, NavDestination? pending}) {
    vehicle.navigationActive = active;
    pendingNavigation = pending;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Preferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NavigationService service;

  setUp(() {
    service = _NavigationService();
    SharedPreferences.setMockInitialValues({});
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previousPreferences);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), null);
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Widget home = const HomeScreen(forceOpen: true),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ScooterService>.value(
        value: service,
        child: EasyDynamicThemeWidget(
          initialThemeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: [
              FlutterI18nDelegate(
                translationLoader: FileTranslationLoader(
                  forcedLocale: const Locale('en'),
                  basePath: 'assets/i18n',
                ),
              ),
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('navigation cue labels its action and reacts to pending and active navigation', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester);

    final cue = find.bySemanticsLabel('Navigation');
    expect(find.text('Navigation'), findsOneWidget);
    expect(tester.getSize(cue).height, greaterThanOrEqualTo(48));
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

    // A queued destination without a display name must still show the dot.
    service.updateNavigation(pending: NavDestination(location: const LatLng(52, 13)));
    await tester.pump();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    expect(
        tester.getSemantics(cue),
        matchesSemantics(
          label: 'Navigation',
          value: 'Pending navigation',
          isButton: true,
          hasTapAction: true,
        ));

    service.updateNavigation(active: true);
    await tester.pump();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    expect(
        tester.getSemantics(cue),
        matchesSemantics(
          label: 'Navigation',
          value: 'Navigation is active',
          isButton: true,
          hasTapAction: true,
        ));

    service.updateNavigation(active: false);
    await tester.pump();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('navigation drawer uses the action sheet style in ${brightness.name} mode', (tester) async {
      await pumpHome(tester, brightness: brightness);
      await tester.tap(find.text('Navigation'));
      await tester.pumpAndSettle();

      expect(tester.widget<NavigationScreen>(find.byType(NavigationScreen)).embedded, isTrue);
      final sheet = find.byType(BottomSheet);
      expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
      final surface =
          tester.widget<Material>(find.descendant(of: sheet, matching: find.byType(Material)).first);
      expect(
          surface.shape,
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ));
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(surface.color, Theme.of(tester.element(sheet)).colorScheme.surfaceContainerLow);
      expect(tester.getSize(sheet).height, closeTo(600 * 0.9, 1));
      final title = find.descendant(of: find.byType(NavigationScreen), matching: find.text('Navigation'));
      expect(tester.getCenter(title).dx, closeTo(tester.getCenter(sheet).dx, 1));
      final close = find.byTooltip('Close');
      expect(tester.getRect(title).right, lessThan(tester.getRect(close).left));
      expect(tester.takeException(), isNull);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('navigation cue and drawer title fit a narrow screen with larger text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHome(tester, textScale: 2);
    expect(find.text('Navigation'), findsOneWidget);
    await tester.tap(find.text('Navigation'));
    await tester.pumpAndSettle();
    final title = find.descendant(of: find.byType(NavigationScreen), matching: find.text('Navigation'));
    expect(tester.getRect(title).right, lessThan(tester.getRect(find.byTooltip('Close')).left));
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(of: find.byType(NavigationScreen), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(0);
    await tester.pump();
    await tester.drag(scrollable, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full-screen navigation retains its app bar and back navigation', (tester) async {
    await pumpHome(tester, home: Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const NavigationScreen(),
          )),
          child: const Text('Open full-screen'),
        ),
      );
    }));
    await tester.tap(find.text('Open full-screen'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationScreen>(find.byType(NavigationScreen)).embedded, isFalse);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Navigation'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deliberate swipe still opens navigation but a short drag does not', (tester) async {
    await pumpHome(tester);
    await tester.drag(find.text('Navigation'), const Offset(0, -35));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsNothing);
    await tester.drag(find.text('Navigation'), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
