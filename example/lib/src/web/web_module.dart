import 'package:grund/grund.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import 'login_api.dart';
import 'tasks_site.dart';

/// The pages of the tasks application and the session they share with the
/// API: [SessionModule], [LoginApi] and the Jaspr pages of [TasksSite],
/// which read the services [tasks] exports.
///
/// Written with the explicit API in both graphs: `JasprModule(app:)` takes
/// a function, which an annotation cannot hold.
final class WebModule extends Module {
  /// The pages over the tasks module [tasks].
  const WebModule(this.tasks);

  /// `TasksModule` or `ExplicitTasksModule`.
  final Module tasks;

  @override
  List<Module> get imports => [
    // Plain http in the example; keep the default secure: true in an
    // application served over HTTPS.
    const SessionModule(config: SessionConfig(secure: false)),
    JasprModule(app: TasksSite.new, imports: [tasks]),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<LoginApi>(
      (i) => LoginApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
