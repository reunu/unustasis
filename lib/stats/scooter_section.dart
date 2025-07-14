import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_screen.dart';
import '../stats/stats_screen.dart';
import '../onboarding_screen.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
import '../domain/theme_helper.dart';
import '../domain/color_utils.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';
import '../helper_widgets/color_picker_dialog.dart';
import '../features.dart';
import '../services/image_cache_service.dart';

class ScooterSection extends StatefulWidget {
  const ScooterSection({
    super.key,
    this.isListView = false,
    this.onNavigateBack,
  });

  final bool isListView;
  final VoidCallback? onNavigateBack;

  @override
  State<ScooterSection> createState() => _ScooterSectionState();
}

class _ScooterSectionState extends State<ScooterSection> {
  int color = 1;
  String? nameCache;
  TextEditingController nameController = TextEditingController();
  FocusNode nameFocusNode = FocusNode();

  void setupInitialColor() async {
    int initialColor = await SharedPreferencesAsync().getInt("color") ?? 1;
    setState(() {
      color = initialColor;
    });
  }

  @override
  void initState() {
    super.initState();
    setupInitialColor();
  }

  List<SavedScooter> sortedScooters(BuildContext context) {
    List<SavedScooter> scooters = context.read<ScooterService>().savedScooters.values.toList();
    scooters.sort((a, b) {
      // Check if either scooter is the connected one
      if (a.id == context.read<ScooterService>().myScooter?.remoteId.toString()) {
        return -1;
      }
      if (b.id == context.read<ScooterService>().myScooter?.remoteId.toString()) {
        return 1;
      }

      // If neither is the connected scooter, sort by lastPing
      return b.lastPing.compareTo(a.lastPing);
    });
    return scooters;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shrinkWrap: true,
      children: [
        ...sortedScooters(context).map((scooter) {
          final bool connected = (scooter.id == context.read<ScooterService>().myScooter?.remoteId.toString() &&
              context.select<ScooterService, ScooterState?>((service) => service.state) != ScooterState.disconnected);

          if (widget.isListView) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: SavedScooterListItem(
                savedScooter: scooter,
                single: sortedScooters(context).length == 1,
                connected: connected,
                rebuild: () => setState(() {}),
                onNavigateBack: widget.onNavigateBack,
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: SavedScooterCard(
                savedScooter: scooter,
                single: sortedScooters(context).length == 1,
                connected: connected,
                rebuild: () => setState(() {}),
                onNavigateBack: widget.onNavigateBack,
              ),
            );
          }
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () async {
              ScooterService service = context.read<ScooterService>();
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
            icon: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.surface,
              size: 16,
            ),
            label: Text(
              FlutterI18n.translate(context, "settings_add_scooter").toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }
}

class SavedScooterCard extends StatelessWidget {
  final log = Logger("ScooterSection");
  final bool connected;
  final SavedScooter savedScooter;
  final bool single;
  final void Function() rebuild;
  final VoidCallback? onNavigateBack;
  SavedScooterCard({
    super.key,
    required this.savedScooter,
    required this.connected,
    required this.single,
    required this.rebuild,
    this.onNavigateBack,
  });

  void setColor(int newColor, BuildContext context) async {
    savedScooter.color = newColor;
    // Clear custom color when selecting a predefined color
    if (newColor >= 0) {
      savedScooter.colorHex = null;
      savedScooter.cloudImages = null;
    }
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) {
      context.read<ScooterService>().scooterColor = newColor;
    }
  }

  Future<void> _linkToCloudScooter(BuildContext context) async {
    final cloudService = context.read<ScooterService>().cloudService;
    
    try {
      final cloudScooters = await cloudService.getScooters();
      if (cloudScooters.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(FlutterI18n.translate(context, "cloud_no_scooters")),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      // Check for automatic BLE MAC matching
      final localId = savedScooter.id.toLowerCase();
      Map<String, dynamic>? matchingScooter;
      for (final scooter in cloudScooters) {
        final bleMac = (scooter['ble_mac'] as String?)?.toLowerCase();
        if (bleMac != null && bleMac == localId) {
          matchingScooter = scooter;
          break;
        }
      }

      if (matchingScooter != null && context.mounted) {
        // Show automatic match confirmation dialog
        final shouldAutoLink = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(FlutterI18n.translate(context, "cloud_auto_match_title")),
            content: Text(FlutterI18n.translate(
              context,
              "cloud_auto_match_message",
              translationParams: {
                "cloudName": matchingScooter?['name'] ?? 'Unknown',
                "localName": savedScooter.name,
              },
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(FlutterI18n.translate(context, "cloud_manual_select")),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "cloud_auto_link")),
              ),
            ],
          ),
        );

        if (shouldAutoLink == true) {
          if (context.mounted) {
            await _linkScooter(context, matchingScooter);
          }
          return;
        } else if (shouldAutoLink == false) {
          // User chose manual selection, continue to selection dialog
        } else {
          // User cancelled
          return;
        }
      }

      if (context.mounted) {
        final selectedScooter = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => _CloudScooterSelectionDialog(cloudScooters: cloudScooters),
        );

        if (selectedScooter != null && context.mounted) {
          await _linkScooter(context, selectedScooter);
        }
      }
    } catch (e, stack) {
      log.severe('Failed to link cloud scooter', e, stack);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_link_failed")),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _linkScooter(BuildContext context, Map<String, dynamic> selectedScooter) async {
    final cloudService = context.read<ScooterService>().cloudService;
    
    // Check if data sync is needed
    final cloudName = selectedScooter['name'] as String?;
    final cloudColorName = _getCloudColorName(selectedScooter);
    final localName = savedScooter.name;
    final localColorName = _getLocalColorName(savedScooter);
    
    bool needsSync = false;
    if (cloudName != null && cloudName != localName) needsSync = true;
    if (cloudColorName != localColorName) needsSync = true;
    
    if (needsSync && context.mounted) {
      final syncChoice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(FlutterI18n.translate(context, "cloud_sync_data_title")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(FlutterI18n.translate(context, "cloud_sync_data_message")),
              const SizedBox(height: 16),
              if (cloudName != null && cloudName != localName) ...[
                Text(FlutterI18n.translate(context, "cloud_sync_name_diff")),
                Text('Local: $localName'),
                Text('Cloud: $cloudName'),
                const SizedBox(height: 8),
              ],
              if (cloudColorName != localColorName) ...[
                Text(FlutterI18n.translate(context, "cloud_sync_color_diff")),
                Text('Local: $localColorName'),
                Text('Cloud: $cloudColorName'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('no_sync'),
              child: Text(FlutterI18n.translate(context, "cloud_sync_no_sync")),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('from_cloud'),
              child: Text(FlutterI18n.translate(context, "cloud_sync_from_cloud")),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('to_cloud'),
              child: Text(FlutterI18n.translate(context, "cloud_sync_to_cloud")),
            ),
          ],
        ),
      );
      
      if (syncChoice == null) return; // User cancelled
      
      // Apply sync choice
      if (syncChoice == 'from_cloud' && context.mounted) {
        // Update local scooter with cloud data
        savedScooter.updateFromCloudData(selectedScooter);
      } else if (syncChoice == 'to_cloud') {
        // TODO: Update cloud scooter with local data
      }
    }
    
    await cloudService.assignScooterToDevice(
      selectedScooter['id'], 
      savedScooter.id,
      cloudScooterName: selectedScooter['name'],
    );
    rebuild();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
            context, 
            "cloud_scooter_linked",
            translationParams: {"name": selectedScooter['name'] ?? 'Unknown'},
          )),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _unlinkCloudScooter(BuildContext context) async {
    final cloudService = context.read<ScooterService>().cloudService;
    
    try {
      await cloudService.unassignScooterFromDevice(savedScooter.id);
      rebuild();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_scooter_unlinked")),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stack) {
      log.severe('Failed to unlink cloud scooter', e, stack);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlutterI18n.translate(context, "cloud_unlink_failed")),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            bool showOnboarding = snapshot.data?.getBool("color_onboarded") != true;
            // Check for april fools
            bool forceHover =
                snapshot.data?.getBool("seasonal") == true && DateTime.now().month == 4 && DateTime.now().day == 1;
            return Column(
              children: [
                const SizedBox(height: 4),
                GestureDetector(
                  child: _buildScooterImage(savedScooter, forceHover),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    int? newColor = await showColorDialog(
                        savedScooter.hasCustomColor ? -1 : savedScooter.color,
                        savedScooter.name,
                        context,
                        customColorHex: savedScooter.colorHex);
                    if (newColor != null && context.mounted) {
                      setColor(newColor, context);
                      rebuild();
                    }
                    if (showOnboarding && snapshot.hasData) {
                      snapshot.data!.setBool("color_onboarded", true);
                      rebuild();
                    }
                  },
                ),
                if (showOnboarding)
                  Text(
                    FlutterI18n.translate(context, "settings_color_onboarding"),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
                const SizedBox(height: 4),
                // Scooter name and edit button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 32),
                        Flexible(
                          child: Text(
                            savedScooter.name,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  height: 1.1,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.edit_outlined,
                          size: 20,
                        ),
                      ],
                    ),
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      String? newName = await showRenameDialog(savedScooter.name, context);
                      if (newName != null && newName.isNotEmpty && newName != savedScooter.name && context.mounted) {
                        context.read<ScooterService>().renameSavedScooter(name: newName, id: savedScooter.id);
                        rebuild();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 2),
                // Scooter state or last ping
                connected
                    ? Text(
                        context
                                .select<ScooterService, ScooterState?>((service) => service.state)
                                ?.description(context) ??
                            FlutterI18n.translate(context, "stats_unknown"),
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      )
                    : Text(
                        FlutterI18n.translate(context, "stats_last_ping_toast", translationParams: {
                          "time": savedScooter.lastPing.calculateExactTimeDifferenceInShort(context).toLowerCase()
                        }),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                SizedBox(height: 8),
                BatteryBars(
                  primarySOC: savedScooter.lastPrimarySOC,
                  secondarySOC: savedScooter.lastSecondarySOC,
                  dataIsOld: savedScooter.dataIsOld,
                ),
                const SizedBox(height: 24),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                if (savedScooter.lastLocation != null && !connected)
                  Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 0,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                if (savedScooter.lastLocation != null && !connected)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      FlutterI18n.translate(context, "stats_last_seen_near"),
                    ),
                    subtitle: FutureBuilder<String?>(
                      future: GeoHelper.getAddress(savedScooter.lastLocation!, context),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Text(snapshot.data!);
                        } else {
                          return Text(
                            FlutterI18n.translate(context, "stats_no_location"),
                          );
                        }
                      },
                    ),
                    trailing: const Icon(Icons.exit_to_app_outlined),
                    onTap: () {
                      MapsLauncher.launchCoordinates(
                        savedScooter.lastLocation!.latitude,
                        savedScooter.lastLocation!.longitude,
                      );
                    },
                  ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                if (!single) // only show this if there's more than one scooter
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(FlutterI18n.translate(context, "stats_scooter_auto_connect")),
                    subtitle: Text(savedScooter.autoConnect
                        ? FlutterI18n.translate(context, "stats_scooter_auto_connect_on_description")
                        : FlutterI18n.translate(context, "stats_scooter_auto_connect_off_description")),
                    trailing: Switch(
                      value: savedScooter.autoConnect,
                      onChanged: (value) {
                        savedScooter.autoConnect = value;
                        rebuild();
                      },
                    ),
                  ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text("ID"),
                  subtitle: Text(
                    savedScooter.id,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Cloud linking status as list item
                FutureBuilder<bool>(
                  future: Features.isCloudConnectivityEnabled,
                  builder: (context, cloudSnapshot) {
                    final isCloudEnabled = cloudSnapshot.data ?? false;
                    if (!isCloudEnabled) return const SizedBox.shrink();
                    
                    return FutureBuilder<bool>(
                      future: context.read<ScooterService>().cloudService.isAuthenticated,
                      builder: (context, authSnapshot) {
                        final isAuthenticated = authSnapshot.data ?? false;
                        if (!isAuthenticated) return const SizedBox.shrink();
                        
                        return Column(
                          children: [
                            Divider(
                              indent: 16,
                              endIndent: 16,
                              height: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.1),
                            ),
                            if (savedScooter.cloudScooterId != null)
                              ListTile(
                                title: Text(FlutterI18n.translate(context, "cloud_linked_to")),
                                subtitle: Text(savedScooter.cloudScooterName ?? 'Unknown'),
                                trailing: TextButton(
                                  onPressed: () => _unlinkCloudScooter(context),
                                  child: Text(
                                    FlutterI18n.translate(context, "cloud_unlink"),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            if (savedScooter.cloudScooterId == null)
                              ListTile(
                                title: Text(FlutterI18n.translate(context, "cloud_not_linked")),
                                subtitle: Text(FlutterI18n.translate(context, "cloud_link")),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _linkToCloudScooter(context),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (connected)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                          ),
                          onPressed: () async {
                            ScooterService service = context.read<ScooterService>();
                            service.stopAutoRestart();
                            service.myScooter?.disconnect();
                            service.myScooter = null;
                            rebuild();
                          },
                          icon: const Icon(
                            Icons.close_outlined,
                            size: 16,
                          ),
                          label: Text(
                            FlutterI18n.translate(context, "settings_disconnect").toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (!connected)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                          ),
                          onPressed: () async {
                            try {
                              log.info("Trying to connect to ${savedScooter.id}");
                              // Start the connection but don't wait for it to fully complete
                              // Just initiate it and navigate back immediately
                              context.read<ScooterService>().connectToScooterId(savedScooter.id);

                              if (context.mounted) {
                                // Start auto-restart targeting this specific scooter
                                context.read<ScooterService>().startAutoRestart(targetScooterId: savedScooter.id);
                                rebuild();
                                // Navigate back to main screen after initiating connection
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  onNavigateBack?.call();
                                });
                              }
                            } catch (e, stack) {
                              log.severe("Couldn't connect to ${savedScooter.id}", e, stack);
                              if (context.mounted) {
                                Fluttertoast.showToast(
                                    msg: FlutterI18n.translate((context), "settings_connect_failed",
                                        translationParams: {"name": savedScooter.name}));
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.bluetooth,
                            size: 16,
                          ),
                          label: Text(
                            FlutterI18n.translate(context, "settings_connect").toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                        ),
                        onPressed: () async {
                          bool? forget = await showForgetDialog(context);
                          if (forget == true && context.mounted) {
                            String name = savedScooter.name;
                            context.read<ScooterService>().forgetSavedScooter(savedScooter.id);
                            rebuild();
                            Fluttertoast.showToast(
                                msg: FlutterI18n.translate(
                              context,
                              "forget_alert_success",
                              translationParams: {"name": name},
                            ));
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 16,
                        ),
                        label: Text(
                          FlutterI18n.translate(context, "settings_forget").toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
    );
  }

  Future<String?> showRenameDialog(String initialValue, BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController textController = TextEditingController(text: initialValue);
        FocusNode textFieldNode = FocusNode();

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            FocusScope.of(context).requestFocus(textFieldNode);
          }
        });

        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "stats_name")),
          content: TextField(
            controller: textController,
            focusNode: textFieldNode,
          ),
          actions: [
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context)
                    .pop(textController.text); // Return the text
              },
            ),
          ],
        );
      },
    );
  }

  Future<int?> showColorDialog(
      int initialValue, String scooterName, BuildContext context, {String? customColorHex}) {
    int selectedValue = initialValue;

    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(FlutterI18n.translate(context, "settings_color")),
              const SizedBox(height: 4),
              Text(
                FlutterI18n.translate(context, "settings_color_info"),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          scrollable: true,
          content: Builder(builder: (context) {
            return StatefulBuilder(builder: (context, setState) {
              return Column(
                children: [
                  if (customColorHex != null) ...[
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      value: -1,
                      groupValue: selectedValue,
                      onChanged: null, // Disabled - can't select custom color from here
                      title: Text(FlutterI18n.translate(context, "custom_color")),
                      subtitle: Text(FlutterI18n.translate(context, "custom_color_from_cloud")),
                      secondary: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: ColorUtils.parseHexColor(customColorHex) ?? Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: context.isDarkMode
                                  ? Colors.white
                                  : Colors.black,
                              width: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                  ],
                  _colorRadioTile(
                    colorName: "black",
                    colorValue: 0,
                    color: Colors.black,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "white",
                    colorValue: 1,
                    color: Colors.white,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "green",
                    colorValue: 2,
                    color: Colors.green.shade900,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "gray",
                    colorValue: 3,
                    color: Colors.grey,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "orange",
                    colorValue: 4,
                    color: Colors.deepOrange.shade400,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "red",
                    colorValue: 5,
                    color: Colors.red,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "blue",
                    colorValue: 6,
                    color: Colors.blue,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  if (scooterName == magic("Rpyvcfr"))
                    _colorRadioTile(
                      colorName: "eclipse",
                      colorValue: 7,
                      color: Colors.grey.shade800,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    ),
                  if (scooterName == magic("Xbev"))
                    _colorRadioTile(
                      colorName: "idioteque",
                      colorValue: 8,
                      color: Colors.teal.shade200,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    ),
                  if (scooterName == magic("Ubire"))
                    _colorRadioTile(
                      colorName: "hover",
                      colorValue: 9,
                      color: Colors.lightBlue,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    )
                ],
              );
            });
          }),
          actions: [
            TextButton(
              child:
                  Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context).pop(selectedValue); // Return the text
>>>>>>> decf862 (feat: improve custom color support)
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool?> showForgetDialog(BuildContext context) {
    return showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: Text(FlutterI18n.translate(context, "forget_alert_title")),
            content: Text(FlutterI18n.translate(context, "forget_alert_body")),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(FlutterI18n.translate(context, "forget_alert_cancel")),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(FlutterI18n.translate(context, "forget_alert_confirm")),
              ),
            ],
          );
        });
  }
}

