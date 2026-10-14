# dartnest_annotations example

A complete application in two files. The annotations describe it;
`dartnest_cli gen` (or `dartnest_build`) writes `lib/my_app.dartnest.dart`
with the explicit `package:dartnest` code.

```yaml
# pubspec.yaml
name: my_app
environment:
  sdk: ^3.8.0
dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0
  dartnest_io: ^0.1.0
dev_dependencies:
  dartnest_cli: ^0.1.0
```

```dart
// lib/src/hello.dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

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
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:my_app/my_app.dartnest.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:${adapter.port}/hello');
}
```

```sh
dart pub get
dart run dartnest_cli gen     # writes lib/my_app.dartnest.dart
dart run bin/main.dart
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
```

`dart run dartnest_cli init my_app` creates exactly this package. The
repository's `example/` directory has a larger application (guards, pipes,
filters, interceptors, middleware, tokens, `Bind`) written in both styles.
