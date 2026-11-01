import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';

const hashReadTimeout = Duration(minutes: 5);

class HashReadException implements Exception {
  const HashReadException(this.code);
  final String code;

  @override
  String toString() => 'Hash read failed: $code';
}

// Never reset on reconnect: even a delayed notification from the same device
// must not match a newly allocated logical read. Exhaustion fails closed.
int _nextId = Random.secure().nextInt(0xffffffff) + 1;
int _issuedIds = 0;

String _allocateId() {
  if (_issuedIds == 0xffffffff) throw StateError('Hash read IDs exhausted');
  final id = _nextId.toRadixString(16).padLeft(8, '0');
  _nextId = _nextId % 0xffffffff + 1;
  _issuedIds++;
  return id;
}

/// Reads an atomic, ordered array of raw Redis strings or missing-field nulls.
/// The caller supplies its captured connection-generation guard and confirms
/// hash=1 before calling. The server owns the hash/field permission list.
Future<List<String?>> readHashFieldsCommand(
  BluetoothDevice device,
  CharacteristicRepository repo,
  String hash,
  List<String> fields, {
  required bool Function() isCurrent,
  Duration responseTimeout = extendedResponseTimeout,
  Duration readTimeout = hashReadTimeout,
}) {
  final name = RegExp(r'^[A-Za-z0-9:_-]+$');
  if (!name.hasMatch(hash) ||
      fields.isEmpty ||
      fields.length > 2 ||
      fields.toSet().length != fields.length ||
      fields.any((field) => !name.hasMatch(field))) {
    throw ArgumentError('Invalid hash or field selection');
  }
  final selection = List<String>.unmodifiable(fields);
  final id = _allocateId();
  final commandPrefix = 'hash:read:$id:';
  return withExtendedChannel(() async {
    void check() {
      checkCommandCurrent(isCurrent);
      if (device.isDisconnected) throw StateError('Scooter disconnected');
    }

    check();
    final command = repo.extendedCommandCharacteristic;
    final response = repo.extendedResponseCharacteristic;
    if (command == null || response == null || repo.gattTableMismatch) {
      throw StateError('Extended command channel unavailable');
    }
    final budget = min(244, device.mtuNow - 3);
    if (budget < 20) throw StateError('ATT MTU is below 23');
    final startCommand = '$commandPrefix$budget:$hash/${selection.join(',')}';
    if (startCommand.length > 100) {
      throw ArgumentError('Hash read request exceeds 100 ASCII bytes');
    }
    await ensureExtendedNotify(repo, response, isCurrent: isCurrent).timeout(responseTimeout);
    check();
    final replies = _HashReplies(device, response, id, budget, check);
    final elapsed = Stopwatch()..start();
    Future<String> request(String text) async {
      check();
      final remaining = readTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Hash read expired');
      }
      final timeout = remaining < responseTimeout ? remaining : responseTimeout;
      final reply = replies.expect();
      // Attach the error handler before the write: a disconnect or malformed
      // synchronous notification can complete the reply while write is pending.
      final exchange = Future.wait<Object?>([
        reply,
        sendCommand(device, repo, text, characteristic: command, allowLongWrite: true, isCurrent: isCurrent),
      ], eagerError: true);
      final results = await exchange.timeout(timeout);
      replies.checkAlive();
      repo.noteExtendedResponse();
      return results.first as String;
    }

    try {
      final start = await request(startCommand);
      final header = start.split(':');
      if (header.length != 4 || header[1] != 's') {
        throw const FormatException('Invalid hash snapshot header');
      }
      final length = _base36(header[3]);
      if (length < 2 || length > 4096) {
        throw const FormatException('Invalid hash snapshot length');
      }
      final bytes = BytesBuilder(copy: false);
      var offset = 0;
      while (offset < length) {
        final offsetText = offset.toRadixString(36);
        final chunk = (await request('hash:get:$id:$offsetText:$budget')).split(':');
        if (chunk.length != 5 ||
            chunk[1] != 'p' ||
            chunk[3] != offsetText ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(chunk[4])) {
          throw const FormatException('Invalid hash chunk');
        }
        final data = base64Url.decode(base64Url.normalize(chunk[4]));
        if (data.isEmpty || offset + data.length > length || base64Url.encode(data).replaceAll('=', '') != chunk[4]) {
          throw const FormatException('Invalid hash chunk bytes');
        }
        bytes.add(data);
        offset += data.length;
      }
      final end = await request('hash:get:$id:${offset.toRadixString(36)}:$budget');
      if (end != 'r:e:$id:${offset.toRadixString(36)}') {
        throw const FormatException('Invalid hash EOF');
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! List || decoded.length != selection.length) {
        throw const FormatException('Invalid hash field array');
      }
      final values = <String?>[];
      for (final value in decoded) {
        if (value != null &&
            (value is! String || utf8.encode(value).length > 256 || utf8.decode(utf8.encode(value)) != value)) {
          throw const FormatException('Invalid hash field value');
        }
        values.add(value as String?);
      }
      replies.checkAlive();
      return List.unmodifiable(values);
    } on TimeoutException {
      repo.noteSilentExtendedCommand();
      rethrow;
    } finally {
      await replies.cancel();
    }
  });
}

