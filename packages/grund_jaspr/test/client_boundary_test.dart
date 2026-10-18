import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The files that compile for the server and for the browser: they may import
/// `package:jaspr/jaspr.dart` and each other, nothing else.
const _neutral = [
  'lib/client_components.dart',
  'lib/src/client/client_component.dart',
  'lib/src/client/client_components.dart',
  'lib/src/client/client_entry.dart',
];

/// The browser side: the neutral library and `package:jaspr/client.dart`.
const _browser = ['lib/client.dart', 'lib/src/client/grund_client.dart'];

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// The URIs of the import and export directives of [path], resolved against
/// the package for relative ones.
List<String> _targets(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (_directive.firstMatch(line)?.group(1) case final uri?)
      uri.startsWith('package:') || uri.startsWith('dart:')
          ? uri
          : p.normalize(p.join(p.dirname(path), uri)),
];

void main() {
  for (final path in [..._neutral, ..._browser]) {
    test('$path exists', () => expect(File(path).existsSync(), isTrue));
  }

  for (final path in _neutral) {
    test('$path imports only jaspr.dart and the neutral library', () {
      final allowed = {'package:jaspr/jaspr.dart', ..._neutral};
      final targets = _targets(path);

      // An empty list would mean the directive pattern stopped matching.
      expect(targets, isNotEmpty);
      expect(targets.where((uri) => !allowed.contains(uri)), isEmpty);
    });
  }

  for (final path in _browser) {
    test('$path imports only browser-safe libraries', () {
      final allowed = {
        'package:jaspr/client.dart',
        'package:jaspr/jaspr.dart',
        ..._neutral,
        'lib/src/client/grund_client.dart',
      };
      final targets = _targets(path);

      expect(targets, isNotEmpty);
      expect(targets.where((uri) => !allowed.contains(uri)), isEmpty);
    });
  }
}
