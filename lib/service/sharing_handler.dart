import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/location_url_parser.dart';
import '../domain/nav_destination.dart';
import '../geo_helper.dart';
import '../navigation_screen.dart';
import '../scooter_service.dart';

final _log = Logger('SharingHandler');

class SharingHandler with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey;
  final ScooterService service;
  StreamSubscription? _intentSub;
  bool _initialMediaHandled = false;

  /// Guards against concurrent/duplicate processing.
  bool _processing = false;

  SharingHandler({required this.navigatorKey, required this.service});

  void init() {
    WidgetsBinding.instance.addObserver(this);

    // Listen while app is in memory (handles Android warm starts / iOS URL opens)
    _intentSub = FlutterSharingIntent.instance.getMediaStream().listen(
      (List<SharedFile> value) {
        _log.info('getMediaStream fired with ${value.length} files');
        _handleSharedMedia(value);
      },
      onError: (err) => _log.warning('getMediaStream error: $err'),
    );

    // Defer initial media check until after the first frame
    // so the Navigator is ready (handles cold starts)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialMedia();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On iOS, the Share Extension cannot open the host app's URL scheme
    // (extensionContext.open is blocked for Share Extensions). Instead the
    // extension saves data to the shared App Group UserDefaults and dismisses.
    // We pick it up here when the user returns to the app.
    if (state == AppLifecycleState.resumed) {
      _checkResumedMedia();
    }
  }

  Future<void> _checkResumedMedia() async {
    if (_processing) return;
    final value = await FlutterSharingIntent.instance.getInitialSharing();
    if (value.isNotEmpty) {
      _log.info('Picked up pending share on resume: ${value.length} files');
      await _handleSharedMedia(value);
    }
  }

  Future<void> _checkInitialMedia() async {
    if (_initialMediaHandled) return;
    _initialMediaHandled = true;
    _log.info('Checking initial media...');
    final value = await FlutterSharingIntent.instance.getInitialSharing();
    _log.info('getInitialSharing returned ${value.length} files');
    if (value.isNotEmpty) {
      await _handleSharedMedia(value);
    }
  }

  Future<void> _handleSharedMedia(List<SharedFile> files) async {
    if (files.isEmpty) return;

    // Extract text content from shared media
    String? sharedText;
    for (final file in files) {
      _log.info('SharedFile: type=${file.type}, value="${file.value}"');
      if (file.value != null && file.value!.isNotEmpty) {
        sharedText = file.value;
        break;
      }
    }

    if (sharedText == null || sharedText.isEmpty) return;

    // Deduplicate: skip if we're already processing the same share
    if (_processing) {
      _log.info('Already processing a share, skipping duplicate');
      return;
    }
    _processing = true;
    // Clear the plugin's stored data so no second path can re-read it
    FlutterSharingIntent.instance.reset();

    _log.info('Received shared text: $sharedText');

    try {
      // Check if any saved scooter is a Librescoot
      final hasLibrescoot = service.savedScooters.values.any(
        (scooter) => scooter.isLibrescoot == true,
      );

      if (!hasLibrescoot) {
        _showNoLibrescootDialog();
        return;
      }

      final parsed = await LocationUrlParser.parse(sharedText);

      if (parsed != null) {
        // Sanitize the name (replace umlauts/accents, strip non-ASCII).
        // Google Maps URL-path names are already shortened by the parser;
        // other sources (Apple Maps ?q=, geo: labels, context lines) are
        // typically clean short names already.
        String? name = parsed.name;
        if (name != null) {
          name = GeoHelper.sanitizeName(name.trim());
          if (name.isEmpty) name = null;
        }

        // Build NavDestination
        var dest = NavDestination(
          location: parsed.location,
          name: name,
        );
        dest = await dest.ensureNamed();
        _log.info('Parsed destination: ${dest.name} @ ${dest.location}');

        // Open NavigationScreen with the destination for user confirmation
        _pushNavigationScreen(initialDestination: dest);
      } else {
        _log.info('Could not parse location from shared text');
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          Fluttertoast.showToast(
            msg: FlutterI18n.translate(
              // ignore: use_build_context_synchronously
              ctx,
              "share_parse_error",
            ),
            toastLength: Toast.LENGTH_LONG,
          );
        }

        // Open NavigationScreen so the user can search manually
        _pushNavigationScreen();
      }
    } finally {
      _processing = false;
    }
  }

  void _pushNavigationScreen({NavDestination? initialDestination}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // If NavigationScreen is already open, pop it first so we get a fresh
    // instance that shows the confirmation dialog for the new destination.
    bool alreadyOnNavScreen = false;
    nav.popUntil((route) {
      if (route.settings.name == 'navigation') {
        alreadyOnNavScreen = true;
      }
      return true; // don't actually pop
    });
    if (alreadyOnNavScreen) {
      // Pop the existing NavigationScreen, then push a new one
      nav.popUntil((route) => route.settings.name != 'navigation');
    }
    nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'navigation'),
        builder: (context) => NavigationScreen(
          initialDestination: initialDestination,
        ),
      ),
    );
  }

  void _showNoLibrescootDialog() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(FlutterI18n.translate(ctx, "share_no_librescoot_title")),
        content: Text(FlutterI18n.translate(ctx, "share_no_librescoot_body")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(FlutterI18n.translate(ctx, "share_no_librescoot_close")),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse("https://github.com/reunu/unustasis/wiki/Librescoot"),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(FlutterI18n.translate(ctx, "share_no_librescoot_learn_more")),
          ),
        ],
      ),
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSub?.cancel();
  }
}
