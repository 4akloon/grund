/// Sources of a small annotated application `hello` with a `bin/main.dart`
/// that serves it on a loopback port (its first argument, an ephemeral
/// port without one) and prints
/// `listening on <port>`; `GET /hello` answers the greeting and the pid.
abstract final class DevSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:hello/src/app_module.dart';

Future<void> main(List<String> arguments) async {
  final port = arguments.isEmpty ? 0 : int.parse(arguments.first);
  final app = App(
    root: const AppModule(),
    overrides: [
      Singleton<HttpConfig>(
        (_) => HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
        dependsOn: const [],
      ),
    ],
  );
  await app.start();
  final adapter = app.container.all<HttpAdapter>().first;
  print('listening on \${adapter is IoAdapter ? adapter.port : port}');
}
''';

  /// `lib/src/greeter.dart`.
  static const greeter = '''
import 'package:grund/annotations.dart';

@Injectable()
final class Greeter {
  String greet() => 'hello v1';
}
''';

  /// `lib/src/hello_api.dart`.
  static const api = '''
import 'dart:io';

import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'greeter.dart';

part 'hello_api.g.dart';

@Api('/hello')
final class HelloApi {
  HelloApi(this.greeter);

  final Greeter greeter;

  @Get('/')
  Map<String, Object> hello() => {'text': greeter.greet(), 'pid': pid};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

import 'app_module.g.dart';
import 'greeter.dart';
import 'hello_api.dart';

@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [Greeter, HelloApi],
)
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// The files of the application.
  static const files = {
    'bin/main.dart': main,
    'lib/src/greeter.dart': greeter,
    'lib/src/hello_api.dart': api,
    'lib/src/app_module.dart': module,
  };
}
