import 'dart:convert';
import 'dart:typed_data';

import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:test/test.dart';

void main() {
  group('RawResponse', () {
    test('skips a header line without a colon', () {
      final response = RawResponse.parse(
        Uint8List.fromList(
          latin1.encode(
            'HTTP/1.1 200 OK\r\nnot a header\r\ncontent-length: 2\r\n\r\nok',
          ),
        ),
      );

      expect(response.status, 200);
      expect(response.headers['content-length'], '2');
      expect(response.text, 'ok');
    });
  });
}
