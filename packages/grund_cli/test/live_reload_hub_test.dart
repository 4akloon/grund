import 'dart:io';

import 'package:grund_cli/src/dev/live_reload_hub.dart';
import 'package:test/test.dart';

import 'helpers/event_client.dart';

/// A started hub, closed after the test.
Future<LiveReloadHub> startHub({
  Duration keepAlive = const Duration(seconds: 15),
}) async {
  final hub = await LiveReloadHub.start(keepAlive: keepAlive);
  addTearDown(hub.close);
  return hub;
}

/// A page connected to [hub], dropped after the test.
Future<EventClient> connect(LiveReloadHub hub) async {
  final page = await EventClient.connect(hub.url);
  addTearDown(page.close);
  await page.nextComment('connected');
  return page;
}

void main() {
  test('listens on loopback and passes its URL in the environment', () async {
    final hub = await startHub();

    expect(hub.url.host, '127.0.0.1');
    expect(hub.environment, {'GRUND_LIVE_RELOAD_URL': '${hub.url}'});
  });

  test('answers an event stream any origin may read', () async {
    final hub = await startHub();

    final page = await connect(hub);

    final headers = page.response.headers;
    expect(headers.contentType?.mimeType, 'text/event-stream');
    expect(headers.value('access-control-allow-origin'), '*');
    expect(headers.value('cache-control'), 'no-cache');
  });

  test('every connected page receives reload', () async {
    final hub = await startHub();
    final first = await connect(hub);
    final second = await connect(hub);

    hub.broadcastReload();

    expect(await first.nextEvent(), 'reload');
    expect(await second.nextEvent(), 'reload');
  });

  test('sends a keep-alive comment', () async {
    final hub = await startHub(keepAlive: const Duration(milliseconds: 50));

    final page = await connect(hub);

    expect(await page.nextComment('keep-alive'), isTrue);
  });

  test('a page that left does not stop the next broadcast', () async {
    final hub = await startHub();
    hub.broadcastReload();
    (await connect(hub)).close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final page = await connect(hub);

    hub
      ..broadcastReload()
      ..broadcastReload();

    expect(await page.nextEvent(), 'reload');
  });

  test('close ends every stream and frees the port (RF7)', () async {
    final hub = await LiveReloadHub.start();
    final page = await connect(hub);

    await hub.close();

    expect(await page.nextEvent(), isNull);
    await expectLater(
      EventClient.connect(hub.url),
      throwsA(isA<SocketException>()),
    );
  });
}
