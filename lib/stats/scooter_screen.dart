import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_screen.dart';
import '../infrastructure/utils.dart';
import '../onboarding_screen.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';
import '../helper_widgets/color_picker_dialog.dart';

class ScooterScreen extends StatefulWidget {
  const ScooterScreen({
    super.key,
    this.onNavigateBack,
  });

  final VoidCallback? onNavigateBack;

  @override
  State<ScooterScreen> createState() => _ScooterScreenState();
}

class _ScooterScreenState extends State<ScooterScreen> {
  bool _isListView = false;
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
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isListView = prefs.getBool('scooter_list_view_mode') ?? false;
    });
  }

  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isListView = !_isListView;
    });
    await prefs.setBool('scooter_list_view_mode', _isListView);
  }

  Future<void> _handleAddScooter(BuildContext context) async {
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
  }

  List<SavedScooter> sortedScooters(ScooterService service) {
    List<SavedScooter> scooters = service.savedScooters.values.toList();
    scooters.sort((a, b) {
      // Check if either scooter is the connected one
      if (a.id == service.myScooter?.remoteId.toString()) {
        return -1;
      }
      if (b.id == service.myScooter?.remoteId.toString()) {
        return 1;
      }

      // If neither is the connected scooter, sort by lastPing
      return b.lastPing.compareTo(a.lastPing);
    });
    return scooters;
  }

  @override
  Widget build(BuildContext context) {
    final scooterService = context.watch<ScooterService>();
    final scooters = sortedScooters(scooterService);
    final bool single = scooters.length == 1;

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
            onPressed: () => _handleAddScooter(context),
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shrinkWrap: true,
          children: [
            ...scooters.map((scooter) {
              final bool connected = (scooter.id == scooterService.myScooter?.remoteId.toString() &&
                  scooterService.state != ScooterState.disconnected);

              if (_isListView) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: SavedScooterListItem(
                    savedScooter: scooter,
                    single: single,
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
                    single: single,
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
                onPressed: () => _handleAddScooter(context),
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
        ),
      ),
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
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) context.read<ScooterService>().scooterColor = newColor;
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
                  child: Image.asset(
                    "images/scooter/side_${forceHover ? 9 : savedScooter.color}.webp",
                    height: 160,
                  ),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    int? newColor = await showColorDialog(savedScooter.color, savedScooter.name, context);
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
                      future: GeoHelper.getAddress(savedScooter),
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
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                Navigator.of(context).pop(textController.text); // Return the text
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
                                future: GeoHelper.getAddress(savedScooter),
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
}
