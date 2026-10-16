import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'home_page.dart';
import 'login_page.dart';

/// The root component of the pages: picks the page for the path.
final class TasksSite extends StatelessComponent {
  /// Creates the site.
  const TasksSite();

  @override
  Component build(BuildContext context) {
    switch (Uri.parse(context.url).path) {
      case '/':
        return const HomePage();
      case '/login':
        return const LoginPage();
      default:
        context.setStatusCode(StatusCode.notFound);
        return Component.text('No page here.');
    }
  }
}
