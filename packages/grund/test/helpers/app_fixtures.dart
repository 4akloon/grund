// A small users application shared by dispatcher, application and e2e
// tests.
import 'package:grund/grund.dart';

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

/// Route metadata: roles allowed to call a handler.
final class Roles {
  const Roles(this.names);
  final List<String> names;
}

/// Accepts `authorization: Bearer <role>`; stores the role in `items`.
final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final header = context.header('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    context.items[#role] = header.substring('Bearer '.length);
    return true;
  }
}

/// Allows a handler only for the roles in its [Roles] metadata.
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null || roles.names.contains(context.items[#role]);
  }
}

/// Maps [UserMissing] to 404.
final class UserMissingFilter extends ExceptionFilter<UserMissing> {
  const UserMissingFilter();

  @override
  Object? handle(UserMissing error, ExecutionContext context) =>
      throw NotFoundException(message: 'No user ${error.id}');
}

/// Handlers of `/users`.
final class UsersController {
  UsersController(this.service);
  final UsersService service;

  List<User> list(int limit) => service.list(limit: limit);
  User findOne(int id) => service.find(id);
  User create(CreateUserDto dto) => service.create(dto.name);
}

/// The users controller: reads are public, writes need an admin.
final usersController = Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  enhancers: const Enhancers(filters: [UserMissingFilter()]),
  routes: [
    Route.get(
      '/',
      (c, ctx) async => c.list(await ctx.query<int?>('limit') ?? 10),
      name: 'list',
    ),
    Route.get(
      '/:id',
      (c, ctx) async => c.findOne(await ctx.param<int>('id')),
      name: 'findOne',
    ),
    Route.post(
      '/',
      (c, ctx) async {
        final user = c.create(await ctx.bodyAs(CreateUserDto.fromJson));
        ctx.switchToHttp().response
          ..status = StatusCode.created
          ..headers.set('location', '/users/${user.id}');
        return user;
      },
      name: 'create',
      enhancers: const Enhancers(guards: [Use<AuthGuard>(), Use<RolesGuard>()]),
      metadata: const [
        Roles(['admin']),
      ],
    ),
  ],
);

/// Module with [usersController] and its providers.
Module usersModule() => Module(
  id: 'users',
  providers: [
    Provider((i) => UsersService()),
    Provider((i) => AuthGuard()),
    Provider((i) => RolesGuard()),
  ],
  controllers: [usersController],
);

/// The application root.
Module appModule() => Module(id: 'app', imports: [usersModule()]);
