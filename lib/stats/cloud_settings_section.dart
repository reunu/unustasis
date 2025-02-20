import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';

import '../cloud_service.dart';
import '../scooter_service.dart';
import '../cloud_scooter_selection_dialog.dart';

class CloudSettingsSection extends StatefulWidget {
  const CloudSettingsSection({super.key});

  @override
  State<CloudSettingsSection> createState() => _CloudSettingsSectionState();
}

class _CloudSettingsSectionState extends State<CloudSettingsSection> {
  final CloudService _cloudService = CloudService();
  bool _isAuthenticated = false;
  List<Map<String, dynamic>> _cloudScooters = [];
  String? _cloudScooterId;
  bool _isLoading = false;
  final log = Logger('CloudSettings');

  @override
  void initState() {
    super.initState();
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

  Future<void> _refreshScooters() async {
    try {
      final scooters = await _cloudService.getScooters();
      setState(() {
        _cloudScooters = scooters;
      });
    } catch (e, stack) {
      log.severe('Error fetching scooters', e, stack);
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, "cloud_refresh_error")
      );
    }
  }

  Future<void> _handleCloudLogin() async {
    // Launch browser for authentication
    final Uri url = Uri.parse('https://sunshine.rescoot.org/account');
    if (await canLaunchUrl(url)) {
      // Show dialog to paste token
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
              msg: FlutterI18n.translate(
                context, 
                "cloud_token_invalid",
                translationParams: {"error": e.toString()}
              )
            );
            await _cloudService.logout();
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
    setState(() {
      _isAuthenticated = false;
      _cloudScooters = [];
      _cloudScooterId = null;
    });
  }

  Future<void> _handleScooterSelection() async {
    final scooterService = context.read<ScooterService>();
    if (scooterService.myScooter == null) {
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, "cloud_no_ble_scooter")
      );
      return;
    }

    // Find current assignments
    final assignments = await _cloudService.getCurrentAssignments();
    
    // Show selection dialog
    showDialog(
      context: context,
      builder: (BuildContext context) => ScooterSelectionDialog(
        scooters: _cloudScooters,
        currentlyAssignedId: _cloudScooterId,
        assignedIds: assignments.values.toList(),
        onSelect: (selectedScooter) async {
          try {
            final bleId = scooterService.myScooter!.remoteId.toString();
            
            // If this scooter was assigned elsewhere, remove that assignment
            if (assignments.containsValue(selectedScooter['id'])) {
              final oldBleId = assignments.entries
                  .firstWhere((entry) => entry.value == selectedScooter['id'])
                  .key;
              await _cloudService.removeAssignment(oldBleId);
            }
            
            // Create new assignment
            await _cloudService.assignScooter(
              bleId: bleId,
              cloudId: selectedScooter['id'],
            );
            
            setState(() {
              _cloudScooterId = selectedScooter['id'];
            });
            
            if (mounted) {
              Fluttertoast.showToast(
                msg: FlutterI18n.translate(
                  context, 
                  "cloud_assignment_success",
                  translationParams: {"name": selectedScooter['name']}
                )
              );
            }
          } catch (e, stack) {
            log.severe('Error assigning scooter: $e', e, stack);
            if (mounted) {
              Fluttertoast.showToast(
                msg: FlutterI18n.translate(
                  context, 
                  "cloud_assignment_error",
                  translationParams: {"error": e.toString()}
                )
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _launchCloudDashboard() async {
    final Uri url = Uri.parse('https://sunshine.rescoot.org/scooters/');
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
        ListTile(
          leading: const Icon(Icons.cloud_queue),
          title: Text(FlutterI18n.translate(context, "cloud_select_scooter")),
          subtitle: Text(_cloudScooterId != null 
            ? FlutterI18n.translate(context, "cloud_scooter_assigned")
            : FlutterI18n.translate(context, "cloud_no_scooter_assigned")
          ),
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