import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

/// Adds `server-timing: handler;dur=<ms>` to every routed response: the
/// time the pipes and the handler took (guards run before interceptors).
/// Registered for the whole application in `TasksApp.enhancers`.
@Injectable()
final class TimingInterceptor implements Interceptor {
  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await next();
    } finally {
      final milliseconds = stopwatch.elapsedMicroseconds / 1000;
      context.switchToHttp().response.headers.set(
        'server-timing',
        'handler;dur=${milliseconds.toStringAsFixed(1)}',
      );
    }
  }
}
