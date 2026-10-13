import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Builds the dartnest [HttpRequest] for a `dart:io` request.
abstract final class IoRequestMapper {
  /// The request for [native]: its method, its target as a path with the
  /// raw query, every header value except `transfer-encoding` (the body
  /// is already de-chunked), the unread body stream and the client
  /// address.
  static HttpRequest map(io.HttpRequest native) {
    final headers = HeaderMap();
    native.headers.forEach((name, values) {
      if (name == io.HttpHeaders.transferEncodingHeader) return;
      for (final value in values) {
        headers.add(name, value);
      }
    });
    final connection = native.connectionInfo;
    return HttpRequest(
      method: native.method,
      uri: target(native.uri),
      headers: headers,
      body: RequestBody(native),
      connectionInfo: connection == null
          ? null
          : ConnectionInfo(
              remoteAddress: connection.remoteAddress.address,
              remotePort: connection.remotePort,
            ),
    );
  }

  /// The path and raw query of [parsed], the target as `dart:io` parsed it
  /// (`Uri.parse`, so dot segments are already removed). An origin-form
  /// target that starts with `//` comes back with its first segment as
  /// the authority; it is put back into the path. The first segment of a
  /// `//` target is case-folded because `Uri.parse` treats it as an
  /// authority. `Host` is not used, so it cannot change the routed path.
  static Uri target(Uri parsed) {
    final path = parsed.hasAuthority && !parsed.hasScheme
        ? '//${parsed.authority}${parsed.path}'
        : parsed.path;
    return Uri(
      path: path.isEmpty ? '/' : path,
      query: parsed.hasQuery ? parsed.query : null,
    );
  }
}
