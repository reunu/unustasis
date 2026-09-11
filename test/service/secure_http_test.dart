import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unustasis/service/secure_http.dart';

void main() {
  test('rejects cleartext endpoint before creating a client', () async {
    var createdClient = false;

    await expectLater(
      httpsGet(
        Uri.parse('http://example.test/data'),
        clientFactory: () {
          createdClient = true;
          return MockClient((_) async => http.Response('', 200));
        },
      ),
      throwsArgumentError,
    );
    expect(createdClient, isFalse);
  });

  test('rejects redirects from a fixed HTTPS endpoint', () async {
    final requested = <Uri>[];

    await expectLater(
      httpsGet(
        Uri.parse('https://example.test/data'),
        clientFactory: () => MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            '',
            302,
            headers: {'location': 'http://example.test/cleartext'},
          );
        }),
      ),
      throwsStateError,
    );
    expect(requested, [Uri.parse('https://example.test/data')]);
  });

  test('returns a successful fixed HTTPS response', () async {
    final response = await httpsGet(
      Uri.parse('https://example.test/data'),
      clientFactory: () => MockClient(
        (_) async => http.Response('ok', 200),
      ),
    );

    expect(response.body, 'ok');
  });
}
