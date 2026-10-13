import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:test/test.dart';

void main() {
  group('conformanceModule', () {
    late ConformanceProbe probe; // Set in setUp before every test.
    late Application app; // Set in setUp before every test.
    late TestClient client; // Set in setUp before every test.

    setUp(() async {
      probe = ConformanceProbe();
      app = await Application.create(() => conformanceModule(probe));
      client = TestClient(app);
    });
    tearDown(() => app.close());

    test('serves the users API', () async {
      final created = await client.post('/users', json: {'name': 'cid'});

      expect((await client.get('/users/1')).json, {'id': 1, 'name': 'ann'});
      expect((created.status, created.headers['location']), (201, '/users/3'));
      expect((await client.get('/users/9')).status, 404);
    });

    test('echoes the request', () async {
      final response = await client.request(
        'PUT',
        '/probe/echo?b=%20x',
        body: 'hi',
        headers: {'X-Multi': 'a'},
      );

      expect(response.json, {
        'method': 'PUT',
        'path': '/probe/echo',
        'query': 'b=%20x',
        'headers': {
          'x-multi': ['a'],
        },
        'body': 'hi',
        'remoteAddress': null,
        'remotePort': null,
      });
    });

    test('streams an upload and reports its length and checksum', () async {
      final response = await client.send(
        HttpRequest(
          method: 'POST',
          uri: Uri.parse('/probe/upload'),
          body: RequestBody(ConformanceData.chunks(200000)),
        ),
      );

      expect(response.json, {
        'length': 200000,
        'checksum': ConformanceData.checksum(ConformanceData.bytes(200000)),
      });
      expect(probe.firstUploadChunk.isCompleted, isTrue);
    });

    test('downloads the payload streamed and in memory', () async {
      final streamed = await client.get('/probe/download?size=100000');
      final fixed = await client.get('/probe/download-fixed?size=100000');

      expect(streamed.bytes, ConformanceData.bytes(100000));
      expect(fixed.bytes, ConformanceData.bytes(100000));
    });

    test('holds the gated stream until the probe releases it', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/gated-stream')),
      );
      final body = response.body.readAll();

      await probe.entered.future;
      probe.release.complete();

      expect(utf8.decode(await body), 'first;last');
    });

    test('reports when the endless stream is cancelled', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/endless')),
      );
      final subscription = switch (response.body) {
        StreamBody(:final stream) => stream.listen(null),
        BytesBody() => fail('expected a stream body'),
      };

      await subscription.cancel();

      expect(probe.endlessCancelled.isCompleted, isTrue);
    });

    test('fails the broken stream after one chunk', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/broken-stream')),
      );

      await expectLater(response.body.readAll(), throwsStateError);
    });

    test('sends repeated headers and framing edge cases', () async {
      final cookies = await client.get('/probe/cookies');

      expect(cookies.headers.all('set-cookie'), ['a=1', 'b=2']);
      expect(cookies.headers.all('x-multi'), ['one', 'two']);
      expect(
        (await client.get('/probe/framing')).headers['transfer-encoding'],
        'chunked',
      );
      expect((await client.get('/probe/empty')).status, 204);
      expect((await client.get('/probe/fail')).status, 500);
    });
  });
}
