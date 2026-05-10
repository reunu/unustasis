import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keycard_add_dialog.dart';
import 'service/ble_commands.dart';
import 'scooter_service.dart';

class LsKeycardScreen extends StatefulWidget {
  const LsKeycardScreen({super.key});

  @override
  State<LsKeycardScreen> createState() => _LsKeycardScreenState();
}

class _LsKeycardScreenState extends State<LsKeycardScreen> {
  List<String> keycards = [];
  Map<String, String> _aliases = {};
  bool _isLoadingKeycards = false;
  bool _isBackgroundScanning = false;
  String? _highlightedUid;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _loadAliases();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIndicatorKey.currentState?.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_keycard_title")),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddKeycardDialog,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _loadKeycards,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: keycards.length,
          itemBuilder: (context, index) {
            final keycard = keycards[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: KeycardCard(
                key: ValueKey(keycard),
                index: index,
                uid: keycard,
                alias: _aliases[keycard],
                onlyCard: keycards.length == 1,
                highlighted: _highlightedUid == keycard,
                onDelete: _deleteKeycard,
                onRename: _renameKeycard,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadKeycards() async {
    if (_isLoadingKeycards) return;

    setState(() {
      _isLoadingKeycards = true;
    });

    try {
      List<String> loadedKeycards = await listKeycardsCommand(
        context.read<ScooterService>().myScooter,
        context.read<ScooterService>().characteristicRepository,
      );
      Logger('LsKeycardScreen').info('Loaded keycards: $loadedKeycards');
      if (!mounted) return;
      setState(() {
        keycards = loadedKeycards;
      });
      _startBackgroundNfcScan();
    } catch (e) {
      Logger('LsKeycardScreen').severe('Failed to load keycards: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(FlutterI18n.translate(context, "ls_keycard_load_error", translationParams: {"error": e.toString()})),
        ),
      );
    } finally {
      setState(() {
        _isLoadingKeycards = false;
      });
    }
  }

  Future<void> _showRefreshIndicatorAndReload() async {
    final refreshIndicatorState = _refreshIndicatorKey.currentState;
    if (refreshIndicatorState != null) {
      await refreshIndicatorState.show();
      return;
    }
    await _loadKeycards();
  }

  @override
  void dispose() {
    _stopBackgroundNfcScan();
    super.dispose();
  }

  void _startBackgroundNfcScan() async {
    if (!Platform.isAndroid) return;
    if (_isBackgroundScanning) return;
    final availability = await NfcManager.instance.checkAvailability();
    if (availability == NfcAvailability.unsupported || availability == NfcAvailability.disabled || !mounted) return;
    setState(() => _isBackgroundScanning = true);
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        final uid = extractKeycardUid(tag);
        if (uid != null && keycards.contains(uid)) {
          await HapticFeedback.lightImpact();
          if (!mounted) return;
          setState(() => _highlightedUid = uid);
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          setState(() => _highlightedUid = null);
        }
      },
    );
  }

  void _stopBackgroundNfcScan() {
    if (!_isBackgroundScanning) return;
    NfcManager.instance.stopSession();
    if (mounted) setState(() => _isBackgroundScanning = false);
  }

