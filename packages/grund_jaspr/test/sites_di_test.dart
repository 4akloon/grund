import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';

/// Declares an admin page without importing the admin site module.
final class StrayAdminPagesModule extends Module {
  const StrayAdminPagesModule();

  @override
  List<Binding<Object>> get bindings => [
    Pages.under<AdminSite>(
      (_) => [Page('/', build: (_) => const Component.text('x'))],
    ),
  ];
}

/// Declares the same site pages twice.
final class TwiceModule extends Module {
  const TwiceModule();

  @override
  List<Module> get imports => const [AdminSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Pages.under<AdminSite>(
      (_) => [Page('/', build: (_) => const Component.text('a'))],
    ),
    Pages.under<AdminSite>(
      (_) => [Page('/b', build: (_) => const Component.text('b'))],
    ),
  ];
}

/// A page that reads a service of its own module from the context.
final class ServicePagesModule extends Module {
  const ServicePagesModule();

  @override
  List<Module> get imports => const [PublicSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>((_) => UsersService(), dependsOn: const []),
    Pages.under<PublicSite>(
      (_) => [
        Page('/', build: (_) => const Component.text('Home')),
        Page(
          '/svc',
          build: (c) => Component.text(c<UsersService>().nameOf('9')),
        ),
      ],
    ),
  ];
}

/// Pages of [UserSite], whose hook sets a [CurrentUser].
final class MePagesModule extends Module {
  const MePagesModule();

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<UserSite>(UserSite.new),
    Pages.under<UserSite>((_) => [Page('/', build: (_) => const WhoAmI())]),
  ];
}

void main() {
  test('a builder sees a service of its pages module', () async {
    final client = await PagesApp.start([
      const JasprModule(),
      const ServicePagesModule(),
    ]);

    final response = await client.get('/svc');

    expect(response.text, contains('user-9'));
  });

  test('a value a site hook set is read in the component', () async {
    final client = await PagesApp.start([
      const JasprModule(),
      const MePagesModule(),
    ]);

    final response = await client.get('/me');

    expect(response.text, contains('who ann'));
  });

  test('Pages.under for a site the module cannot see fails the graph', () {
    final started = PagesApp.start([
      const JasprModule(),
      const AdminSiteModule(),
      const StrayAdminPagesModule(),
    ]);

    expect(started, throwsA(isA<GraphError>()));
  });

  test('Pages.under without JasprModule is a MissingProviderError', () {
    final started = PagesApp.start([
      const PublicSiteModule(),
      const HomePagesModule(),
    ]);

    expect(started, throwsA(isA<MissingProviderError>()));
  });

  test('two Pages.under for one site in a module is a duplicate', () {
    final started = PagesApp.start([const JasprModule(), const TwiceModule()]);

    expect(started, throwsA(isA<DuplicateBindingError>()));
  });
}
