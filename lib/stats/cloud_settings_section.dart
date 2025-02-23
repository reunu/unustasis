import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';

import '../cloud_service.dart';
import '../scooter_service.dart';
import '../cloud_scooter_selection_dialog.dart';
import '../components/cloud_scooter_card.dart';

class CloudSettingsSection extends StatefulWidget {
  const CloudSettingsSection({super.key});

  @override
  State<CloudSettingsSection> createState() => _CloudSettingsSectionState();
}

class _CloudSettingsSectionState extends State<CloudSettingsSection> {
  late final CloudService _cloudService;
  bool _isAuthenticated = false;
  List<Map<String, dynamic>> _cloudScooters = [];
  bool _isLoading = false;
  final log = Logger('CloudSettings');

  @override
  void initState() {
    super.initState();
    _cloudService = CloudService(context.read<ScooterService>());
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAuth = await _cloudService.isAuthenticated;
      if (isAuth) {
        await _refreshScooters();
      }

      setState(() {
        _isAuthenticated = isAuth;
        _isLoading = false;
      });
    } catch (e, stack) {
      log.severe('Error checking auth status', e, stack);
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAssignment(int? scooterId) async {
    final service = context.read<ScooterService>();
    if (scooterId != null) {
      service.setCloudScooterId(scooterId);
    }
  }

  Future<void> _refreshScooters() async {
    try {
      final scooters = await _cloudService.getScooters();
      setState(() {
        _cloudScooters = scooters;
      });
    } catch (e, stack) {
      log.severe('Error fetching scooters', e, stack);
      Fluttertoast.showToast(msg: FlutterI18n.translate(context, "cloud_refresh_error"));
    }
  }

  Future<void> _handleCloudLogin() async {
    final Uri url = Uri.parse('https://sunshine.rescoot.org/account');
    if (await canLaunchUrl(url)) {
      final token = await showDialog<String>(
        context: context,
        builder: (BuildContext context) => TokenInputDialog(),
      );

      if (token != null && token.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });

        try {
          await _cloudService.setToken(token);
          await _checkAuthStatus();
        } catch (e, stack) {
          log.severe('Token validation failed', e, stack);
          if (mounted) {
            Fluttertoast.showToast(
                msg: FlutterI18n.translate(context, "cloud_token_invalid", translationParams: {"error": e.toString()}));
            await _cloudService.logout();
            await _saveAssignment(null);
            await _checkAuthStatus();
          }
        }
      }
    } else {
      log.warning('Could not launch URL: $url');
    }
  }

  Future<void> _handleCloudLogout() async {
    await _cloudService.logout();
    await _saveAssignment(null);
    setState(() {
      _isAuthenticated = false;
      _cloudScooters = [];
    });
  }

  Widget _buildLinkedScooterTile() {
    final service = context.read<ScooterService>();
    final currentCloudScooterId = service.getCurrentCloudScooterId();

    if (currentCloudScooterId == null) return Container();

    final scooter = _cloudScooters.firstWhere(
      (s) => s['id'] == currentCloudScooterId,
    );

    return CloudScooterCard(
      scooter: scooter,
      expanded: true,
    );
  }

  Future<void> _handleScooterSelection() async {
    final scooterService = context.read<ScooterService>();
    final currentScooterId = scooterService.currentScooterId;

    if (currentScooterId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FlutterI18n.translate(context, "cloud_no_ble_scooter"))));
      return;
    }

    final assignments = await _cloudService.getCurrentAssignments();
    if (!mounted) return;

    // Get the current cloud scooter ID for this local scooter
    final currentCloudScooterId = assignments[currentScooterId];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => ScooterSelectionDialog(
        scooters: _cloudScooters,
        currentlyAssignedId: currentCloudScooterId,
        assignedIds: assignments.values.toList(),
        onSelect: (selectedScooter) async {
          if (!context.mounted) return;

          try {
            if (assignments.containsValue(selectedScooter['id'])) {
              // Remove the old assignment first
              final oldBleId = assignments.entries.firstWhere((entry) => entry.value == selectedScooter['id']).key;
              await _cloudService.removeAssignment(oldBleId);
            }

            await _cloudService.assignScooter(
              bleId: currentScooterId,
              cloudId: selectedScooter['id'] as int,
            );

            await _saveAssignment(selectedScooter['id'] as int);

            if (!context.mounted) return;
            
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(FlutterI18n.translate(context, "cloud_assignment_success",
                    translationParams: {"name": selectedScooter['name']}))));

            // Refresh the scooter list
            await _refreshScooters();
          } catch (e, stack) {
            log.severe('Error linking scooter: $e', e, stack);
            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  FlutterI18n.translate(context, "cloud_assignment_error", translationParams: {"error": e.toString()})),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          }
        },
      ),
    );
  }

  Future<void> _launchCloudDashboard() async {
    final Uri url = Uri.parse('https://sunshine.rescoot.org/');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text("Checking cloud status..."),
      );
    }

    if (!_isAuthenticated) {
      return ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(FlutterI18n.translate(context, "cloud_connect")),
        subtitle: Text(FlutterI18n.translate(context, "cloud_connect_desc")),
        onTap: _handleCloudLogin,
      );
    }

    return Column(
      children: [
        _buildLinkedScooterTile(),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(FlutterI18n.translate(context, "cloud_select_scooter")),
          subtitle: Text(context.read<ScooterService>().getCurrentCloudScooterId() != null
              ? FlutterI18n.translate(context, "cloud_scooter_linked_to", translationParams: {
                  "name": _cloudScooters.firstWhere(
                      (s) => s['id'] == context.read<ScooterService>().getCurrentCloudScooterId(),
                      orElse: () => {'name': 'Unknown'})['name']
                })
              : FlutterI18n.translate(context, "cloud_no_scooter_linked")),
          onTap: _handleScooterSelection,
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: Text(FlutterI18n.translate(context, "cloud_refresh")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_refresh_desc")),
          onTap: _refreshScooters,
        ),
        ListTile(
          leading: const Icon(Icons.open_in_browser),
          title: Text(FlutterI18n.translate(context, "cloud_open_browser")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_open_browser_desc")),
          onTap: _launchCloudDashboard,
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(FlutterI18n.translate(context, "cloud_logout")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_logout_desc")),
          onTap: _handleCloudLogout,
        ),
      ],
    );
  }
}

class TokenInputDialog extends StatelessWidget {
  final TextEditingController _controller = TextEditingController();

  TokenInputDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FlutterI18n.translate(context, "cloud_token_title")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(FlutterI18n.translate(context, "cloud_token_description")),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: FlutterI18n.translate(context, "cloud_token_label"),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: Text(FlutterI18n.translate(context, "cloud_token_get")),
            onPressed: () async {
              final Uri url = Uri.parse('https://sunshine.rescoot.org/account');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(FlutterI18n.translate(context, "cloud_token_cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(FlutterI18n.translate(context, "cloud_token_save")),
        ),
      ],
    );
  }
}
