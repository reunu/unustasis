import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../domain/ota_protocol.dart';
import '../infrastructure/characteristic_repository.dart';

final log = Logger('OtaTransferService');

enum OtaTransferState {
  idle,
  hashing,
  handshaking,
  transferring,
  verifying,
  installing,
  pendingReboot,
  success,
  failure,
}

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
  OtaTransferState state = OtaTransferState.idle;

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
  }) async {
    if (busy) throw StateError("transfer already running");
    final dataChar = repo.otaDataCharacteristic;
    final ctrlChar = repo.otaControlCharacteristic;
    final statusChar = repo.otaStatusCharacteristic;
    if (dataChar == null || ctrlChar == null || statusChar == null) {
      throw "OTA characteristics not available (firmware too old?)";
    }

    _abortRequested = false;
    resumable = false;
    installPercent = 0;
    progress = 0;
    throughput = 0;
    ackedBytes = 0;

    final totalSize = await bundle.length();
    totalBytes = totalSize;

    _set(OtaTransferState.hashing, "Preparing bundle...");
    final digest = await _hashFile(bundle);

    StreamSubscription<List<int>>? sub;
    StreamSubscription<BluetoothConnectionState>? connSub;
    final messages = StreamController<OtaStatusMessage>.broadcast();
    RandomAccessFile? raf;
    try {
      await statusChar.setNotifyValue(true);
      sub = statusChar.onValueReceived.listen((v) {
        final m = OtaStatusMessage.parse(v);
        if (m != null) messages.add(m);
      });
      // a disconnect must unblock everything awaiting scooter messages
      connSub = scooter.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !messages.isClosed) {
          messages.addError("Connection to scooter lost");
        }
      });

      // handshake
      _set(OtaTransferState.handshaking, "Contacting scooter...");
      final ack = await _startHandshake(
        scooter, ctrlChar, messages.stream,
        component: component,
        totalSize: totalSize,
        sha256: Uint8List.fromList(digest.bytes),
        bundleId: bundleId,
      );

      final chunkSize = min(
        ack.maxChunk,
        min(OtaProtocol.maxChunkSize, max(20, scooter.mtuNow - 3 - 4)),
      );
      final window = max(1, ack.windowChunks) * chunkSize;

      raf = await bundle.open();

      // windowed send
      _set(OtaTransferState.transferring, "Transferring...");
      await _sendWindowed(
        raf, dataChar, messages.stream,
        totalSize: totalSize,
        chunkSize: chunkSize,
        windowBytes: window,
        from: ack.resumeOffset,
      );

      // completion: the scooter hashes the staged file, then queues the install
      _set(OtaTransferState.verifying, "Verifying on scooter...");
      final completion = messages.stream
          .where((m) => m is OtaCompleteAck)
          .cast<OtaCompleteAck>()
          .first
          .timeout(_completeAckTimeout);
      await ctrlChar.write(OtaProtocol.encodeComplete());
      final completeAck = await completion;
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

      // install phase: follow INSTALL_PROGRESS until a terminal phase
      _set(OtaTransferState.installing, "Installing...");
      await _followInstall(messages.stream);
    } catch (e) {
      if (state != OtaTransferState.failure) {
        // disconnects and timeouts are resumable: the scooter keeps the
        // partial transfer and START returns the persisted offset
        resumable = state == OtaTransferState.transferring ||
            state == OtaTransferState.handshaking;
        _set(OtaTransferState.failure, e.toString());
      }
      rethrow;
    } finally {
      await raf?.close();
      await sub?.cancel();
      await connSub?.cancel();
      await messages.close();
      try {
        if (scooter.isConnected) await statusChar.setNotifyValue(false);
      } catch (_) {}
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
  }) async {
    final start = OtaProtocol.encodeStart(
      component: component,
      chunkSize: OtaProtocol.maxChunkSize,
      totalSize: totalSize,
      sha256: sha256,
      bundleId: bundleId,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      final ackFuture = messages
          .where((m) => m is OtaStartAck)
          .cast<OtaStartAck>()
          .first
          .timeout(_startAckTimeout);
      await ctrl.write(start, allowLongWrite: true);
      try {
        final ack = await ackFuture;
        if (!ack.accepted) {
          switch (ack.status) {
            case OtaProtocol.startNoSpace:
              throw "Not enough space on the scooter";
            case OtaProtocol.startInstalling:
              throw "An installation is already in progress";
            case OtaProtocol.startBusy:
              throw "Another transfer is in progress";
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
  }) async {
    var acked = from; // highest cumulative acknowledged offset
    var sendPos = from; // next offset to transmit
    var lastAckAt = DateTime.now();
    var rewinds = 0;

    // rolling throughput over the last few seconds
    var rateMark = DateTime.now();
    var rateBase = from;

    final ackSub = messages.listen((m) {
      if (m is OtaAck) {
        if (m.offset > acked) {
          acked = m.offset;
          lastAckAt = DateTime.now();
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
    }, onError: (_) {
      // disconnects surface through the write path / awaited futures
    });

    try {
      while (acked < totalSize) {
        if (_abortRequested) {
          throw "Transfer cancelled";
        }
        if (rewinds > _maxRewinds) {
          throw "Link too unstable (too many retransmissions)";
        }

        if (sendPos < totalSize && sendPos - acked < windowBytes) {
          await raf.setPosition(sendPos);
          final chunk = await raf.read(min(chunkSize, totalSize - sendPos));
          await dataChar.write(
            OtaProtocol.encodeData(sendPos, chunk),
            withoutResponse: true,
          );
          sendPos += chunk.length;
        } else {
          // window full (or everything sent): wait for ACK movement
          await Future.delayed(const Duration(milliseconds: 20));
          if (DateTime.now().difference(lastAckAt) > _ackTimeout) {
            log.warning("ACK timeout, rewinding to $acked");
            sendPos = acked;
            lastAckAt = DateTime.now();
            rewinds++;
          }
        }

        // progress + throughput bookkeeping
        var dirty = false;
        final now = DateTime.now();
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
              "Installed — lock the scooter to reboot and finish the update");
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
}

/// Minimal accumulator sink for chunked hashing (crypto package pattern).
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
