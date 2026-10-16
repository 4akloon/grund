import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The sign-in form; it posts the name to `LoginApi`.
final class LoginPage extends StatelessComponent {
  /// Creates the page.
  const LoginPage();

  @override
  Component build(BuildContext context) => Document(
    title: 'Sign in',
    head: [link(href: '/styles.css', rel: 'stylesheet')],
    body: main_([
      h1([Component.text('Sign in')]),
      form(action: '/login', method: FormMethod.post, [
        label(htmlFor: 'name', [Component.text('Name ')]),
        input(id: 'name', name: 'name', type: InputType.text),
        button(type: ButtonType.submit, [Component.text('Sign in')]),
      ]),
    ]),
  );
}