class SavedScooterListItem extends StatelessWidget {
  final log = Logger("ScooterSection");
  final bool connected;
  final SavedScooter savedScooter;
  final bool single;
  final void Function() rebuild;
  final VoidCallback? onNavigateBack;

  SavedScooterListItem({
    super.key,
    required this.savedScooter,
    required this.connected,
    required this.single,
    required this.rebuild,
    this.onNavigateBack,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: !connected
          ? () async {
              try {
                log.info("Trying to connect to ${savedScooter.id}");

                // Start the connection but don't wait for it to fully complete
                // Just initiate it and navigate back immediately
                context.read<ScooterService>().connectToScooterId(savedScooter.id);

                if (context.mounted) {
                  // Start auto-restart targeting this specific scooter
                  context.read<ScooterService>().startAutoRestart(targetScooterId: savedScooter.id);
                  rebuild();
                  // Navigate back to main screen after initiating connection
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onNavigateBack?.call();
                  });
                }
              } catch (e, stack) {
                log.severe("Couldn't connect to ${savedScooter.id}", e, stack);
                if (context.mounted) {
                  Fluttertoast.showToast(
                      msg: FlutterI18n.translate(context, "settings_connect_failed",
                          translationParams: {"name": savedScooter.name}));
                }
              }
            }
          : null,
      onLongPress: () async {
        HapticFeedback.mediumImpact();
        savedScooter.autoConnect = !savedScooter.autoConnect;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedScooter.autoConnect
                  ? FlutterI18n.translate(context, "stats_auto_connect_on")
                  : FlutterI18n.translate(context, "stats_auto_connect_off"),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        rebuild();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          color: Theme.of(context).colorScheme.surfaceContainer,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // First row: Scooter image and name
                Row(
                  children: [
                    // Scooter image - half the current size with connection indicator
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: GestureDetector(
                        onLongPress: () async {
                          HapticFeedback.mediumImpact();
                          int? newColor = await showColorDialog(savedScooter.color, savedScooter.name, context);
                          if (newColor != null && context.mounted) {
                            setColor(newColor, context);
                            rebuild();
                          }
                        },
                        child: SizedBox(
                          height: 80,
                          child: Stack(
                            children: [
                              Image.asset(
                                "images/scooter/side_${savedScooter.color}.webp",
                                height: 80,
                              ),
                              // Green circle indicator for connected scooter
                              if (connected)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name and status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: GestureDetector(
                              onLongPress: () async {
                                HapticFeedback.mediumImpact();
                                String? newName = await showRenameDialog(savedScooter.name, context);
                                if (newName != null &&
                                    newName.isNotEmpty &&
                                    newName != savedScooter.name &&
                                    context.mounted) {
                                  context.read<ScooterService>().renameSavedScooter(name: newName, id: savedScooter.id);
                                  rebuild();
                                }
                              },
                              child: Text(
                                savedScooter.name,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      height: 1.1,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Connection status for connected scooters only
                          if (connected)
                            Text(
                              context
                                      .select<ScooterService, ScooterState?>((service) => service.state)
                                      ?.description(context) ??
                                  FlutterI18n.translate(context, "stats_unknown"),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          // Battery SOC data
                          if (savedScooter.lastPrimarySOC != null || savedScooter.lastSecondarySOC != null) ...[
                            BatteryBars(
                              primarySOC: savedScooter.lastPrimarySOC,
                              secondarySOC: savedScooter.lastSecondarySOC,
                              dataIsOld: savedScooter.dataIsOld,
                              compact: true,
                              alignment: MainAxisAlignment.start,
                            ),
                          ],
                          // Location on separate line (for disconnected scooters)
                          if (!connected && savedScooter.lastLocation != null) ...[
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                MapsLauncher.launchCoordinates(
                                  savedScooter.lastLocation!.latitude,
                                  savedScooter.lastLocation!.longitude,
                                );
                              },
                              child: FutureBuilder<String?>(
                                future: GeoHelper.getAddress(savedScooter.lastLocation!, context),
                                builder: (context, snapshot) {
                                  String locationText = snapshot.hasData
                                      ? snapshot.data!
                                      : FlutterI18n.translate(context, "stats_no_location");
                                  return Text(
                                    locationText,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                          ],
                          // Last seen timestamp at bottom (for disconnected scooters only)
                          if (!connected) ...[
                            const SizedBox(height: 4),
                            Text(
                              "${savedScooter.lastPing.calculateExactTimeDifferenceInShort(context).toLowerCase()} ago",
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Auto-connect indicator in top right corner
            if (savedScooter.autoConnect)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.sync,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void setColor(int newColor, BuildContext context) async {
    savedScooter.color = newColor;
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) context.read<ScooterService>().scooterColor = newColor;
  }

  Future<String?> showRenameDialog(String initialValue, BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController textController = TextEditingController(text: initialValue);
        FocusNode textFieldNode = FocusNode();

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            FocusScope.of(context).requestFocus(textFieldNode);
          }
        });

        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "stats_name")),
          content: TextField(
            controller: textController,
            focusNode: textFieldNode,
          ),
          actions: [
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context).pop(textController.text); // Return the text
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool?> showForgetDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "forget_alert_title")),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(FlutterI18n.translate(context, "forget_alert_body",
                    translationParams: {"name": savedScooter.name})),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(FlutterI18n.translate(context, "forget_alert_cancel")),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "forget_alert_confirm")),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  /// Builds the scooter image widget, handling both local assets and cloud images
  Widget _buildScooterImage(SavedScooter scooter, bool forceHover) {
    if (scooter.hasCustomColor && scooter.cloudImageSide != null) {
      // Use cached cloud image for custom colors (side view for info list)
      return FutureBuilder<File?>(
        future: ImageCacheService().getImage(scooter.cloudImageSide!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.file(
              snapshot.data!,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to color-based placeholder
                return _buildColorPlaceholder(scooter);
              },
            );
          } else if (snapshot.hasError) {
            return _buildColorPlaceholder(scooter);
          } else {
            // Loading state
            return SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(scooter.effectiveColor),
                ),
              ),
            );
          }
        },
      );
    } else {
      // Use local asset image for predefined colors
      return Image.asset(
        "images/scooter/side_${forceHover ? 9 : scooter.color}.webp",
        height: 160,
      );
    }
  }

