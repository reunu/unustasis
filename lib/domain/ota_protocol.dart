import 'dart:typed_data';

/// Byte-level encoding of the librescoot BLE OTA transfer protocol.
///
/// Mirrors bluetooth-service's pkg/ota/protocol.go — keep the two in sync
/// (shared golden vectors live in test/ota_protocol_test.dart and
/// pkg/ota/protocol_test.go). All multi-byte fields are little-endian.
///
/// Transport: DATA payloads are written to the OTA_DATA characteristic
/// (write without response), control messages to OTA_CONTROL (write with
/// response), and the scooter answers with notifications on OTA_STATUS.
class OtaProtocol {
  // Phone -> scooter control opcodes.
  static const int opStart = 0x01;
  static const int opComplete = 0x03;
  static const int opAbort = 0x04;
  static const int opStatusReq = 0x05;

  // Scooter -> phone opcodes.
  static const int opStartAck = 0x81;
  static const int opAck = 0x82;
  static const int opCompleteAck = 0x83;
  static const int opInstallProgress = 0x84;
  static const int opAbortAck = 0x85;
  static const int opError = 0x86;

  // START_ACK status codes.
  static const int startResume = 0x00;
  static const int startNew = 0x01;
  static const int startNoSpace = 0x10;
  static const int startBusy = 0x11;
  static const int startBadParams = 0x12;
  static const int startInstalling = 0x13;

  // ACK flags.
  static const int ackFlagRewind = 0x01;

  // COMPLETE_ACK status codes.
  static const int completeOk = 0x00;
  static const int completeShaMismatch = 0x01;
  static const int completeSizeMismatch = 0x02;
  static const int completeQueueFailed = 0x03;

  // INSTALL_PROGRESS phases.
  static const int phaseVerifying = 0x00;
  static const int phaseInstalling = 0x01;
  static const int phasePendingReboot = 0x02;
  static const int phaseRebooting = 0x03;
  static const int phaseSuccess = 0x04;
  static const int phaseFailure = 0x05;
  static const int phaseIdle = 0x06;

  // ERROR codes (1 and 2 originate on the nRF tunnel itself).
  static const int errSuspendedCode = 0x01;
  static const int errOverflowCode = 0x02;
  static const int errInternalCode = 0x03;
  static const int errWriteFailedCode = 0x04;
  static const int errNoSpaceCode = 0x05;
  static const int errNoSessionCode = 0x06;

  // ABORT reasons.
  static const int abortUserCancel = 0x00;
  static const int abortAppError = 0x01;

  // Components.
  static const int componentMdb = 0x00;
  static const int componentDbc = 0x01;

  /// The largest chunk the scooter accepts (fits ATT MTU 247).
  static const int maxChunkSize = 240;

  static Uint8List encodeStart({
    required int component,
    required int chunkSize,
    required int totalSize,
    required Uint8List sha256,
    required String bundleId,
    int version = 1,
  }) {
    assert(sha256.length == 32);
    final id = bundleId.codeUnits;
    assert(id.isNotEmpty && id.length <= 64);
    final b = BytesBuilder();
    b.addByte(opStart);
    b.addByte(version);
    b.addByte(component);
    b.add(_u16(chunkSize));
    b.add(_u32(totalSize));
    b.add(sha256);
    b.addByte(id.length);
    b.add(id);
    return b.toBytes();
  }

  static Uint8List encodeData(int offset, List<int> chunk) {
    final b = BytesBuilder();
    b.add(_u32(offset));
    b.add(chunk);
    return b.toBytes();
  }

  static Uint8List encodeComplete() => Uint8List.fromList([opComplete]);

  static Uint8List encodeAbort(int reason) => Uint8List.fromList([opAbort, reason]);

  static Uint8List encodeStatusReq() => Uint8List.fromList([opStatusReq]);

  static Uint8List _u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    return b.buffer.asUint8List();
  }
}

/// A parsed OTA_STATUS notification.
sealed class OtaStatusMessage {
  const OtaStatusMessage();

  /// Parses a notification payload; returns null for unknown or malformed
  /// messages (forward compatibility: ignore what we don't understand).
  static OtaStatusMessage? parse(List<int> raw) {
    if (raw.isEmpty) return null;
    final p = Uint8List.fromList(raw);
    final d = ByteData.sublistView(p);
    switch (p[0]) {
      case OtaProtocol.opStartAck:
        if (p.length < 11) return null;
        return OtaStartAck(
          status: p[1],
          resumeOffset: d.getUint32(2, Endian.little),
          windowChunks: d.getUint16(6, Endian.little),
          ackEvery: p[8],
          maxChunk: d.getUint16(9, Endian.little),
        );
      case OtaProtocol.opAck:
        if (p.length < 6) return null;
        return OtaAck(
          flags: p[1],
          offset: d.getUint32(2, Endian.little),
        );
      case OtaProtocol.opCompleteAck:
        if (p.length < 2) return null;
        return OtaCompleteAck(status: p[1]);
      case OtaProtocol.opInstallProgress:
        if (p.length < 4) return null;
        final len = p[3];
        final msg = p.length >= 4 + len ? String.fromCharCodes(p.sublist(4, 4 + len)) : "";
        return OtaInstallProgress(phase: p[1], percent: p[2], message: msg);
      case OtaProtocol.opAbortAck:
        return const OtaAbortAck();
      case OtaProtocol.opError:
        if (p.length < 3) return null;
        final len = p[2];
        final msg = p.length >= 3 + len ? String.fromCharCodes(p.sublist(3, 3 + len)) : "";
        return OtaErrorMessage(code: p[1], message: msg);
      default:
        return null;
    }
  }
}

class OtaStartAck extends OtaStatusMessage {
  final int status;
  final int resumeOffset;
  final int windowChunks;
  final int ackEvery;
  final int maxChunk;
  const OtaStartAck({
    required this.status,
    required this.resumeOffset,
    required this.windowChunks,
    required this.ackEvery,
    required this.maxChunk,
  });

  bool get accepted => status == OtaProtocol.startResume || status == OtaProtocol.startNew;
}

class OtaAck extends OtaStatusMessage {
  final int flags;
  final int offset;
  const OtaAck({required this.flags, required this.offset});

  bool get rewind => flags & OtaProtocol.ackFlagRewind != 0;
}

class OtaCompleteAck extends OtaStatusMessage {
  final int status;
  const OtaCompleteAck({required this.status});
}

class OtaInstallProgress extends OtaStatusMessage {
  final int phase;
  final int percent;
  final String message;
  const OtaInstallProgress({required this.phase, required this.percent, required this.message});
}

class OtaAbortAck extends OtaStatusMessage {
  const OtaAbortAck();
}

class OtaErrorMessage extends OtaStatusMessage {
  final int code;
  final String message;
  const OtaErrorMessage({required this.code, required this.message});
}
