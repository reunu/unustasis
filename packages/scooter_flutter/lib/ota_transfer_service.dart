import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import 'package:scooter_core/ota_protocol.dart';
import 'package:scooter_core/ota_update.dart';
export 'package:scooter_core/ota_update.dart';
import 'package:scooter_core/update_planner.dart';
import 'src/ble/characteristic_repository.dart';

final log = Logger('OtaTransferService');

/// Drives a windowed, resumable firmware-bundle transfer to the scooter over
/// the OTA GATT service (see lib/domain/ota_protocol.dart for the wire format).
///
/// Flow: START (handshake, returns a resume offset) -> stream DATA chunks with
/// at most [OtaStartAck.windowChunks] chunks unacknowledged -> cumulative ACKs
/// advance the window; a REWIND ACK or an ACK timeout rewinds the send position
/// (go-back-N) -> COMPLETE triggers scooter-side SHA-256 verification and the
/// install; INSTALL_PROGRESS notifications are relayed until a terminal phase.
///
/// A BLE disconnect fails the attempt with [resumable] set; calling [transfer]
/// again after reconnecting resumes from the scooter's persisted offset.
class OtaTransferService extends ChangeNotifier {
  OtaTransferService({bool? isAndroid, DateTime Function()? now})
      : _isAndroid = isAndroid ?? Platform.isAndroid,
        _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final bool _isAndroid;
  bool _disposed = false;
  void Function()? _interrupt;
  bool awaitingReconnect = false;

  /// Release observations when the composed session is replaced or disposed.
  /// An accepted installation remains unconfirmed, never converted to success.
  void invalidate() => _interrupt?.call();

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  OtaTransferState state = OtaTransferState.idle;

  /// The update step being (or last) executed, set by the update controller so a
  /// re-opened screen can restore what this transfer belongs to.
  UpdateStep? activeStep;

  /// 0.0 .. 1.0 transfer progress (acknowledged bytes / total).
  double progress = 0;

  /// Install progress percent (0-100) once the scooter is installing.
  int installPercent = 0;

  /// Last human-readable status or error detail.
  String statusMessage = "";

  /// Acknowledged throughput in bytes/second (rolling, ~1 s window).
  double throughput = 0;

  /// Bytes acknowledged by the scooter so far / total bundle size.
  int ackedBytes = 0;
  int totalBytes = 0;

  /// Estimated seconds until the transfer completes, or null when unknown.
  int? get etaSeconds {
    if (throughput <= 0 || totalBytes == 0 || ackedBytes >= totalBytes) {
      return null;
    }
    return ((totalBytes - ackedBytes) / throughput).round();
  }

  /// Whether a failed transfer can be resumed by calling [transfer] again.
  bool resumable = false;

  bool get busy =>
      state != OtaTransferState.idle &&
      state != OtaTransferState.success &&
      state != OtaTransferState.failure;

  /// Whether a transfer or install is actively running. [pendingReboot] is a
  /// settled outcome — the bundle has been consumed by the scooter — so a
  /// fresh planning pass or the next update step may proceed.
  bool get active =>
      busy && state != OtaTransferState.pendingReboot && !awaitingReconnect;

  bool _abortRequested = false;

  static const Duration _startAckTimeout = Duration(seconds: 5);
  static const Duration _ackTimeout = Duration(seconds: 5);
  static const Duration _completeAckTimeout = Duration(seconds: 30);
  static const int _maxRewinds = 30;

  void _set(OtaTransferState s, [String? msg]) {
    state = s;
    if (msg != null) statusMessage = msg;
    notifyListeners();
  }

  /// Requests a graceful abort of a running transfer.
  void abort() {
    _abortRequested = true;
  }

  /// Clears a finished transfer back to idle so a fresh planning pass starts
  /// with a clean slate. No-op while a transfer or install is running.
  void reset() {
    if (active || awaitingReconnect) return;
    state = OtaTransferState.idle;
    statusMessage = "";
    progress = 0;
    installPercent = 0;
    ackedBytes = 0;
    totalBytes = 0;
    throughput = 0;
    resumable = false;
    activeStep = null;
    notifyListeners();
  }

