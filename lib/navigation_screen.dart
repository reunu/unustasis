import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_photon/flutter_photon.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/location_polling.dart';
import '../service/photon_service.dart';
import '../domain/nav_destination.dart';
import '../domain/saved_scooter.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';
import '../service/ble_commands.dart';

class NavigationScreen extends StatefulWidget {
  final NavDestination? initialDestination;
  const NavigationScreen({this.initialDestination, super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  List<NavDestination> _destinations = [];
  bool _loading = false;
  bool _osmConsent = false;
  bool _initialLoad = true;
  bool _showingCached = false;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadOsmConsent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<ScooterService>();
      if (service.connected) {
        _fetchDestinations();
      } else {
        _loadCachedDestinations();
      }
      if (widget.initialDestination != null) {
        _showDestinationConfirmation(widget.initialDestination!);
      }
    });
  }

  Future<void> _loadOsmConsent() async {
    final prefs = SharedPreferencesAsync();
    final consent = await prefs.getBool("osmConsent");
    if (mounted) {
      setState(() => _osmConsent = consent ?? false);
    }
  }

  Future<void> _loadCachedDestinations() async {
    final service = context.read<ScooterService>();
    final savedScooter = await _getCurrentSavedScooter(service);
    final cached = savedScooter?.cachedDestinations;
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() {
        _destinations = cached;
        _showingCached = true;
        _initialLoad = false;
      });
    } else if (mounted) {
      setState(() => _initialLoad = false);
    }
  }

  Future<SavedScooter?> _getCurrentSavedScooter(ScooterService service) async {
    if (service.myScooter != null) {
      final id = service.myScooter!.remoteId.toString();
      if (service.savedScooters.containsKey(id)) {
        return service.savedScooters[id];
      }
    }
    return await service.getMostRecentScooter();
  }

  Future<void> _fetchDestinations() async {
    final service = context.read<ScooterService>();
    if (!service.connected) return;

    setState(() => _loading = true);
    try {
      final favs = await listFavDestinationsCommand(
        service.myScooter!,
        service.characteristicRepository,
      );
      // Ensure every destination has a display name
      final named = await Future.wait(
        favs.map((d) => d.ensureNamed()),
      );
      if (mounted) {
        setState(() {
          _destinations = named;
          _loading = false;
          _initialLoad = false;
          _showingCached = false;
        });
        // Cache the fetched destinations for offline display
        final savedScooter = await _getCurrentSavedScooter(service);
        savedScooter?.cachedDestinations = named;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _initialLoad = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load destinations: $e")),
        );
      }
    }
  }

  /// Returns true if the user confirms (or the check is skipped).
  /// Shows a warning dialog if the destination is >100 km from the
  /// scooter's last known location.
  Future<bool> _confirmIfFarAway(LatLng destination) async {
    final service = context.read<ScooterService>();
    var scooterLocation = service.lastLocation;
    if (scooterLocation == null) {
      // Scooter location not loaded yet (e.g. cold start via share intent).
      // Fall back to the device's last known GPS position.
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          scooterLocation = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}
    }
    if (scooterLocation == null) return true;

    const distCalc = Distance();
    final km = distCalc.as(LengthUnit.Kilometer, scooterLocation, destination);
    if (km <= 100) return true;

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Destination far away"),
            content: Text(
              "This destination is about ${km.round()} km from your scooter's last known location. Continue?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                ),
                child: const Text("Continue"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _navigateToFav(NavDestination destination) async {
    if (!await _confirmIfFarAway(destination.location)) return;
    if (!mounted) return;
    final service = context.read<ScooterService>();
    if (!service.connected) {
      // Queue for when a librescoot connects
      await service.setPendingNavigation(destination);
      return;
    }
    try {
      final success = await navigateFavCommand(
        service.myScooter!,
        service.characteristicRepository,
        destination.id!,
      );
      if (!success) throw "Failed to start navigation.";
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void _showDestinationConfirmation(NavDestination dest) {
    final service = context.read<ScooterService>();
    final isConnected = service.connected;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dest.name ?? 'Unknown destination'),
        content: Text(isConnected
            ? "What would you like to do?"
            : "Navigation will start automatically when you connect to your scooter."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          if (isConnected)
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add),
              label: const Text("Save"),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showSaveDestinationDialog(dest);
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.navigation),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            label: Text(isConnected ? "Navigate" : "Queue navigation"),
            onPressed: () {
              Navigator.of(ctx).pop();
              _navigateToDestination(dest);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToDestination(NavDestination dest) async {
    if (!await _confirmIfFarAway(dest.location)) return;
    if (!mounted) return;
    final service = context.read<ScooterService>();
    if (!service.connected) {
      await service.setPendingNavigation(dest);
      return;
    }
    try {
      final success = await navigateCommand(
        service.myScooter!,
        service.characteristicRepository,
        dest,
      );
      if (!success) throw "Failed to start navigation.";
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  void _showSaveDestinationDialog(NavDestination dest) {
    final nameController = TextEditingController(text: dest.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Save destination"),
          content: TextField(
            controller: nameController,
            autofocus: true,
            onChanged: (_) => setStateDialog(() {}),
            decoration: InputDecoration(
              labelText: "Name",
              errorText: nameController.text.isEmpty ? null : _validateDestName(nameController.text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: _validateDestName(nameController.text) == null
                  ? () {
                      Navigator.of(ctx).pop();
                      _saveNavDestination(dest, nameController.text.trim());
                    }
                  : null,
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNavDestination(NavDestination dest, String name) async {
    final service = context.read<ScooterService>();
    if (name.isEmpty) name = dest.name ?? 'Destination';
    try {
      await saveNavDestinationCommand(
        service.myScooter!,
        service.characteristicRepository,
        NavDestination(location: dest.location, name: name),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name" to favorites')),
        );
        _fetchDestinations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save destination: $e')),
        );
      }
    }
  }

  /// Returns an error string if [name] contains characters invalid for BLE
  /// destination names (non-printable ASCII or colon), null if valid.
  static String? _validateDestName(String name) {
    if (name.trim().isEmpty) return 'Name cannot be empty';
    if (name.contains(':')) return 'Name cannot contain colons';
    if (RegExp(r'[^\x20-\x7E]').hasMatch(name)) return 'Name contains invalid characters';
    return null;
  }

  void _showRenameFavDialog(NavDestination destination) {
    final nameController = TextEditingController(text: destination.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Rename destination"),
          content: TextField(
            controller: nameController,
            autofocus: true,
            onChanged: (_) => setStateDialog(() {}),
            decoration: InputDecoration(
              labelText: "Name",
              errorText: nameController.text.isEmpty ? null : _validateDestName(nameController.text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: _validateDestName(nameController.text) == null
                  ? () async {
                      final newName = nameController.text.trim();
                      Navigator.of(ctx).pop();
                      await _renameFav(destination, newName);
                    }
                  : null,
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFav(NavDestination destination, String newName) async {
    final service = context.read<ScooterService>();
    try {
      // Delete old entry, then re-add with new name
      await deleteFavDestinationCommand(
        service.myScooter!,
        service.characteristicRepository,
        destination.id!,
      );
      await saveNavDestinationCommand(
        service.myScooter!,
        service.characteristicRepository,
        NavDestination(location: destination.location, name: newName),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Renamed to \"$newName\"")),
        );
        _fetchDestinations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to rename: $e")),
        );
      }
    }
  }

  Future<bool> _confirmDeleteFav(NavDestination destination) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete destination"),
            content: Text("Remove \"${destination.name}\" from saved destinations?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Delete"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteFav(NavDestination destination) async {
    final service = context.read<ScooterService>();
    // Optimistically remove from list immediately
    setState(() => _destinations.remove(destination));
    try {
      await deleteFavDestinationCommand(
        service.myScooter!,
        service.characteristicRepository,
        destination.id!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("\"${destination.name}\" removed")),
        );
        // Update cache with the current list (destination already removed)
        final savedScooter = await _getCurrentSavedScooter(service);
        savedScooter?.cachedDestinations = _destinations;
      }
    } catch (e) {
      // Restore on failure
      if (mounted) {
        setState(() => _destinations.add(destination));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete: $e")),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteFav(NavDestination destination) async {
    if (await _confirmDeleteFav(destination)) {
      _deleteFav(destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.select<ScooterService, bool>((s) => s.connected);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Navigation"),
        forceMaterialTransparency: true,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: _osmConsent &&
              context.watch<ScooterService>().pendingNavigation == null &&
              context.watch<ScooterService>().vehicle.navigationActive != true
          ? FloatingActionButton(
              onPressed: () => _searchFocusNode.requestFocus(),
              tooltip: "Search for an address",
              child: Icon(
                Icons.navigation_outlined,
                color: Theme.of(context).colorScheme.surface,
              ),
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              if (_osmConsent) _searchField(),
              const SizedBox(height: 8),
              if (_loading && _initialLoad)
                const Expanded(child: _DestinationsLoading())
              else if (_destinations.isEmpty && !connected && !_showingCached)
                const Expanded(child: _DisconnectedEmpty())
              else if (_destinations.isEmpty)
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchDestinations,
                    child: const _NoDestinationsEmpty(),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchDestinations,
                    child: _destinationList(connected),
                  ),
                ),
            ],
          ),
          Selector<ScooterService, ({String? pendingName, bool isNavigating})>(
            selector: (_, s) => (
              pendingName: s.pendingNavigation?.name,
              isNavigating: s.vehicle.navigationActive == true,
            ),
            builder: (context, state, _) {
              if (state.pendingName == null && !state.isNavigating) return const SizedBox.shrink();
              return Positioned(
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
                left: 16,
                right: 16,
                child: _navigationStatusCard(
                  isNavigating: state.isNavigating,
                  pendingName: state.pendingName,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _PhotonAutocomplete(
        onSelected: (feature) {
          final dest = NavDestination(
            location: LatLng(feature.coordinates.latitude.toDouble(), feature.coordinates.longitude.toDouble()),
            name: GeoHelper.nameFromFeature(feature),
          );
          _showDestinationConfirmation(dest);
        },
        formatFeature: GeoHelper.fullNameFromFeature,
        focusNode: _searchFocusNode,
      ),
    );
  }

  Widget _destinationQuickLaunch(bool connected) {
    List<NavDestination> specialDests = _destinations.where((d) => d.type != null).toList();
    if (specialDests.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 16),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      crossAxisCount: 2,
      childAspectRatio: 1.5,
      children: specialDests.map((dest) => _specialDestinationCard(dest)).toList(),
    );
  }

  Widget _destinationList(bool connected) {
    final regularDests = _destinations.where((d) => d.type == null).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: regularDests.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _destinationQuickLaunch(connected);
        return _destinationCard(regularDests[index - 1], index - 1);
      },
    );
  }

  Widget _specialDestinationCard(NavDestination destination) {
    IconData icon;
    switch (destination.type) {
      case SpecialDestinationType.home:
        icon = Icons.home_outlined;
      case SpecialDestinationType.work:
        icon = Icons.work_outline_rounded;
      case SpecialDestinationType.school:
        icon = Icons.school_outlined;
      default:
        icon = Icons.star_border_rounded;
    }
    return Material(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: () => _navigateToFav(destination),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 40),
                const SizedBox(height: 8),
                Text(
                  destination.name!,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                _showingCached
                    ? Text(
                        "Cached",
                        style: TextStyle(fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      )
                    : Text(
                        "${destination.location.latitude.toStringAsFixed(4)}, ${destination.location.longitude.toStringAsFixed(4)}",
                        textAlign: TextAlign.center,
                      ),
              ],
            ),
            if (!_showingCached)
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'rename') _showRenameFavDialog(destination);
                    if (value == 'delete') _confirmAndDeleteFav(destination);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _destinationCard(NavDestination dest, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: Key(dest.id ?? dest.name ?? "$index"),
        direction: _showingCached ? DismissDirection.none : DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            _showRenameFavDialog(dest);
            return false;
          } else {
            return await _confirmDeleteFav(dest);
          }
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            _deleteFav(dest);
          }
        },
        background: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          alignment: Alignment.centerLeft,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(
              Icons.edit,
              color: Colors.white,
            ),
          ),
        ),
        secondaryBackground: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            color: Theme.of(context).colorScheme.errorContainer,
          ),
          alignment: Alignment.centerRight,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            leading: const Icon(Icons.place_outlined),
            title: Text(dest.name ?? "Unknown"),
            subtitle: _showingCached
                ? const Text("Cached", style: TextStyle(fontStyle: FontStyle.italic))
                : Text(
                    "${dest.location.latitude.toStringAsFixed(4)}, ${dest.location.longitude.toStringAsFixed(4)}",
                  ),
            onTap: () => _navigateToFav(dest),
            trailing: _showingCached
                ? Icon(Icons.navigate_next)
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename') _showRenameFavDialog(dest);
                      if (value == 'delete') _confirmAndDeleteFav(dest);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _navigationStatusCard({required bool isNavigating, String? pendingName}) {
    final service = context.read<ScooterService>();
    return Dismissible(
      key: const Key("navigation_status_card"),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        if (isNavigating) {
          cancelNavigationCommand(
            service.myScooter,
            service.characteristicRepository,
          );
        } else {
          service.setPendingNavigation(null);
        }
      },
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: ListTile(
          leading: Icon(isNavigating ? Icons.navigation : Icons.schedule, color: Theme.of(context).colorScheme.surface),
          title: Text(
            isNavigating ? "Navigation is active" : "Pending navigation",
            style: TextStyle(color: Theme.of(context).colorScheme.surface),
          ),
          subtitle: Text(
            isNavigating
                ? "Follow directions on your scooter's display."
                : "Your scooter will navigate to ${pendingName ?? "your destination"} next time you connect.",
            style: TextStyle(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
          ),
          trailing: IconButton(
            icon: Icon(Icons.close, color: Theme.of(context).colorScheme.surface),
            tooltip: "Cancel",
            onPressed: () {
              if (isNavigating) {
                cancelNavigationCommand(
                  service.myScooter,
                  service.characteristicRepository,
                );
              } else {
                service.setPendingNavigation(null);
              }
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
    );
  }
}

class _DestinationsLoading extends StatelessWidget {
  const _DestinationsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _DisconnectedEmpty extends StatelessWidget {
  const _DisconnectedEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            "Scooter not connected",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            "Connect to your scooter to see saved destinations.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _NoDestinationsEmpty extends StatelessWidget {
  const _NoDestinationsEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                "No saved destinations",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                "Pull down to refresh.",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotonAutocomplete extends StatefulWidget {
  final void Function(PhotonFeature feature) onSelected;
  final String Function(PhotonFeature feature) formatFeature;
  final FocusNode? focusNode;

  const _PhotonAutocomplete({
    required this.onSelected,
    required this.formatFeature,
    this.focusNode,
  });

  @override
  State<_PhotonAutocomplete> createState() => _PhotonAutocompleteState();
}

class _PhotonAutocompleteState extends State<_PhotonAutocomplete> {
  Timer? _debounce;
  List<PhotonFeature> _suggestions = [];
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  LatLng? _lastOwnLocation;

  @override
  void initState() async {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    pollLocation().then((loc) {
      _lastOwnLocation = loc;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    // Only dispose the FocusNode if we created it internally
    if (widget.focusNode == null) _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.length < 3) {
      _removeOverlay();
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await photonForwardSearch(
          query,
          ownLocation: _lastOwnLocation,
        );
        if (mounted) {
          setState(() => _suggestions = results);
          if (results.isNotEmpty && _focusNode.hasFocus) {
            _showOverlay();
          } else {
            _removeOverlay();
          }
        }
      } catch (_) {
        // silently ignore search errors
      }
    });
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final feature = _suggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(widget.formatFeature(feature)),
                    onTap: () {
                      _controller.clear();
                      _removeOverlay();
                      _focusNode.unfocus();
                      setState(() => _suggestions = []);
                      widget.onSelected(feature);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: "Search for an address...",
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    _removeOverlay();
                    setState(() => _suggestions = []);
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
