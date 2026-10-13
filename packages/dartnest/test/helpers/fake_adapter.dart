// An HttpAdapter that records calls instead of opening sockets.
import 'package:dartnest/dartnest.dart';

/// Records `listen` and `close` calls; [send] plays the native server.
final class FakeAdapter implements HttpAdapter {
  RequestHandler? handler;
  Object? address;
  int? port;
  final List<bool> closeCalls = [];

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    this.handler = handler;
    this.address = address;
    this.port = port;
  }

  @override
  Future<void> close({bool force = false}) async => closeCalls.add(force);

  /// Delivers [request] the way a server would.
  Future<HttpResponse> send(HttpRequest request) {
    final current = handler;
    if (current == null) throw StateError('listen was not called');
    return current(request);
  }
}
