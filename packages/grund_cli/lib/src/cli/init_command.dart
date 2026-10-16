import 'package:args/command_runner.dart';

import '../init/project_kind.dart';
import '../init/project_scaffold.dart';
import 'cli_exit_code.dart';
import 'grund_cli.dart';
import 'shell_word.dart';

/// `init [--template <name>] <directory>`: scaffolds a new application of a
/// [ProjectKind].
final class InitCommand extends Command<int> {
  /// Creates the command of [cli].
  InitCommand(this.cli) {
    argParser.addOption(
      'template',
      allowed: [for (final kind in ProjectKind.values) kind.name],
      allowedHelp: {
        for (final kind in ProjectKind.values) kind.name: kind.summary,
      },
      defaultsTo: ProjectKind.api.name,
      help: 'What the new application is.',
    );
  }

  /// The command line this command belongs to.
  final GrundCli cli;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Creates a grund application in a new or empty directory.';

  @override
  String get invocation => 'grund_cli init [--template <name>] <directory>';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('init was not parsed.'));
    if (options.rest.length != 1) {
      usageException('init takes exactly one directory.');
    }
    final target = options.rest.single;
    final kind = ProjectKind.values.byName(
      options.option('template') ?? ProjectKind.api.name,
    );
    final scaffold = ProjectScaffold(target, kind: kind);
    final files = scaffold.write();
    cli.out
      ..writeln('Created package ${scaffold.name} in ${scaffold.directory}:')
      ..writeAll([for (final file in files) '  $file\n'])
      ..writeln('Next:')
      ..writeln('  cd ${ShellWord.quote(target)}')
      ..writeln('  dart pub get')
      ..writeAll([for (final step in kind.nextSteps) '  $step\n']);
    return CliExitCode.success.code;
  }
}
