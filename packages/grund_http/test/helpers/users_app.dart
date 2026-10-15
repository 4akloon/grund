// A small users application written in the explicit form, shared by the
// server and end-to-end tests.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_module.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  UserMissing(this.id);

  final int id;
}

/// A user.
final class User {
  User(this.id, this.name);

  final int id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// Body of `POST /users`.
final class CreateUserDto {
  CreateUserDto(this.name);

  factory CreateUserDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUserDto(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  final String name;
}

/// In-memory users.
final class UsersService {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  List<User> list({required int limit}) => _users.values.take(limit).toList();

  User find(int id) => _users[id] ?? (throw UserMissing(id));

  User create(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }
}

/// The role of the caller, set by [AuthHook].
final class CurrentRole {
  CurrentRole(this.name);

  final String name;
}

/// Accepts `authorization: Bearer <role>` and sets [CurrentRole].
final class AuthHook extends HttpHook {
  const AuthHook();

  @override
  void before(HttpCtx c) {
    final header = c.headers.stringOrNull('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    c.set<CurrentRole>(CurrentRole(header.substring('Bearer '.length)));
  }
}

/// Allows a route only for the given roles; the roles are the hook's
/// parameters, so it is used as a constant instance.
final class RolesHook extends HttpHook {
  const RolesHook(this.names);

  final List<String> names;

  @override
  void before(HttpCtx c) {
    if (!names.contains(c<CurrentRole>().name)) {
      throw const ForbiddenException(code: 'role_not_allowed');
    }
  }
}

/// Translates [UserMissing] into a 404.
final class UserMissingHook extends HttpHook {
  const UserMissingHook();

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is UserMissing) {
      throw NotFoundException(
        message: 'No user ${error.id}',
        code: 'user_not_found',
      );
    }
    return null;
  }
}

/// `/users`: reads are public, writes need an admin.
final class UsersApi extends HttpApi {
  UsersApi(super.injector, this._users);

  final UsersService _users;

  @override
  String get path => '/users';

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<UserMissingHook>.type()];

  @override
  List<Route> get routes => [
    Route.get(
      '/',
      (c) => _users.list(limit: c.query.integerOrNull('limit') ?? 10),
    ),
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async {
        final user = _users.create((await c.body(CreateUserDto.fromJson)).name);
        c.response.headers.set('location', '/users/${user.id}');
        return user;
      },
      status: 201,
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
  ];
}

/// Everything above as a module.
final class UsersModule extends Module {
  const UsersModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>((i) => UsersService(), dependsOn: const []),
    Singleton<AuthHook>((i) => const AuthHook(), dependsOn: const []),
    Singleton<UserMissingHook>(
      (i) => const UserMissingHook(),
      dependsOn: const [],
    ),
    Singleton<UsersApi>(
      (i) => UsersApi(i, i<UsersService>()),
      dependsOn: const [Key<UsersService>()],
    ),
  ];
}

/// The application root: the users module served through [adapter].
final class UsersAppModule extends Module {
  UsersAppModule(this.adapter, {this.http = const HttpModule()});

  /// The adapter the server uses.
  final HttpAdapter adapter;

  /// The HTTP module, to vary its settings.
  final HttpModule http;

  @override
  List<Module> get imports => [
    http,
    AdapterModule(adapter),
    const UsersModule(),
  ];
}
