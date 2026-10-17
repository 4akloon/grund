import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'sites.dart';
import 'temp_dir.dart';

/// A static directory with `styles.css`, `favicon.ico` and `sub/a.txt`.
TempDir staticDirectory() => TempDir.create()
  ..write('styles.css', 'body{}')
  ..write('favicon.ico', 'icon')
  ..write('sub/a.txt', 'nested');

/// The config that serves [dir] with `favicon.ico` also at the root.
JasprConfig staticConfig(TempDir dir) =>
    JasprConfig(staticDirectory: dir.path, rootFiles: const ['favicon.ico']);

/// Starts the public site with the pages `/` and `/:slug` and [dir] as the
/// static directory.
Future<TestClient> startWithStatic(TempDir dir) => startPublic([
  homePage(const Component.text('Home')),
  Page('/:slug', build: (_) => const Component.text('slug page')),
], config: staticConfig(dir));
