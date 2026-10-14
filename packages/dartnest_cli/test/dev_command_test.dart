import 'dart:async';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/exploding_construct.dart';
import 'helpers/line_sink.dart';
import 'helpers/dev_sources.dart';
import 'helpers/temp_package.dart';

void main() {
  test('dev --help shows the target option', () async {
    final run = await CliRun.run(['dev', '--help']);

    expect(run.exitCode, CliExitCode.success.code);
    expect(run.out, contains('--target'));
    expect(run.out, contains('(defaults to "bin/main.dart")'));
  });

  test('dev without the entry point fails before starting', () async {
    final package = await TempPackage.create(
      'hello',
      Map.of(DevSources.files)..remove('bin/main.dart'),
    );

    final run = await CliRun.run(['dev', '-C', package.dir.path]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, contains('No bin/main.dart in '));
    expect(run.err, contains('pass the entry point with --target.'));
  });

  test('--entry is the --target of the design', () async {
    final package = await TempPackage.create('hello', DevSources.files);

    final run = await CliRun.run([
      'dev',
      '-C',
      package.dir.path,
      '--entry',
      'bin/server.dart',
    ]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, contains('No bin/server.dart in '));
  });

  test(
    'an entry point outside a directory of the package is refused',
    () async {
      final package = await TempPackage.create('hello', DevSources.files);

      for (final target in ['main.dart', '../main.dart']) {
        final run = await CliRun.run([
          'dev',
          '-C',
          package.dir.path,
          '-t',
          target,
        ]);

        expect(run.exitCode, CliExitCode.usage.code, reason: target);
        expect(run.err, contains('such as bin/; $target is not.'));
      }
    },
  );

  test('an unknown option is a usage error', () async {
    final run = await CliRun.run(['dev', '--port', '1']);

    expect(run.exitCode, CliExitCode.usage.code);
    expect(run.err, contains('Could not find an option named "--port"'));
  });

  test('a failure of a run ends dev with the software exit code', () async {
    final package = await TempPackage.create('hello', DevSources.files);
    final out = StringBuffer();
    final err = StringBuffer();
    final signals = StreamController<void>.broadcast();

    final code = await DartnestCli(
      out: out,
      err: err,
      generator: const DartnestGenerator([ExplodingConstruct()]),
      interruption: Interruption(signals: () => signals.stream),
      keys: () => const Stream<String>.empty(),
    ).run(['dev', '-C', package.dir.path]);

    expect(code, CliExitCode.software.code);
    expect(err.toString(), contains('dev stopped: FormatException: boom'));
    expect(out.toString(), isNot(contains('Started ')));
    // A listener on the signals would keep the process alive.
    expect(signals.hasListener, isFalse);
  });

  test('dev -t lib/main.dart watches lib/ only', () async {
    final package = await TempPackage.create('hello', {
      ...DevSources.files,
      'lib/main.dart': DevSources.files['bin/main.dart'] ?? '',
    });
    final out = LineSink();
    final stop = Completer<void>();
    final done = DartnestCli(
      out: out,
      err: out,
      interruption: Interruption(untilStopped: () => stop.future),
      keys: () => const Stream<String>.empty(),
    ).run(['dev', '-C', package.dir.path, '-t', 'lib/main.dart']);

    await out.nextWhere((line) => line.startsWith('Watching '));
    stop.complete();
    await done;

    expect(out.lines, contains(startsWith('Watching lib/ for changes')));
  });
}
