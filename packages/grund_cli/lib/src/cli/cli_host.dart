import '../bundle/compile_runner.dart';
import '../bundle/process_compile_runner.dart';
import '../dev/terminal_keys.dart';
import 'interruption.dart';

/// The process-level seams of [GrundCli]: how it is interrupted, where `dev`
/// reads its keys from and what `bundle` compiles with.
///
/// The defaults are the real process; tests replace them.
final class CliHost {
  /// Creates the host: [interruption] stops `gen --watch` and `dev` (Ctrl+C,
  /// or `SIGTERM` outside Windows, by default), `dev` reads its `r` and `R`
  /// from [keys] (the terminal by default) and `bundle` compiles with
  /// [compileRunner] (`dart compile js` by default).
  CliHost({
    Interruption? interruption,
    Stream<String> Function()? keys,
    this.compileRunner = const ProcessCompileRunner(),
  }) : interruption = interruption ?? Interruption(),
       keys = keys ?? TerminalKeys.read;

  /// How `gen --watch` and `dev` are stopped.
  final Interruption interruption;

  /// Called when `dev` starts: the keys pressed while it runs.
  final Stream<String> Function() keys;

  /// What `bundle` compiles with.
  final CompileRunner compileRunner;
}
