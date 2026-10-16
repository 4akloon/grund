import 'dart:io';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/content_types.dart';
import 'package:grund_jaspr/src/static_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

/// A temp directory with `web/app.css`, `web/.env` and, next to `web/`,
/// `secret.txt`; returns the files of `web/`.
StaticFiles _web(TempDir dir) {
  dir
    ..write('web/app.css', 'body{}')
    ..write('web/sub/page.js', 'go()')
    ..write('web/.env', 'secret')
    ..write('web/C:/secret.txt', 'secret')
    ..write('secret.txt', 'secret');
  return StaticFiles(dir.resolve('web'));
}

/// The segments of [path] as the router decodes them (`%2F` becomes `/`).
List<String> _decoded(String path) => Uri(path: path).pathSegments;

void main() {
  test('a file of the directory is found by its segments', () {
    final dir = TempDir.create();
    final files = _web(dir);

    expect(files.find(['app.css']), dir.resolve('web/app.css'));
    expect(files.find(['sub', 'page.js']), dir.resolve('web/sub/page.js'));
  });

  test('a directory, a missing file and the root are not files', () {
    final files = _web(TempDir.create());

    expect(files.find(['sub']), isNull);
    expect(files.find(['missing.css']), isNull);
    expect(files.find([]), isNull);
  });

  for (final segments in [
    ['..', 'secret.txt'],
    ['sub', '..', '..', 'secret.txt'],
    ['sub', '..', 'app.css'],
    _decoded('/%2e%2e/secret.txt'),
    ['.env'],
    ['../secret.txt'],
    [r'..\secret.txt'],
    ['C:', 'secret.txt'],
    ['', 'app.css'],
    ['app.css\x00'],
  ]) {
    test('$segments never leaves the directory', () {
      final files = _web(TempDir.create());

      expect(files.find(segments), isNull);
    });
  }

  // Each of these names an existing file of the directory when the rule
  // against its character is taken away.
  group('a segment with a forbidden character is never a file', () {
    late TempDir dir; // set in setUp, before every test body
    late StaticFiles files; // set in setUp, before every test body

    setUp(() {
      dir = TempDir.create();
      files = _web(dir);
      dir
        ..write('web/sub/with\\backslash.txt', 'x')
        ..write('web/with\x7fdelete.txt', 'x');
    });

    test('a slash (%2F)', () {
      expect(_decoded('/sub%2Fpage.js'), ['sub/page.js']);
      expect(files.find(_decoded('/sub%2Fpage.js')), isNull);
    });

    test(r'a backslash (%5C)', () {
      expect(files.find(_decoded('/sub/with%5Cbackslash.txt')), isNull);
    });

    test('a delete character (0x7f)', () {
      expect(files.find(['with\x7fdelete.txt']), isNull);
    });

    test('a colon', () {
      expect(files.find(['C:', 'secret.txt']), isNull);
    });

    test('a dot at the start', () {
      expect(files.find(['.env']), isNull);
    });
  });

  test(
    'a symbolic link out of the directory is not served',
    () {
      final dir = TempDir.create();
      final files = _web(dir);
      Link(dir.resolve('web/link.txt')).createSync(dir.resolve('secret.txt'));

      expect(files.find(['link.txt']), isNull);
    },
    skip: Platform.isWindows
        ? 'creating symbolic links needs privileges on Windows'
        : false,
  );

  test('a symbolic link inside the directory is served', () {
    final dir = TempDir.create();
    final files = _web(dir);
    Link(dir.resolve('web/alias.css')).createSync(dir.resolve('web/app.css'));

    expect(files.find(['alias.css']), dir.resolve('web/app.css'));
  });

  test('a directory that does not exist serves nothing', () {
    final dir = TempDir.create();

    expect(StaticFiles(dir.resolve('none')).find(['app.css']), isNull);
  });

  test('a relative directory is resolved against the working directory', () {
    expect(StaticFiles('web').root, p.join(Directory.current.path, 'web'));
  });

  test('a file is answered with its bytes, its type and no-cache', () async {
    final dir = TempDir.create();
    final files = _web(dir);

    final response = await files.respond(dir.resolve('web/app.css'));

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/css; charset=utf-8');
    expect(response.headers['cache-control'], 'no-cache');
    expect(String.fromCharCodes((response.body as BytesBody).bytes), 'body{}');
  });

  test('the type comes from the extension, in any case', () {
    expect(ContentTypes.forPath('a/b.PNG'), 'image/png');
    expect(ContentTypes.forPath('app.js'), 'text/javascript; charset=utf-8');
    expect(ContentTypes.forPath('font.woff2'), 'font/woff2');
    expect(ContentTypes.forPath('data.bin'), 'application/octet-stream');
    expect(ContentTypes.forPath('Makefile'), 'application/octet-stream');
  });
}
