import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages cannot import app code; runtime_boundary_test separately guards
/// the Provider composition, activity adapter and UI capability-only boundary.
void main() {
  final directive = RegExp(
    r'''\b(?:import|export|part)\s+['"]([^'"]+)['"]''',
  );

  for (final package in ['scooter_core', 'scooter_flutter']) {
    test('$package cannot depend on application code or escape its lib', () {
      final lib = Directory('packages/$package/lib').absolute;
      expect(lib.existsSync(), isTrue);
      final root = lib.uri.normalizePath().toString();
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in directive.allMatches(file.readAsStringSync())) {
          final uri = Uri.parse(match.group(1)!);
          expect(uri.scheme, isNot('file'), reason: file.path);
          if (uri.scheme == 'package') {
            expect(uri.pathSegments.first, isNot('unustasis'), reason: file.path);
          } else if (!uri.hasScheme) {
            expect(file.uri.resolveUri(uri).toString().startsWith(root), isTrue,
                reason: '${file.path} escapes package lib via $uri');
          }
        }
      }
    });
  }

  test('app telemetry facade delegates subscriptions and capability probes', () {
    final facade = File('lib/scooter_service.dart').readAsStringSync();
    for (final algorithm in [
      'wireSubscriptions(',
      'wireNrfVersion(',
      'wireOdometer(',
      '_probeLsCapabilities(',
      'computeAggregateState(',
      'getPmCapabilitiesCommand(',
      'getLsCapabilitiesCommand(',
      'cacheSoc:',
    ]) {
      expect(facade, isNot(contains(algorithm)), reason: algorithm);
    }
    for (final name in ['battery_state', 'vehicle_status']) {
      final source = File('lib/state/$name.dart').readAsStringSync();
      expect(source.trim(), startsWith('export '));
      expect(source, isNot(contains('class ')));
    }
    expect(File('lib/state/scooter_identity.dart').readAsStringSync(), isNot(contains('readNrfVersion(')));
  });

  test('core imports only Dart and declared pure runtime libraries', () {
    // Keep this list explicit: adding a plugin to core must fail CI even if
    // the local Flutter SDK happens to make its imports resolvable.
    const packages = {'scooter_core', 'logging', 'latlong2'};
    for (final file in Directory('packages/scooter_core/lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final uri = Uri.parse(match.group(1)!);
        if (uri.scheme == 'package') {
          expect(packages, contains(uri.pathSegments.first), reason: file.path);
        }
        expect(uri.toString(), isNot('dart:ui'), reason: file.path);
      }
    }
  });
}
