// A global configuration module: a token value, a bound interface and a
// service other modules use without importing it.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The greeting word.
const greetingWord = Token<String>('greeting.word');

/// User status.
enum Status { active, banned }

/// Tells the time.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// A clock stuck at the epoch, so responses are stable.
@Injectable()
final class EpochClock implements Clock {
  @override
  DateTime now() => DateTime.utc(1970);
}

/// Builds greetings.
@Injectable()
final class Greeter {
  /// Creates the greeter.
  Greeter(@Inject(greetingWord) this.word, this.clock);

  /// The greeting word.
  final String word;

  /// The clock.
  final Clock clock;

  /// A greeting for [name].
  Map<String, Object?> greet(String name) => {
    'greeting': '$word, $name!',
    'at': clock.now().toIso8601String(),
  };
}

/// Greets callers and echoes statuses.
@Controller()
final class GreetingController {
  /// Creates the controller.
  GreetingController(this.greeter);

  /// The greeter.
  final Greeter greeter;

  /// `GET /hello`, with an optional `x-name` header.
  @Get('/hello')
  Map<String, Object?> hello(@Header('x-name') String? name) =>
      greeter.greet(name ?? 'world');

  /// `GET /status/:status` echoes an enum path parameter.
  @Get('/status/:status')
  Map<String, String> status(@Param('status') Status status) => {
    'status': status.name,
  };

  /// `DELETE /hello` does nothing: 204.
  @Delete('/hello')
  void forget() {}
}
