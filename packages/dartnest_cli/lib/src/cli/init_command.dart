import 'package:args/command_runner.dart';

import '../init/project_scaffold.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';

/// `init <directory>`: scaffolds a new application.
final class InitCommand extends Command<int> {
  /// Creates the command of [cli].
  InitCommand(this.cli);

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Creates a dartnest application in a new or empty directory.';

  @override
  String get invocation => 'dartnest_cli init <directory>';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('init was not parsed.'));
    if (options.rest.length != 1) {
      usageException('init takes exactly one directory.');
    }
    final target = options.rest.single;
    final scaffold = ProjectScaffold(target);
    final files = scaffold.write();
    cli.out
      ..writeln('Created package ${scaffold.name} in ${scaffold.directory}:')
      ..writeAll([for (final file in files) '  $file\n'])
      ..writeln('Next:')
      ..writeln('  cd ${_shellWord(target)}')
      ..writeln('  dart pub get')
      ..writeln('  dart run dartnest_cli gen')
      ..writeln('  dart run bin/server.dart');
    return CliExitCode.success.code;
  }

  /// [word] as one shell word: quoted unless it is made of safe characters.
  static String _shellWord(String word) =>
      RegExp(r'^[\w./~:@%+=-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", r"'\''")}'";
}
