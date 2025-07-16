import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scooter_service.dart';
import 'stats/scooter_section.dart';
import 'onboarding_screen.dart';

class ScooterScreen extends StatefulWidget {
  const ScooterScreen({super.key});

  @override
  State<ScooterScreen> createState() => _ScooterScreenState();
}

class _ScooterScreenState extends State<ScooterScreen> {
  bool _isListView = false;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isListView = prefs.getBool('scooter_list_view_mode') ?? false;
    });
  }

  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isListView = !_isListView;
    });
    await prefs.setBool('scooter_list_view_mode', _isListView);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_scooter')),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          Consumer<ScooterService>(
            builder: (context, scooterService, child) {
              final scooterCount = scooterService.savedScooters.length;
              if (scooterCount > 1) {
                return IconButton(
                  icon: Icon(_isListView ? Icons.grid_view : Icons.list),
                  onPressed: _toggleViewMode,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final service = context.read<ScooterService>();
              service.myScooter?.disconnect();
              service.myScooter = null;

              List<String> savedIds = await service.getSavedScooterIds();
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) {
                    return OnboardingScreen(
                      excludedScooterIds: savedIds,
                      skipWelcome: true,
                    );
                  },
                ));
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.3,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Selector<ScooterService, DateTime?>(
          selector: (context, service) => service.lastPing,
          builder: (context, lastPing, _) {
            bool dataIsOld = lastPing == null ||
                lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
            return ScooterSection(
              dataIsOld: dataIsOld,
              isListView: _isListView,
              onNavigateBack: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            );
          },
        ),
      ),
    );
  }
}