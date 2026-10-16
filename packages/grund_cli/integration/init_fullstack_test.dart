@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../test/helpers/cli_run.dart';
import '../test/helpers/temp_dir.dart';
import '../test/helpers/workspace_package_config.dart';

void main() {
  test('the tests of a new fullstack application pass', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_site');
    final init = await CliRun.run(['init', '--template', 'fullstack', target]);
    expect(init.exitCode, 0, reason: init.err);
    await WorkspacePackageConfig.write(target, 'my_site');

    // The VM runs the test file directly: `dart test` would resolve the
    // new package with `pub get`, and tests do not touch the network.
    final run = await Process.run(Platform.resolvedExecutable, [
      'test/app_test.dart',
    ], workingDirectory: target);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(run.stdout, contains('All tests passed!'));
  });
}
