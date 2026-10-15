/// The command line tool of grund: `gen` and `gen --watch` write the
/// generated files (`*.g.dart`) from the annotations
/// of a package, `init` scaffolds a new application.
///
/// [GrundCli] is the command line itself; [GenerationSession] is the
/// generation it drives, kept in memory between runs, for tools that
/// regenerate on their own schedule.
library;

export 'package:grund_generator/grund_generator.dart' show SyntaxProblem;

export 'src/cli/cli_exit_code.dart';
export 'src/cli/cli_failure.dart';
export 'src/cli/grund_cli.dart';
export 'src/cli/interruption.dart';
export 'src/generate/generation_report.dart';
export 'src/generate/generation_session.dart';
export 'src/generate/write_outcome.dart';
export 'src/package/package_root.dart';
