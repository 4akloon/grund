import 'package:grund_auth/grund_auth.dart' as auth;
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../tasks/tasks_service.dart';
import 'task_panel.dart';

/// The content of the `/` page: the task list, who is signed in, and the form
/// to sign out.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) {
    final tasks = context.call<TasksService>().list();
    // grund_auth's CurrentUser, not the example's own (the API key's).
    final user = context.maybe<auth.CurrentUser>();
    return Component.fragment([
      if (_takeFlash(context))
        p(classes: 'flash', [Component.text('Signed in.')]),
      h1([Component.text('Tasks')]),
      TaskPanel(tasks: tasks, editable: user != null),
      if (user == null)
        a(href: '/login', [Component.text('Sign in')])
      else
        form(action: '/logout', method: FormMethod.post, [
          Component.text('Signed in as ${user.id}. '),
          button(type: ButtonType.submit, [Component.text('Sign out')]),
        ]),
    ]);
  }

  // Read through grund: Jaspr's context.cookies throws on a malformed
  // cookie of another application on the same host.
  static bool _takeFlash(BuildContext context) {
    final flash = GrundScope.of(context).cookies.stringOrNull('flash');
    if (flash == null) return false;
    context.setCookie('flash', '', maxAge: 0, path: '/');
    return flash == 'signed-in';
  }
}
