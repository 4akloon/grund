/// Sources of a small annotated package `shop`: a clock service, an API
/// that uses it and the root module.
abstract final class ShopSources {
  /// The generated module library of `lib/src/app_module.dart`.
  static const moduleOutput = 'lib/src/app_module.g.dart';

  /// The generated part of `lib/src/time_api.dart`.
  static const apiOutput = 'lib/src/time_api.g.dart';

  /// Every file the valid package generates.
  static const outputs = [moduleOutput, apiOutput];

  /// `lib/src/clock.dart`.
  static const clock = '''
import 'package:grund/annotations.dart';

@Injectable()
final class Clock {
  DateTime now() => DateTime.utc(2026);
}
''';

  /// `lib/src/time_api.dart`.
  static const api = '''
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'clock.dart';

part 'time_api.g.dart';

@Api('/time')
final class TimeApi {
  TimeApi(this.clock);

  final Clock clock;

  @Get('/')
  Map<String, String> now() => {'now': clock.now().toIso8601String()};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'app_module.g.dart';
import 'clock.dart';
import 'time_api.dart';

@Module(providers: [Clock, TimeApi])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// `lib/src/app_module.dart` without the clock: a `missing_provider`.
  static const moduleWithoutClock = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'app_module.g.dart';
import 'time_api.dart';

@Module(providers: [TimeApi])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_api.dart': api,
    'lib/src/app_module.dart': module,
  };
}
