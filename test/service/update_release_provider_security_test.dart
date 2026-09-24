import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:unustasis/service/update_release_provider.dart';

void main() {
  test('firmware bundle downloads require HTTPS', () async {
    const asset = FirmwareAsset(
      name: 'firmware.mender',
      url: 'http://downloads.example.test/firmware.mender',
      size: 1,
    );

    await expectLater(
      AppUpdateReleaseProvider().fetchBundle(asset),
      throwsArgumentError,
    );
  });

  test('firmware redirects never request an HTTP downgrade', () async {
    final requested = <Uri>[];
    final provider = AppUpdateReleaseProvider(
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://cdn.example.test/firmware.mender'},
        );
      }),
    );
    const asset = FirmwareAsset(
      name: 'firmware.mender',
      url: 'https://downloads.example.test/firmware.mender',
      size: 1,
    );

    await expectLater(provider.fetchBundle(asset), throwsStateError);
    expect(requested, hasLength(1));
    expect(requested.single.scheme, 'https');
  });

  test('firmware follows relative HTTPS redirects', () async {
    final requested = <Uri>[];
    final provider = AppUpdateReleaseProvider(
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        if (request.url.host == 'downloads.example.test') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example.test/firmware.mender'},
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    const asset = FirmwareAsset(
      name: 'firmware.mender',
      url: 'https://downloads.example.test/firmware.mender',
      size: 3,
    );

    final download = await provider.fetchBundle(asset);
    expect((await download.bytes.toList()).expand((chunk) => chunk), [1, 2, 3]);
    download.close();
    expect(requested, hasLength(2));
    expect(requested.map((uri) => uri.scheme), everyElement('https'));
  });

  test('firmware redirect loops are bounded', () async {
    var requestCount = 0;
    final provider = AppUpdateReleaseProvider(
      clientFactory: () => MockClient((request) async {
        requestCount++;
        return http.Response('', 302, headers: {'location': '/again'});
      }),
    );
    const asset = FirmwareAsset(
      name: 'firmware.mender',
      url: 'https://downloads.example.test/firmware.mender',
      size: 1,
    );

    await expectLater(provider.fetchBundle(asset), throwsStateError);
    expect(requestCount, 6);
  });
}
