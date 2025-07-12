import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

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
  List<Map<String, dynamic>> _cloudScooters = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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

        if (authenticated) {
          await _loadCloudScooters();
        }
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

  Future<void> _loadCloudScooters() async {
    try {
      final cloudService = context.read<ScooterService>().cloudService;
      final scooters = await cloudService.getScooters();
      if (mounted) {
        setState(() {
          _cloudScooters = scooters;
        });
      }
    } catch (e, stack) {
      log.severe('Failed to load cloud scooters', e, stack);
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

  Future<void> _assignCloudScooter(int cloudScooterId, String scooterName) async {
    final scooterService = context.read<ScooterService>();
    final currentScooterId = scooterService.myScooter?.remoteId.toString();
    
    if (currentScooterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "cloud_no_local_scooter")),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      final cloudService = scooterService.cloudService;
      await cloudService.assignScooterToDevice(cloudScooterId, currentScooterId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(
              context, 
              "cloud_scooter_assigned",
              translationParams: {"name": scooterName},
            )),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stack) {
      log.severe('Failed to assign cloud scooter', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_assignment_failed")),
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            FlutterI18n.translate(context, "cloud_settings_title"),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SwitchListTile(
          title: Text(FlutterI18n.translate(context, "cloud_connectivity_enable")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_connectivity_description")),
          value: _isCloudEnabled,
          onChanged: (_) => _toggleCloudConnectivity(),
        ),
        if (_isCloudEnabled) ...[
          const Divider(),
          if (!_isAuthenticated) ...[
            ListTile(
              title: Text(FlutterI18n.translate(context, "cloud_connect")),
              subtitle: Text(FlutterI18n.translate(context, "cloud_connect_description")),
              trailing: const Icon(Icons.login),
              onTap: _authenticateWithCloud,
            ),
          ] else ...[
            ListTile(
              title: Text(FlutterI18n.translate(context, "cloud_connected")),
              subtitle: Text(FlutterI18n.translate(context, "cloud_connected_description")),
              trailing: const Icon(Icons.cloud_done, color: Colors.green),
            ),
            ListTile(
              title: Text(FlutterI18n.translate(context, "cloud_dashboard")),
              subtitle: Text(FlutterI18n.translate(context, "cloud_dashboard_description")),
              trailing: const Icon(Icons.open_in_browser),
              onTap: _openCloudDashboard,
            ),
            if (_cloudScooters.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  FlutterI18n.translate(context, "cloud_scooters_title"),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ..._cloudScooters.map((scooter) => ListTile(
                title: Text(scooter['name'] ?? 'Unknown'),
                subtitle: Text('ID: ${scooter['id']}'),
                trailing: ElevatedButton(
                  onPressed: () => _assignCloudScooter(
                    scooter['id'],
                    scooter['name'] ?? 'Unknown',
                  ),
                  child: Text(FlutterI18n.translate(context, "cloud_assign")),
                ),
              )),
            ],
            const Divider(),
            ListTile(
              title: Text(FlutterI18n.translate(context, "cloud_logout")),
              subtitle: Text(FlutterI18n.translate(context, "cloud_logout_description")),
              trailing: const Icon(Icons.logout, color: Colors.red),
              onTap: _logout,
            ),
          ],
        ],
      ],
    );
  }
}