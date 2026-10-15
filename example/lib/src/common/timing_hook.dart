import 'package:grund_http/grund_http.dart';

/// Adds `server-timing: handler;dur=<ms>` to every routed response, also to
/// an error one: the time the hooks after it and the handler took. Global:
/// `HttpModule(use:)` in `ServingModule`.
final class TimingHook extends HttpHook {
  /// Creates the hook.
  const TimingHook();

  @override
  void before(HttpCtx c) => c.set<Stopwatch>(Stopwatch()..start());

  @override
  void after(HttpCtx c, Object? result) => _stamp(c);

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    _stamp(c);
    return null;
  }

  void _stamp(HttpCtx c) {
    final milliseconds = c<Stopwatch>().elapsedMicroseconds / 1000;
    c.response.headers.set(
      'server-timing',
      'handler;dur=${milliseconds.toStringAsFixed(1)}',
    );
  }
}