  /// Transfers [bundle] and installs it on the scooter. [bundleId] must be
  /// the real asset basename: without the ".mender" extension for full images
  /// (the scooter appends it when staging), WITH the ".delta" extension for
  /// delta bundles (the scooter preserves it so update-service applies the
  /// file as a delta). The scooter derives the installed version from the
  /// filename. Resumes automatically when the scooter has a matching partial
  /// transfer.
  Future<void> transfer(
    BluetoothDevice scooter,
    CharacteristicRepository repo,
    File bundle, {
    required String bundleId,
    int component = OtaProtocol.componentMdb,
    bool Function()? isCurrent,
  }) async {
    if (_disposed) throw StateError("transfer disposed");
    if (active || awaitingReconnect) {
      throw StateError("transfer already running");
    }
    final dataChar = repo.otaDataCharacteristic;
    final ctrlChar = repo.otaControlCharacteristic;
    final statusChar = repo.otaStatusCharacteristic;
    if (dataChar == null || ctrlChar == null || statusChar == null) {
      throw "OTA characteristics not available (firmware too old?)";
    }

    void checkCurrent() {
      if (scooter.isDisconnected) throw const _OtaLinkLost();
      if (_disposed || isCurrent?.call() == false) {
        throw "Update session replaced";
      }
    }

    _abortRequested = false;
    resumable = false;
    awaitingReconnect = false;
    installPercent = 0;
    progress = 0;
    throughput = 0;
    ackedBytes = 0;
    StreamSubscription<List<int>>? sub;
    StreamSubscription<BluetoothConnectionState>? connSub;
    StreamSubscription<OtaStatusMessage>? installSub;
    StreamController<OtaStatusMessage>? installation;
    final messages = StreamController<OtaStatusMessage>.broadcast();
    RandomAccessFile? raf;
    var accepted = false;
    _interrupt = () {
      if (!messages.isClosed) messages.addError(const _OtaLinkLost());
    };
    try {
      _set(OtaTransferState.hashing, "Preparing bundle...");
      checkCurrent();
      if (_isAndroid) {
        // The scooter renegotiates its power-friendly connection parameters
        // (up to a 75 ms interval) a few seconds after connecting, overriding
        // the high priority requested at connect time — and at 75 ms the link
        // tops out around 30 kB/s. The central can set parameters
        // unilaterally, so re-request high priority (11.25-15 ms) for the
        // transfer; the nRF's own OTA link boost is best-effort only.
        try {
          await scooter.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high);
        } catch (e) {
          log.warning("Connection priority request failed (continuing): $e");
        }
      }

      checkCurrent();
      final totalSize = await bundle.length();
      totalBytes = totalSize;
      checkCurrent();
      final digest = await _hashFile(bundle);
      checkCurrent();
      await statusChar.setNotifyValue(true);
      checkCurrent();
      sub = statusChar.onValueReceived.listen((v) {
        final m = OtaStatusMessage.parse(v);
        if (m != null) messages.add(m);
      });
      // a disconnect must unblock everything awaiting scooter messages
      connSub = scooter.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !messages.isClosed) {
          messages.addError(const _OtaLinkLost());
        }
      });

      // handshake
      _set(OtaTransferState.handshaking, "Contacting scooter...");
      final ack = await _startHandshake(
        scooter,
        ctrlChar,
        messages.stream,
        component: component,
        totalSize: totalSize,
        sha256: Uint8List.fromList(digest.bytes),
        bundleId: bundleId,
        checkCurrent: checkCurrent,
      );

      // ATT-MTU minus 3 (ATT header) minus 4 (DATA offset prefix). No floor:
      // a chunk larger than the negotiated MTU is truncated/rejected on every
      // write, which surfaces as endless rewinds instead of a clean error.
      final chunkSize = min(
        ack.maxChunk,
        min(OtaProtocol.maxChunkSize, scooter.mtuNow - 7),
      );
      if (chunkSize < 1) {
        throw "Negotiated ATT MTU (${scooter.mtuNow}) too small for OTA";
      }
      final window = max(1, ack.windowChunks) * chunkSize;

      checkCurrent();
      raf = await bundle.open();
      checkCurrent();

      // windowed send
      _set(OtaTransferState.transferring, "Transferring...");
      await _sendWindowed(
        raf,
        dataChar,
        messages.stream,
        totalSize: totalSize,
        chunkSize: chunkSize,
        windowBytes: window,
        from: ack.resumeOffset,
        checkCurrent: checkCurrent,
      );

      checkCurrent();
      // Subscribe before COMPLETE: firmware may emit terminal progress in the
      // same notification burst as its acknowledgement.
      installation = StreamController<OtaStatusMessage>();
      installSub = messages.stream.listen((m) {
        if (m is OtaInstallProgress) installation!.add(m);
      }, onError: (Object e, StackTrace s) => installation!.addError(e, s));
      // completion: the scooter hashes the staged file, then queues the install
      _set(OtaTransferState.verifying, "Verifying on scooter...");
      final completeAck = await _request<OtaCompleteAck>(messages.stream, () {
        checkCurrent();
        return ctrlChar.write(OtaProtocol.encodeComplete());
      }, _completeAckTimeout);
      switch (completeAck.status) {
        case OtaProtocol.completeOk:
          break;
        case OtaProtocol.completeShaMismatch:
          throw "Transfer corrupted (checksum mismatch) — please retry";
        case OtaProtocol.completeSizeMismatch:
          throw "Transfer incomplete (size mismatch) — please retry";
        default:
          throw "Scooter could not queue the installation";
      }

      accepted = true;
      // install phase: follow INSTALL_PROGRESS until a terminal phase
      _set(OtaTransferState.installing, "Installing...");
      await _followInstall(installation.stream);
    } catch (e) {
      if (accepted && e is _OtaLinkLost) {
        awaitingReconnect = true;
        _set(OtaTransferState.installing,
            "Connection lost — installation continues on the scooter");
        return;
      }
      if (state != OtaTransferState.failure) {
        // disconnects and timeouts are resumable: the scooter keeps the
        // partial transfer and START returns the persisted offset
        resumable = state == OtaTransferState.transferring ||
            state == OtaTransferState.handshaking;
        _set(OtaTransferState.failure, e.toString());
      }
      rethrow;
    } finally {
      _interrupt = null;
      await installSub?.cancel();
      // A single-subscription buffer may never have been consumed on rejection.
      if (installation != null && !accepted) {
        installation.stream.listen((_) {}, onError: (_) {});
      }
      await installation?.close();
      await raf?.close();
      await sub?.cancel();
      await connSub?.cancel();
      await messages.close();
      try {
        if (scooter.isConnected) await statusChar.setNotifyValue(false);
      } catch (_) {}
    }
  }

  Future<T> _request<T extends OtaStatusMessage>(
      Stream<OtaStatusMessage> messages,
      Future<void> Function() write,
      Duration timeout) async {
    final result = Completer<T>();
    final sub = messages.listen((m) {
      if (m is T && !result.isCompleted) result.complete(m);
    }, onError: (Object e, StackTrace s) {
      if (!result.isCompleted) result.completeError(e, s);
    });
    final timer = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(TimeoutException('Future not completed', timeout));
      }
    });
    // Attach the error handler before awaiting the native write. Its duration
    // is intentionally not bounded by the response timeout (legacy policy).
    final observed = result.future
        .then<Object>((v) => v, onError: (Object e, StackTrace s) => (e, s));
    try {
      await write();
      final value = await observed;
      if (value is (Object, StackTrace)) {
        Error.throwWithStackTrace(value.$1, value.$2);
      }
      return value as T;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<Digest> _hashFile(File f) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in f.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single;
  }

  Future<OtaStartAck> _startHandshake(
    BluetoothDevice scooter,
    BluetoothCharacteristic ctrl,
    Stream<OtaStatusMessage> messages, {
    required int component,
    required int totalSize,
    required Uint8List sha256,
    required String bundleId,
    required void Function() checkCurrent,
  }) async {
    final start = OtaProtocol.encodeStart(
      component: component,
      chunkSize: OtaProtocol.maxChunkSize,
      totalSize: totalSize,
      sha256: sha256,
      bundleId: bundleId,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      checkCurrent();
      try {
        final ack = await _request<OtaStartAck>(messages,
            () => ctrl.write(start, allowLongWrite: true), _startAckTimeout);
        checkCurrent();
        if (!ack.accepted) {
          switch (ack.status) {
            case OtaProtocol.startNoSpace:
              throw "Not enough space on the scooter";
            case OtaProtocol.startInstalling:
              throw "An installation is already in progress";
            case OtaProtocol.startBusy:
              throw "Another transfer is in progress";
            case OtaProtocol.startAlreadyInstalled:
              throw "This version is already installed on the scooter";
            default:
              throw "Scooter rejected the transfer (code ${ack.status})";
          }
        }
        if (ack.status == OtaProtocol.startResume && ack.resumeOffset > 0) {
          log.info("Resuming transfer at offset ${ack.resumeOffset}");
        }
        return ack;
      } on TimeoutException {
        log.warning("START_ACK timeout (attempt ${attempt + 1})");
      }
    }
    throw "Scooter did not answer the transfer request";
  }

  Future<void> _sendWindowed(
    RandomAccessFile raf,
    BluetoothCharacteristic dataChar,
    Stream<OtaStatusMessage> messages, {
    required int totalSize,
    required int chunkSize,
    required int windowBytes,
    required int from,
    required void Function() checkCurrent,
  }) async {
    var acked = from; // highest cumulative acknowledged offset
    var sendPos = from; // next offset to transmit
    var lastAckAt = _now();
    var rewinds = 0;

    // rolling throughput over the last few seconds
    var rateMark = _now();
    var rateBase = from;

    // throughput diagnostics, logged every few seconds: distinguishes a
    // phone-side bottleneck (high avg write time, window never full) from a
    // scooter-side one (fast writes, sender mostly parked on a full window)
    var diagWrites = 0;
    var diagWriteMicros = 0;
    var diagWindowWaits = 0;
    var diagRewindBase = 0;
    var diagMark = _now();

    Object? streamError;
    final ackSub = messages.listen((m) {
      if (m is OtaAck) {
        if (m.offset > acked) {
          acked = m.offset;
          lastAckAt = _now();
        }
        if (m.rewind && m.offset < sendPos) {
          log.fine("Rewind requested to ${m.offset}");
          sendPos = m.offset;
          rewinds++;
        }
      } else if (m is OtaErrorMessage) {
        // nRF-side drop (suspend/overflow): the offset gap will trigger a
        // rewind; log for diagnostics only
        log.warning("Scooter OTA error ${m.code}: ${m.message}");
      }
    }, onError: (Object e) {
      streamError = e;
    });

    try {
      while (acked < totalSize) {
        checkCurrent();
        if (streamError != null) throw streamError!;
        if (_abortRequested) {
          throw "Transfer cancelled";
        }
        if (rewinds > _maxRewinds) {
          throw "Link too unstable (too many retransmissions)";
        }

        if (sendPos < totalSize && sendPos - acked < windowBytes) {
          await raf.setPosition(sendPos);
          final chunk = await raf.read(min(chunkSize, totalSize - sendPos));
          checkCurrent();
          final writeStart = _now();
          await dataChar.write(
            OtaProtocol.encodeData(sendPos, chunk),
            withoutResponse: true,
          );
          diagWriteMicros += _now().difference(writeStart).inMicroseconds;
          diagWrites++;
          sendPos += chunk.length;
        } else {
          // window full (or everything sent): wait for ACK movement
          diagWindowWaits++;
          await Future.delayed(const Duration(milliseconds: 20));
          if (_now().difference(lastAckAt) > _ackTimeout) {
            log.warning("ACK timeout, rewinding to $acked");
            sendPos = acked;
            lastAckAt = _now();
            rewinds++;
          }
        }

        if (_now().difference(diagMark).inSeconds >= 5) {
          final avgWriteMs = diagWrites > 0
              ? (diagWriteMicros / diagWrites / 1000).toStringAsFixed(1)
              : "-";
          log.info("OTA diag: ${(throughput / 1024).toStringAsFixed(1)} kB/s, "
              "$diagWrites writes (avg $avgWriteMs ms), "
              "$diagWindowWaits window-full waits, "
              "${rewinds - diagRewindBase} rewinds, "
              "in-flight ${sendPos - acked}/$windowBytes B");
          diagWrites = 0;
          diagWriteMicros = 0;
          diagWindowWaits = 0;
          diagRewindBase = rewinds;
          diagMark = _now();
        }

        // progress + throughput bookkeeping
        var dirty = false;
        final now = _now();
        final dt = now.difference(rateMark).inMilliseconds;
        if (dt >= 1000) {
          throughput = (acked - rateBase) * 1000 / dt;
          rateMark = now;
          rateBase = acked;
          dirty = true; // repaint the speed even when progress barely moves
        }
        if (acked != ackedBytes) {
          ackedBytes = acked;
          final p = acked / totalSize;
          if ((p - progress).abs() > 0.001) {
            progress = p;
            dirty = true;
          }
        }
        if (dirty) notifyListeners();
      }
      progress = 1;
      ackedBytes = totalSize;
      notifyListeners();
    } finally {
      await ackSub.cancel();
    }
  }

  Future<void> _followInstall(Stream<OtaStatusMessage> messages) async {
    await for (final m in messages) {
      if (m is! OtaInstallProgress) continue;
      switch (m.phase) {
        case OtaProtocol.phaseVerifying:
          _set(OtaTransferState.verifying, "Verifying on scooter...");
        case OtaProtocol.phaseInstalling:
          installPercent = m.percent;
          _set(OtaTransferState.installing, "Installing... ${m.percent}%");
        case OtaProtocol.phasePendingReboot:
          _set(OtaTransferState.pendingReboot,
              "Installed — the scooter reboots after 3 minutes in standby");
          return;
        case OtaProtocol.phaseSuccess:
          _set(OtaTransferState.success, "Update installed");
          return;
        case OtaProtocol.phaseFailure:
          resumable = false;
          _set(OtaTransferState.failure,
              m.message.isNotEmpty ? m.message : "Installation failed");
          throw "Installation failed: ${m.message}";
      }
    }
    // notification stream ended (disconnect) while installing: the install
    // continues on the scooter; report the state we know
    _set(OtaTransferState.installing,
        "Connection lost — installation continues on the scooter");
  }

  /// Recovers an installation that outlived the app. The scooter retains the
  /// install phase/percent (even after it finished) and answers STATUS_REQ
  /// with it, and keeps notifying INSTALL_PROGRESS while update-service
  /// works — so after a force-close the app can re-adopt the session here.
  ///
  /// Adopts a running install (or a pending reboot) into [state] and, while
  /// still running, keeps following progress notifications in the background
  /// until a terminal phase or disconnect. Stale settled outcomes (success /
  /// failure retained from an earlier session) are NOT adopted. Returns true
  /// when a session was adopted. Also confirms an accepted installation after its link was lost.
  Future<bool> syncFromScooter(
    BluetoothDevice scooter,
    CharacteristicRepository repo, {
    bool Function()? isCurrent,
    void Function()? onAdopting,
  }) async {
    if (_disposed || (state != OtaTransferState.idle && !awaitingReconnect)) {
      return false;
    }
    final recovering = awaitingReconnect;
    final ctrlChar = repo.otaControlCharacteristic;
    final statusChar = repo.otaStatusCharacteristic;
    if (ctrlChar == null || statusChar == null || scooter.isDisconnected) {
      return false;
    }

    await statusChar.setNotifyValue(true);
    final messages = StreamController<OtaStatusMessage>.broadcast();
    if (_disposed || isCurrent?.call() == false) {
      if (scooter.isConnected) await statusChar.setNotifyValue(false);
      return false;
    }
    final buffered = StreamController<OtaStatusMessage>();
    final bufferSub = messages.stream.listen((m) {
      if (m is OtaInstallProgress) buffered.add(m);
    }, onError: buffered.addError);
    var following = false;
    final sub = statusChar.onValueReceived.listen((v) {
      final m = OtaStatusMessage.parse(v);
      if (m != null && !messages.isClosed) messages.add(m);
    });

    Future<void> release() async {
      _interrupt = null;
      await bufferSub.cancel();
      if (!following) buffered.stream.listen((_) {}, onError: (_) {});
      await buffered.close();
      await sub.cancel();
      await messages.close();
      try {
        if (scooter.isConnected) await statusChar.setNotifyValue(false);
      } catch (_) {}
    }

    OtaInstallProgress? probe;
    try {
      probe = await _request<OtaInstallProgress>(
          messages.stream,
          () => ctrlChar.write(OtaProtocol.encodeStatusReq()),
          const Duration(seconds: 4));
    } catch (e) {
      log.warning("OTA status query failed: $e");
    }

    // The scooter retains the last phase indefinitely, so a stale success or
    // failure from an earlier session would be re-adopted on every screen
    // open, blocking the planning pass with a dead-end tile (the failure
    // context — active step, resume — is gone after an app restart anyway).
    // Only running installs and a pending reboot are worth re-attaching to;
    // for settled outcomes the fresh plan re-offers the step instead.
    if (_disposed ||
        isCurrent?.call() == false ||
        probe == null ||
        probe.phase == OtaProtocol.phaseIdle ||
        (!recovering &&
            (probe.phase == OtaProtocol.phaseSuccess ||
                probe.phase == OtaProtocol.phaseFailure))) {
      await release();
      return false;
    }

    // Acquire the controller's captured owner before any adopted-state
    // publication (including synchronous listeners that replace the session).
    try {
      onAdopting?.call();
    } catch (_) {
      await release();
      rethrow;
    }
    if (_disposed || isCurrent?.call() == false) {
      await release();
      return false;
    }
    awaitingReconnect = false;
    log.info(
        "Adopting scooter OTA session: phase ${probe.phase} (${probe.percent}%)");
    switch (probe.phase) {
      case OtaProtocol.phaseSuccess:
        _set(OtaTransferState.success, "Update installed");
      case OtaProtocol.phaseFailure:
        _set(OtaTransferState.failure,
            probe.message.isEmpty ? "Installation failed" : probe.message);
      case OtaProtocol.phaseVerifying:
        _set(OtaTransferState.verifying, "Verifying on scooter...");
      case OtaProtocol.phaseInstalling:
      case OtaProtocol.phaseRebooting:
        installPercent = probe.percent;
        _set(OtaTransferState.installing, "Installing... ${probe.percent}%");
      case OtaProtocol.phasePendingReboot:
        _set(OtaTransferState.pendingReboot,
            "Installed — the scooter reboots after 3 minutes in standby");
    }

    if (_disposed || isCurrent?.call() == false) {
      awaitingReconnect = state == OtaTransferState.verifying ||
          state == OtaTransferState.installing;
      await release();
      return true;
    }
    if (state == OtaTransferState.verifying ||
        state == OtaTransferState.installing) {
      following = true;
      _interrupt = () {
        if (!messages.isClosed) messages.addError(const _OtaLinkLost());
      };
      unawaited(_followAdopted(scooter, messages, buffered.stream, release));
    } else {
      // pending reboot: settled, nothing more will arrive
      await release();
    }
    return true;
  }

  /// Follows INSTALL_PROGRESS of an adopted session until a terminal phase or
  /// disconnect, then releases the notification plumbing.
  Future<void> _followAdopted(
    BluetoothDevice scooter,
    StreamController<OtaStatusMessage> messages,
    Stream<OtaStatusMessage> installation,
    Future<void> Function() release,
  ) async {
    StreamSubscription<BluetoothConnectionState>? connSub;
    try {
      connSub = scooter.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !messages.isClosed) {
          messages.addError(const _OtaLinkLost());
        }
      });
      await _followInstall(installation);
    } catch (e) {
      // phaseFailure already set the failure state in _followInstall; a
      // stream error (disconnect) keeps the last known state — the install
      // continues on the scooter and can be re-adopted later.
      if (e is _OtaLinkLost) {
        awaitingReconnect = true;
        _set(OtaTransferState.installing,
            "Connection lost — installation continues on the scooter");
      }
      log.warning("Adopted OTA session follow ended: $e");
    } finally {
      await connSub?.cancel();
      await release();
    }
  }
}

/// Minimal accumulator sink for chunked hashing (crypto package pattern).
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}

class _OtaLinkLost implements Exception {
  const _OtaLinkLost();
  @override
  String toString() => "Connection to scooter lost";
}
