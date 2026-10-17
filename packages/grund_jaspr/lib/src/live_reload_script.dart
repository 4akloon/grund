import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'error/jaspr_error.dart';
import 'jaspr_response.dart';

/// The script that reloads a page in the browser when `grund dev` reloaded
/// or restarted the application.
///
/// `grund dev` serves server-sent events on a loopback port and passes its
/// URL in [environmentVariable]; the script listens there for `reload`. The
/// variable is trusted only when its host is loopback, so a value from
/// elsewhere cannot point every page at another server.
abstract final class LiveReloadScript {
  /// The variable `grund dev` sets for the application it runs.
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';

  static const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

  static const _isProduct = bool.fromEnvironment('dart.vm.product');

  /// The URL in [environment], or `null` when it is not set or [isProduct];
  /// throws [JasprSetupError] when it is not an absolute `http` URL with a
  /// loopback host (`127.0.0.1`, `localhost` or `::1`).
  static Uri? urlFrom(
    Map<String, String> environment, {
    bool isProduct = _isProduct,
  }) {
    final value = environment[environmentVariable];
    if (isProduct || value == null) return null;
    final url = Uri.tryParse(value);
    if (url == null ||
        !url.isScheme('http') ||
        !_loopbackHosts.contains(url.host)) {
      throw JasprSetupError(
        '$environmentVariable must be an absolute http URL on a loopback '
        'host (127.0.0.1, localhost or [::1]); it is "$value".',
      );
    }
    return url;
  }

  /// [response] with the script for [url] before its last `</body>`, or at
  /// its end without one; a response that is not UTF-8 HTML is returned as
  /// it is.
  static HttpResponse addTo(HttpResponse response, Uri url) {
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    final body = response.body;
    if (!JasprResponse.isHtml(type) ||
        !type.contains('charset=utf-8') ||
        body is! BytesBody) {
      return response;
    }
    return HttpResponse(
      response.status,
      headers: response.headers,
      body: BytesBody(utf8.encode(inject(utf8.decode(body.bytes), url))),
    );
  }

  /// [html] with the script for [url] before its last `</body>` (in any
  /// case), or appended when there is none.
  static String inject(String html, Uri url) {
    final end = html.toLowerCase().lastIndexOf('</body>');
    final script = tag(url);
    return end < 0
        ? '$html$script'
        : '${html.substring(0, end)}$script${html.substring(end)}';
  }

  /// The `<script>` element for [url]. [Uri] percent-encodes `<`, `"` and
  /// `\` in every component, so the JSON string cannot close the element or
  /// the string literal.
  static String tag(Uri url) {
    final literal = jsonEncode('$url');
    return '<script>new EventSource($literal).addEventListener("reload",'
        'function(){location.reload()})</script>';
  }
}
