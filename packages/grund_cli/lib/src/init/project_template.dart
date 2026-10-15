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
  grund_annotations: $grundVersion
  grund_io: $grundVersion

dev_dependencies:
  grund_cli: $grundVersion
  lints: ^5.1.0
''';

  static const _hello = '''
import 'package:grund_annotations/grund_annotations.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, \$name!'};
}

/// `GET /hello?name=...`.
@Controller('/hello')
final class HelloController {
  /// Creates the controller.
  HelloController(this.service);

  /// The service.
  final HelloService service;

  /// Greets [name], or the world.
  @Get()
  Map<String, String> hello(@Query('name') String? name) =>
      service.greet(name ?? 'world');
}

/// The root module.
@Module(id: 'app', providers: [HelloService], controllers: [HelloController])
final class AppModule {}
''';

  static String _main(String name) =>
      '''
import 'package:grund/grund.dart';
import 'package:grund_io/grund_io.dart';
import 'package:$name/$name.grund.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:\${adapter.port}/hello');
}
''';
}
