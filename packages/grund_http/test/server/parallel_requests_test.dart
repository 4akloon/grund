import 'dart:async';

import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

void main() {
  test('parallel requests never see each other\'s c.set (RF-2)', () async {
    final release = Completer<void>();
    final app = await TestApp.start(
      root: ProbeRoot(FakeAdapter(), [
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [
            Route.get('/who', (c) async {
              // Every request waits here, so all of them are in flight
              // together before any answers.
              await release.future;
              return '${c<CurrentUser>().name}/${identityHashCode(c<Tx>())}';
            }),
          ],
          use: [HookRef<UserHook>.type()],
        ),
      ]),
    );
    addTearDown(app.close);
    final client = TestClient.of(app);

    final responses = [
      for (var i = 0; i < 20; i++)
        client.get('/who', headers: {'x-user': 'user$i'}),
    ];
    await pumpEventQueue();
    release.complete();
    final texts = [for (final r in await Future.wait(responses)) r.text];

    for (var i = 0; i < 20; i++) {
      expect(texts[i], startsWith('user$i/'));
    }
    expect(texts.map((t) => t.split('/').last).toSet(), hasLength(20));
    final log = app.app.container.all<TxLog>().single;
    expect(log.created, 20);
    expect(log.disposed, 20);
  });
}
