import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:unustasis/service/battery_handoff_client.dart';

class _Client extends MockClient {
  _Client(super.fn);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  final battery = BatteryIdentity(
    serialNumber: '00000000000000AB',
    source: BatteryIdentitySource.nfc,
    checkedAt: DateTime.utc(2026),
  );
  final challenge = 'a' * 43;
  final code = 'b' * 43;
  Map<String, dynamic> responseData({bool claim = false}) => {
        claim ? 'code' : 'challenge': claim ? code : challenge,
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
      };
  http.Response jsonResponse(Map<String, dynamic> data) =>
      http.Response(jsonEncode(data), 201, headers: {'content-type': 'application/json; charset=utf-8'});
  Matcher failure(BatteryHandoffFailure reason) =>
      isA<BatteryHandoffException>().having((e) => e.reason, 'reason', reason);

  test('only the explicit prepare call sends data, then returns an opaque fixed-origin URL', () async {
    final requests = <http.Request>[];
    final client = _Client((request) async {
      requests.add(request);
      return jsonResponse(responseData(claim: requests.length == 2));
    });
    final service = BatteryHandoffClient(clientFactory: () => client);
    expect(requests, isEmpty);
    final handoff = await service.prepare(battery);
    expect(requests.length, 2);
    expect(requests.map((r) => r.url.path), ['/api/v1/battery_tracker/challenges', '/api/v1/battery_tracker/claims']);
    for (final request in requests) {
      expect(request.method, 'POST');
      expect(request.url.scheme, 'https');
      expect(request.url.host, batteryTrackerHost);
      expect(request.url.hasQuery, isFalse);
      expect(request.followRedirects, isFalse);
      expect(request.headers['cookie'], isNull);
      expect(request.headers['authorization'], isNull);
    }
    expect(jsonDecode(requests.first.body), isEmpty);
    expect(jsonDecode(requests.last.body),
        {'challenge': challenge, 'serial_number': battery.serialNumber, 'source': 'nfc'});
    expect(handoff.uri, Uri.https(batteryTrackerHost, '/battery_tracker/handoff').replace(fragment: 'code=$code'));
    expect(handoff.uri.hasQuery, isFalse);
    expect(handoff.uri.toString(), isNot(contains(battery.serialNumber)));
    expect(client.closed, isTrue);
  });

  for (final status in [200, 301, 302, 303, 307, 308, 400, 401, 403, 409, 410, 422, 429, 500, 503]) {
    test('HTTP $status is sanitized and never followed or automatically retried', () async {
      var requests = 0;
      final client = _Client((_) async {
        requests++;
        return http.Response('private serial $code', status, headers: {'location': 'https://attacker.test/'});
      });
      await expectLater(BatteryHandoffClient(clientFactory: () => client).prepare(battery),
          throwsA(failure(status == 429 ? BatteryHandoffFailure.rateLimited : BatteryHandoffFailure.unavailable)));
      expect(requests, 1);
      expect(client.closed, isTrue);
    });
  }

  for (final badToken in [null, '', 'a' * 42, 'a' * 44, '../$code', 'private serial']) {
    test('rejects malformed challenge token $badToken before sharing a serial', () async {
      var requests = 0;
      final client = _Client((_) async {
        requests++;
        return jsonResponse({...responseData(), 'challenge': badToken});
      });
      await expectLater(BatteryHandoffClient(clientFactory: () => client).prepare(battery),
          throwsA(failure(BatteryHandoffFailure.invalidResponse)));
      expect(requests, 1);
      expect(client.closed, isTrue);
    });
  }

  test('rejects expired or unbounded expiry before sharing a serial', () async {
    for (final expiry in [
      null,
      'invalid',
      DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String(),
      DateTime.now().add(const Duration(days: 1)).toIso8601String()
    ]) {
      var requests = 0;
      final client = _Client((_) async {
        requests++;
        return jsonResponse({...responseData(), 'expires_at': expiry});
      });
      await expectLater(BatteryHandoffClient(clientFactory: () => client).prepare(battery),
          throwsA(failure(BatteryHandoffFailure.invalidResponse)));
      expect(requests, 1);
    }
  });

