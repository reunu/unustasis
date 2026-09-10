import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unustasis/cloud_service.dart';
import 'package:unustasis/scooter_service.dart';

class _FakeScooterService extends Fake implements ScooterService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late CloudService service;
  late List<http.Request> requests;
  late MockClient client;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'oauth_state': 'saved-state',
      'oauth_code_verifier': 'test-verifier',
    });
    service = CloudService(_FakeScooterService());
    requests = [];
    client = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode({
            'access_token': 'test-access',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
          }),
          200);
    });
  });

  Future<bool> callback(String query) => http.runWithClient(
        () => service.handleOAuthCallback(Uri.parse('unustasis://oauth/callback?$query')),
        () => client,
      );

  group('CloudService.handleOAuthCallback', () {
    for (final missing in ['callback', 'stored', 'both']) {
      test('rejects missing $missing state before token exchange', () async {
        if (missing != 'callback') await storage.delete(key: 'oauth_state');
        final query = missing == 'stored' ? 'code=test-code&state=saved-state' : 'code=test-code';

        expect(await callback(query), isFalse);
        expect(requests, isEmpty);
        expect(await storage.read(key: 'access_token'), isNull);
        expect(await storage.read(key: 'oauth_code_verifier'), 'test-verifier');
      });
    }

    test('rejects mismatched state before token exchange', () async {
      expect(await callback('code=test-code&state=other-state'), isFalse);
      expect(requests, isEmpty);
      expect(await storage.read(key: 'oauth_state'), 'saved-state');
    });

    test('rejects missing authorization code', () async {
      expect(await callback('state=saved-state'), isFalse);
      expect(requests, isEmpty);
    });

    test('still requires the PKCE verifier with matching state', () async {
      await storage.delete(key: 'oauth_code_verifier');
      expect(await callback('code=test-code&state=saved-state'), isFalse);
      expect(requests, isEmpty);
    });

    test('matching state exchanges code with PKCE, saves tokens and clears temporary secrets', () async {
      expect(await callback('code=test-code&state=saved-state'), isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/oauth/token');
      expect(requests.single.bodyFields, containsPair('code', 'test-code'));
      expect(requests.single.bodyFields, containsPair('code_verifier', 'test-verifier'));
      expect(requests.single.bodyFields, containsPair('grant_type', 'authorization_code'));
      expect(await storage.read(key: 'access_token'), 'test-access');
      expect(await storage.read(key: 'refresh_token'), 'test-refresh');
      expect(DateTime.parse((await storage.read(key: 'token_expires_at'))!).isAfter(DateTime.now()), isTrue);
      expect(await storage.read(key: 'oauth_state'), isNull);
      expect(await storage.read(key: 'oauth_code_verifier'), isNull);

      expect(await callback('code=test-code&state=saved-state'), isFalse);
      expect(requests, hasLength(1), reason: 'A consumed callback must not exchange tokens again');
    });
  });
}
