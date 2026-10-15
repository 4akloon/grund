import 'dart:io' as io;

import 'package:grund/grund.dart';

/// Answers every request with `ok`.
Future<HttpResponse> answerOk(HttpRequest request) async =>
    HttpResponse.text('ok');

final loopback = io.InternetAddress.loopbackIPv4;

/// A port nothing listens on right now.
Future<int> freePort() async {
  final socket = await io.ServerSocket.bind(loopback, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Fails unless [port] can be bound, i.e. no server holds it.
Future<void> expectPortFree(int port) async {
  final socket = await io.ServerSocket.bind(loopback, port);
  await socket.close();
}

/// GETs `/` from [port] and returns the response.
Future<io.HttpClientResponse> getRoot(io.HttpClient client, int port) async =>
    (await client.get('127.0.0.1', port, '/')).close();

/// The status code of `GET /` on [port].
Future<int> statusOf(io.HttpClient client, int port) async =>
    (await getRoot(client, port)).statusCode;
