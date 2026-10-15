import 'dart:async';
import 'dart:convert';

import 'package:grund/grund.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';

/// The application every adapter serves in the conformance suite: a small
/// users API plus `/probe` routes that expose what the adapter delivered.
///
/// - `GET /users/:id`, `POST /users` (`{"name"}` → 201 with `location`).
/// - `GET|POST|PUT|PATCH|DELETE /probe/echo`: method, path, raw query,
///   every header value, the body as text and the client address.
/// - `GET /probe/segments/:value`: the decoded path parameter.
/// - `POST /probe/upload`: streams the body; answers its length and
///   checksum.
/// - `GET /probe/download?size=n` (streamed) and
///   `GET /probe/download-fixed?size=n` (in memory): [ConformanceData].
/// - `GET /probe/gated-stream`, `GET /probe/slow`, `GET /probe/endless`:
///   wait for or report through the [ConformanceProbe].
/// - `GET /probe/broken-stream`: a body stream that fails after a chunk.
/// - `GET /probe/cookies`, `/probe/framing`, `/probe/close-connection`,
///   `/probe/empty`, `/probe/fail`: header and error edge cases.
/// - `GET /probe/bad-header`, `/probe/bad-length`:
///   responses whose head cannot be written.
Module conformanceModule(ConformanceProbe probe) => Module(
  id: 'conformance',
  providers: [Provider.value(probe), Provider((i) => _ConformanceUsers())],
  controllers: [_usersController, _probeController],
);

/// In-memory users of the conformance application.
final class _ConformanceUsers {
  final Map<int, String> _names = {1: 'ann', 2: 'bob'};

  /// The user with [id] as JSON; [NotFoundException] when absent.
  Map<String, Object?> find(int id) => switch (_names[id]) {
    final name? => {'id': id, 'name': name},
    null => throw NotFoundException(message: 'No user $id'),
  };

  /// Adds a user called [name] and returns it as JSON.
  Map<String, Object?> create(String name) {
    final id = _names.length + 1;
    _names[id] = name;
    return find(id);
  }
}

final _usersController = Controller<_ConformanceUsers>(
  path: '/users',
  create: (i) => i.get(),
  routes: [
    Route.get('/:id', (users, ctx) async => users.find(await ctx.param('id'))),
    Route.post('/', (users, ctx) async {
      final name = await ctx.bodyAs(
        (json) => switch (json) {
          {'name': final String name} => name,
          _ => throw const FormatException('"name" must be a string'),
        },
      );
      final user = users.create(name);
      ctx.switchToHttp().response
        ..status = StatusCode.created
        ..headers.set('location', '/users/${user['id']}');
      return user;
    }),
  ],
);

final _probeController = Controller<ConformanceProbe>(
  path: '/probe',
  create: (i) => i.get(),
  routes: [
    Route.get('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.post('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.put('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.patch('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.delete('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.get(
      '/segments/:value',
      (_, ctx) async => {'value': await ctx.param<String>('value')},
    ),
    Route.post('/upload', _ProbeHandlers.upload),
    Route.get(
      '/download',
      (_, ctx) async =>
          HttpResponse.stream(ConformanceData.chunks(await ctx.query('size'))),
    ),
    Route.get(
      '/download-fixed',
      (_, ctx) async =>
          HttpResponse.bytes(ConformanceData.bytes(await ctx.query('size'))),
    ),
    Route.get(
      '/gated-stream',
      (probe, _) => HttpResponse.stream(_ProbeHandlers.gated(probe)),
    ),
    Route.get('/slow', (probe, _) async {
      probe.entered.complete();
      await probe.release.future;
      return 'done';
    }),
    Route.get(
      '/endless',
      (probe, _) => HttpResponse.stream(
        ConformanceData.endless(probe.endlessCancelled.complete),
      ),
    ),
    Route.get(
      '/broken-stream',
      (_, _) => HttpResponse.stream(_ProbeHandlers.broken()),
    ),
    Route.get('/cookies', (_, _) => _ProbeHandlers.cookies()),
    Route.get(
      '/framing',
      (_, _) => HttpResponse.text(
        'framed',
        headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
      ),
    ),
    Route.get(
      '/close-connection',
      (_, _) => HttpResponse.text(
        'bye',
        headers: HeaderMap.of({'connection': 'close'}),
      ),
    ),
    Route.get(
      '/bad-header',
      (_, _) => HttpResponse.text(
        'x',
        headers: HeaderMap.of({'x-bad': 'one\r\ntwo'}),
      ),
    ),
    Route.get(
      '/bad-length',
      (_, _) => HttpResponse.stream(
        Stream.value(utf8.encode('x')),
        headers: HeaderMap.of({'content-length': 'abc'}),
      ),
    ),
    Route.get('/empty', (_, _) => null),
    Route.get('/fail', (_, _) => throw StateError('handler failure')),
  ],
);

/// Handlers of the probe routes that do not fit in one expression.
abstract final class _ProbeHandlers {
  static Future<Map<String, Object?>> echo(ExecutionContext ctx) async {
    final request = ctx.switchToHttp().request;
    return {
      'method': request.method,
      'path': request.uri.path,
      'query': request.uri.query,
      'headers': {
        for (final name in request.headers.names)
          name: request.headers.all(name),
      },
      'body': await request.body.text(),
      'remoteAddress': request.connectionInfo?.remoteAddress,
      'remotePort': request.connectionInfo?.remotePort,
    };
  }

  static Future<Map<String, Object?>> upload(
    ConformanceProbe probe,
    ExecutionContext ctx,
  ) async {
    var length = 0;
    var checksum = 0;
    await for (final chunk in ctx.body.stream) {
      if (!probe.firstUploadChunk.isCompleted) {
        probe.firstUploadChunk.complete();
      }
      length += chunk.length;
      checksum = (checksum + ConformanceData.checksum(chunk)) % 65521;
    }
    return {'length': length, 'checksum': checksum};
  }

  static Stream<List<int>> gated(ConformanceProbe probe) async* {
    yield utf8.encode('first;');
    probe.entered.complete();
    await probe.release.future;
    yield utf8.encode('last');
  }

  static Stream<List<int>> broken() async* {
    yield utf8.encode('partial');
    // Gives the adapter time to flush the first chunk before the failure.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('broken body stream');
  }

  static HttpResponse cookies() => HttpResponse.text(
    'cookies',
    headers: HeaderMap()
      ..add('set-cookie', 'a=1')
      ..add('set-cookie', 'b=2')
      ..add('x-multi', 'one')
      ..add('x-multi', 'two'),
  );
}