  /// Builds a color-based placeholder when image fails to load
  Widget _buildColorPlaceholder(SavedScooter scooter) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: scooter.effectiveColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scooter.effectiveColor,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.electric_scooter,
        size: 80,
        color: scooter.effectiveColor,
      ),
    );
  }

  /// Gets human-readable color name from cloud scooter data
  String _getCloudColorName(Map<String, dynamic> cloudData) {
    final cloudColor = cloudData['color'] as String?;
    if (cloudColor == 'custom') {
      final colorHex = cloudData['color_hex'] as String?;
      return colorHex ?? 'Custom color';
    } else {
      final colorId = cloudData['color_id'] as int?;
      return _getColorNameFromId(colorId ?? 1);
    }
  }

  /// Gets human-readable color name from local scooter
  String _getLocalColorName(SavedScooter scooter) {
    if (scooter.hasCustomColor) {
      return scooter.colorHex ?? 'Custom color';
    } else {
      return _getColorNameFromId(scooter.color);
    }
  }

  /// Maps color ID to human-readable name
  String _getColorNameFromId(int colorId) {
    return ColorUtils.getColorName(colorId);
  }
}

class _CloudScooterSelectionDialog extends StatelessWidget {
  final List<Map<String, dynamic>> cloudScooters;

  const _CloudScooterSelectionDialog({required this.cloudScooters});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FlutterI18n.translate(context, "cloud_select_scooter")),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: cloudScooters.length,
          itemBuilder: (context, index) {
            final scooter = cloudScooters[index];
            final name = scooter['name'] ?? 'Unknown';
            final vin = scooter['vin'];
            final isOnline = scooter['online'] == true;
            final images = scooter['images'] as Map<String, dynamic>?;
            final sideImageUrl = images?['right'] ?? images?['left'];
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: sideImageUrl != null
                        ? FutureBuilder<File?>(
                            future: ImageCacheService().getImage(sideImageUrl),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Image.file(
                                  snapshot.data!,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Fallback to color swatch if image fails
                                    final colorHex = scooter['color_hex'] ?? '#FFFFFF';
                                    return Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: ColorUtils.parseHexColor(colorHex) ?? Colors.grey,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                          width: 1,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              } else if (snapshot.hasError) {
                                // Fallback to color swatch if loading fails
                                final colorHex = scooter['color_hex'] ?? '#FFFFFF';
                                return Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: ColorUtils.parseHexColor(colorHex) ?? Colors.grey,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                      width: 1,
                                    ),
                                  ),
                                );
                              } else {
                                // Loading state
                                return SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      ColorUtils.parseHexColor(scooter['color_hex']) ?? Colors.grey,
                                    ),
                                  ),
                                );
                              }
                            },
                          )
                        : Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey.shade400,
                                width: 1,
                              ),
                            ),
                            child: const Icon(Icons.electric_scooter, size: 20),
                          ),
                  ),
                  if (isOnline)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(name),
              subtitle: vin != null ? Text(vin) : null,
              onTap: () => Navigator.of(context).pop(scooter),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
        ),
      ],
    );
  }
}
