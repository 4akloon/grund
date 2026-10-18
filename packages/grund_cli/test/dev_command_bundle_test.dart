import 'dart:async';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/dev_sources.dart';
import 'helpers/fake_compile_runner.dart';
import 'helpers/line_sink.dart';
import 'helpers/temp_package.dart';

Future<int> _dev(
  List<String> arguments,
  FakeCompileRunner runner,
  LineSink out,
  Future<void> Function() whenRunning,
) async {
  final stop = Completer<void>();
  final done = GrundCli(
    out: out,
    err: out,
    host: CliHost(
      interruption: Interruption(untilStopped: () => stop.future),
      keys: () => const Stream.empty(),
      compileRunner: runner,
    ),
  ).run(['dev', ...arguments]);
  await whenRunning();
  stop.complete();
  return done;
}

void main() {
  test(
    '--client-entry and --output reach the bundler; --entry stays the target',
    () async {
      final package = await TempPackage.create('hello', {
        ...DevSources.files,
        'lib/other.client.dart': 'void main() {}',
      });
      final runner = FakeCompileRunner();
      final out = LineSink();

      final code = await _dev(
        [
          '-C',
          package.dir.path,
          '--entry',
          'bin/main.dart',
          '--client-entry',
          'lib/other.client.dart',
          '--output',
          'out',
        ],
        runner,
        out,
        () => out.nextWhere((line) => line.startsWith('Bundled out/')),
      );

      expect(code, 0);
      expect(runner.entries, ['lib/other.client.dart']);
      expect(runner.releases, [false]);
      expect(
        File('${package.dir.path}/out/other.client.dart.js').existsSync(),
        isTrue,
      );
    },
  );

  test('a package without a browser entry is not bundled', () async {
    final package = await TempPackage.create('hello', DevSources.files);
    final runner = FakeCompileRunner();
    final out = LineSink();

    final code = await _dev(
      ['-C', package.dir.path],
      runner,
      out,
      () => out.nextWhere((line) => line.startsWith('Watching ')),
    );

    expect(code, 0);
    expect(runner.entries, isEmpty);
    expect(out.lines.where((line) => line.contains('undle')), isEmpty);
  });
}
