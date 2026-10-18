import 'dart:async';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/line_sink.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

void main() {
  // The roadmap's "file change without restart" test, on the real file
  // system watcher.
  test('gen --watch regenerates on a change until stopped', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final lines = LineSink();
    final stop = Completer<void>();
    addTearDown(() {
      if (!stop.isCompleted) stop.complete();
    });
    final exitCode = GrundCli(
      out: lines,
      err: lines,
      host: CliHost(
        interruption: Interruption(untilStopped: () => stop.future),
      ),
    ).run(['gen', '--watch', '--directory', package.dir.path]);

    expect(await lines.next(), startsWith('Generated 2 files'));
    expect(await lines.next(), startsWith('Watching lib/ for changes'));
    package.dir.write(
      'lib/src/time_api.dart',
      ShopSources.api.replaceFirst("@Get('/')", "@Get('/now')"),
    );
    expect(await lines.next(), startsWith('Generated 1 file in'));
    expect(package.dir.read(ShopSources.apiOutput), contains("'/now'"));

    stop.complete();
    expect(await exitCode, CliExitCode.success.code);
  });
}
