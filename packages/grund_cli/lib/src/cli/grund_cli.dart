import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';

import 'bundle_command.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'cli_host.dart';
import 'dev_command.dart';
import 'gen_command.dart';
import 'init_command.dart';

/// The `grund_cli` command line.
///
/// `bin/grund_cli.dart` runs it with the core and the HTTP constructs; a
/// package with constructs of its own runs it from `tool/grund.dart`:
/// `GrundCli(generator: GrundGenerator([...])).run(arguments)`.
final class GrundCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default), `gen` runs [generator], and [host] holds the
  /// process-level seams (interruption, keys, the JavaScript compiler).
  GrundCli({
    StringSink? out,
    StringSink? err,
    this.generator = StandardGenerator.instance,
    CliHost? host,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       host = host ?? CliHost();

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final GrundGenerator generator;

  /// The process-level seams.
  final CliHost host;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)
      ..addCommand(BundleCommand(this))
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
