import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:logging/logging.dart';
import 'package:tasks_api/tasks_api.dart';

import 'api_response.dart';

/// The tasks application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and what went wrong on the way.
final class LoopbackServer {
  LoopbackServer._(this.app, this.port, this.errors, this._logOutput);

  /// Serves the module graph [style] names with the adapter [kind].
  static Future<LoopbackServer> start(
    ModuleStyle style,
    AdapterKind kind,
  ) async {
    final errors = <Object>[];
    // An unexpected failure is logged (`SEVERE` on `grund.http`); the
    // adapters also report to `onError`. Both end up in [errors]. The
    // warning about the client bundle is expected: the tests do not build it.
    final logOutput = LogOutput.console(
      level: Level.WARNING,
      color: false,
      sink: (line) {
        if (!line.contains('The client bundle')) errors.add(line);
      },
    ).attach();
    final app = App(
      root: ServingModule(
        TasksApp.graph(style),
        kind,
        address: InternetAddress.loopbackIPv4,
        port: 0,
        onError: (error, _) => errors.add(error),
      ),
    );
    await app.start();
    final port = switch (app.container.all<HttpAdapter>().first) {
      IoAdapter(:final port) => port,
      ShelfAdapter(:final port) => port,
      final other => throw StateError('Unexpected adapter $other.'),
    };
    return LoopbackServer._(app, port, errors, logOutput);
  }

  /// The served application.
  final App app;

  /// The port the adapter bound.
  final int port;

  /// What the application logged at `WARNING` or above and what the
  /// adapter reported as unexpected.
  final List<Object> errors;

  static final _formType = ContentType('application', 'x-www-form-urlencoded');

  final LogSubscription _logOutput;
  final HttpClient _client = HttpClient();

  /// Sends [method] to [target] with [headers] and [json] or the form
  /// fields [form] (already encoded) as the body; reads the whole response
  /// and does not follow a redirect.
  Future<ApiResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    Object? json,
    String? form,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$target'),
    );
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    if (form != null) {
      request.headers.contentType = _formType;
      request.write(form);
    }
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final first = <String, String>{};
    response.headers.forEach((name, values) => first[name] = values.first);
    final cookies = response.headers[HttpHeaders.setCookieHeader] ?? const [];
    return ApiResponse(response.statusCode, first, body, setCookies: cookies);
  }

  /// Closes the client and the application.
  Future<void> close() async {
    _client.close(force: true);
    await app.container.all<HttpAdapter>().first.close(force: true);
    await app.close();
    await _logOutput.cancel();
  }
}
