# grund_annotations example

A complete application in two files. The annotations describe it;
`grund_cli gen` (or `grund_build`) writes `lib/my_app.grund.dart`
with the explicit `package:grund` code.

```yaml
# pubspec.yaml
name: my_app
environment:
  sdk: ^3.8.0
dependencies:
  grund: ^0.1.0
  grund_annotations: ^0.1.0
  grund_io: ^0.1.0
dev_dependencies:
  grund_cli: ^0.1.0
```

```dart
// lib/src/hello.dart
import 'package:grund_annotations/grund_annotations.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
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
```

```dart
// bin/main.dart
import 'package:grund/grund.dart';
import 'package:grund_io/grund_io.dart';
import 'package:my_app/my_app.grund.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:${adapter.port}/hello');
}
```

```sh
dart pub get
dart run grund_cli gen     # writes lib/my_app.grund.dart
dart run bin/main.dart
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
```

`dart run grund_cli init my_app` creates exactly this package. The
repository's `example/` directory has a larger application (guards, pipes,
filters, interceptors, middleware, tokens, `Bind`) written in both styles.
