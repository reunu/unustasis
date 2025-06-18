import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:home_widget/home_widget.dart';
import '../scooter_service.dart';
import '../home_screen.dart';
import '../onboarding_screen.dart';
import '../support_screen.dart';
import '../stats/stats_screen.dart';
import '../driving_screen.dart';
import '../control_screen.dart';

// Track if we've handled initial navigation
bool _initialNavigationHandled = false;

final _log = Logger('Router');

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    // Remove splash screen after we've determined the initial route
    if (!_initialNavigationHandled) {
      _initialNavigationHandled = true;
      // Small delay to ensure the redirect is processed
      Future.delayed(const Duration(milliseconds: 100), () {
        FlutterNativeSplash.remove();
      });
    }

    // Only redirect if we're not in debug mode and not already on onboarding
    if (!kDebugMode && state.matchedLocation != '/onboarding') {
      try {
        // Check if there are any saved scooter IDs
        final scooterService = context.read<ScooterService>();
        final savedScooterIds = await scooterService.getSavedScooterIds();
        _log.info("Saved scooters: $savedScooterIds");

        if (savedScooterIds.isEmpty) {
          return '/onboarding';
        }
      } catch (e) {
        _log.warning("Could not check saved scooters during routing", e);
      }
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => HomeScreen(
        forceOpen:
            state.uri.queryParameters['forceOpen']?.toLowerCase() == 'true',
      ),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => OnboardingScreen(),
    ),
    GoRoute(
      path: '/addNew',
      builder: (context, state) {
        return OnboardingScreen(
          skipWelcome: true,
          excludedScooterIds: state.extra as List<String>?,
        );
      },
    ),
    // Routes that should stack on top (use push)
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        GoRoute(
          path: '/support',
          builder: (context, state) => const SupportScreen(),
        ),
        GoRoute(
          path: '/stats',
          builder: (context, state) => const StatsScreen(),
        ),
        GoRoute(
          path: '/driving',
          builder: (context, state) => const DrivingScreen(),
        ),
        GoRoute(
          path: '/control',
          builder: (context, state) => const ControlScreen(),
        ),
      ],
    ),
  ],
);
