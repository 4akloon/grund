import 'package:args/command_runner.dart';

import '../bundle/bundle_result.dart';
import '../bundle/client_bundler.dart';
import '../package/package_root.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'grund_cli.dart';

/// `bundle`: compiles the browser entry to the production JavaScript bundle.
final class BundleCommand extends Command<int> {
  /// Creates the command of [cli].
  BundleCommand(this.cli) {
    argParser
      ..addOption(
        'entry',
        defaultsTo: ClientBundler.defaultEntry,
        valueHelp: 'file',
        help: 'The browser entry point, relative to the package.',
      )
      ..addOption(
        'output',
        defaultsTo: ClientBundler.defaultOutputDirectory,
        valueHelp: 'dir',
        help: 'Where the bundle goes, relative to the package.',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'The package to bundle.',
      );
  }

  /// The command line this command belongs to.
  final GrundCli cli;

  @override
  String get name => 'bundle';

  @override
  String get description =>
      'Compiles the browser entry to the production JavaScript bundle '
      '(dart compile js -O2).';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('bundle was not parsed.'));
    if (options.rest.isNotEmpty) {
      usageException('bundle takes no positional arguments.');
    }
    final output =
        options.option('output') ?? ClientBundler.defaultOutputDirectory;
    final bundler = ClientBundler(
      PackageRoot.open(options.option('directory') ?? '.'),
      entry: options.option('entry') ?? ClientBundler.defaultEntry,
      outputDirectory: output,
      runner: cli.host.compileRunner,
    );
    switch (await bundler.build(release: true)) {
      case BundleBuilt(:final elapsed):
        cli.out.writeln(
          'Bundled $output/${bundler.outputName} in '
          '${elapsed.inMilliseconds} ms.',
        );
      case BundleSkipped():
        cli.out.writeln('No ${bundler.entry}: nothing to bundle.');
      case BundleFailed(output: final compilerOutput):
        throw CliFailure(
          CliExitCode.problems,
          'bundle failed:\n$compilerOutput',
        );
    }
    return CliExitCode.success.code;
  }
}
