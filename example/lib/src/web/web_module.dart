import 'package:grund/grund.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import '../tasks/tasks_service.dart';

import 'home_markdown.dart';
import 'home_page.dart';
import 'login_api.dart';
import 'login_page.dart';
import 'public_site.dart';
import 'task_fragments.dart';

/// The pages of the tasks application and the session they share with the
/// API: [SessionModule], [LoginApi] and the pages of [PublicSite], which
/// read the services [tasks] exports.
///
/// Written with the explicit API in both graphs: pages are values, which
/// an annotation cannot hold.
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
    // Imported once here: this web part is shared by both roots, AppModule
    // and ExplicitAppModule.
    const JasprModule(),
    tasks,
  ];

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<PublicSite>(PublicSite.new),
    Pages.under<PublicSite>(
      (_) => [
        Page(
          '/',
          build: (_) => const HomePage(),
          meta: const PageMeta(title: 'Tasks'),
          // The same service as the HTML page, so both list the same tasks.
          alternates: [
            PageAlternate.markdown(
              (c, _) => HomeMarkdown.of(c<TasksService>().list()),
            ),
          ],
        ),
        Page(
          '/login',
          build: (_) => const LoginPage(),
          meta: const PageMeta(title: 'Sign in'),
        ),
      ],
    ),
    Singleton<LoginApi>(
      (i) => LoginApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
    Singleton<TaskFragments>(
      (i) => TaskFragments(i, i<TasksService>()),
      dependsOn: const [Key<TasksService>()],
    ),
  ];
}
