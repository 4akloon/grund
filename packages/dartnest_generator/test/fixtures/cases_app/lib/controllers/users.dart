// A controller using every supported binding.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'components.dart';

/// Renames a JSON field, like `JsonKey` of json_serializable; the
/// generator matches it by name.
final class JsonKey {
  /// Creates the annotation.
  const JsonKey({this.name});

  /// The JSON name.
  final String? name;
}

/// User status.
enum Status { active, banned }

/// A user.
final class User {
  /// Creates a user.
  const User(this.id, this.name, {this.status = Status.active});

  /// The id.
  final int id;

  /// The display name.
  @JsonKey(name: 'display_name')
  final String name;

  /// The status.
  final Status status;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'display_name': name};
}

/// Body of `POST /users`.
final class CreateUser {
  /// Creates the body.
  const CreateUser(this.name);

  /// Reads the body.
  factory CreateUser.fromJson(Map<String, dynamic> json) =>
      CreateUser(json['name'] as String);

  /// The name.
  final String name;
}

/// Users.
@Controller('/users')
@UseGuards([OpenGuard])
@Roles(['admin'])
final class UsersController {
  /// Lists users.
  @Get()
  @UseInterceptors([PassInterceptor])
  Future<List<User>> list(
    @Query('limit') int? limit,
    @Query('status') Status? status,
  ) async => const [];

  /// Finds one user.
  @Get('/:id')
  User find(@Param('id') int id, @Header('x-trace') String? trace) =>
      User(id, 'ann');

  /// Creates a user.
  @Post()
  @UsePipes([TrimPipe])
  @UseFilters([StateFilter])
  @Roles(['owner'])
  User create(@Body() CreateUser body, ExecutionContext context) =>
      User(1, body.name);

  /// Stores a text body.
  @Put('/:id/note')
  void note(@Param('id') String id, @Body() String text, HttpRequest request) {}

  /// Stores a binary body.
  @Put('/:id/avatar')
  Future<void> avatar(@Param('id') String id, @Body() List<int> bytes) async {}

  /// Merges a JSON object.
  @Patch('/:id')
  Map<String, Object?> merge(@Body() Map<String, Object?> patch) => patch;

  /// Removes every user.
  @Delete()
  void clear() {}

  /// Not a route.
  void helper() {}
}
