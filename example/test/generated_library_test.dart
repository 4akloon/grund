// The committed lib/tasks_api.grund.dart is what `grund gen` writes
// for the current sources. After changing an annotated class, regenerate:
//   dart run grund_cli gen
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/example_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

void main() {
  test('the committed generated library is up to date', () async {
    final copy = TempDir.create();
    copy.write(
      'pubspec.yaml',
      'name: tasks_api\nenvironment:\n  sdk: ^3.8.0\n',
    );
    (await ExampleSources.files()).forEach(copy.write);
    await WorkspacePackageConfig.write(copy.path, 'tasks_api');
    final session = GenerationSession(PackageRoot.open(copy.path));
    addTearDown(session.close);

    final report = await session.run();

    expect(report.problemLines, isEmpty);
    expect(
      File(copy.resolve(ExampleSources.generatedLibrary)).readAsStringSync(),
      await ExampleSources.committedLibrary(),
      reason: 'Run `dart run grund_cli gen` in example/ and commit.',
    );
  });
}
