/// Sources of a small annotated package `shop`: a clock service, a
/// controller that uses it and the root module.
abstract final class ShopSources {
  /// The generated library of `shop`.
  static const output = 'lib/shop.dartnest.dart';

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

  /// `lib/src/app_module.dart` without the clock: a `missing_provider`.
  static const moduleWithoutClock = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'time_controller.dart';

@Module(id: 'app', controllers: [TimeController])
final class AppModule {}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };
}