  test('ignores untrusted response URLs and only uses the opaque code on the fixed origin', () async {
    var requests = 0;
    final client = _Client((_) async => jsonResponse({
          ...responseData(claim: ++requests == 2),
          'url': 'https://attacker.test/?serial=${battery.serialNumber}',
        }));
    final handoff = await BatteryHandoffClient(clientFactory: () => client).prepare(battery);
    expect(handoff.uri.host, batteryTrackerHost);
    expect(handoff.uri.hasQuery, isFalse);
    expect(handoff.uri.fragment, 'code=$code');
  });

  test('invalid claim response cannot become a browser URL', () async {
    var requests = 0;
    final client = _Client((_) async => jsonResponse(++requests == 1
        ? responseData()
        : {
            ...responseData(claim: true),
            'code': 'https://attacker.test',
          }));
    await expectLater(BatteryHandoffClient(clientFactory: () => client).prepare(battery),
        throwsA(failure(BatteryHandoffFailure.invalidResponse)));
    expect(requests, 2);
  });

  test('non-JSON, malformed, non-object and oversized responses cannot leak content', () async {
    for (final response in [
      http.Response('private serial', 201),
      http.Response('private serial', 201, headers: {'content-type': 'application/json'}),
      http.Response('[]', 201, headers: {'content-type': 'application/json'}),
      http.Response('x' * 4097, 201, headers: {'content-type': 'application/json'}),
    ]) {
      var requests = 0;
      final client = _Client((_) async {
        requests++;
        return response;
      });
      try {
        await BatteryHandoffClient(clientFactory: () => client).prepare(battery);
        fail('must reject malformed response');
      } on BatteryHandoffException catch (error) {
        expect(error.toString(), isNot(contains('private serial')));
        expect(error.toString(), isNot(contains(code)));
      }
      expect(requests, 1);
      expect(client.closed, isTrue);
    }
  });

