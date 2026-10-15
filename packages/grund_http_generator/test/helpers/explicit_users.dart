// The users application written with the explicit API: what the generator is
// expected to write for lib/src/*.dart, by hand. It reuses the classes of
// users_app, so only the wiring differs.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:users_app/users_app.dart';

/// `AuthModule` without annotations.
final class ExplicitAuthModule extends Module {
  /// Creates the module.
  const ExplicitAuthModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AuthHook>((i) => const AuthHook(), dependsOn: const []),
    Singleton<UserMissingHook>(
      (i) => const UserMissingHook(),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<AuthHook>(), Key<UserMissingHook>()];
}

/// `UsersModule` without annotations.
final class ExplicitUsersModule extends Module {
  /// Creates the module.
  const ExplicitUsersModule();

  @override
  List<Module> get imports => const [ExplicitAuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>(
      (i) => UsersService(
        i<UserStore>(),
        i<UsersConfig>(),
        audit: i<StringBuffer>('audit'),
      ),
      dependsOn: const [
        Key<UserStore>(),
        Key<UsersConfig>(),
        Key<StringBuffer>('audit'),
      ],
    ),
    Singleton<UsersApi>(
      (i) => UsersApi(i<UsersService>()),
      dependsOn: const [Key<UsersService>()],
    ),
    Singleton<UserStore>((i) => InMemoryUserStore(), dependsOn: const []),
    Singleton<UsersConfig>(
      (i) => const UsersConfig(greeting: 'hello'),
      dependsOn: const [],
    ),
    Singleton<StringBuffer>(
      (i) async => StringBuffer(),
      name: 'audit',
      dependsOn: const [],
    ),
    Scoped<RequestInfo>((i) => RequestInfo(++_requests), dependsOn: const []),
    Singleton<ExplicitUsersApi>(
      (i) => ExplicitUsersApi(i, i<UsersApi>()),
      dependsOn: const [Key<UsersApi>()],
    ),
  ];

  @override
  List<Object> get exports => const [
    Key<UsersService>(),
    Key<StringBuffer>('audit'),
  ];

  static int _requests = 0;
}

/// The routes of `UsersApi`, written by hand.
final class ExplicitUsersApi extends HttpApi {
  /// Creates the routes.
  ExplicitUsersApi(super.injector, this._api);

  final UsersApi _api;

  @override
  String get path => '/users';

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<UserMissingHook>.type()];

  @override
  List<Route> get routes => [
    Route.get(
      '/',
      (c) => _api.list(
        limit: c.query.integerOrNull('limit', min: 1, max: 100) ?? 10,
        query: c.query.stringOrNull('q', minLength: 1, maxLength: 20),
      ),
    ),
    Route.get(
      '/me',
      (c) => _api.me(c<RequestInfo>(), c.headers.stringOrNull('accept')),
    ),
    Route.get('/export', (c) => _api.export()),
    Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _api.create(await c.body(CreateUser.fromJson)),
      status: 201,
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
    Route.delete(
      '/:id',
      (c) {
        _api.remove(c.path.integer('id'));
        return null;
      },
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
  ];
}

/// `AppModule` without annotations.
final class ExplicitAppModule extends Module {
  /// Creates the module.
  const ExplicitAppModule();

  @override
  List<Module> get imports => const [
    ExplicitAuthModule(),
    ExplicitUsersModule(),
  ];
}
