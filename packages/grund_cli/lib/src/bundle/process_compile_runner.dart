import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import 'compile_outcome.dart';
import 'compile_runner.dart';

/// Runs `dart compile js` as a child process of the Dart executable the CLI
/// itself runs under.
final class ProcessCompileRunner implements CompileRunner {
  /// Creates the runner; [executable] is [Platform.resolvedExecutable] by
  /// default.
  const ProcessCompileRunner({this._executable});

  final String? _executable;

  /// The arguments of `dart` for compiling [entry] to [output].
  ///
  /// Release is `-O2` with the release define and no source maps; the
  /// development build is `-O1` and keeps the maps. There is no `-O0`.
  static List<String> arguments({
    required String entry,
    required String output,
    required bool release,
  }) => [
    'compile',
    'js',
    if (release) ...[
      '-O2',
      '-Djaspr.flags.release=true',
      '--no-source-maps',
    ] else
      '-O1',
    '-o',
    output,
    entry,
  ];

  @override
  Future<CompileOutcome> compileJs({
    required String entry,
    required String output,
    required bool release,
    required String workingDirectory,
  }) async {
    final executable = _executable ?? Platform.resolvedExecutable;
    if (!{'dart', 'dart.exe'}.contains(p.basename(executable))) {
      throw CliFailure(
        CliExitCode.software,
        'Cannot compile JavaScript: $executable is not the Dart VM (an '
        'AOT-compiled grund cannot run dart compile js). Run grund with '
        '`dart run grund_cli` or `dart pub global run grund_cli`.',
      );
    }
    final result = await Process.run(
      executable,
      arguments(entry: entry, output: output, release: release),
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return CompileOutcome(result.exitCode, '${result.stdout}${result.stderr}');
  }
}
