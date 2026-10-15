import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grund_generator/grund_generator.dart';

import '../dev/terminal_keys.dart';
import '../generate/default_generator.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'dev_command.dart';
import 'gen_command.dart';
import 'init_command.dart';
import 'interruption.dart';

/// The `grund_cli` command line.
///
/// `bin/grund_cli.dart` runs it with the core and the HTTP constructs; a package
/// with constructs of its own runs it from `tool/grund.dart`:
/// `GrundCli(generator: GrundGenerator([...])).run(arguments)`.
final class GrundCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default), `gen` runs [generator], `gen --watch` and `dev`
  /// stop on the first interrupt of [interruption] (Ctrl+C, or `SIGTERM`
  /// outside Windows, by default) and `dev` reads its `r` and `R` from
  /// [keys] (the terminal by default).
  GrundCli({
    StringSink? out,
    StringSink? err,
    this.generator = DefaultGenerator.instance,
    Interruption? interruption,
    Stream<String> Function()? keys,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       interruption = interruption ?? Interruption(),
       keys = keys ?? TerminalKeys.read;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final GrundGenerator generator;

  /// How `gen --watch` and `dev` are stopped.
  final Interruption interruption;

  /// Called when `dev` starts: the keys pressed while it runs.
  final Stream<String> Function() keys;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)
      ..addCommand(DevCommand(this))
      ..addCommand(GenCommand(this))
      ..addCommand(InitCommand(this));
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
    : super('grund', 'Generates and scaffolds grund applications.');

  final StringSink _out;

  @override
  void printUsage() => _out.writeln(usage);
}
