import 'dart:async';
import 'dart:io';

import 'package:dartnest_cli/src/cli/report_printer.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:dartnest_cli/src/watch/watch_loop.dart';
import 'package:test/test.dart';

import 'helpers/fake_watcher.dart';
import 'helpers/line_sink.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

const _quiet = Duration(milliseconds: 500);

final _generated = RegExp(r'^Generated lib/shop\.dartnest\.dart in \d+ ms\.$');

/// A running [WatchLoop] over a fresh `shop` package.
final class _Loop {
  _Loop._(this.package, this.watcher, this.lines, this._stop, this._done);

  static Future<_Loop> start() async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = GenerationSession(package.root);
    final watcher = FakeWatcher(package.dir.resolve('lib'));
    final lines = LineSink();
    final stop = Completer<void>();
    final done = WatchLoop(
      session,
      ReportPrinter(lines, lines),
    ).run(watcher, stop.future);
    final loop = _Loop._(package, watcher, lines, stop, done);
    addTearDown(() async {
      await loop.stop();
      await session.close();
    });
    expect(await lines.next(), matches(_generated));
    expect(
      await lines.next(),
      'Watching lib/ for changes; press Ctrl+C to stop.',
    );
    return loop;
  }

  final TempPackage package;
  final FakeWatcher watcher;
  final LineSink lines;
  final Completer<void> _stop;
  final Future<void> _done;

  /// Writes [content] to [path] and reports it [times] times.
  void change(String path, String content, {int times = 1}) {
    final file = package.dir.write(path, content);
    for (var i = 0; i < times; i++) {
      watcher.modify(file);
    }
  }

  Future<void> stop() {
    if (!_stop.isCompleted) _stop.complete();
    return _done;
  }
}

void main() {
  // Review Focus 6: an editor's save is a storm of events.
  test('a burst of events gives one run', () async {
    final loop = await _Loop.start();

    loop.change(
      'lib/src/time_controller.dart',
      ShopSources.controller.replaceFirst('@Get()', "@Get('/now')"),
      times: 5,
    );

    expect(await loop.lines.after(_quiet), [matches(_generated)]);
    expect(loop.package.dir.read(ShopSources.output), contains("'/now'"));
  });

  test('its own output and other files do not start a run', () async {
    final loop = await _Loop.start();

    loop.watcher
      ..modify(loop.package.dir.resolve(ShopSources.output))
      ..modify(loop.package.dir.resolve('lib/notes.txt'));

    expect(await loop.lines.after(_quiet), isEmpty);
  });

  test('a problem is reported and the next change recovers', () async {
    final loop = await _Loop.start();

    loop.change('lib/src/app_module.dart', ShopSources.moduleWithoutClock);
    expect(await loop.lines.next(), endsWith('[missing_provider]'));
    expect(
      await loop.lines.next(),
      '1 problem; lib/shop.dartnest.dart was not changed.',
    );

    loop.change('lib/src/app_module.dart', ShopSources.module);
    expect(await loop.lines.next(), contains('is up to date'));
  });

  test('a failure to write is reported and watching goes on', () async {
    final loop = await _Loop.start();
    final output = loop.package.dir.resolve(ShopSources.output);
    File(output).deleteSync();
    Directory(output).createSync();

    loop.change('lib/src/clock.dart', '${ShopSources.clock}// v2\n');
    expect(
      await loop.lines.next(),
      startsWith('Cannot write lib/shop.dartnest.dart: '),
    );

    Directory(output).deleteSync();
    loop.change('lib/src/clock.dart', '${ShopSources.clock}// v3\n');
    expect(await loop.lines.next(), matches(_generated));
  });
}
