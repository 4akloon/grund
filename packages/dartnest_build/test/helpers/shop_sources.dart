/// Sources of a small annotated package `shop`: a clock service, a
/// controller that uses it, the root module, and the variants the builder
/// tests need.
abstract final class ShopSources {
  /// The package name.
  static const package = 'shop';

  /// `lib/src/clock.dart`.
  static const clock = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Clock {
  DateTime now() => DateTime.utc(2026);
}
''';

  /// `lib/src/time_controller.dart`.
  static const controller = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'clock.dart';

@Controller('/time')
final class TimeController {
  TimeController(this.clock);

  final Clock clock;

  @Get()
  Map<String, String> now() => {'now': clock.now().toIso8601String()};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'clock.dart';
import 'time_controller.dart';

@Module(id: 'app', providers: [Clock], controllers: [TimeController])
final class AppModule {}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };

  /// `lib/src/broken.dart`: two syntax errors on one line.
  static const broken = 'final class Broken { void f( }\n';

  /// `lib/src/user.dart`: a request body whose `fromJson` lives in a part
  /// that another builder (json_serializable) generates.
  static const user = '''
part 'user.g.dart';

final class User {
  const User(this.name);

  factory User.fromJson(Map<String, Object?> json) => _\$UserFromJson(json);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}
''';

  /// `lib/src/user.g.dart`, the generated part of [user].
  static const userPart = '''
part of 'user.dart';

User _\$UserFromJson(Map<String, Object?> json) => User(json['name'] as String);
''';

  /// `lib/src/users.dart`: a controller and module that take a [user].
  static const users = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'user.dart';

@Controller('/users')
final class UsersController {
  @Post()
  User create(@Body() User user) => user;
}

@Module(id: 'users', controllers: [UsersController])
final class UsersModule {}
''';
}
