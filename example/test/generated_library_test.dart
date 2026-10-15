// The committed *.g.dart files are what the CLI
// writes for the current sources. After changing an annotated class,
// regenerate:
//   dart run grund_cli gen
//
// The test runs the CLI's own `GenerationSession` on a copy of the
// hand-written sources in a temporary directory, so it writes nothing into
// the example.
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/example_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

void main() {
  test('the committed generated files are up to date', () async {
    final copy = TempDir.create();
    copy.write(
      'pubspec.yaml',
      'name: tasks_api\nenvironment:\n  sdk: ^3.8.0\n',
    );
    (await ExampleSources.sources()).forEach(copy.write);
    await WorkspacePackageConfig.write(copy.path, 'tasks_api');
    final session = GenerationSession(PackageRoot.open(copy.path));
    addTearDown(session.close);

    final report = await session.run();

    expect(report.problemLines, isEmpty);
    expect(
      _generatedIn(copy.path),
      await ExampleSources.committedGenerated(),
      reason: 'Run `dart run grund_cli gen` in example/ and commit.',
    );
  });
}

/// The generated files below [root]/lib: path (relative to [root], with `/`
/// separators) to content.
Map<String, String> _generatedIn(String root) => {
  for (final file in Directory(p.join(root, 'lib')).listSync(recursive: true))
    if (file is File &&
        ExampleSources.isGenerated(file.path)) // by name, as in the checkout
      p.posix.joinAll(p.split(p.relative(file.path, from: root))): file
          .readAsStringSync(),
};
