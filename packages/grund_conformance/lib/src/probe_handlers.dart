import 'dart:async';
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';

/// Handlers of the probe routes that do not fit in one expression.
abstract final class ProbeHandlers {
  /// The request as JSON: method, path, raw query, every header value, the
  /// body as text and the client address.
  static Future<Map<String, Object?>> echo(HttpCtx c) async {
    final request = c.request;
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

  /// Streams the request body; answers its length and checksum.
  static Future<Map<String, Object?>> upload(
    ConformanceProbe probe,
    HttpCtx c,
  ) async {
    var length = 0;
    var checksum = 0;
    await for (final chunk in c.request.body.stream) {
      if (!probe.firstUploadChunk.isCompleted) {
        probe.firstUploadChunk.complete();
      }
      length += chunk.length;
      checksum = (checksum + ConformanceData.checksum(chunk)) % 65521;
    }
    return {'length': length, 'checksum': checksum};
  }

  /// `first;`, then waits for the probe's release, then `last`.
  static Stream<List<int>> gated(ConformanceProbe probe) async* {
    yield utf8.encode('first;');
    probe.entered.complete();
    await probe.release.future;
    yield utf8.encode('last');
  }

  /// One chunk, then a failure.
  static Stream<List<int>> broken() async* {
    yield utf8.encode('partial');
    // Gives the adapter time to flush the first chunk before the failure.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('broken body stream');
  }

  /// A response with repeated `set-cookie` and `x-multi` headers.
  static HttpResponse cookies() => HttpResponse.text(
    'cookies',
    headers: HeaderMap()
      ..add('set-cookie', 'a=1')
      ..add('set-cookie', 'b=2')
      ..add('x-multi', 'one')
      ..add('x-multi', 'two'),
  );
}
