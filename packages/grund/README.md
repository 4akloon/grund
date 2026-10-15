# grund

Modular backend framework core for Dart, without `dart:mirrors`: modules,
typed dependency injection, call scopes and runners. It has no code
generation, no server and no HTTP; those are separate packages.

```dart
// Excerpt: Clock and Greeter are your classes.
import 'package:grund/grund.dart';

final class AppModule extends Module {
  const AppModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Clock>((i) => Clock(), dependsOn: const []),
    Singleton<Greeter>(
      (i) => Greeter(i<Clock>()),
      dependsOn: const [Key<Clock>()],
    ),
  ];
}

Future<void> main(List<String> args) =>
    App(root: const AppModule()).run(only: Runners.fromArgs(args));
```

A complete runnable version is `example/grund_example.dart`; tests use
`TestApp` from `package:grund/testing.dart`. The dependency-injection
annotations (`@Module`, `@Injectable`, `@Provides`, `Bind`, `@Named`) are in
`package:grund/annotations.dart`, a library of its own because `Module`
shares its name with the base class; `grund_generator` turns them into the
classes above. Logging goes through `package:logging` on `grund.<area>`
loggers; `App.run` attaches `LogOutput.console()` by default (`log:` changes it),
`App.start` and `TestApp` attach nothing. HTTP is the separate package `grund_http`; the
repository's `docs/` directory has the guides.
