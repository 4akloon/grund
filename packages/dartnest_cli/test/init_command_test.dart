import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

/// Errors and warnings of the Dart files of [root]'s `lib/` and `bin/`.
Future<List<String>> _analyze(String root) async {
  final collection = AnalysisContextCollection(includedPaths: [root]);
  addTearDown(collection.dispose);
  final files = [
    for (final directory in ['lib', 'bin'])
      for (final entity in Directory(
        '$root/$directory',
      ).listSync(recursive: true))
        if (entity.path.endsWith('.dart')) entity.path,
  ];
  return [
    for (final file in files)
      if (await collection.contextFor(file).currentSession.getErrors(file)
          case final ErrorsResult result)
        for (final diagnostic in result.diagnostics)
          if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.INFO)
            '$file: ${diagnostic.message}',
  ];
}

void main() {
  test('init writes an application that generates and analyzes', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_app');

    final init = await CliRun.run(['init', target]);
    await WorkspacePackageConfig.write(target, 'my_app');
    final gen = await CliRun.run(['gen', '-C', target]);

    expect(init.exitCode, 0, reason: init.err);
    expect(init.out, startsWith('Created package my_app in $target:\n'));
    expect(init.out, contains('  dart run dartnest_cli gen\n'));
    expect(dir.read('my_app/pubspec.yaml'), contains('name: my_app\n'));
    expect(gen.exitCode, 0, reason: gen.err);
    expect(dir.exists('my_app/lib/my_app.dartnest.dart'), isTrue);
    expect(await _analyze(target), isEmpty);
  });

  test('init refuses a directory that is not empty', () async {
    final dir = TempDir.create();
    dir.write('my_app/notes.txt', 'mine');

    final run = await CliRun.run(['init', dir.resolve('my_app')]);

    expect(run.exitCode, CliExitCode.cannotCreate.code);
    expect(run.err, contains('is not an empty directory'));
    expect(dir.exists('my_app/pubspec.yaml'), isFalse);
  });

  test('init needs one directory with a package name', () async {
    final dir = TempDir.create();

    final none = await CliRun.run(['init']);
    final invalid = await CliRun.run(['init', dir.resolve('My-App')]);

    expect(none.exitCode, CliExitCode.usage.code);
    expect(none.err, startsWith('init takes exactly one directory.'));
    expect(invalid.exitCode, CliExitCode.usage.code);
    expect(invalid.err, startsWith('"My-App" is not a valid package name'));
    expect(dir.exists('My-App'), isFalse);
  });
}
