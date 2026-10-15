import 'package:grund/grund.dart';

import '../adapter/http_adapter.dart';
import '../api/http_api.dart';
import '../hook/middleware_chain.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_code.dart';
import '../http/problem_responder.dart';
import '../serialize/response_serializer.dart';
import '../serialize/serializer_registry.dart';
import 'access_log.dart';
import 'active_calls.dart';
import 'http_config.dart';
import 'http_module.dart';
import 'request_dispatcher.dart';
import 'route_executor.dart';
import 'route_table.dart';
import 'route_table_builder.dart';
import 'server_log.dart';

/// Serves the `HttpApi`s of the application over an `HttpAdapter`.
///
/// `HttpModule` binds it; `App` finds it as a [Runner] named `http`.
/// [prepare] builds the route table and checks it (so a conflicting route
/// or a missing hook fails the start, before anything listens); [start] hands
/// [handle] to the adapter; [stop] stops accepting, waits for the requests in
/// progress and tells the ones that stay behind to give up.
final class HttpServer extends Runner {
  /// Creates the server; `HttpModule` does this with the bindings of the
  /// graph. [module] supplies the global hooks, the middleware and the codecs.
  HttpServer(
    HttpModule module, {
    required HttpAdapter adapter,
    required HttpConfig config,
  }) : this._(module, adapter, config, ProblemResponder(debug: config.debug));

  HttpServer._(this._module, this._adapter, this._config, this._problems)
    : _dispatcher = _dispatcherFor(_module, _config, _problems),
      _access = AccessLog(enabled: _config.accessLog);

  final HttpModule _module;
  final HttpAdapter _adapter;
  final HttpConfig _config;
  final ProblemResponder _problems;
  final RequestDispatcher _dispatcher;
  final AccessLog _access;
  final ServerLog _log = const ServerLog();
  final ActiveCalls _calls = ActiveCalls();
  RouteTable? _table;
  var _listening = false;
  var _stopping = false;
  Future<void>? _stopped;

  static RequestDispatcher _dispatcherFor(
    HttpModule module,
    HttpConfig config,
    ProblemResponder problems,
  ) {
    final registry = SerializerRegistry();
    for (final codec in module.codecs) {
      codec.registerIn(registry);
    }
    return RequestDispatcher(
      problems: problems,
      executor: RouteExecutor(
        serializer: ResponseSerializer(registry),
        problems: problems,
        maxBodyBytes: config.maxBodyBytes,
      ),
    );
  }

  @override
  String get name => 'http';

  /// The served routes as `'GET /users/:id'`, sorted; empty before the
  /// application is prepared.
  List<String> get routes => _table?.routes ?? const [];

  /// Answers [request] the way the adapter does, counted as in flight until
  /// it completes: the entry for `TestClient` and `shelfHandler`.
  ///
  /// Never throws for a request; every failure is a problem response, and a
  /// server that is shutting down answers 503.
  Future<HttpResponse> handle(HttpRequest request) {
    if (_stopping) {
      return _access.record(request, () async => _unavailable(request));
    }
    return _calls.track(() => _answer(request));
  }

  @override
  Future<void> prepare(Injector injector) async {
    final table = await _buildTable(injector);
    _table = table;
    _log.mapped(table.routes);
  }

  @override
  Future<void> start(Injector injector) async {
    _listening = true;
    try {
      await _adapter.listen(
        _answer,
        address: _config.address,
        port: _config.port,
      );
    } on Object {
      // The adapter is third-party code; the failure (a port in use) goes on
      // unchanged, but this server must not claim to listen.
      _listening = false;
      rethrow;
    }
    _log.listening(_config.address, _config.port);
  }

  @override
  Future<void> stop() => _stopped ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    // When the adapter fails to close, its state is unknown: the failure is
    // reported without waiting for requests that may never finish.
    try {
      if (_listening) await _adapter.close();
      await _calls.idle;
      if (_listening) _log.closed();
    } finally {
      _calls.cancelAll();
    }
  }

  @override
  Future<ReassembleReport> reassemble(Injector injector) async {
    final next = await _buildTable(injector);
    final previous = routes;
    _table = next;
    final report = ReassembleReport.between(previous, next.routes);
    _log
      ..mapped(report.added)
      ..unmapped(report.removed);
    return report;
  }

  Future<RouteTable> _buildTable(Injector injector) =>
      RouteTableBuilder.build(injector.all<HttpApi>(), _module.use);

  Future<HttpResponse> _answer(HttpRequest request) =>
      _access.record(request, () => _serve(request));

  Future<HttpResponse> _serve(HttpRequest request) async {
    final table = _table;
    if (table == null) {
      throw const ApplicationStateError(
        operation: 'handle',
        reason: 'the application is not started',
      );
    }
    if (_stopping) return _unavailable(request);
    final cancel = _calls.open();
    // Request boundary: a middleware is user code; its failure is a problem
    // response, like that of a hook, and the adapter never sees a throw.
    try {
      return await MiddlewareChain.run(
        _module.middleware,
        request,
        () => _dispatcher.dispatch(request, table, cancel),
      );
    } on Object catch (error, stackTrace) {
      return _problems.respond(error, stackTrace, instance: request.uri.path);
    } finally {
      _calls.release(cancel);
    }
  }

  HttpResponse _unavailable(HttpRequest request) => _problems.respond(
    const ServiceUnavailableException(
      message: 'The server is shutting down.',
      code: ProblemCode.serverUnavailable,
    ),
    StackTrace.current,
    instance: request.uri.path,
  );
}
