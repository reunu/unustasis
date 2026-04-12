import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_photon/flutter_photon.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/photon_service.dart';
import '../domain/nav_destination.dart';
import '../domain/saved_scooter.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';
import '../service/ble_commands.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  List<NavDestination> _destinations = [];
  bool _loading = false;
  bool _osmConsent = false;
  bool _initialLoad = true;
  bool _showingCached = false;

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
        favs.map((d) => GeoHelper.nameDestination(d)),
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
    final scooterLocation = service.lastLocation;
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
                child: const Text("Continue"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _navigateToFav(NavDestination destination) async {
    if (!await _confirmIfFarAway(destination.location)) return;
    final service = context.read<ScooterService>();
    if (!service.connected) {
      // Queue for when a librescoot connects
      await service.setPendingNavigation(destination);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Navigation to \"${destination.name}\" queued")),
        );
      }
      return;
    }
    try {
      final success = await navigateFavCommand(
        service.myScooter!,
        service.characteristicRepository,
        destination.id!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? "Navigation started to ${destination.name}" : "Failed to start navigation."),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Future<void> _navigateToAddress(PhotonFeature feature) async {
    final service = context.read<ScooterService>();
    final name = GeoHelper.createNameFromPhotonFeature(feature);
    final dest = NavDestination(
      location: LatLng(feature.coordinates.latitude.toDouble(), feature.coordinates.longitude.toDouble()),
      name: name,
    );
    if (!await _confirmIfFarAway(dest.location)) return;
    if (!service.connected) {
      // Queue for when a librescoot connects
      await service.setPendingNavigation(dest);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation to "$name" queued')),
        );
      }
      return;
    }
    try {
      final success = await navigateCommand(
        service.myScooter!,
        service.characteristicRepository,
        dest,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? "Navigation started to $name" : "Failed to start navigation."),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  String _namePhotonSuggestion(PhotonFeature feature) {
    final parts = <String>[];
    if (feature.name != null && feature.name != feature.street) {
      parts.add(feature.name!);
    }
    if (feature.street != null) {
      String street = feature.street!;
      if (feature.houseNumber != null) {
        street += " ${feature.houseNumber!}";
      }
      parts.add(street);
    } else if (feature.name != null) {
      parts.add(feature.name!);
    }
    final locality = <String>[];
    if (feature.postcode != null) locality.add(feature.postcode!);
    if (feature.city != null) locality.add(feature.city!);
    if (locality.isNotEmpty) parts.add(locality.join(" "));
    return parts.isNotEmpty ? parts.join(", ") : "${feature.coordinates.latitude}, ${feature.coordinates.longitude}";
  }

  void _showNavigateConfirmation(PhotonFeature feature) {
    final name = GeoHelper.createNameFromPhotonFeature(feature);
    final service = context.read<ScooterService>();
    final isConnected = service.connected;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
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
                _showSaveFavoriteDialog(feature);
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.navigation),
            label: Text(isConnected ? "Navigate" : "Queue navigation"),
            onPressed: () {
              Navigator.of(ctx).pop();
              _navigateToAddress(feature);
            },
          ),
        ],
      ),
    );
  }

  /// Returns an error string if [name] contains characters invalid for BLE
  /// destination names (non-printable ASCII or colon), null if valid.
  static String? _validateDestName(String name) {
    if (name.trim().isEmpty) return 'Name cannot be empty';
    if (name.contains(':')) return 'Name cannot contain colons';
    if (RegExp(r'[^\x20-\x7E]').hasMatch(name)) return 'Name contains invalid characters';
    return null;
  }

  void _showSaveFavoriteDialog(PhotonFeature feature) {
    final name = GeoHelper.createNameFromPhotonFeature(feature);
    final nameController = TextEditingController(text: name);
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
                      _saveDestination(feature, nameController.text.trim());
                    }
                  : null,
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDestination(PhotonFeature feature, String name) async {
    final service = context.read<ScooterService>();
    if (name.isEmpty) {
      name = GeoHelper.createNameFromPhotonFeature(feature);
    }
    try {
      await saveNavDestinationCommand(
        service.myScooter!,
        service.characteristicRepository,
        NavDestination(
          location: LatLng(feature.coordinates.latitude.toDouble(), feature.coordinates.longitude.toDouble()),
          name: name,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved \"$name\" to favorites")),
        );
        _fetchDestinations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save destination: $e")),
        );
      }
    }
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
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  @override
  Widget build(BuildContext context) {
    final connected = context.select<ScooterService, bool>((s) => s.connected);
    final pendingNav = context.select<ScooterService, NavDestination?>((s) => s.pendingNavigation);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Navigation"),
        actions: [
          if (connected)
            IconButton(
              icon: const Icon(Icons.location_off_outlined),
              onPressed: () => cancelNavigationCommand(
                context.read<ScooterService>().myScooter,
                context.read<ScooterService>().characteristicRepository,
              ),
              tooltip: "Stop navigation",
            )
        ],
      ),
      body: Column(
        children: [
          if (pendingNav != null) _buildPendingCard(pendingNav),
          if (_osmConsent) _buildSearchField(),
          Expanded(child: _buildDestinationList(connected)),
        ],
      ),
    );
  }

  Widget _buildPendingCard(NavDestination destination) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        title: Text(
          destination.name ?? "Unknown destination",
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        subtitle: Text(
          "Pending \u2014 will start on next connection",
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.close,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          tooltip: "Cancel pending navigation",
          onPressed: () => context.read<ScooterService>().setPendingNavigation(null),
        ),
      ),
    );
  }

  Widget _buildDestinationList(bool connected) {
    if (_loading && _initialLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_destinations.isEmpty && !connected && !_showingCached) {
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
    if (_destinations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchDestinations,
        child: ListView(
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
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDestinations,
      child: ListView.builder(
        itemCount: _destinations.length,
        itemBuilder: (context, index) {
          final dest = _destinations[index];
          if (_showingCached) {
            return ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(dest.name ?? "Unknown"),
              subtitle: const Text(
                "Cached",
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.navigation),
                tooltip: "Navigate here",
                onPressed: () => _navigateToFav(dest),
              ),
            );
          }
          return Dismissible(
            key: Key(dest.id ?? dest.name ?? "$index"),
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
              color: Colors.blue,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.edit,
                  color: Colors.white,
                ),
              ),
            ),
            secondaryBackground: Container(
              color: Colors.red,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.delete,
                  color: Colors.white,
                ),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.bookmark),
              title: Text(dest.name ?? "Unknown"),
              subtitle: Text(
                "${dest.location.latitude.toStringAsFixed(4)}, ${dest.location.longitude.toStringAsFixed(4)}",
              ),
              trailing: IconButton(
                icon: const Icon(Icons.navigation),
                tooltip: "Navigate here",
                onPressed: () => _navigateToFav(dest),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _PhotonAutocomplete(
        onSelected: _showNavigateConfirmation,
        formatFeature: _namePhotonSuggestion,
      ),
    );
  }
}

class _PhotonAutocomplete extends StatefulWidget {
  final void Function(PhotonFeature feature) onSelected;
  final String Function(PhotonFeature feature) formatFeature;

  const _PhotonAutocomplete({
    required this.onSelected,
    required this.formatFeature,
  });

  @override
  State<_PhotonAutocomplete> createState() => _PhotonAutocompleteState();
}

class _PhotonAutocompleteState extends State<_PhotonAutocomplete> {
  Timer? _debounce;
  List<PhotonFeature> _suggestions = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
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
        final results = await photonForwardSearch(query);
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
