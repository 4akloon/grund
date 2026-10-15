/// Sources of a small annotated package `shop`: a clock service, an API
/// that uses it, the root module, and the variants the builder tests need.
abstract final class ShopSources {
  /// The package name.
  static const package = 'shop';

  /// The generated module library of `lib/src/app_module.dart`.
  static const moduleOutput = 'lib/src/app_module_module.g.dart';

  /// The generated part of `lib/src/time_api.dart`.
  static const apiOutput = 'lib/src/time_api_api.g.dart';

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

part 'time_api_api.g.dart';

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

import 'app_module_module.g.dart';
import 'clock.dart';
import 'time_api.dart';

@Module(providers: [Clock, TimeApi])
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

  /// `lib/src/only_module.dart`: a module and no API.
  static const onlyModule = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'clock.dart';
import 'only_module_module.g.dart';

@Module(providers: [Clock])
final class OnlyModule extends grund.Module with \$OnlyModule {
  const OnlyModule();
}
''';

  /// `lib/src/both.dart`: a module and an API in one library.
  static const both = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'both_module.g.dart';

part 'both_api.g.dart';

@Api('/both')
final class BothApi {
  @Get('/')
  String hello() => 'hello';
}

@Module(providers: [BothApi])
final class BothModule extends grund.Module with \$BothModule {
  const BothModule();
}
''';

  /// `lib/src/broken.dart`: two syntax errors on one line.
  static const broken = 'final class Broken { void f( }\n';

  /// `lib/src/inner.dart`: a module whose provider needs a `Clock` nobody
  /// provides, a `missing_provider`.
  static const inner = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'clock.dart';
import 'inner_module.g.dart';

@Injectable()
final class NeedsClock {
  NeedsClock(this.clock);

  final Clock clock;
}

@Module(providers: [NeedsClock])
final class InnerModule extends grund.Module with \$InnerModule {
  const InnerModule();
}
''';

  /// `lib/src/outer.dart`: a valid module that imports [inner].
  static const outer = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'inner.dart';
import 'outer_module.g.dart';

@Module(imports: [InnerModule()])
final class OuterModule extends grund.Module with \$OuterModule {
  const OuterModule();
}
''';

  /// `lib/src/second.dart`: a second module with nothing in it.
  static const second = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'second_module.g.dart';

@Module()
final class SecondModule extends grund.Module with \$SecondModule {
  const SecondModule();
}
''';

  /// `lib/src/both_modules.dart`: a module importing [onlyModule] and
  /// [second], so it reaches two modules.
  static const bothModules = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'both_modules_module.g.dart';
import 'only_module.dart';
import 'second.dart';

@Module(imports: [OnlyModule(), SecondModule()])
final class BothModules extends grund.Module with \$BothModules {
  const BothModules();
}
''';
}
