import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../control_screen.dart';
import '../features.dart';
import '../scooter_service.dart';

class CloudSettingsSection extends StatefulWidget {
  const CloudSettingsSection({super.key});

  @override
  State<CloudSettingsSection> createState() => _CloudSettingsSectionState();
}

class _CloudSettingsSectionState extends State<CloudSettingsSection> {
  final log = Logger('CloudSettingsSection');
  bool _isCloudEnabled = false;
  bool _isAuthenticated = false;
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
      setState(() {
        _isCloudEnabled = cloudEnabled;
      });

      if (cloudEnabled && mounted) {
        final cloudService = context.read<ScooterService>().cloudService;
        final authenticated = await cloudService.isAuthenticated;
        setState(() {
          _isAuthenticated = authenticated;
        });

      }
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
      final cloudService = context.read<ScooterService>().cloudService;
      await cloudService.logout();
      await _loadCloudStatus();
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
          if (!_isAuthenticated) ...[
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(FlutterI18n.translate(context, "cloud_connect")),
              subtitle: Text(FlutterI18n.translate(context, "cloud_connect_description")),
              onTap: _authenticateWithCloud,
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.cloud_done, color: Colors.green),
              title: Text(FlutterI18n.translate(context, "cloud_connected")),
              subtitle: const Text("Tap to log out"),
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
          ],
        ],
      ],
    );
  }
}