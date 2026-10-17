import 'dart:io';

import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import 'helpers/static_site.dart';
import 'helpers/temp_dir.dart';

const _path = '/static/app.js';

TempDir _directory() => TempDir.create()
  ..write('app.js', 'plain')
  ..write('app.js.br', 'brotli')
  ..write('app.js.gz', 'gzip');

Future<String> _body(TestClient client, String? acceptEncoding) async {
  final response = await client.get(
    _path,
    headers: {'accept-encoding': ?acceptEncoding},
  );
  return response.text;
}

void main() {
  test('br is preferred, with the type and the encoding header', () async {
    final client = await startWithStatic(_directory());

    final response = await client.get(
      _path,
      headers: {'accept-encoding': 'br, gzip'},
    );

    expect(response.text, 'brotli');
    expect(response.headers['content-encoding'], 'br');
    expect(response.headers['content-type'], contains('javascript'));
  });

  test('the accepted encoding and its quality pick the sibling', () async {
    final client = await startWithStatic(_directory());

    expect(await _body(client, 'gzip'), 'gzip');
    expect(await _body(client, 'br;q=0, gzip'), 'gzip');
    expect(await _body(client, 'gzip;q=1, br;q=0.5'), 'gzip');
    expect(await _body(client, 'br;q=0.5, gzip;q=0.5'), 'brotli');
    expect(await _body(client, '*'), 'brotli');
    expect(await _body(client, '*;q=0, gzip'), 'gzip');
    expect(await _body(client, 'identity'), 'plain');
    expect(await _body(client, null), 'plain');
  });

  test('a missing sibling falls back to the other, then to the file', () async {
    final dir = _directory();
    File(dir.resolve('app.js.br')).deleteSync();
    final client = await startWithStatic(dir);
    expect(await _body(client, 'br, gzip'), 'gzip');

    File(dir.resolve('app.js.gz')).deleteSync();
    final plain = await client.get(
      _path,
      headers: {'accept-encoding': 'br, gzip'},
    );
    expect(plain.text, 'plain');
    expect(plain.headers['content-encoding'], isNull);
  });

  test('a sibling older than the file is ignored', () async {
    final dir = _directory();
    final old = File(dir.resolve('app.js')).lastModifiedSync();
    File(dir.resolve('app.js.br'))
        .setLastModifiedSync(old.subtract(const Duration(hours: 1)));
    final client = await startWithStatic(dir);

    expect(await _body(client, 'br, gzip'), 'gzip');
  });

  test('a sibling linked to a file outside the root is ignored', () async {
    final outside = TempDir.create()..write('secret.br', 'secret');
    final dir = _directory();
    File(dir.resolve('app.js.br')).deleteSync();
    Link(dir.resolve('app.js.br')).createSync(outside.resolve('secret.br'));
    final client = await startWithStatic(dir);

    expect(await _body(client, 'br'), 'plain');
  });

  test('a sibling requested directly is a plain file', () async {
    final client = await startWithStatic(_directory());

    final response = await client.get(
      '/static/app.js.br',
      headers: {'accept-encoding': 'br, gzip'},
    );

    expect(response.text, 'brotli');
    expect(response.headers['content-encoding'], isNull);
  });

  test('every answer varies by accept-encoding, 304 too', () async {
    final client = await startWithStatic(_directory());

    final plain = await client.get(_path);
    final variant = await client.get(_path, headers: {'accept-encoding': 'br'});
    final notModified = await client.get(
      _path,
      headers: {
        'accept-encoding': 'br',
        'if-none-match': variant.headers['etag']!,
      },
    );

    expect(plain.headers['vary'], 'accept-encoding');
    expect(variant.headers['vary'], 'accept-encoding');
    expect(notModified.status, 304);
    expect(notModified.headers['vary'], 'accept-encoding');
  });

  test('each variant has its own etag and is revalidated by it', () async {
    final client = await startWithStatic(_directory());

    Future<String> etag(String? encoding) async => (await client.get(
      _path,
      headers: {'accept-encoding': ?encoding},
    )).headers['etag']!;
    final tags = {await etag(null), await etag('br'), await etag('gzip')};
    final other = await client.get(
      _path,
      headers: {'accept-encoding': 'gzip', 'if-none-match': await etag('br')},
    );

    expect(tags, hasLength(3));
    expect(other.status, 200);
  });
}
