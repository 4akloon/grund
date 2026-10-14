import 'dart:async';

import 'package:dartnest_cli/dartnest_cli.dart';
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
    final exitCode = DartnestCli(
      out: lines,
      err: lines,
      interruption: Interruption(untilStopped: () => stop.future),
    ).run(['gen', '--watch', '--directory', package.dir.path]);

    expect(await lines.next(), startsWith('Generated lib/shop.dartnest.dart'));
    expect(await lines.next(), startsWith('Watching lib/ for changes'));
    package.dir.write(
      'lib/src/time_controller.dart',
      ShopSources.controller.replaceFirst('@Get()', "@Get('/now')"),
    );
    expect(await lines.next(), startsWith('Generated lib/shop.dartnest.dart'));
    expect(package.dir.read(ShopSources.output), contains("'/now'"));

    stop.complete();
    expect(await exitCode, CliExitCode.success.code);
  });
}
