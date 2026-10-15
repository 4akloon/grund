import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/serialize/response_serializer.dart';
import 'package:grund_http/src/server/request_dispatcher.dart';
import 'package:grund_http/src/server/route_executor.dart';
import 'package:grund_http/src/server/route_table.dart';
import 'package:grund_http/src/server/route_table_builder.dart';

import 'http_fixtures.dart';
import 'probe_api.dart';
import 'recording_error_log.dart';

/// A started graph with a route table and a dispatcher, without a server.
final class DispatchHarness {
  DispatchHarness._(this._app, this.table, this.dispatcher, this.log);

  /// Starts a module with [bindings] and serves the `HttpApi`s among them.
  static Future<DispatchHarness> start(
    List<Binding<Object>> bindings, {
    List<HookRef<HttpHook>> global = const [],
    int? maxBodyBytes,
    bool debug = false,
  }) async {
    final log = RecordingErrorLog();
    final app = await TestApp.start(root: ProbeModule(bindings));
    final RouteTable table;
    try {
      table = await RouteTableBuilder.build(
        app.app.container.all<HttpApi>(),
        global,
      );
    } on Object {
      // Test helper: do not leave the application open when the table fails.
      await app.close();
      rethrow;
    }
    final problems = ProblemResponder(debug: debug, log: log);
    final executor = RouteExecutor(
      serializer: ResponseSerializer(SerializerRegistry()),
      problems: problems,
      maxBodyBytes: maxBodyBytes,
    );
    return DispatchHarness._(
      app,
      table,
      RequestDispatcher(executor: executor, problems: problems),
      log,
    );
  }

  final TestApp _app;

  /// The routes of the graph.
  final RouteTable table;

  /// The dispatcher under test.
  final RequestDispatcher dispatcher;

  /// What the responder reported.
  final RecordingErrorLog log;

  /// Resolves a singleton of the graph.
  T call<T extends Object>() => _app.call<T>();

  /// Dispatches a request and returns the response.
  Future<HttpResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    String? body,
    CancelSignal? cancel,
  }) => dispatcher.dispatch(
    requestFor(method, target, headers: headers, body: body),
    table,
    cancel ?? CancelSignal(),
  );

  /// Closes the application.
  Future<void> close() => _app.close();
}
