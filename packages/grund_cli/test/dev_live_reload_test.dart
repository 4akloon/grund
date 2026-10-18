import 'dart:async';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/dev_sources.dart';
import 'helpers/event_client.dart';
import 'helpers/line_sink.dart';
import 'helpers/temp_package.dart';

/// The `hello` application, printing the live reload URL it was given.
final _files = {
  ...DevSources.files,
  'bin/main.dart': DevSources.main.replaceFirst(
    "  print('listening",
    "  print('live reload \${Platform.environment['GRUND_LIVE_RELOAD_URL']}');\n"
        "  print('listening",
  ),
};

void main() {
  test('dev passes its live reload URL and announces a reload there', () async {
    final package = await TempPackage.create('hello', _files);
    final out = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final done = GrundCli(
      out: out,
      err: out,
      host: CliHost(
        interruption: Interruption(untilStopped: () => stop.future),
        keys: () => keys.stream,
      ),
    ).run(['dev', '-C', package.dir.path]);
    final line = await out.nextWhere((line) => line.startsWith('live reload '));
    final events = await EventClient.connect(
      Uri.parse(line.substring('live reload '.length)),
    );
    addTearDown(events.close);
    await events.nextComment('connected');

    keys.add('r');
    await out.nextWhere((line) => line.startsWith('Reloaded '));
    stop.complete();

    expect(await done, 0);
    // The start may have been announced before the page connected; the
    // reload of `r` was announced after it. The stream ends with dev.
    expect(await events.rest(), contains('reload'));
  });
}
