import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unustasis/domain/location_url_parser.dart';

void main() {
  test('plain-text destinations do not use online geocoding by default', () async {
    final result = await LocationUrlParser.parse('Alexanderplatz, Berlin');

    expect(result, isNull);
  });

  test('plain-text destinations stay local when opt-in is false', () async {
    final result = await LocationUrlParser.parse(
      'Alexanderplatz, Berlin',
      allowOnlineGeocoding: false,
    );

    expect(result, isNull);
  });

  test('coordinates remain available without online geocoding', () async {
    final result = await LocationUrlParser.parse('52.5200, 13.4050');

    expect(result, isNotNull);
    expect(result!.location.latitude, closeTo(52.52, 0.0001));
    expect(result.location.longitude, closeTo(13.405, 0.0001));
  });

  test('short-link redirects never request an HTTP downgrade', () async {
    final requested = <Uri>[];
    final result = await LocationUrlParser.parse(
      'https://maps.app.goo.gl/example',
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://maps.example.test/place'},
        );
      }),
    );

    expect(result, isNull);
    expect(requested, isNotEmpty);
    expect(requested.every((uri) => uri.scheme == 'https'), isTrue);
  });

  test('Google page redirects never request an HTTP downgrade', () async {
    final requested = <Uri>[];
    final result = await LocationUrlParser.parse(
      'https://www.google.com/maps/place/example',
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://maps.example.test/place'},
        );
      }),
    );

    expect(result, isNull);
    expect(requested, hasLength(1));
    expect(requested.single.scheme, 'https');
  });

  test('short links still follow relative HTTPS redirects', () async {
    final requested = <Uri>[];
    final result = await LocationUrlParser.parse(
      'https://maps.app.goo.gl/example',
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/example') {
          return http.Response('', 302, headers: {'location': '/resolved'});
        }
        return http.Response('<meta content="/@52.5200,13.4050">', 200);
      }),
    );

    expect(result, isNotNull);
    expect(result!.location.latitude, closeTo(52.52, 0.0001));
    expect(requested.map((uri) => uri.scheme), everyElement('https'));
  });
}
