import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Writes `.dart_tool/package_config.json` for a package outside the
/// workspace, so the analyzer resolves `package:grund`,
/// `package:grund_http` and the rest from this checkout without
/// `dart pub get` (tests do not touch the network).
abstract final class WorkspacePackageConfig {
  /// Writes the config of package [name] at [root]: every package of the
  /// test's own config (with absolute root URIs) plus [name] itself.
  static Future<void> write(String root, String name) async {
    final source = await Isolate.packageConfig;
    if (source == null) {
      throw StateError('The test isolate has no package config.');
    }
    final json = jsonDecode(File.fromUri(source).readAsStringSync());
    final entries = (json as Map<String, Object?>)['packages'] as List<Object?>;
    final packages = [
      for (final entry in entries.cast<Map<String, Object?>>())
        if (entry['name'] != name)
          {
            ...entry,
            'rootUri': '${source.resolve(entry['rootUri'] as String)}',
          },
      {
        'name': name,
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      },
    ];
    final file = File(p.join(root, '.dart_tool', 'package_config.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'configVersion': 2, 'packages': packages}),
    );
  }
}
