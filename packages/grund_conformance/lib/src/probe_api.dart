import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';
import 'probe_handlers.dart';

/// The `/probe` routes: they expose what the adapter delivered and produce
/// the responses that stress it.
///
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
/// - `GET /probe/bad-header`, `/probe/bad-length`: responses whose head
///   cannot be written.
final class ProbeApi extends HttpApi {
  /// Creates the API over [_probe].
  ProbeApi(super.injector, this._probe);

  final ConformanceProbe _probe;

  @override
  String get path => '/probe';

  @override
  List<Route> get routes => [
    ..._echoRoutes,
    ..._streamRoutes,
    ..._headerRoutes,
    ..._failureRoutes,
  ];

  List<Route> get _echoRoutes => [
    Route.get('/echo', ProbeHandlers.echo),
    Route.post('/echo', ProbeHandlers.echo),
    Route.put('/echo', ProbeHandlers.echo),
    Route.patch('/echo', ProbeHandlers.echo),
    Route.delete('/echo', ProbeHandlers.echo),
    Route.get('/segments/:value', (c) => {'value': c.path.string('value')}),
  ];

  List<Route> get _streamRoutes => [
    Route.post('/upload', (c) => ProbeHandlers.upload(_probe, c)),
    Route.get(
      '/download',
      (c) =>
          HttpResponse.stream(ConformanceData.chunks(c.query.integer('size'))),
    ),
    Route.get(
      '/download-fixed',
      (c) => HttpResponse.bytes(ConformanceData.bytes(c.query.integer('size'))),
    ),
    Route.get(
      '/gated-stream',
      (_) => HttpResponse.stream(ProbeHandlers.gated(_probe)),
    ),
    Route.get('/slow', (_) async {
      _probe.entered.complete();
      await _probe.release.future;
      return 'done';
    }),
    Route.get(
      '/endless',
      (_) => HttpResponse.stream(
        ConformanceData.endless(_probe.endlessCancelled.complete),
      ),
    ),
  ];

  List<Route> get _headerRoutes => [
    Route.get('/cookies', (_) => ProbeHandlers.cookies()),
    Route.get(
      '/framing',
      (_) => HttpResponse.text(
        'framed',
        headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
      ),
    ),
    Route.get(
      '/close-connection',
      (_) => HttpResponse.text(
        'bye',
        headers: HeaderMap.of({'connection': 'close'}),
      ),
    ),
    Route.get('/empty', (_) => null),
  ];

  List<Route> get _failureRoutes => [
    Route.get(
      '/broken-stream',
      (_) => HttpResponse.stream(ProbeHandlers.broken()),
    ),
    Route.get(
      '/bad-header',
      (_) => HttpResponse.text(
        'x',
        headers: HeaderMap.of({'x-bad': 'one\r\ntwo'}),
      ),
    ),
    Route.get(
      '/bad-length',
      (_) => HttpResponse.stream(
        Stream.value(utf8.encode('x')),
        headers: HeaderMap.of({'content-length': 'abc'}),
      ),
    ),
    Route.get('/fail', (_) => throw StateError('handler failure')),
  ];
}
