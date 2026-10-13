import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_response.dart';

/// HTTP/1.1 over a plain loopback socket, for requests `HttpClient` would
/// normalize (dot segments, a target starting with `//`, pipelining) and
/// for reading exactly what the server wrote.
abstract final class RawHttp {
  /// How long a raw exchange may take before the test fails.
  static const timeout = Duration(seconds: 10);

  /// The head of a request for [method] and [target] with `Host` and
  /// [headers]; add `Connection: close` to make [exchange] end.
  static String head(
    String method,
    String target, {
    Map<String, String> headers = const {'Connection': 'close'},
  }) {
    final lines = [
      '$method $target HTTP/1.1',
      'Host: 127.0.0.1',
      for (final MapEntry(:key, :value) in headers.entries) '$key: $value',
    ];
    return '${lines.join('\r\n')}\r\n\r\n';
  }

  /// Sends [request] (raw text, possibly several pipelined requests) to
  /// 127.0.0.1:[port] and reads until the server closes the connection.
  static Future<RawResponse> exchange(int port, String request) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.add(latin1.encode(request));
    await socket.flush();
    final received = BytesBuilder(copy: false);
    // The server may reset the connection after a failed body; what was
    // received until then is the result.
    await socket
        .listen(received.add, cancelOnError: true)
        .asFuture<void>()
        .catchError((Object _) {}, test: (error) => error is SocketException)
        .timeout(timeout);
    socket.destroy();
    return RawResponse.parse(received.takeBytes());
  }

  /// Sends [request], waits for the first bytes of the response and
  /// closes the socket, like a client that goes away mid-response.
  static Future<void> abortAfterFirstBytes(int port, String request) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.add(latin1.encode(request));
    await socket.flush();
    await socket.first.timeout(timeout);
    socket.destroy();
  }
}
