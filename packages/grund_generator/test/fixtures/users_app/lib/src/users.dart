// Users: the service, the DTOs and the controller.
import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

import 'auth.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  /// Creates the error.
  UserMissing(this.id);

  /// The unknown id.
  final int id;
}

/// A user.
final class User {
  /// Creates a user.
  User(this.id, this.name);

  /// The id.
  final int id;

  /// The name.
  final String name;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// Body of `POST /users`.
final class CreateUserDto {
  /// Creates the body.
  CreateUserDto(this.name);

  /// Reads the body; an empty name is a 400.
  factory CreateUserDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUserDto(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  /// The name.
  final String name;
}

/// In-memory users.
@Injectable()
final class UsersService {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  /// The first [limit] users.
  List<User> list({required int limit}) => _users.values.take(limit).toList();

  /// The user [id].
  User find(int id) => _users[id] ?? (throw UserMissing(id));

  /// Adds a user.
  User create(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }
}

/// Maps [UserMissing] to 404.
@Injectable()
final class UserMissingFilter extends ExceptionFilter<UserMissing> {
  @override
  Object? handle(UserMissing error, ExecutionContext context) =>
      throw NotFoundException(message: 'No user ${error.id}');
}

/// Reads are public, writes need an admin.
@Controller('/users')
@UseFilters([UserMissingFilter])
final class UsersController {
  /// Creates the controller.
  UsersController(this.service);

  /// The users.
  final UsersService service;

  /// Lists users, 10 unless `?limit=` says otherwise.
  @Get()
  List<User> list(@Query('limit') int? limit) =>
      service.list(limit: limit ?? 10);

  /// Finds one user.
  @Get('/:id')
  User findOne(@Param('id') int id) => service.find(id);

  /// Creates a user: 201 with its location.
  @Post()
  @UseGuards([AuthGuard, RolesGuard])
  @Roles(['admin'])
  User create(@Body() CreateUserDto dto, ExecutionContext context) {
    final user = service.create(dto.name);
    context.switchToHttp().response
      ..status = StatusCode.created
      ..headers.set('location', '/users/${user.id}');
    return user;
  }
}
