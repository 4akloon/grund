/// The files of a new grund application, as `init` writes them.
///
/// A flat catalog of file contents without logic.
abstract final class ProjectTemplate {
  /// The version constraint of the grund packages in a new pubspec: the
  /// first published release.
  static const grundVersion = '^0.1.0';

  /// The files of application [name] (relative path to content), sorted by
  /// path.
  ///
  /// [name] is interpolated into the files as is: it must be a valid Dart
  /// package name (`[a-z_][a-z0-9_]*`), which `ProjectScaffold` checks.
  static Map<String, String> files(String name) => {
    '.gitignore': '.dart_tool/\n',
    'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
    'bin/main.dart': _main(name),
    'lib/src/app_module.dart': _appModule,
    'lib/src/hello.dart': _hello,
    'pubspec.yaml': _pubspec(name),
  };

  static String _pubspec(String name) =>
      '''
name: $name
description: A grund application.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  grund: $grundVersion
  grund_http: $grundVersion
  grund_io: $grundVersion

dev_dependencies:
  grund_cli: $grundVersion
  lints: ^5.1.0
''';

  // The `part` and the prefixed import are what a host of `@Api` needs; the
  // routes are generated into `hello_api.g.dart`.
  static const _hello = '''
import 'package:grund/annotations.dart';
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'hello_api.g.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, \$name!'};
}

/// `GET /hello?name=...`.
@Api('/hello')
final class HelloApi {
  /// Creates the API.
  HelloApi(this.service);

  /// The service.
  final HelloService service;

  /// Greets [name], or the world.
  @Get('/')
  Map<String, String> hello(@Query() String? name) =>
      service.greet(name ?? 'world');
}
''';

  static const _appModule = '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

import 'app_module_module.g.dart';
import 'hello.dart';

/// The root module: the HTTP server over dart:io and the hello API.
@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [HelloService, HelloApi],
)
final class AppModule extends grund.Module with \$AppModule {
  /// Creates the module.
  const AppModule();
}
''';

  static String _main(String name) =>
      '''
import 'package:grund/grund.dart';
import 'package:$name/src/app_module.dart';

/// Serves the application until Ctrl+C; `--only=http` selects runners.
///
/// `run` prints the log to the console; see grund's `docs/logging.md` to
/// send it elsewhere (`run(log: ...)`).
Future<void> main(List<String> arguments) async {
  await App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
}
''';
}
