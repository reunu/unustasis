import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../domain/saved_scooter.dart';
import '../features.dart';
import '../helper_widgets/header.dart';
import '../scooter_service.dart';
import 'scooter_screen.dart';

class CloudSettingsSection extends StatefulWidget {
  const CloudSettingsSection({super.key});

  @override
  State<CloudSettingsSection> createState() => _CloudSettingsSectionState();
}

class _CloudSettingsSectionState extends State<CloudSettingsSection> {
  final log = Logger('CloudSettingsSection');
  bool _isCloudEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCloudStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh cloud status when returning from OAuth or other changes
    _loadCloudStatus();
  }

  Future<void> _loadCloudStatus() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final cloudEnabled = await Features.isCloudConnectivityEnabled;
      if (!mounted) return;
      setState(() {
        _isCloudEnabled = cloudEnabled;
      });
      // Auth state lives on ScooterService so the OAuth deep link can publish
      // it; this widget reads it through a Selector in build().
      await context.read<ScooterService>().refreshCloudAuthState();
    } catch (e, stack) {
      log.severe('Failed to load cloud status', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _toggleCloudConnectivity() async {
    final newValue = !_isCloudEnabled;
    await Features.setCloudConnectivityEnabled(newValue);
    await _loadCloudStatus();
  }

  Future<void> _authenticateWithCloud() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cloudService = context.read<ScooterService>().cloudService;
      await cloudService.initiateOAuth();
      // Note: Authentication completion is handled via deep link callback
    } catch (e, stack) {
      log.severe('Failed to authenticate with cloud', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_auth_failed")),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = context.read<ScooterService>();
      await service.cloudService.logout();
      await service.refreshCloudAuthState();
    } catch (e, stack) {
      log.severe('Failed to logout from cloud', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<SavedScooter?> _scooterToLink() async {
    final service = context.read<ScooterService>();
    return service.currentScooter ?? await service.getMostRecentScooter();
  }

  Future<void> _openCloudDashboard() async {
    try {
      final cloudService = context.read<ScooterService>().cloudService;
      await cloudService.openCloudDashboard();
    } catch (e, stack) {
      log.severe('Failed to open cloud dashboard', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_dashboard_failed")),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Header(FlutterI18n.translate(context, "cloud_settings_title")),
        SwitchListTile(
          secondary: const Icon(Icons.cloud_outlined),
          title: Text(FlutterI18n.translate(context, "cloud_connectivity_enable")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_connectivity_description")),
          value: _isCloudEnabled,
          onChanged: (_) => _toggleCloudConnectivity(),
        ),
        if (_isCloudEnabled) ...[
          Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          // Auth state lives on ScooterService so the OAuth deep link can push it
          // here without this widget being rebuilt from scratch.
          Selector<ScooterService, bool>(
            selector: (context, s) => s.isCloudAuthenticated,
            builder: (context, isAuthenticated, _) {
              if (!isAuthenticated) {
                return ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(FlutterI18n.translate(context, "cloud_connect")),
                  subtitle: Text(FlutterI18n.translate(context, "cloud_connect_description")),
                  onTap: _authenticateWithCloud,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_done, color: Colors.green),
                    title: Text(FlutterI18n.translate(context, "cloud_connected")),
                    subtitle: Text(FlutterI18n.translate(context, "cloud_logout_description")),
                    trailing: const Icon(Icons.logout, color: Colors.red),
                    onTap: _logout,
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_browser),
                    title: Text(FlutterI18n.translate(context, "cloud_dashboard")),
                    subtitle: Text(FlutterI18n.translate(context, "cloud_dashboard_description")),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openCloudDashboard,
                  ),
                  // Signing in is only half the setup, and nothing else says so.
                  FutureBuilder<SavedScooter?>(
                    future: _scooterToLink(),
                    builder: (context, snapshot) {
                      final scooter = snapshot.data;
                      if (scooter == null) return const SizedBox.shrink();
                      final linked = scooter.cloudScooterId != null;
                      return ListTile(
                        leading: Icon(linked ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                        title: Text(FlutterI18n.translate(context, linked ? "cloud_linked_to" : "cloud_not_linked")),
                        subtitle: Text(
                          linked
                              ? (scooter.cloudScooterName ?? scooter.name)
                              : FlutterI18n.translate(context, "cloud_link_hint"),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ScooterScreen()),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}