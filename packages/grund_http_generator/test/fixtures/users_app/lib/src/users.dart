import 'package:grund/grund.dart' as grund;
import 'package:grund_http/annotations.dart';
import 'package:grund/annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'auth.dart';
import 'users_module.g.dart';

part 'users_api.g.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  /// Creates the error.
  UserMissing(this.id);

  /// The id that has no user.
  final int id;
}

/// A user.
final class User {
  /// Creates the user.
  User(this.id, this.name);

  /// The identifier.
  final int id;

  /// The name.
  final String name;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// The body of `POST /users`.
final class CreateUser {
  /// Creates the body.
  CreateUser(this.name);

  /// Reads the body, or throws a [FormatException] for a bad one.
  factory CreateUser.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUser(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  /// The name of the new user.
  final String name;
}

/// Where users live.
abstract interface class UserStore {
  /// Every user, in id order.
  List<User> all();

  /// The user [id], or `null`.
  User? find(int id);

  /// Adds a user named [name].
  User add(String name);

  /// Removes the user [id]; whether there was one.
  bool remove(int id);
}

/// Keeps users in memory, seeded with two.
@Injectable()
final class InMemoryUserStore implements UserStore {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  @override
  List<User> all() => _users.values.toList();

  @override
  User? find(int id) => _users[id];

  @override
  User add(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }

  @override
  bool remove(int id) => _users.remove(id) != null;
}

/// Settings of the users module.
final class UsersConfig {
  /// Creates the settings.
  const UsersConfig({required this.greeting});

  /// What the users service says.
  final String greeting;
}

/// Identifies one request; one is created per call.
final class RequestInfo {
  /// Creates the value.
  RequestInfo(this.number);

  /// The running number of the request.
  final int number;
}

/// The users use cases.
@Injectable()
final class UsersService {
  /// Creates the service.
  UsersService(this.store, this.config, {@Named('audit') required this.audit});

  /// Where users live.
  final UserStore store;

  /// The settings.
  final UsersConfig config;

  /// Receives the name of every change.
  final StringBuffer audit;

  /// The first [limit] users whose name contains [query].
  List<User> list({required int limit, String? query}) => [
    for (final user in store.all())
      if (query == null || user.name.contains(query)) user,
  ].take(limit).toList();

  /// The user [id], or throws [UserMissing].
  User find(int id) => store.find(id) ?? (throw UserMissing(id));

  /// Adds a user.
  User create(String name) {
    audit.writeln('create $name');
    return store.add(name);
  }

  /// Removes the user [id], or throws [UserMissing].
  void remove(int id) {
    if (!store.remove(id)) throw UserMissing(id);
    audit.writeln('remove $id');
  }
}

/// Users: bindings, settings and the API.
@Module(
  imports: [AuthModule()],
  providers: [UsersService, UsersApi, Bind<UserStore, InMemoryUserStore>()],
  exports: [UsersService, grund.Key<StringBuffer>('audit')],
)
final class UsersModule extends grund.Module with $UsersModule {
  /// Creates the module.
  const UsersModule();

  static int _requests = 0;

  /// The settings.
  @Provides()
  static UsersConfig config() => const UsersConfig(greeting: 'hello');

  /// Where changes are written; a singleton may be created asynchronously.
  @Provides()
  @Named('audit')
  static Future<StringBuffer> audit() async => StringBuffer();

  /// One value per call.
  @Provides(scope: Scope.call)
  static RequestInfo requestInfo() => RequestInfo(++_requests);
}

/// The users API.
@Api('/users', use: [HookRef<UserMissingHook>.type()])
final class UsersApi {
  /// Creates the API.
  UsersApi(this.users);

  /// The use cases.
  final UsersService users;

  /// Lists users.
  @Get('/')
  List<User> list({
    @Query() @Range(min: 1, max: 100) int limit = 10,
    @Query(name: 'q') @Length(min: 1, max: 20) String? query,
  }) => users.list(limit: limit, query: query);

  /// Describes the current request.
  @Get('/me')
  Map<String, Object?> me(RequestInfo info, @Header() String? accept) => {
    'request': info.number,
    'greeting': users.config.greeting,
    'accept': accept,
  };

  /// Streams the names of all users.
  @Get('/export')
  Stream<List<int>> export() => Stream.value(
    users.list(limit: 100).map((u) => u.name).join('\n').codeUnits,
  );

  /// Returns one user.
  @Get('/:id')
  User find(@Path() int id) => users.find(id);

  /// Creates a user.
  @Post(
    '/',
    status: 201,
    use: [
      HookRef<AuthHook>.type(),
      HookRef<RolesHook>.instance(RolesHook(['admin'])),
    ],
  )
  Future<User> create(@Body() CreateUser body) async => users.create(body.name);

  /// Removes a user.
  @Delete(
    '/:id',
    use: [
      HookRef<AuthHook>.type(),
      HookRef<RolesHook>.instance(RolesHook(['admin'])),
    ],
  )
  void remove(@Path() int id) => users.remove(id);
}
