import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

/// A `dart:io` request whose `requestedUri` is built from the request
/// target only (the host is the placeholder `localhost`, as dart:io does
/// not expose the local address).
///
/// `shelf_io` takes `requestedUri` from `dart:io`, which honours the
/// client-sent `X-Forwarded-Host` and `X-Forwarded-Proto` headers: a host
/// of `x/admin` turns `GET /public` into the path `/admin/public`. This
/// wrapper hands `shelf_io` a URI no header can influence; everything else
/// is the wrapped request.
final class TargetRequest extends Stream<Uint8List> implements io.HttpRequest {
  /// Wraps [request].
  TargetRequest(this._request);

  final io.HttpRequest _request;

  @override
  Uri get requestedUri {
    final parsed = _request.uri;
    // An origin-form target that starts with // parses with its first
    // segment as the authority; it is a path (RFC 9112).
    final path = parsed.hasAuthority && !parsed.hasScheme
        ? '//${parsed.authority}${parsed.path}'
        : parsed.path;
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: _request.connectionInfo?.localPort,
      path: path.isEmpty ? '/' : path,
      query: parsed.hasQuery ? parsed.query : null,
    );
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _request.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  io.X509Certificate? get certificate => _request.certificate;

  @override
  io.HttpConnectionInfo? get connectionInfo => _request.connectionInfo;

  @override
  int get contentLength => _request.contentLength;

  @override
  List<io.Cookie> get cookies => _request.cookies;

  @override
  io.HttpHeaders get headers => _request.headers;

  @override
  String get method => _request.method;

  @override
  bool get persistentConnection => _request.persistentConnection;

  @override
  String get protocolVersion => _request.protocolVersion;

  @override
  io.HttpResponse get response => _request.response;

  @override
  io.HttpSession get session => _request.session;

  @override
  Uri get uri => _request.uri;
}
