import 'dart:io';

import 'package:grund_cli/grund_cli.dart';

/// A [CompileRunner] that writes [files] next to the requested output
/// instead of compiling, and records the flags it was called with.
final class FakeCompileRunner implements CompileRunner {
  /// Creates the runner; [files] are the names (relative to the output's
  /// directory) it writes, [exitCode] the exit it reports.
  FakeCompileRunner({
    this.files = const ['{output}', '{output}.deps', '{output}.map'],
    this.exitCode = 0,
  });

  /// File names to write; `{output}` stands for the output's own name.
  final List<String> files;

  /// The exit code reported.
  final int exitCode;

  /// The `release` argument of each call.
  final List<bool> releases = [];

  /// The `entry` argument of each call.
  final List<String> entries = [];

  @override
  Future<CompileOutcome> compileJs({
    required String entry,
    required String output,
    required bool release,
    required String workingDirectory,
  }) async {
    releases.add(release);
    entries.add(entry);
    if (exitCode != 0) return CompileOutcome(exitCode, 'Error: broken');
    final directory = File(output).parent;
    final name = output.split(Platform.pathSeparator).last;
    for (final file in files) {
      File(
        '${directory.path}${Platform.pathSeparator}${file.replaceAll('{output}', name)}',
      ).writeAsStringSync('new');
    }
    return const CompileOutcome(0, '');
  }
}
