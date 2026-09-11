import 'package:scooter_core/ota_update.dart';
import 'package:test/test.dart';

void main() {
  test('transfer enum preserves wire/presentation names and order', () {
    expect(OtaTransferState.values.map((s) => s.name), [
      'idle',
      'hashing',
      'handshaking',
      'transferring',
      'verifying',
      'installing',
      'pendingReboot',
      'success',
      'failure',
    ]);
  });
  test('HTTP/check errors retain structured presentation inputs', () {
    const http = UpdateHttpError(503, index: true);
    const error = UpdateCheckError(http);
    expect(error.cause, same(http));
    expect(http.statusCode, 503);
    expect(http.index, true);
    expect(http.toString(), 'Index failed (HTTP 503)');
    expect(const UpdateHttpError(404, index: false).toString(),
        'Download failed (HTTP 404)');
  });
}
