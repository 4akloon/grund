import 'dart:io';

import 'package:test/test.dart';

import '../../test/helpers/event_client.dart';
import 'dev_run.dart';
import 'site_sources.dart';

/// `dev` of the site with its live reload stream open from before the
/// application starts, so that the reload `dev` announces once the
/// application serves is consumed here and never mistaken for the reload of
/// a later edit.
abstract final class StartupEvents {
  /// The application prints its live reload URL and then waits for this
  /// file, so the test can connect before the application serves.
  static const _gate = 'start.gate';

  /// `bin/main.dart` that prints `live reload <url>` and waits for [_gate].
  static final main = SiteSources.main.replaceFirst(
    '  final app = App(',
    '''  print('live reload \${Platform.environment['GRUND_LIVE_RELOAD_URL']}');
  while (!File('$_gate').existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final app = App(''',
  );

  /// Starts `dev` of the package in [directory] (whose `bin/main.dart` is
  /// [main]) and returns it with the stream, after the startup reload.
  static Future<({DevRun dev, EventClient events})> start(
    String directory,
  ) async {
    late EventClient events;
    final dev = await DevRun.start(
      directory,
      port: await freePort(),
      whileStarting: (lines) async {
        final line = await lines.nextWhere((l) => l.startsWith('live reload '));
        events = await EventClient.connect(
          Uri.parse(line.substring('live reload '.length)),
        );
        addTearDown(events.close);
        expect(await events.nextComment('connected'), isTrue);
        File('$directory/$_gate').writeAsStringSync('');
      },
    );
    expect(await events.nextEvent(), 'reload', reason: 'the startup reload');
    return (dev: dev, events: events);
  }
}
