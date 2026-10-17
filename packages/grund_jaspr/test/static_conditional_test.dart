import 'dart:io';

import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import 'helpers/static_site.dart';
import 'helpers/temp_dir.dart';

const _path = '/static/styles.css';

Future<(TestClient, TempDir)> _start() async {
  final dir = staticDirectory();
  return (await startWithStatic(dir), dir);
}

void main() {
  test('a file is answered with its validators', () async {
    final (client, _) = await _start();

    final response = await client.get(_path);

    expect(response.status, 200);
    expect(response.headers['etag'], startsWith('W/"'));
    expect(HttpDate.parse(response.headers['last-modified']!), isA<DateTime>());
    expect(response.headers['cache-control'], 'no-cache');
    expect(response.headers['x-content-type-options'], 'nosniff');
  });

  test('a matching if-none-match is answered with an empty 304', () async {
    final (client, _) = await _start();
    final first = await client.get(_path);

    final response = await client.get(
      _path,
      headers: {'if-none-match': first.headers['etag']!},
    );

    expect(response.status, 304);
    expect(response.bytes, isEmpty);
    expect(response.headers['etag'], first.headers['etag']);
    expect(response.headers['last-modified'], first.headers['last-modified']);
    expect(response.headers['cache-control'], 'no-cache');
  });

  test('a tag without the weak prefix, a star and a list match', () async {
    final (client, _) = await _start();
    final tag = (await client.get(_path)).headers['etag']!;

    for (final header in [
      tag.substring(2),
      '*',
      '"other", $tag',
      '"other" ,  ${tag.substring(2)}',
    ]) {
      final response = await client.get(
        _path,
        headers: {'if-none-match': header},
      );
      expect(response.status, 304, reason: header);
    }
  });

  test('a tag that does not match is answered with 200', () async {
    final (client, _) = await _start();

    final response = await client.get(
      _path,
      headers: {'if-none-match': 'W/"nope"'},
    );

    expect(response.status, 200);
  });

  test('if-modified-since decides by the second', () async {
    final (client, _) = await _start();
    final modified = (await client.get(_path)).headers['last-modified']!;
    final earlier = HttpDate.format(
      HttpDate.parse(modified).subtract(const Duration(hours: 1)),
    );

    final same = await client.get(
      _path,
      headers: {'if-modified-since': modified},
    );
    final older = await client.get(
      _path,
      headers: {'if-modified-since': earlier},
    );

    expect(same.status, 304);
    expect(older.status, 200);
  });

  test(
    'if-none-match without a match beats a fresh if-modified-since',
    () async {
      final (client, _) = await _start();
      final modified = (await client.get(_path)).headers['last-modified']!;

      final response = await client.get(
        _path,
        headers: {'if-none-match': '"other"', 'if-modified-since': modified},
      );

      expect(response.status, 200);
    },
  );

  test('an unparsable if-modified-since is ignored', () async {
    final (client, _) = await _start();

    final response = await client.get(
      _path,
      headers: {'if-modified-since': 'yesterday'},
    );

    expect(response.status, 200);
  });

  test('a rewritten file of another size has another etag', () async {
    final (client, dir) = await _start();
    final before = (await client.get(_path)).headers['etag'];

    dir.write('styles.css', 'body{color:red}');
    final after = (await client.get(_path)).headers['etag'];

    expect(after, isNot(before));
  });
}
