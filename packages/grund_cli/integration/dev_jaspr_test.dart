@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../test/helpers/event_client.dart';
import '../test/helpers/temp_package.dart';
import 'helpers/dev_run.dart';
import 'helpers/site_sources.dart';

/// The HTML of `GET /` on [port].
Future<String> page(int port) async {
  final client = HttpClient();
  try {
    final request = await client.get('127.0.0.1', port, '/');
    return await utf8.decodeStream(await request.close());
  } finally {
    client.close(force: true);
  }
}

/// The URL the live reload script of [html] listens on.
Uri liveReloadUrl(String html) {
  final match = RegExp(r'new EventSource\("([^"]+)"\)').firstMatch(html);
  return Uri.parse(match?[1] ?? fail('No live reload script in $html'));
}

void main() {
  test(
    'a page edit shows in the next response and reloads open pages',
    () async {
      final package = await TempPackage.create('site', SiteSources.files);
      final dev = await DevRun.start(package.dir.path, port: await freePort());
      final first = await page(dev.port);
      final events = await EventClient.connect(liveReloadUrl(first));
      addTearDown(events.close);
      expect(await events.nextComment('connected'), isTrue);

      package.dir.write(
        'lib/site.dart',
        SiteSources.site.replaceFirst('page v1', 'page v2'),
      );

      expect(await events.nextEvent(), 'reload');
      final second = await page(dev.port);
      expect(second, contains('page v2'));
      expect(_pid(second), _pid(first));

      dev.keys.add('R');
      expect(await events.nextEvent(), 'reload');
      expect(_pid(await page(dev.port)), isNot(_pid(first)));

      await dev.stop();
      expect(await events.nextEvent(), isNull);
    },
  );
}

String? _pid(String html) => RegExp(r'pid (\d+)').firstMatch(html)?[1];
