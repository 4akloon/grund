import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'auth.dart';
import 'users.dart';

part 'users_api.g.dart';

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
