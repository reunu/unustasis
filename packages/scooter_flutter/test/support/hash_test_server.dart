import 'dart:convert';
import 'dart:math';

class HashTestServer {
  final hashes = <String, Map<String, String?>>{
    'battery:0': {'present': 'true', 'serial-number': 'T-UNU22205090007'},
    'battery:1': {'present': 'false', 'serial-number': 'retained'},
  };
  final requests = <String>[];
  final _snapshots = <String, List<int>>{};
  List<int>? rawSnapshot;

  String answer(String command) {
    requests.add(command);
    final start = RegExp(r'^hash:read:([0-9a-f]{8}):([0-9]+):([^/]+)/(.+)$').firstMatch(command);
    if (start != null) {
      final id = start[1]!;
      final values = start[4]!.split(',').map((f) => hashes[start[3]]?[f]).toList();
      final bytes = rawSnapshot ?? utf8.encode(jsonEncode(values));
      _snapshots[id] = bytes;
      return 'r:s:$id:${bytes.length.toRadixString(36)}';
    }
    final get = command.split(':');
    final id = get[2];
    final offsetText = get[3];
    final offset = int.parse(offsetText, radix: 36);
    final budget = int.parse(get[4]);
    final bytes = _snapshots[id]!;
    if (offset == bytes.length) {
      _snapshots.remove(id);
      return 'r:e:$id:$offsetText';
    }
    final prefix = 'r:p:$id:$offsetText:';
    final size = min(bytes.length - offset, (budget - prefix.length) * 3 ~/ 4);
    final data = base64Url.encode(bytes.sublist(offset, offset + size)).replaceAll('=', '');
    return '$prefix$data';
  }
}
