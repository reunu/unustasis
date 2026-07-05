import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/ota_protocol.dart';

/// Golden vectors shared with bluetooth-service
/// (pkg/ota/protocol_test.go TestGoldenVectors) — keep in sync.
String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('golden vectors', () {
    test('start', () {
      final sha = Uint8List.fromList(List.generate(32, (i) => i));
      final got = OtaProtocol.encodeStart(
        component: OtaProtocol.componentMdb,
        chunkSize: 240,
        totalSize: 0x01020304,
        sha256: sha,
        bundleId: 'bundle-v1',
      );
      expect(
        hexOf(got),
        '010100f0000403020100010203040506'
        '0708090a0b0c0d0e0f10111213141516'
        '1718191a1b1c1d1e1f'
        '09${hexOf('bundle-v1'.codeUnits)}',
      );
    });

    test('data', () {
      expect(hexOf(OtaProtocol.encodeData(0xAABBCCDD, [0xde, 0xad])), 'ddccbbaadead');
    });

    test('start_ack parse', () {
      final m = OtaStatusMessage.parse(fromHex('810000000100400010f000'));
      expect(m, isA<OtaStartAck>());
      final ack = m as OtaStartAck;
      expect(ack.status, OtaProtocol.startResume);
      expect(ack.resumeOffset, 0x00010000);
      expect(ack.windowChunks, 64);
      expect(ack.ackEvery, 16);
      expect(ack.maxChunk, 240);
      expect(ack.accepted, isTrue);
    });

    test('ack parse', () {
      final m = OtaStatusMessage.parse(fromHex('820178563412'));
      expect(m, isA<OtaAck>());
      final ack = m as OtaAck;
      expect(ack.rewind, isTrue);
      expect(ack.offset, 0x12345678);
    });

    test('complete_ack parse', () {
      final m = OtaStatusMessage.parse(fromHex('8300'));
      expect(m, isA<OtaCompleteAck>());
      expect((m as OtaCompleteAck).status, OtaProtocol.completeOk);
    });

    test('install_progress parse', () {
      final m = OtaStatusMessage.parse(fromHex('84012a026f6b'));
      expect(m, isA<OtaInstallProgress>());
      final p = m as OtaInstallProgress;
      expect(p.phase, OtaProtocol.phaseInstalling);
      expect(p.percent, 42);
      expect(p.message, 'ok');
    });

    test('error parse', () {
      final m = OtaStatusMessage.parse(fromHex('86020a${hexOf('E:overflow'.codeUnits)}'));
      expect(m, isA<OtaErrorMessage>());
      final e = m as OtaErrorMessage;
      expect(e.code, OtaProtocol.errOverflowCode);
      expect(e.message, 'E:overflow');
    });

    test('abort_ack parse', () {
      expect(OtaStatusMessage.parse(fromHex('85')), isA<OtaAbortAck>());
    });
  });

  group('robustness', () {
    test('unknown opcode ignored', () {
      expect(OtaStatusMessage.parse([0x7F, 1, 2]), isNull);
    });
    test('truncated messages ignored', () {
      expect(OtaStatusMessage.parse([OtaProtocol.opStartAck, 0]), isNull);
      expect(OtaStatusMessage.parse([OtaProtocol.opAck, 0, 1]), isNull);
      expect(OtaStatusMessage.parse([]), isNull);
    });
    test('control encodings', () {
      expect(hexOf(OtaProtocol.encodeComplete()), '03');
      expect(hexOf(OtaProtocol.encodeAbort(OtaProtocol.abortUserCancel)), '0400');
      expect(hexOf(OtaProtocol.encodeStatusReq()), '05');
    });
  });
}