int _base36(String text) {
  if (text.length > 3 || !RegExp(r'^(0|[1-9a-z][0-9a-z]*)$').hasMatch(text)) {
    throw const FormatException('Invalid hash base36 number');
  }
  return int.parse(text, radix: 36);
}

class _HashReplies {
  _HashReplies(BluetoothDevice device, BluetoothCharacteristic response, this.id, this.budget, this.check) {
    _notifications = response.onValueReceived
        .listen(_receive, onError: _fail, onDone: () => _fail(StateError('Hash response closed')));
    _connection = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _fail(StateError('Scooter disconnected'));
      }
    }, onError: _fail);
  }

  final String id;
  final int budget;
  final void Function() check;
  late final StreamSubscription<List<int>> _notifications;
  late final StreamSubscription<BluetoothConnectionState> _connection;
  Completer<String>? _pending;
  Object? _failure;

  void checkAlive() {
    check();
    if (_failure != null) throw _failure!;
  }

  Future<String> expect() {
    checkAlive();
    return (_pending = Completer<String>()).future;
  }

  void _fail(Object error) {
    _failure ??= error;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  bool _correlates(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 0x72 || bytes[1] != 0x3a) return false;
    final kindEnd = bytes.indexOf(0x3a, 2);
    if (kindEnd < 0) return false;
    final idStart = kindEnd + 1;
    final idEnd = idStart + id.length;
    if (idEnd > bytes.length || (idEnd < bytes.length && bytes[idEnd] != 0x3a)) {
      return false;
    }
    for (var i = 0; i < id.length; i++) {
      if (bytes[idStart + i] != id.codeUnitAt(i)) return false;
    }
    return true;
  }

  void _receive(List<int> bytes) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    try {
      check();
      // Other extended replies can have a different budget and encoding. Only
      // inspect their raw header; validate the payload after exact correlation.
      if (!_correlates(bytes)) return;
      // The radio can zero-fill the notification to the negotiated payload
      // size. Padding is transport framing, never part of the ASCII response.
      final trailingZeros = bytes.reversed.takeWhile((b) => b == 0).length;
      final frame = bytes.sublist(0, bytes.length - trailingZeros);
      if (bytes.length > budget || frame.any((b) => b < 0x20 || b > 0x7e)) {
        final nonPrintable = frame.where((b) => b < 0x20 || b > 0x7e).length;
        Logger('BleHashRead').warning(
            'Rejected hash frame: bytes=${bytes.length} budget=$budget nonPrintable=$nonPrintable trailingZeros=$trailingZeros');
        throw const FormatException('Invalid hash notification');
      }
      final text = ascii.decode(frame);
      final parts = text.split(':');
      if (parts[1] == 'x') {
        if (parts.length != 4 ||
            !const {
              'command',
              'denied',
              'redis',
              'large',
              'utf8',
              'busy',
              'session',
              'offset',
              'budget',
              'id',
            }.contains(parts[3])) {
          throw const FormatException('Invalid hash error');
        }
        throw HashReadException(parts[3]);
      }
      pending.complete(text);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> cancel() async {
    await _notifications.cancel();
    await _connection.cancel();
  }
}
