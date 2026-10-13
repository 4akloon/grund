import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../client_response.dart';
import '../conformance_data.dart';
import '../conformance_server.dart';
import '../raw_http.dart';
import '../raw_response.dart';

/// Bodies stream in both directions without being buffered whole, use
/// `content-length` or chunked framing as appropriate, and `HEAD` sends
/// headers only.
abstract final class BodyConformance {
  /// Bytes in a "large" body: far above any socket or adapter buffer.
  static const largeSize = 8 * 1024 * 1024;

  /// How long a test waits for a step the adapter must make on its own.
  static const stepTimeout = Duration(seconds: 5);

  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('bodies', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('streams a large chunked upload to the handler', () async {
        final request = await server.client.post(
          '127.0.0.1',
          server.port,
          '/probe/upload',
        );
        await request.addStream(ConformanceData.chunks(largeSize));
        final response = await ClientResponse.read(await request.close());

        expect(response.json, {
          'length': largeSize,
          'checksum': ConformanceData.checksum(
            ConformanceData.bytes(largeSize),
          ),
        });
      });

      test('hands the upload to the handler before it ends', () async {
        final request = await server.client.post(
          '127.0.0.1',
          server.port,
          '/probe/upload',
        );
        request.bufferOutput = false;
        request.add(ConformanceData.bytes(1024));
        await request.flush();
        await server.probe.firstUploadChunk.future.timeout(stepTimeout);
        request.add(ConformanceData.bytes(1024));
        final response = await ClientResponse.read(await request.close());

        expect((response.json as Map)['length'], 2048);
      });

      test('streams a large download with chunked framing', () async {
        final response = await server.send(
          'GET',
          '/probe/download?size=$largeSize',
        );

        expect(response.headers.chunkedTransferEncoding, isTrue);
        expect(response.headers.contentLength, -1);
        expect(response.bytes.length, largeSize);
        expect(
          ConformanceData.checksum(response.bytes),
          ConformanceData.checksum(ConformanceData.bytes(largeSize)),
        );
      });

      test('sends content-length for an in-memory body', () async {
        const size = 1024 * 1024;
        final response = await server.send(
          'GET',
          '/probe/download-fixed?size=$size',
        );

        expect(response.headers.contentLength, size);
        expect(response.headers.chunkedTransferEncoding, isFalse);
        expect(response.bytes, ConformanceData.bytes(size));
      });

      // Review Focus 1: server-sent events need unbuffered chunks.
      test('flushes each chunk of a streamed response', () async {
        final request = await server.client.get(
          '127.0.0.1',
          server.port,
          '/probe/gated-stream',
        );
        final response = await request.close().timeout(stepTimeout);
        final chunks = StreamIterator(response);

        expect(await chunks.moveNext().timeout(stepTimeout), isTrue);
        expect(utf8.decode(chunks.current), 'first;');
        server.probe.release.complete();
        final rest = <int>[];
        while (await chunks.moveNext()) {
          rest.addAll(chunks.current);
        }
        expect(utf8.decode(rest), 'last');
      });

      test('answers HEAD with the GET headers and no body', () async {
        final get = await server.send('GET', '/users/1');
        final head = await RawHttp.exchange(
          server.port,
          RawHttp.head('HEAD', '/users/1'),
        );

        expect(head.status, 200);
        expect(head.headers['content-length'], '${get.bytes.length}');
        expect(head.headers['content-type'], get.headers.value('content-type'));
        expect(head.bytes.length, _headLength(head));
      });

      // Review Focus 2: dart:io drains a HEAD body to its end.
      test('cancels a streamed body for HEAD without reading it', () async {
        final head = await RawHttp.exchange(
          server.port,
          RawHttp.head('HEAD', '/probe/endless'),
        );

        expect(head.status, 200);
        expect(head.bytes.length, _headLength(head));
        await server.probe.endlessCancelled.future.timeout(stepTimeout);
      });

      // Review Focus 5: shelf treats such a body as already chunked.
      test('frames the body itself despite an app transfer-encoding', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/framing'),
        );

        expect((response.isComplete, response.text), (true, 'framed'));
      });

      test(
        'closes the connection when the app sends connection: close',
        () async {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', '/probe/close-connection', headers: const {}) +
                RawHttp.head('GET', '/probe/echo'),
          );

          expect(response.text, 'bye');
          expect(
            'HTTP/1.1 '.allMatches(latin1.decode(response.bytes)),
            hasLength(1),
          );
        },
      );
    });
  }

  /// Length of the status line and headers of [response], including the
  /// blank line: all a body-less response may contain.
  static int _headLength(RawResponse response) =>
      latin1.decode(response.bytes).indexOf('\r\n\r\n') + 4;
}
