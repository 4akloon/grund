import 'package:path/path.dart' as p;

/// The `content-type` of a static file, by its extension.
///
/// A small table of the types a web page uses; anything else is
/// `application/octet-stream`.
abstract final class ContentTypes {
  /// The type of the file at [path].
  static String forPath(String path) =>
      _byExtension[p.extension(path).toLowerCase()] ??
      'application/octet-stream';

  static const _byExtension = {
    '.avif': 'image/avif',
    '.css': 'text/css; charset=utf-8',
    '.gif': 'image/gif',
    '.htm': 'text/html; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.ico': 'image/x-icon',
    '.jpeg': 'image/jpeg',
    '.jpg': 'image/jpeg',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json',
    '.map': 'application/json',
    '.mjs': 'text/javascript; charset=utf-8',
    '.otf': 'font/otf',
    '.pdf': 'application/pdf',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.txt': 'text/plain; charset=utf-8',
    '.wasm': 'application/wasm',
    '.webmanifest': 'application/manifest+json',
    '.webp': 'image/webp',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.xml': 'application/xml',
  };
}
