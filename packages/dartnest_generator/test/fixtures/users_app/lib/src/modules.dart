// The module graph, in annotations.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'auth.dart';
import 'greeting.dart';
import 'users.dart';

/// Configuration every module sees.
@Module(
  id: 'config',
  providers: [
    Value('Hello', token: greetingWord),
    Bind<Clock, EpochClock>(),
    Greeter,
  ],
  exports: [Greeter],
  global: true,
)
class ConfigModule {}

/// Users and their guards.
@Module(
  id: 'users',
  providers: [UsersService, AuthGuard, RolesGuard, UserMissingFilter],
  controllers: [UsersController],
)
class UsersModule {}

/// Greetings; [Greeter] comes from the global [ConfigModule].
@Module(id: 'greeting', controllers: [GreetingController])
class GreetingModule {}

/// The application root.
@Module(id: 'app', imports: [ConfigModule, UsersModule, GreetingModule])
class AppModule {}
