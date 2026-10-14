import 'package:meta/meta.dart';

import '../di/container.dart';
import '../di/module.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/serializer_registry.dart';
import '../routing/router.dart';
import '../pipeline/application_error.dart';
import 'application_assembly.dart';
import 'http_adapter.dart';
import 'in_flight_requests.dart';
import 'middleware.dart';
import 'request_dispatcher.dart';

/// A started dartnest application: the container, the route table and the
/// request pipeline. Works without a server through [handle]; serves HTTP
/// through an [HttpAdapter] and [listen].
///
/// ```dart
/// final app = await Application.create(appModule);
/// final response = await app.handle(
///   HttpRequest(method: 'GET', uri: Uri.parse('/users/1')),
/// );
/// await app.close();
/// ```
final class Application {
  Application._({
    required this.container,
    required Router<Endpoint> router,
    required HttpAdapter? adapter,
    required HttpErrorResponder errors,
  }) : _router = router,
       _adapter = adapter,
       _errors = errors,
       _dispatcher = RequestDispatcher(
         serializer: ResponseSerializer(SerializerRegistry()),
         errors: errors,
       );

  /// Builds the module returned by [root], validates the routes, starts the
  /// container, creates the controllers and builds the route table.
  ///
  /// [root] is a function so that the module graph can be rebuilt after a
  /// hot reload. [enhancers] are the application-level components, resolved
  /// through the root module. [debug] adds error details to 500 responses;
  /// [onError] receives unexpected errors (default: print); it must not
  /// throw, or [handle] fails.
  ///
  /// Fails fast: a `RoutingError` before any provider is created, an
  /// `InjectionError` or `ApplicationError` (or any other failure) before the
  /// application is returned (the container is closed first).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) => fromModule(
    root(),
    adapter: adapter,
    enhancers: enhancers,
    debug: debug,
    onError: onError,
  );

  /// Like [create], for a module value.
  static Future<Application> fromModule(
    Module root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) async {
    final (:container, :router) = await ApplicationAssembly.start(
      root,
      enhancers,
    );
    return Application._(
      container: container,
      router: router,
      adapter: adapter,
      errors: HttpErrorResponder(
        debug: debug,
        log: onError ?? HttpErrorResponder.printError,
      ),
    );
  }

  /// The started dependency container.
  final Container container;

  /// Converters for result types without `toJson()`.
  SerializerRegistry get serializers => _dispatcher.serializer.registry;

  Router<Endpoint> _router;
  final HttpAdapter? _adapter;
  final HttpErrorResponder _errors;
  final RequestDispatcher _dispatcher;
  final List<Middleware> _middleware = [];
  final InFlightRequests _inFlight = InFlightRequests();
  Future<void>? _closing;
  bool _listening = false;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Adds [middleware] after the ones added before (it runs inside them);
  /// fails with [ApplicationStateError] after [close] has started.
  void use(Middleware middleware) {
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'use',
        reason: 'the application is closed',
      );
    }
    _middleware.add(middleware);
  }

  /// Answers [request]; never throws. After [close] it answers 503.
  ///
  /// The route table is read once per request, so a request keeps the table
  /// it started with even if [replaceRoutes] runs meanwhile.
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) return _unavailable();
    final router = _router;
    final chain = List.of(_middleware);
    return _inFlight.track(() => _answer(request, router, chain));
  }

  /// Serves the application through the adapter on [address] and [port]. The
  /// adapter gets an uncounted variant of [handle] (same answers, 503 after
  /// [close]); it counts its own in-flight requests. Fails with
  /// [ApplicationStateError] without an adapter, after [close], or when
  /// already listening. When the adapter fails to start, the error is passed
  /// on and [listen] can be called again, e.g. on another port.
  Future<void> listen({required int port, Object address = 'localhost'}) async {
    final adapter = _adapter;
    if (adapter == null) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'no HttpAdapter was passed to Application.create',
      );
    }
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is closed',
      );
    }
    if (_listening) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is already listening',
      );
    }
    _listening = true;
    // A failed start must not block a retry, e.g. on another port.
    var started = false;
    try {
      await adapter.listen(_handleForAdapter, address: address, port: port);
      started = true;
    } finally {
      if (!started) _listening = false;
    }
  }

  /// Stops the application: the adapter stops accepting requests, new
  /// requests answer 503, in-flight requests finish (unless [force]), then
  /// the container closes. Every call returns the same future; [force] of
  /// later calls is ignored.
  ///
  /// The adapter's `close` waits for the requests it delivered and may give
  /// up on them after a timeout of its own; this method then waits for the
  /// [handle] calls made directly, e.g. by `TestClient`.
  ///
  /// If the adapter's `close` throws, the wait for in-flight requests is
  /// skipped (the container is still closed and the error propagates to
  /// every `close()` caller), so a failing adapter can cut in-flight
  /// requests short.
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// Replaces the route table in one assignment. Requests already running
  /// finish on the table they started with. For hot reload; not public API.
  @internal
  void replaceRoutes(Router<Endpoint> router) => _router = router;

  // Not counted in _inFlight: the adapter's close waits for the requests it
  // delivered and may abandon them after its timeout; counting them here as
  // well would leave close waiting for a handler the adapter gave up on.
  Future<HttpResponse> _handleForAdapter(HttpRequest request) {
    if (isClosed) return _unavailable();
    return _answer(request, _router, List.of(_middleware));
  }

  Future<HttpResponse> _unavailable() => Future.value(
    _errors.respond(
      const ServiceUnavailableException(
        message: 'The application is shutting down.',
      ),
      StackTrace.current,
    ),
  );

  Future<void> _shutdown({required bool force}) async {
    final adapter = _adapter;
    try {
      if (_listening && adapter != null) await adapter.close(force: force);
      if (!force) await _inFlight.idle;
    } finally {
      await container.close();
    }
  }

  Future<HttpResponse> _answer(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
  ) async {
    // Request boundary: a throwing middleware still gets an answer.
    try {
      return await _next(request, router, chain, 0);
    } on Object catch (error, stackTrace) {
      return _errors.respond(error, stackTrace);
    }
  }

  Future<HttpResponse> _next(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
    int index,
  ) {
    if (index == chain.length) return _dispatcher.dispatch(request, router);
    return chain[index](
      request,
      () => _next(request, router, chain, index + 1),
    );
  }
}
