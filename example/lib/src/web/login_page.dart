import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The content of the `/login` page: the form that posts the name to
/// `LoginApi`.
final class LoginPage extends StatelessComponent {
  /// Creates the page.
  const LoginPage();

  @override
  Component build(BuildContext context) => Component.fragment([
    h1([Component.text('Sign in')]),
    form(action: '/login', method: FormMethod.post, [
      label(htmlFor: 'name', [Component.text('Name ')]),
      input(id: 'name', name: 'name', type: InputType.text),
      button(type: ButtonType.submit, [Component.text('Sign in')]),
    ]),
  ]);
}