  void _showAddKeycardDialog() async {
    _stopBackgroundNfcScan();
    // Check NFC availability before showing the dialog
    final NfcAvailability nfcAvailability = await NfcManager.instance.checkAvailability();
    if (!mounted) {
      _startBackgroundNfcScan();
      return;
    }
    if (nfcAvailability == NfcAvailability.unsupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_nfc_unavailable"))),
      );
      _startBackgroundNfcScan();
      return;
    } else if (nfcAvailability == NfcAvailability.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_keycard_nfc_disabled")),
        ),
      );
      _startBackgroundNfcScan();
      return;
    }

    // show the dialog and wait for a UID to be determined
    final String? uid = await showDialog<String>(
      context: context,
      builder: (context) => KeycardAddDialog(existingUids: keycards),
    );

    if (uid == null || !mounted) {
      _startBackgroundNfcScan();
      return;
    }

    // optimistically add the card to the list
    setState(() {
      keycards.add(uid);
    });

    // add it to the scooter
    try {
      await addKeycardCommand(
        context.read<ScooterService>().myScooter,
        context.read<ScooterService>().characteristicRepository,
        uid,
      );
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_add_success"))),
      );
    } catch (_) {
      // if it fails, remove the optimistically added card and show an error
      if (!mounted) return;
      setState(() {
        keycards.remove(uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_add_error"))),
      );
    } finally {
      // refresh the list to show the actual new list of keycards
      await _showRefreshIndicatorAndReload();
      _startBackgroundNfcScan();
    }
  }

  Future<void> _loadAliases() async {
    final raw = await SharedPreferencesAsync().getString('keycard_aliases');
    if (raw != null && mounted) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      setState(() => _aliases = decoded.map((k, v) => MapEntry(k, v as String)));
    }
  }

  Future<void> _saveAliases() async {
    await SharedPreferencesAsync().setString('keycard_aliases', jsonEncode(_aliases));
  }

  Future<void> _renameKeycard(String uid, String alias) async {
    setState(() => _aliases[uid] = alias);
    await _saveAliases();
  }

  Future<void> _deleteKeycard(String uid) async {
    setState(() {
      keycards.remove(uid);
    });

    try {
      await deleteKeycardCommand(
        context.read<ScooterService>().myScooter,
        context.read<ScooterService>().characteristicRepository,
        uid,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_keycard_delete_error")),
        ),
      );
    } finally {
      await _showRefreshIndicatorAndReload();
    }
  }
}

class KeycardCard extends StatefulWidget {
  final int index;
  final String uid;
  final String? alias;
  final bool onlyCard;
  final bool highlighted;
  final Future<void> Function(String uid) onDelete;
  final Future<void> Function(String uid, String alias) onRename;

  const KeycardCard({
    super.key,
    required this.index,
    required this.uid,
    required this.onDelete,
    required this.onRename,
    this.alias,
    this.onlyCard = false,
    this.highlighted = false,
  });

  @override
  State<KeycardCard> createState() => _KeycardCardState();
}

class _KeycardCardState extends State<KeycardCard> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
    ]).animate(_animController);
  }

  @override
  void didUpdateWidget(KeycardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && !oldWidget.highlighted) {
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          color: Color.lerp(
            Theme.of(context).colorScheme.surfaceContainer,
            Theme.of(context).colorScheme.primaryContainer,
            _animation.value,
          ),
        ),
        child: child,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getColorForIndex(widget.index),
          foregroundColor: Colors.white,
          child: Text((widget.index + 1).toString()),
        ),
        title: Text(widget.alias?.isNotEmpty == true
            ? widget.alias!
            : FlutterI18n.translate(context, "ls_keycard_default_name",
                translationParams: {"number": (widget.index + 1).toString()})),
        subtitle: Text(widget.uid),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'rename') _showRenameDialog(context);
            if (value == 'delete') _confirmAndDeleteKeycard(context);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            if (!widget.onlyCard) const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Color _getColorForIndex(int index) {
    switch (index % 7) {
      case 0:
        return Color(0xFFFF554C);
      case 1:
        return Color(0xFF0395FF);
      case 2:
        return Color(0xFF245544);
      case 3:
        return Color(0xFF303030);
      case 4:
        return Colors.deepOrange.shade400;
      case 5:
        return Colors.teal.shade500;
      case 6:
        return Colors.deepPurple.shade400;
      default:
        return Colors.grey;
    }
  }

  void _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.alias ?? '');
    final alias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename Keycard"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: "Alias (optional)"),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias != null) await widget.onRename(widget.uid, alias);
  }

  void _confirmAndDeleteKeycard(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, "ls_keycard_delete_title")),
        content: Text(FlutterI18n.translate(context, "ls_keycard_delete_confirm")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(FlutterI18n.translate(context, "cancel")),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await widget.onDelete(widget.uid);
            },
            child: Text(FlutterI18n.translate(context, "ls_keycard_delete_button")),
          ),
        ],
      ),
    );
  }
}

