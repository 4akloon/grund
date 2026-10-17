import 'api_response.dart';
import 'loopback_server.dart';

/// Signing in through the form of the site, as the web tests do.
abstract final class WebSession {
  /// Posts the sign-in form for [name] and returns the `cookie` header a
  /// browser sends afterwards: every cookie the answer set.
  static Future<String> signIn(
    LoopbackServer server,
    String name, {
    Map<String, String> headers = const {},
  }) async => cookieHeader(await login(server, name, headers: headers));

  /// The raw answer of the sign-in form for [name].
  static Future<ApiResponse> login(
    LoopbackServer server,
    String name, {
    Map<String, String> headers = const {},
  }) => server.send(
    'POST',
    '/login',
    form: 'name=${Uri.encodeQueryComponent(name)}',
    headers: headers,
  );

  /// The `cookie` header a browser sends after [response]: the name and
  /// value of every cookie it set.
  static String cookieHeader(ApiResponse response) =>
      response.setCookies.map((cookie) => cookie.split(';').first).join('; ');

  /// Only the session cookie of [response], as a browser keeps it after the
  /// flash cookie was deleted.
  static String sessionOnly(ApiResponse response) => response.setCookies
      .map((cookie) => cookie.split(';').first)
      .firstWhere((pair) => pair.startsWith('grund_sid='));
}
