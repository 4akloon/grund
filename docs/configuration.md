# Configuration and the environment

Configuration that differs between machines (the port, a database URL, a
secret) comes from environment variables. `Environment` reads them with
checks, `EnvironmentModule` makes it available to the whole application, and
`HttpModule.fromEnvironment()` uses it for the address and the port.

Nothing reads the environment on its own: an application opts in by
importing `EnvironmentModule` and asking for what it needs.

## Environment

`Environment` wraps a map of variables. In production it is
`Environment(Platform.environment)`; a test passes any map, so tests never
depend on the machine they run on.

```dart
import 'package:grund/grund.dart';

final environment = Environment({'PORT': '9090', 'GREETING': ''});

environment.has('GREETING');                       // true: empty is set
environment.string('NAME', fallback: 'world');     // 'world': unset
environment.integer('PORT', min: 1, max: 65535);   // 9090
environment.integer('WORKERS', fallback: 4);       // 4: unset
```

The rules are the same for every reader:

- A variable that is **set must be valid**. Only an **unset** variable falls
  back, so `PORT=abc` is an error, never a silent default. An empty value is
  set (`has` is true, `string` returns `''`); for `integer` it is invalid.
- `string(name, {fallback})` returns the value. Unset and no `fallback`
  throws `MissingVariableError`.
- `integer(name, {fallback, min, max})` accepts only decimal digits with an
  optional leading `-` (`007` is 7). `' 80'`, `'+80'`, `'0x50'`, `'1e3'` and
  numbers that overflow `int` are invalid. The `fallback` is written by the
  programmer and is not checked against `min` and `max`.
  A value outside the range or in the wrong format throws
  `InvalidVariableError`.
- Both errors are an `EnvironmentError` (a `GrundError`). Their message names
  the variable and what was expected, and never shows its value, because it
  may be a secret.

## EnvironmentModule

`EnvironmentModule` is a global module that binds the `Environment` of the
process and exports it:

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    EnvironmentModule(),
    HttpModule.fromEnvironment(),
    IoAdapterModule(),
  ];
}
```

Because it is global, any module in the graph can depend on `Environment`
once the module is imported anywhere.

## HTTP address and port

`HttpModule.fromEnvironment()` takes the address from `HOST` and the port
from `PORT` (0 to 65535) when they are set, and everything else from its
`defaults` (`HttpConfig`: `localhost` and 8080 unless you say otherwise):

```sh
dart run bin/main.dart                          # localhost:8080
PORT=9090 dart run bin/main.dart                # localhost:9090
HOST=0.0.0.0 PORT=9090 dart run bin/main.dart   # reachable from outside
```

- Inside a container, hosting platforms and CI set `PORT`; set
  `HOST=0.0.0.0` to listen on every interface so the container is reachable.
- An empty `HOST`, one with white space, or a bad `PORT` is an
  `InvalidVariableError`. It is thrown while the application starts, before
  the adapter binds a socket, and reaches the caller of `App.start` /
  `App.run` as it is (the container passes a `GrundError` through).
  `example/` catches `EnvironmentError` in `main`, prints one line and
  exits with code 64.
- Check that your shell does not export `HOST` for another purpose (some
  shells keep the machine name in a variable of that name); an exported
  `HOST=<machine>` would bind the server to that address.
- Only `HttpModule.fromEnvironment()` reads the environment. `HttpModule()`
  ignores `HOST` and `PORT`, so existing applications behave as before.
  `HttpModule.fromEnvironment()` without `EnvironmentModule` is a
  `MissingProviderError` for `Environment`.
- Outside a module, `HttpConfig.fromEnvironment(environment, defaults: ...)`
  returns the same configuration as a value.

## Your own settings

A provider that takes `Environment` as a parameter reads its own variables.
With annotations:

```dart
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

final class Greeting {
  const Greeting(this.text);
  final String text;
}

@Module(imports: [grund.EnvironmentModule()], exports: [Greeting])
final class GreetingModule extends grund.Module {
  const GreetingModule();

  @Provides()
  static Greeting greeting(grund.Environment environment) =>
      Greeting(environment.string('GREETING', fallback: 'hello'));
}
```

The same with the explicit API, where the dependency is declared with
`dependsOn`:

```dart
final class GreetingModule extends Module {
  const GreetingModule();

  @override
  List<Module> get imports => const [EnvironmentModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeting>(
      (i) => Greeting(i<Environment>().string('GREETING', fallback: 'hello')),
      dependsOn: const [Key<Environment>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<Greeting>()];
}
```

A module whose `@Provides` takes `Environment` imports `EnvironmentModule()`
itself, as above. The generator's dependency check reports `missing_provider`
for a dependency that no module of the package declares, unless the package
imports a module from another package, which it cannot look into. `Environment`
comes from `EnvironmentModule` of the `grund` package, so without the import
in that module the generator names `Environment` as missing; with it, the
check is partial for the package (it only reports keys that a module of the
package binds). Importing the global module again from several modules is
safe: it is built once.

## Tests

Do not touch the process environment in tests. Override the binding with a
map:

```dart
test('greets with the configured text', () async {
  final app = await TestApp.start(
    root: const GreetingModule(),
    overrides: [
      Singleton<Environment>(
        (_) => Environment({'GREETING': 'hi'}),
        dependsOn: const [],
      ),
    ],
  );
  addTearDown(app.close);

  expect(app<Greeting>().text, 'hi');
});
```

An override replaces the bindings with the same key wherever they are
declared (see [testing.md](testing.md)).

## Startup data

Data that the application loads and checks once (content files, a price
list, a migration plan) belongs in a `Singleton` or `@Provides` with the
check in the factory, not in a static field. A factory may be asynchronous;
a failure stops the start with a typed error before the server listens, a
test replaces the value with an override, and a page reads it from the
injector.

```dart
final class SiteContent {
  const SiteContent(this.title);
  final String title;
}

final class ContentModule extends Module {
  const ContentModule();

  @override
  List<Module> get imports => const [EnvironmentModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<SiteContent>(
      (i) async {
        final path = i<Environment>().string('CONTENT', fallback: 'site.txt');
        final title = (await File(path).readAsString()).trim();
        if (title.isEmpty) {
          throw FormatException('$path has no title');
        }
        return SiteContent(title);
      },
      dependsOn: const [Key<Environment>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<SiteContent>()];
}
```

In a Jaspr component (see [jaspr.md](jaspr.md)):

```dart
final class HeaderBar extends StatelessComponent {
  const HeaderBar();

  @override
  Component build(BuildContext context) =>
      h1([Component.text(context.call<SiteContent>().title)]);
}
```

If the file is missing or empty the factory throws. A `GrundError` reaches
the caller of `App.start` unchanged; any other exception, such as the
`FormatException` above, is wrapped in a `ProviderCreationError` that names
the binding and keeps the cause. In a test, override `SiteContent` with
`Singleton<SiteContent>((_) => const SiteContent('Test'), dependsOn:
const [])`.
