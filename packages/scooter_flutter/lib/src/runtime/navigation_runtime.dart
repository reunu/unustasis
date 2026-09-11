import 'dart:async';
import 'dart:convert';

import 'package:scooter_core/navigation.dart';
import 'package:scooter_core/telemetry.dart';
import '../ble/characteristic_repository.dart';
import '../ble/navigation_commands.dart' as commands;
import 'scooter_session.dart';

/// Navigation state/workflows on the existing session, with app-owned storage
/// and naming adapters. No connection engine or independent extended queue.
class NavigationRuntime {
  NavigationRuntime({
    required this.loadPending,
    required this.savePending,
    required this.changed,
    required this.failed,
    NavigationDestination Function(Map<String, dynamic>)? decodeDestination,
  }) : _decode = decodeDestination ?? NavigationDestination.fromJson;

  final Future<String?> Function() loadPending;
  final Future<void> Function(String?) savePending;
  final void Function() changed;
  final void Function(Object, StackTrace) failed;
  final NavigationDestination Function(Map<String, dynamic>) _decode;
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  NavigationDestination? _pending, _active;
  Object _request = Object();
  Object? _dispatchRequest, _dispatchRun;
  SessionConnection? _dispatchConnection;
  Future<void> _persistence = Future.value();
  bool _disposed = false;

  NavigationDestination? get pending => _pending?.copy();
  NavigationDestination? get active => _active?.copy();

  void bind(SessionConnection connection, CharacteristicRepository repository) {
    invalidate();
    if (_disposed || !connection.isCurrent) return;
    _connection = connection;
    _repository = repository;
  }

  void invalidate() {
    _connection = null;
    _repository = null;
  }

  Future<void> restorePending() async {
    final request = _request;
    final json = await loadPending();
    if (_disposed || !identical(request, _request) || json == null) return;
    try {
      _pending = _decode(jsonDecode(json) as Map<String, dynamic>).copy();
    } catch (_) {
      await _persist(null);
    }
  }

  // Serialize preference effects too: a late removal must not erase a newer
  // pending request. Failed writes do not poison subsequent persistence.
  Future<void> _persist(NavigationDestination? destination) {
    final json = destination == null ? null : jsonEncode(destination.toJson());
    final result = _persistence.then((_) => savePending(json));
    _persistence = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> setPending(NavigationDestination? destination) async {
    if (_disposed) return;
    final request = _request = Object();
    _pending = destination?.copy();
    await _persist(_pending);
    if (!_disposed && identical(request, _request)) changed();
  }

  void setActive(NavigationDestination? destination) {
    if (_disposed) return;
    _request = Object();
    _publishActive(destination);
  }

  void _publishActive(NavigationDestination? destination) {
    _active = destination?.copy();
    changed();
  }

  void navigationChanged(bool? active) {
    if (active != true) _active = null;
  }

  void firmwareIdentified(
      SessionConnection connection, FirmwareSnapshot firmware) {
    if (firmware.isLibrescoot == true &&
        identical(connection, _connection) &&
        connection.isCurrent) {
      unawaited(dispatchPending());
    }
  }

  _NavigationTarget _capture() {
    final connection = _connection;
    final repository = _repository;
    if (_disposed ||
        connection == null ||
        repository == null ||
        !connection.isCurrent) {
      throw StateError('Scooter not connected');
    }
    return _NavigationTarget(connection, repository);
  }

  bool _current(_NavigationTarget target) =>
      !_disposed &&
      identical(_connection, target.connection) &&
      target.connection.isCurrent;

  void _check(_NavigationTarget target) {
    if (!_current(target)) throw StateError('Navigation session expired');
  }

  Future<void> dispatchPending() async {
    final destination = _pending?.copy();
    final request = _request;
    if (destination == null ||
        _connection == null ||
        (identical(_dispatchRequest, request) &&
            identical(_dispatchConnection, _connection))) {
      return;
    }
    final run = Object();
    try {
      final target = _capture();
      _dispatchRun = run;
      _dispatchRequest = request;
      _dispatchConnection = target.connection;
      bool current() => _current(target) && identical(request, _request);
      await commands.navigateCommand(
          target.connection.device, target.repository, destination,
          isCurrent: current);
      if (!current()) return;
      _publishActive(destination);
      // Listener publication may synchronously submit another request.
      if (!current()) return;
      await setPending(null);
    } catch (error, stack) {
      if (!_disposed) failed(error, stack);
    } finally {
      if (identical(_dispatchRun, run)) {
        _dispatchRequest = null;
        _dispatchConnection = null;
      }
    }
  }

  Future<void> navigate(NavigationDestination destination,
      {bool favorite = false}) async {
    final target = _capture();
    final snapshot = destination.copy();
    final supersedesPending = _pending != null;
    final request = _request = Object();
    bool current() => _current(target) && identical(request, _request);
    if (favorite) {
      await commands.navigateFavCommand(
          target.connection.device, target.repository, snapshot.id!,
          isCurrent: current);
    } else {
      await commands.navigateCommand(
          target.connection.device, target.repository, snapshot,
          isCurrent: current);
    }
    _check(target);
    if (!current()) return;
    _publishActive(snapshot);
    // This request invalidated any older pending dispatch. On success it also
    // owns retiring that pending destination, otherwise it would replay later.
    // Publication can synchronously replace the request or the session.
    if (supersedesPending && current()) await setPending(null);
  }

  Future<void> cancel() async {
    final request = _request = Object();
    late final _NavigationTarget target;
    try {
      target = _capture();
    } catch (_) {
      // Preserve dismissal of an offline active card too. This is synchronous,
      // so no obsolete transport completion can clear replacement state.
      if (!_disposed && identical(request, _request)) _publishActive(null);
      rethrow;
    }
    bool current() => _current(target) && identical(request, _request);
    try {
      await commands.cancelNavigationCommand(
          target.connection.device, target.repository,
          isCurrent: current);
      _check(target);
    } finally {
      // The UI historically cleared its active presentation even on a failed
      // cancellation. Do not let that failure clear a newer session/request.
      if (current()) _publishActive(null);
    }
  }

  Future<List<NavigationDestination>> listFavorites() async {
    final target = _capture();
    final result = await commands.listFavDestinationsCommand(
        target.connection.device, target.repository,
        isCurrent: () => _current(target));
    _check(target);
    return result;
  }

  Future<String> saveFavorite(NavigationDestination destination) async {
    final target = _capture();
    final result = await commands.saveNavDestinationCommand(
        target.connection.device, target.repository, destination.copy(),
        isCurrent: () => _current(target));
    _check(target);
    return result;
  }

  Future<void> deleteFavorite(String id) async {
    final target = _capture();
    await commands.deleteFavDestinationCommand(
        target.connection.device, target.repository, id,
        isCurrent: () => _current(target));
    _check(target);
  }

  /// Firmware rename is delete then add, not a transaction. Keep both writes on
  /// one captured session; an acknowledged deletion cannot be rolled back.
  Future<String> renameFavorite(
      NavigationDestination destination, String name) async {
    final target = _capture();
    final snapshot = destination.copy()..name = name;
    await commands.deleteFavDestinationCommand(
        target.connection.device, target.repository, snapshot.id!,
        isCurrent: () => _current(target));
    _check(target);
    final result = await commands.saveNavDestinationCommand(
        target.connection.device, target.repository, snapshot,
        isCurrent: () => _current(target));
    _check(target);
    return result;
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}

class _NavigationTarget {
  _NavigationTarget(this.connection, this.repository);
  final SessionConnection connection;
  final CharacteristicRepository repository;
}
