import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_root.dart';

/// Stands for the source code of a route: a test edits it, and a hot
/// reload makes `routes` read it again.
final class _Code {
  static var paths = <String>['/old'];
  static Future<void>? gate;
}

final class _Counter {
  static var created = 0;
}

final class _EditableApi extends HttpApi {
  _EditableApi(super.injector);

  @override
  List<Route> get routes => [
    for (final path in _Code.paths)
      Route.get(path, (c) async {
        await _Code.gate;
        return path;
      }),
  ];
}

void main() {
  late App app;
  late HttpServer server;

  setUp(() async {
    _Code.paths = ['/old'];
    _Code.gate = null;
    _Counter.created = 0;
    app = App(
      root: ProbeRoot(FakeAdapter(), [
        Singleton<_EditableApi>(
          (i) => _EditableApi(i),
          name: 'editable',
          dependsOn: const [],
        ),
        Singleton<_Counter>((i) {
          _Counter.created++;
          return _Counter();
        }, dependsOn: const []),
      ]),
    );
    await app.start();
    server = serverOf(app);
  });

  tearDown(() => app.close());

  test('reports the routes added and removed', () async {
    _Code.paths = ['/new'];

    final report = await app.reassemble();

    expect(report.added, ['GET /new']);
    expect(report.removed, ['GET /old']);
    expect(server.routes, ['GET /new']);
  });

  test('a request in flight finishes on the table it began with', () async {
    final gate = Completer<void>();
    _Code.gate = gate.future;
    final inFlight = server.handle(requestFor('GET', '/old'));
    await pumpEventQueue();
    _Code.paths = ['/new'];
    _Code.gate = null;

    await app.reassemble();
    gate.complete();

    expect((await inFlight).status, 200);
    expect((await server.handle(requestFor('GET', '/old'))).status, 404);
    expect((await server.handle(requestFor('GET', '/new'))).status, 200);
  });

  test('a failed reassemble keeps serving the previous table', () async {
    _Code.paths = ['/old', '/old'];

    await expectLater(app.reassemble(), throwsA(isA<GrundError>()));

    expect(server.routes, ['GET /old']);
    expect((await server.handle(requestFor('GET', '/old'))).status, 200);
  });

  test('singletons of an unchanged module are kept', () async {
    _Code.paths = ['/other'];

    await app.reassemble();

    expect(_Counter.created, 1);
  });
}
