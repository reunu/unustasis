import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';

import '../cloud_service.dart';
import '../scooter_service.dart';

class CloudSettingsSection extends StatefulWidget {
  const CloudSettingsSection({super.key});

  @override
  State<CloudSettingsSection> createState() => _CloudSettingsSectionState();
}

class _CloudSettingsSectionState extends State<CloudSettingsSection> {
  final CloudService _cloudService = CloudService();
  bool _isAuthenticated = false;
  String? _cloudScooterId;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

    Future<void> _checkAuthStatus() async {
    final log = Logger('CloudSettings');
    log.info('Checking auth status...');
    
    setState(() {
      _isChecking = true;
    });
    
    try {
      final isAuth = await _cloudService.isAuthenticated;
      log.info('Authentication check result: $isAuth');
      
      setState(() {
        _isAuthenticated = isAuth;
        _isChecking = false;
      });
      log.info('Updated state - authenticated: $_isAuthenticated, cloudId: $_cloudScooterId');
    } catch (e, stack) {
      log.severe('Error checking auth status', e, stack);
      setState(() {
        _isAuthenticated = false;
        _isChecking = false;
      });
    }
  }

  Future<void> _handleCloudLogin() async {
    final log = Logger('CloudSettings');
    // Launch browser for authentication
    final Uri url = Uri.parse('https://sunshine.rescoot.org/account');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      
      // Show dialog to paste token
      if (mounted) {
        log.info('Showing token input dialog');
        final token = await showDialog<String>(
          context: context,
          builder: (BuildContext context) => TokenInputDialog(),
        );

        if (token != null && token.isNotEmpty) {
          log.info('Received token input (length: ${token.length})');
          try {
            log.info('Setting token in cloud service...');
            await _cloudService.setToken(token);
            
            // Force an immediate check of the token by trying to get scooters
            log.info('Testing token by fetching scooters...');
            final scooters = await _cloudService.getScooters();
            log.info('Found ${scooters.length} scooters');
            
            await _checkAuthStatus();
          } catch (e, stack) {
            log.severe('Token validation failed: $e', e, stack);
            if (mounted) {
              Fluttertoast.showToast(msg: 'Invalid token: ${e.toString()}');
              await _cloudService.logout();
              await _checkAuthStatus();
            }
          }
        } else {
          log.info('No token provided or dialog cancelled');
        }
      }
    } else {
      log.warning('Could not launch URL: $url');
    }
  }

  Future<void> _handleCloudLogout() async {
    await _cloudService.logout();
    await _checkAuthStatus();
  }

  Future<void> _handleLinkScooter(BuildContext context) async {
    final scooterService = context.read<ScooterService>();
    final bleId = scooterService.myScooter?.remoteId.toString();
    final scooterName = scooterService.scooterName;
    
    if (bleId == null) {
      Fluttertoast.showToast(msg: 'No scooter connected via BLE');
      return;
    }

    setState(() {
      _isChecking = true;
    });

    try {
      // Create scooter in cloud with BLE ID as VIN
      await _cloudService.createScooter(
        name: scooterName ?? 'My Scooter',
        bleMac: bleId,
      );
      
      // Verify it was created
      await _checkAuthStatus();
      
      if (mounted) {
        Fluttertoast.showToast(msg: 'Scooter linked to cloud');
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: 'Failed to link scooter: ${e.toString()}');
      }
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isChecking)
          const ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text("Checking cloud status..."),
          )
        else if (!_isAuthenticated)
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(FlutterI18n.translate(context, "settings_cloud_connect")),
            subtitle: Text(FlutterI18n.translate(context, "settings_cloud_connect_desc")),
            onTap: _handleCloudLogin,
          )
        else if (_cloudScooterId == null)
          ListTile(
            leading: const Icon(Icons.cloud_queue),
            title: Text(FlutterI18n.translate(context, "settings_cloud_not_linked")),
            subtitle: Text(FlutterI18n.translate(context, "settings_cloud_not_linked_desc")),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkAuthStatus,
            ),
            onTap: () => _handleLinkScooter(context),
          )
        else
          ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(FlutterI18n.translate(context, "settings_cloud_connected")),
            subtitle: Text(FlutterI18n.translate(context, "settings_cloud_connected_desc")),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleCloudLogout,
            ),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(FlutterI18n.translate(context, "cloud_token_cancel")),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(FlutterI18n.translate(context, "cloud_token_save")),
        ),
      ],
    );
  }
}