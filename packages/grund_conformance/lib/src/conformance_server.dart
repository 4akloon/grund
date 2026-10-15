import 'dart:async';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_under_test.dart';
import 'client_response.dart';
import 'conformance_probe.dart';
import 'conformance_root.dart';

/// The conformance application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the first error the
/// adapter reported.
final class ConformanceServer {
  ConformanceServer._(
    this.app,
    this.adapter,
    this.port,
    this.probe,
    this._errors,
  );

  /// The adapter's `closeTimeout` unless a test sets one: longer than any
  /// wait in the suite, so only the timeout tests reach it.
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// Starts the application with the adapter from [factory] and listens.
  /// [errorLog] replaces the recording `ErrorLog` of the application (to
  /// test one that throws); [closeTimeout] goes to the adapter.
  static Future<ConformanceServer> start(
    AdapterFactory factory, {
    ErrorLog? errorLog,
    Duration? closeTimeout = defaultCloseTimeout,
  }) async {
    final probe = ConformanceProbe();
    final errors = _ReportedErrors();
    final underTest = factory(errors.adapter, closeTimeout);
    final app = App(
      root: ConformanceRoot(probe, adapter: underTest.module),
      overrides: [
        Singleton<ErrorLog>(
          (_) => errorLog ?? errors.application,
          dependsOn: const [],
        ),
      ],
    );
    await app.start();
    final adapter = app.container.root<HttpAdapter>();
    return ConformanceServer._(
      app,
      adapter,
      underTest.portOf(adapter),
      probe,
      errors,
    );
  }

  /// The served application.
  final App app;

  /// The adapter under test, as the application resolved it.
  final HttpAdapter adapter;

  /// The port the adapter bound.
  final int port;

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  final _ReportedErrors _errors;

  /// A client with at most one connection, so keep-alive reuse is visible.
  final HttpClient client = HttpClient()..maxConnectionsPerHost = 1;

  /// Completes with the first error the adapter reports.
  Future<Object> get firstAdapterError => _errors.firstFromAdapter.future;

  /// `http://127.0.0.1:port` + [target].
  Uri uri(String target) => Uri.parse('http://127.0.0.1:$port$target');

  /// Sends [method] to [target] with [headers] and [body]; reads the whole
  /// response.
  Future<ClientResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, uri(target));
    headers.forEach(request.headers.add);
    if (body != null) request.add(body);
    return ClientResponse.read(await request.close());
  }

  /// Closes the client, the adapter (forcefully, so a test that failed
  /// midway does not hang the suite) and the application, and releases
  /// waiting handlers.
  Future<void> close() async {
    if (!probe.release.isCompleted) probe.release.complete();
    client.close(force: true);
    await adapter.close(force: true);
    await app.close();
  }
}

/// Records the first adapter error and silences the application log.
final class _ReportedErrors {
  final Completer<Object> firstFromAdapter = Completer<Object>();

  void adapter(Object error, StackTrace _) {
    if (!firstFromAdapter.isCompleted) firstFromAdapter.complete(error);
  }

  /// Silences the application log: 500s are expected in the suite.
  ErrorLog get application => const _SilentErrorLog();
}

final class _SilentErrorLog implements ErrorLog {
  const _SilentErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) {}
}
