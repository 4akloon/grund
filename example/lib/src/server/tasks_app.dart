import 'package:dartnest/dartnest.dart';

import '../common/request_id_middleware.dart';
import '../common/timing_interceptor.dart';

/// Creates the tasks application the same way for both styles, every
/// adapter and the tests.
abstract final class TasksApp {
  /// The application-level components; resolved from the root module.
  static const enhancers = Enhancers(interceptors: [Use<TimingInterceptor>()]);

  /// Creates the application for [root] (`appModule` from the generated
  /// library or `explicitAppModule`), served by [adapter] if given.
  /// [onError] receives unexpected errors (default: print).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    ErrorLogger? onError,
  }) async {
    final app = await Application.create(
      root,
      adapter: adapter,
      enhancers: enhancers,
      onError: onError,
    );
    app.use(RequestIdMiddleware().call);
    return app;
  }
}
