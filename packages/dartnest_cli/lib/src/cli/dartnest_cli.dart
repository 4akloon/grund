import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'gen_command.dart';

/// The `dartnest_cli` command line.
///
/// `bin/dartnest_cli.dart` runs it with the core constructs; a package
/// with constructs of its own runs it from `tool/dartnest.dart`:
/// `DartnestCli(generator: DartnestGenerator([...])).run(arguments)`.
final class DartnestCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default) and `gen` runs [generator].
  DartnestCli({
    StringSink? out,
    StringSink? err,
    this.generator = const DartnestGenerator.core(),
  }) : out = out ?? stdout,
       err = err ?? stderr;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final DartnestGenerator generator;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)..addCommand(GenCommand(this));
    try {
      return await runner.run(arguments) ?? CliExitCode.success.code;
    } on UsageException catch (error) {
      err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return CliExitCode.usage.code;
    } on CliFailure catch (failure) {
      err.writeln(failure.message);
      return failure.exitCode.code;
    }
  }
}

final class _Runner extends CommandRunner<int> {
  _Runner(this._out)
    : super('dartnest_cli', 'Generates and scaffolds dartnest applications.');

  final StringSink _out;

  @override
  void printUsage() => _out.writeln(usage);
}
