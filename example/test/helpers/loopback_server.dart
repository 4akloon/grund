import 'dart:convert';
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:tasks_api/tasks_api.dart';

import 'api_response.dart';

/// The tasks application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the errors reported on the way.
final class LoopbackServer {
  LoopbackServer._(this.app, this.port, this.errors);

  /// Serves [root] with the adapter [kind] names.
  static Future<LoopbackServer> start(
    Module Function() root,
    AdapterKind kind,
  ) async {
    final errors = <Object>[];
    void record(Object error, StackTrace _) => errors.add(error);
    final HttpAdapter adapter;
    final int Function() boundPort;
    switch (kind) {
      case AdapterKind.io:
        final io = IoAdapter(onError: record);
        (adapter, boundPort) = (io, () => io.port);
      case AdapterKind.shelf:
        final shelf = ShelfAdapter(onError: record);
        (adapter, boundPort) = (shelf, () => shelf.port);
    }
    final app = await TasksApp.create(root, adapter: adapter, onError: record);
    await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
    return LoopbackServer._(app, boundPort(), errors);
  }

  /// The served application.
  final Application app;

  /// The port the adapter bound.
  final int port;

  /// What the application and the adapter reported to `onError`.
  final List<Object> errors;

  final HttpClient _client = HttpClient();

  /// Sends [method] to [target] with [headers] and [json] as the body;
  /// reads the whole response.
  Future<ApiResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    Object? json,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$target'),
    );
    headers.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final first = <String, String>{};
    response.headers.forEach((name, values) => first[name] = values.first);
    return ApiResponse(response.statusCode, first, body);
  }

  /// Closes the client and the application.
  Future<void> close() async {
    _client.close(force: true);
    await app.close(force: true);
  }
}
