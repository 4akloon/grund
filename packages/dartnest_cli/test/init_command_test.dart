import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:dartnest_cli/src/cli/shell_word.dart';
import 'package:dartnest_cli/src/init/project_scaffold.dart';
import 'package:dartnest_cli/src/init/reserved_names.dart';
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

  for (final (name, reason) in [
    ('class', 'a Dart reserved word'),
    ('in', 'a Dart reserved word'),
    ('dartnest', 'a dependency of the new package'),
    ('lints', 'a dependency of the new package'),
  ]) {
    test('init rejects the package name "$name"', () async {
      final dir = TempDir.create();

      final run = await CliRun.run(['init', dir.resolve(name)]);

      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.err, startsWith('"$name" is not a valid package name'));
      expect(run.err, contains(reason));
      expect(dir.exists(name), isFalse);
    });
  }

  test('init accepts the names of packages the template does not use', () {
    for (final name in ['test', 'dartnest_generator']) {
      expect(ReservedNames.reasonFor(name), isNull);
    }
  });

  test('init leaves nothing behind when writing fails midway', () async {
    final dir = TempDir.create();
    final created = dir.resolve('fresh_app');
    final existing = dir.resolve('empty_app');
    Directory(existing).createSync();

    for (final target in [created, existing]) {
      var writes = 0;
      final scaffold = ProjectScaffold(
        target,
        writeFile: (file, content) {
          if (++writes == 3) {
            throw const FileSystemException('disk full');
          }
          file.writeAsStringSync(content);
        },
      );
      expect(
        scaffold.write,
        throwsA(
          isA<CliFailure>().having(
            (failure) => failure.exitCode,
            'exitCode',
            CliExitCode.cannotCreate,
          ),
        ),
      );
    }

    expect(Directory(created).existsSync(), isFalse);
    expect(Directory(existing).existsSync(), isTrue);
    expect(Directory(existing).listSync(), isEmpty);
  });

  test('init removes the missing parent directories it created', () {
    final dir = TempDir.create();
    Directory(dir.resolve('kept')).createSync();
    final scaffold = ProjectScaffold(
      dir.resolve('kept/a/b/my_app'),
      writeFile: (file, content) => throw const FileSystemException('full'),
    );

    expect(scaffold.write, throwsA(isA<CliFailure>()));

    expect(Directory(dir.resolve('kept')).existsSync(), isTrue);
    expect(Directory(dir.resolve('kept')).listSync(), isEmpty);
  });

  test('init quotes the directory in the next steps', () async {
    final dir = TempDir.create();
    final target = dir.resolve("it's here/my_app");

    final run = await CliRun.run(['init', target]);

    final quoted = target.replaceAll("'", r"'\''");
    expect(run.out, contains("  cd '$quoted'\n"));
  });

  test('a shell word is quoted unless it is plainly safe', () {
    expect(ShellWord.quote('/tmp/my_app'), '/tmp/my_app');
    expect(ShellWord.quote('a b'), "'a b'");
    expect(ShellWord.quote("it's"), r"'it'\''s'");
    expect(ShellWord.quote('-x/app'), './-x/app');
    expect(ShellWord.quote('-x y'), "'./-x y'");
  });
}
