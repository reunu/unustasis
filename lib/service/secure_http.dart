import 'package:http/http.dart' as http;

/// Performs a single HTTPS GET without allowing an implicit redirect to a
/// cleartext endpoint. Callers with an intentional redirect policy must
/// validate every hop before sending it instead.
Future<http.Response> httpsGet(
  Uri uri, {
  Map<String, String>? headers,
  http.Client Function()? clientFactory,
}) async {
  if (uri.scheme.toLowerCase() != 'https') {
    throw ArgumentError.value(uri, 'uri', 'HTTPS is required');
  }

  final client = (clientFactory ?? http.Client.new)();
  try {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(headers ?? const {});
    final streamed = await client.send(request);
    if (_isRedirectStatus(streamed.statusCode)) {
      await streamed.stream.drain<void>();
      throw StateError('Unexpected redirect from fixed HTTPS endpoint');
    }
    return await http.Response.fromStream(streamed);
  } finally {
    client.close();
  }
}

bool _isRedirectStatus(int statusCode) =>
    statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;
