import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;

import 'pages_app.dart';

/// The public site: no prefix.
final class PublicSite extends PageSite {
  /// Creates the site.
  PublicSite(super.injector);

  @override
  Component notFound() => const Component.text('public not found');
}

/// The guarded site under `/admin`.
base class AdminSite extends PageSite {
  /// Creates the site.
  AdminSite(super.injector);

  @override
  String get path => '/admin';

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<AdminGuard>.type()];

  @override
  Component shell(Component content) =>
      Component.element(tag: 'main', classes: 'admin', children: [content]);

  @override
  Component notFound() => const Component.text('admin not found');
}

/// Rejects a request without the header `x-admin: 1`.
final class AdminGuard extends HttpHook {
  /// Creates the hook.
  const AdminGuard();

  @override
  void before(HttpCtx c) {
    if (c.headers.stringOrNull('x-admin') != '1') {
      throw const UnauthorizedException(message: 'Admin only.');
    }
  }
}

/// The headers of an admin request.
const adminHeaders = {'x-admin': '1'};

/// A service of the pages modules.
final class UsersService {
  /// The name shown for [id].
  String nameOf(String id) => 'user-$id';
}

/// A value a hook of the site sets.
final class CurrentUser {
  /// Creates the value.
  const CurrentUser(this.name);

  /// The user's name.
  final String name;
}

/// Sets a [CurrentUser] for every request of the site that uses it.
final class CurrentUserHook extends HttpHook {
  /// Creates the hook.
  const CurrentUserHook();

  @override
  void before(HttpCtx c) => c.set<CurrentUser>(const CurrentUser('ann'));
}

/// A site whose hook sets a [CurrentUser].
final class UserSite extends PageSite {
  /// Creates the site.
  UserSite(super.injector);

  @override
  String get path => '/me';

  @override
  List<HookRef<HttpHook>> get use => const [
    HookRef<CurrentUserHook>.instance(CurrentUserHook()),
  ];
}

/// Shows the [CurrentUser] from the render context.
final class WhoAmI extends StatelessComponent {
  /// Creates the component.
  const WhoAmI({super.key});

  @override
  Component build(BuildContext context) =>
      Component.text('who ${context.maybe<CurrentUser>()?.name}');
}

/// Declares [PublicSite].
final class PublicSiteModule extends Module {
  /// Creates the module.
  const PublicSiteModule();

  @override
  List<Binding<Object>> get bindings => Pages.site<PublicSite>(PublicSite.new);

  @override
  List<Object> get exports => const [Key<PublicSite>()];
}

/// Declares [AdminSite] and its guard.
final class AdminSiteModule extends Module {
  /// Creates the module.
  const AdminSiteModule();

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<AdminSite>(AdminSite.new),
    Singleton<AdminGuard>((_) => const AdminGuard(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<AdminSite>(), Key<AdminGuard>()];
}

/// Public pages: `/` and `/about`.
final class HomePagesModule extends Module {
  /// Creates the module.
  const HomePagesModule();

  @override
  List<Module> get imports => const [PublicSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Pages.under<PublicSite>(
      (_) => [
        Page(
          '/',
          build: (_) =>
              const Component.fragment([Component.text('Home'), ShowMatch()]),
        ),
        Page('/about', build: (_) => const Component.text('About')),
      ],
    ),
  ];
}

/// Admin pages: `/`, `/users`, `/users/:id`.
final class UsersPagesModule extends Module {
  /// Creates the module.
  const UsersPagesModule();

  @override
  List<Module> get imports => const [AdminSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>((_) => UsersService(), dependsOn: const []),
    Pages.under<AdminSite>(
      (_) => [
        Page(
          '/',
          build: (_) => const Component.fragment([
            Component.text('Dashboard'),
            ShowMatch(),
          ]),
        ),
        Page('/users', build: (_) => const Component.text('Users')),
        Page(
          '/users/:id',
          build: (c) => Component.text('User ${c.path.string('id')}'),
        ),
      ],
    ),
  ];
}

/// A public page `/users` that must not reach the admin site.
final class PublicUsersModule extends Module {
  /// Creates the module.
  const PublicUsersModule();

  @override
  List<Module> get imports => const [PublicSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Pages.under<PublicSite>(
      (_) => [
        Page('/users', build: (_) => const Component.text('Public users')),
      ],
    ),
  ];
}

/// Public pages given by the test, plus the [extraImports] they need.
final class PublicPagesModule extends Module {
  /// Creates the module.
  const PublicPagesModule(this.pages, {this.extraImports = const []});

  /// The pages; include a `/` page.
  final List<Page> pages;

  /// Modules the pages read services from.
  final List<Module> extraImports;

  @override
  List<Module> get imports => [const PublicSiteModule(), ...extraImports];

  @override
  List<Binding<Object>> get bindings => [Pages.under<PublicSite>((_) => pages)];
}

/// A `/` page that renders [component].
Page homePage(Component component) => Page('/', build: (_) => component);

/// Starts the public site with [pages] (include `/`), serving with [config].
Future<TestClient> startPublic(
  List<Page> pages, {
  JasprConfig config = const JasprConfig(),
  List<Module> modules = const [],
  List<HookRef<HttpHook>> use = const [],
  List<Module> extraImports = const [],
}) => PagesApp.start([
  JasprModule(config: config),
  PublicPagesModule(pages, extraImports: extraImports),
  ...modules,
], use: use);

/// Shows the path of the page match.
final class ShowMatch extends StatelessComponent {
  /// Creates the component.
  const ShowMatch({super.key});

  @override
  Component build(BuildContext context) =>
      Component.text('path ${context.pageMatch?.page.path}');
}

/// Admin pages that count builder calls, behind the guard.
final class GuardedProbeModule extends Module {
  /// Creates the module; [onBuild] runs when the page is built.
  const GuardedProbeModule(this.onBuild);

  /// Called by the builder.
  final void Function() onBuild;

  @override
  List<Module> get imports => const [AdminSiteModule()];

  @override
  List<Binding<Object>> get bindings => [
    Pages.under<AdminSite>(
      (_) => [
        Page(
          '/guarded',
          build: (_) {
            onBuild();
            return const Component.text('guarded');
          },
        ),
      ],
    ),
  ];
}
