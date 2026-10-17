import 'project_template.dart';

/// The files of a new fullstack application (`init --template fullstack`):
/// Jaspr pages rendered on the server, cookie sessions and a sign-in API,
/// written with the explicit API (no code generation).
///
/// A flat catalog of file contents without logic: the long string-literal
/// methods (`_appTest`) are literals, not code, and may exceed the method
/// limit like those of `ProjectTemplate`; for the same reason the file may
/// exceed the file limit.
abstract final class FullstackTemplate {
  /// The files of application [name] (relative path to content), sorted by
  /// path.
  ///
  /// [name] is interpolated into the files as is: it must be a valid Dart
  /// package name (`[a-z_][a-z0-9_]*`), which `ProjectScaffold` checks.
  static Map<String, String> files(String name) => {
    '.gitignore': '.dart_tool/\n',
    'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
    'bin/main.dart': _main(name),
    'lib/src/account_api.dart': _accountApi,
    'lib/src/app_module.dart': _appModule,
    'lib/src/pages/home_page.dart': _homePage,
    'lib/src/pages/login_page.dart': _loginPage,
    'lib/src/home_site_module.dart': _homeSiteModule,
    'lib/src/pages/public_site.dart': _publicSite,
    'pubspec.yaml': _pubspec(name),
    'test/app_test.dart': _appTest(name),
    'web/styles.css': _styles,
  };

  static const _grund = ProjectTemplate.grundVersion;

  static const _grundHttp = ProjectTemplate.grundHttpVersion;

  /// The release with sites and pages (`Pages.site`, `Pages.under`).
  static const _grundJaspr = '^0.2.0';

  static String _pubspec(String name) =>
      '''
name: $name
description: A grund application with server-rendered Jaspr pages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  grund: $_grund
  grund_auth: $_grund
  grund_http: $_grundHttp
  grund_io: $_grund
  grund_jaspr: $_grundJaspr
  jaspr: '>=0.23.5 <0.24.0'

dev_dependencies:
  grund_cli: ^0.1.2
  lints: ^5.1.0
  test: ^1.25.0
''';

  static String _main(String name) =>
      '''
import 'package:grund/grund.dart';
import 'package:$name/src/app_module.dart';

/// Serves the pages and the API until Ctrl+C. Run it from the package
/// root: the static files are read from `web/`.
Future<void> main(List<String> arguments) async {
  await App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
}
''';

  static const _appModule = '''
import 'package:grund/grund.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import 'account_api.dart';
import 'home_site_module.dart';

/// The root module: the HTTP server over dart:io, cookie sessions, the
/// sign-in API and the pages of [HomeSiteModule].
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  // A Secure cookie needs HTTPS; `dart run` serves plain http, a product
  // build (`dart compile exe`) is expected behind HTTPS. `dart run` (JIT)
  // in production is not a product build: the cookie is then sent without
  // Secure unless the app sets `secure: true`.
  static const _isProduct = bool.fromEnvironment('dart.vm.product');

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    SessionModule(config: SessionConfig(secure: _isProduct)),
    // Once, in the application: the sites of the modules below need it.
    JasprModule(),
    HomeSiteModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
''';

  static const _accountApi = '''
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs a visitor in and out; the forms of the pages post here.
final class AccountApi extends HttpApi {
  /// Starts and ends sessions through [_sessions].
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/logout', _logout),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1, maxLength: 40);
    // Check a password or another credential here before signing in.
    await _sessions.start(c, name);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }

  Future<HttpResponse> _logout(HttpCtx c) async {
    await _sessions.end(c);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }
}
''';

  static const _homeSiteModule = '''
import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/public_site.dart';

/// Declares [PublicSite] and its pages.
final class HomeSiteModule extends Module {
  /// Creates the module.
  const HomeSiteModule();

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<PublicSite>(PublicSite.new),
    Pages.under<PublicSite>(
      (_) => [
        Page(
          '/',
          build: (_) => const HomePage(),
          meta: const PageMeta(title: 'Home'),
        ),
        Page(
          '/login',
          build: (_) => const LoginPage(),
          meta: const PageMeta(title: 'Sign in'),
        ),
      ],
    ),
  ];
}
''';

  static const _publicSite = '''
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The pages of the application, served at the root of the site.
///
/// Its shell makes every page, and the not-found answer, a document with
/// the stylesheet and the page title. The files of `web/` are served under
/// `/static`.
final class PublicSite extends PageSite {
  /// Creates the site.
  PublicSite(super.injector);

  @override
  Component shell(Component content) => Builder(
    builder: (context) => Document(
      title: context.pageMatch?.meta.title ?? 'grund',
      head: [link(href: '/static/styles.css', rel: 'stylesheet')],
      body: main_([content]),
    ),
  );

  @override
  Component notFound() => const Component.text('No page here.');
}
''';

  static const _homePage = '''
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The content of the start page: who is signed in, and how to sign in or out.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) {
    final user = context.maybe<CurrentUser>();
    return Component.fragment([
      h1([Component.text('Hello from grund and Jaspr')]),
      if (user == null)
        a(href: '/login', [Component.text('Sign in')])
      else
        form(action: '/logout', method: FormMethod.post, [
          Component.text('Signed in as \${user.id}. '),
          button(type: ButtonType.submit, [Component.text('Sign out')]),
        ]),
    ]);
  }
}
''';

  static const _loginPage = '''
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The content of the sign-in page: the form that posts the name to
/// `AccountApi`.
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
''';

  static const _styles = '''
body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 40rem; }
''';

  // `TestApp` never makes the io adapter listen, so the test needs no socket.
  static String _appTest(String name) =>
      '''
import 'package:grund/testing.dart';
import 'package:grund_http/testing.dart';
import 'package:$name/src/app_module.dart';
import 'package:test/test.dart';

void main() {
  // Both are set in `setUp`, which runs before every test.
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: const AppModule());
    client = TestClient.of(app);
  });
  tearDown(() => app.close());

  test('a path without a page is a 404 HTML page', () async {
    final page = await client.get('/nowhere');

    expect(page.status, 404);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
  });

  test('the stylesheet is served under /static', () async {
    final css = await client.get('/static/styles.css');

    expect(css.status, 200);
  });

  test('GET / renders the start page', () async {
    final page = await client.get('/');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.text, contains('Sign in'));
  });

  test('signing in sets the session cookie; the page sees the user', () async {
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    final cookie = login.headers['set-cookie'] ?? '';
    final page = await client.get(
      '/',
      headers: {'cookie': cookie.split(';').first},
    );

    expect(login.status, 303);
    expect(cookie, contains('HttpOnly'));
    expect(page.text, contains('Signed in as ann.'));
  });
}
''';
}