  test('cancelling during challenge closes the client and prevents serial upload', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = _Client((_) {
      requests++;
      return response.future;
    });
    final service = BatteryHandoffClient(clientFactory: () => client);
    final pending = service.prepare(battery);
    await Future<void>.delayed(Duration.zero);
    final check = expectLater(pending, throwsA(failure(BatteryHandoffFailure.cancelled)));
    service.cancel();
    expect(client.closed, isTrue);
    response.complete(jsonResponse(responseData()));
    await check;
    expect(requests, 1);
  });

  test('timeout closes the client and a late challenge cannot initiate a claim', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = _Client((_) {
      requests++;
      return response.future;
    });
    final service = BatteryHandoffClient(clientFactory: () => client, timeout: const Duration(milliseconds: 10));
    await expectLater(service.prepare(battery), throwsA(failure(BatteryHandoffFailure.unavailable)));
    expect(client.closed, isTrue);
    response.complete(jsonResponse(responseData()));
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
  });

  test('streamed responses without Content-Length are bounded before JSON decoding', () async {
    var requests = 0;
    final client = MockClient.streaming((request, body) async {
      requests++;
      await body.drain<void>();
      return http.StreamedResponse(Stream.fromIterable([List.filled(2048, 0x20), List.filled(2049, 0x20)]), 201,
          headers: {'content-type': 'application/json'});
    });
    await expectLater(BatteryHandoffClient(clientFactory: () => client).prepare(battery),
        throwsA(failure(BatteryHandoffFailure.invalidResponse)));
    expect(requests, 1);
  });

  test('cancelling a claimed response does not return a browser handoff', () async {
    final response = Completer<http.Response>();
    final enteredClaim = Completer<void>();
    var requests = 0;
    final client = _Client((_) {
      if (++requests == 1) return Future.value(jsonResponse(responseData()));
      enteredClaim.complete();
      return response.future;
    });
    final service = BatteryHandoffClient(clientFactory: () => client);
    final pending = service.prepare(battery);
    final check = expectLater(pending, throwsA(failure(BatteryHandoffFailure.cancelled)));
    await enteredClaim.future;
    service.cancel();
    response.complete(jsonResponse(responseData(claim: true)));
    await check;
    expect(requests, 2);
    expect(client.closed, isTrue);
  });

  test('a cancelled request cannot cancel or submit data through a newer client', () async {
    final oldResponse = Completer<http.Response>();
    final newResponse = Completer<http.Response>();
    var oldRequests = 0;
    var newRequests = 0;
    final oldClient = _Client((_) {
      oldRequests++;
      return oldResponse.future;
    });
    final newClient = _Client((_) {
      if (++newRequests == 1) return newResponse.future;
      return Future.value(jsonResponse(responseData(claim: true)));
    });
    var clients = 0;
    final service = BatteryHandoffClient(clientFactory: () => clients++ == 0 ? oldClient : newClient);
    final old = service.prepare(battery);
    final check = expectLater(old, throwsA(failure(BatteryHandoffFailure.cancelled)));
    service.cancel();
    final current = service.prepare(battery);
    oldResponse.complete(jsonResponse(responseData()));
    await check;
    expect(newClient.closed, isFalse);
    newResponse.complete(jsonResponse(responseData()));
    expect((await current).uri.host, batteryTrackerHost);
    expect(oldRequests, 1);
    expect(newRequests, 2);
    expect(newClient.closed, isTrue);
  });

  test('explicit retry after ambiguous POST recovers the same claim with HTTP 200', () async {
    final requests = <http.Request>[];
    final service = BatteryHandoffClient(
        clientFactory: () => _Client((request) async {
              requests.add(request);
              if (requests.length == 1) return jsonResponse(responseData());
              if (requests.length == 2) throw http.ClientException('response lost');
              return http.Response(jsonEncode(responseData(claim: true)), 200,
                  headers: {'content-type': 'application/json'});
            }));
    await expectLater(service.prepare(battery), throwsA(failure(BatteryHandoffFailure.unavailable)));
    expect(requests.length, 2);
    final handoff = await service.prepare(battery);
    expect(requests.length, 3);
    expect(requests[2].url, requests[1].url);
    expect(requests[2].body, requests[1].body);
    expect(handoff.uri.fragment, 'code=$code');
  });

  test('expired challenge is discarded without an automatic retry', () async {
    final requests = <http.Request>[];
    final service = BatteryHandoffClient(
        clientFactory: () => _Client((request) async {
              requests.add(request);
              if (requests.length == 2) return http.Response('', 410);
              return jsonResponse(responseData(claim: requests.length == 4));
            }));
    await expectLater(service.prepare(battery), throwsA(failure(BatteryHandoffFailure.unavailable)));
    expect(requests.length, 2);
    await service.prepare(battery);
    expect(requests.length, 4);
    expect(requests[2].url.path, '/api/v1/battery_tracker/challenges');
  });

  test('cancel discards the retained retry nonce', () async {
    var requests = 0;
    final paths = <String>[];
    final service = BatteryHandoffClient(
        clientFactory: () => _Client((request) async {
              paths.add(request.url.path);
              if (++requests == 2) throw http.ClientException('response lost');
              return jsonResponse(responseData(claim: requests == 4));
            }));
    await expectLater(service.prepare(battery), throwsA(failure(BatteryHandoffFailure.unavailable)));
    service.cancel();
    await service.prepare(battery);
    expect(paths, [
      '/api/v1/battery_tracker/challenges',
      '/api/v1/battery_tracker/claims',
      '/api/v1/battery_tracker/challenges',
      '/api/v1/battery_tracker/claims'
    ]);
  });

  test('a changed battery cannot reuse a pending nonce with different data', () async {
    final requests = <http.Request>[];
    final service = BatteryHandoffClient(
        clientFactory: () => _Client((request) async {
              requests.add(request);
              if (requests.length == 2) throw http.ClientException('response lost');
              return jsonResponse(responseData(claim: requests.length == 4));
            }));
    await expectLater(service.prepare(battery), throwsA(failure(BatteryHandoffFailure.unavailable)));
    final other = BatteryIdentity(
        serialNumber: '00000000000000AC', source: BatteryIdentitySource.ble, checkedAt: DateTime.utc(2026));
    await service.prepare(other);
    expect(requests.length, 4);
    expect(requests[2].url.path, '/api/v1/battery_tracker/challenges');
    expect(jsonDecode(requests[3].body)['serial_number'], other.serialNumber);
    expect(jsonDecode(requests[3].body)['source'], 'ble');
  });

  test('HTTP exception details are not exposed', () async {
    final client = _Client((_) async => throw http.ClientException('private serial $code'));
    try {
      await BatteryHandoffClient(clientFactory: () => client).prepare(battery);
      fail('must fail');
    } on BatteryHandoffException catch (error) {
      expect(error.toString(), 'Battery handoff failed: unavailable');
    }
    expect(client.closed, isTrue);
  });
}
