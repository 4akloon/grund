import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/src/shelf_response_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('ShelfResponseMapper', () {
    test('copies status, every header value and the bytes', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text(
          'hello',
          status: 201,
          headers: HeaderMap()
            ..add('set-cookie', 'a=1')
            ..add('set-cookie', 'b=2'),
        ),
        isHead: false,
      );

      expect(response.statusCode, 201);
      expect(response.headersAll['set-cookie'], ['a=1', 'b=2']);
      expect(response.headers['content-length'], '5');
      expect(await response.readAsString(), 'hello');
    });

    // Review Focus 5.
    test('drops transfer-encoding set by the application', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text(
          'framed',
          headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
        ),
        isHead: false,
      );

      expect(response.headers.containsKey('transfer-encoding'), isFalse);
      expect(await response.readAsString(), 'framed');
    });

    test('streams a stream body without buffering', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.stream(Stream.value(utf8.encode('chunk'))),
        isHead: false,
      );

      expect(response.contentLength, isNull);
      expect(response.context[ShelfResponseMapper.bufferOutputKey], isFalse);
      expect(await response.readAsString(), 'chunk');
    });

    test('HEAD keeps the content-length of bytes and sends none', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text('hello'),
        isHead: true,
      );

      expect(response.headers['content-length'], '5');
      expect(await response.readAsString(), isEmpty);
    });

    test('HEAD sends no body for a stream body', () async {
      final source = StreamController<List<int>>();

      final response = ShelfResponseMapper.map(
        HttpResponse.stream(source.stream),
        isHead: true,
      );

      expect(await response.readAsString(), isEmpty);
      expect(source.hasListener, isFalse);
    });
  });
}
