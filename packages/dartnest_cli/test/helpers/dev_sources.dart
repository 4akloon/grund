/// Sources of a small annotated application `hello` with a `bin/main.dart`
/// that serves it on a loopback port (its first argument, an ephemeral
/// port without one) and prints
/// `listening on <port>`; `GET /hello` answers the greeting and the pid.
abstract final class DevSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:hello/hello.dartnest.dart';

Future<void> main(List<String> arguments) async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  final port = arguments.isEmpty ? 0 : int.parse(arguments.first);
  await app.listen(port: port, address: InternetAddress.loopbackIPv4);
  print('listening on \${adapter.port}');
}
''';

  /// `lib/src/greeter.dart`.
  static const greeter = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Greeter {
  String greet() => 'hello v1';
}
''';

  /// `lib/src/hello_controller.dart`.
  static const controller = '''
import 'dart:io';

import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'greeter.dart';

@Controller('/hello')
final class HelloController {
  HelloController(this.greeter);

  final Greeter greeter;

  @Get()
  Map<String, Object> hello() => {'text': greeter.greet(), 'pid': pid};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'greeter.dart';
import 'hello_controller.dart';

@Module(id: 'app', providers: [Greeter], controllers: [HelloController])
final class AppModule {}
''';

  /// The files of the application.
  static const files = {
    'bin/main.dart': main,
    'lib/src/greeter.dart': greeter,
    'lib/src/hello_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };
}
