import 'package:grund/grund.dart';

/// A service the example module provides.
final class Greeter {
  /// Creates a greeter that opens with [salutation].
  Greeter(this.salutation);

  /// How every greeting starts.
  final String salutation;

  /// The greeting for [name].
  String greet(String name) => '$salutation, $name!';
}

/// Greets when the application starts: a stand-in for an HTTP server or a
/// job worker, which are runners too.
final class GreetingRunner extends Runner {
  /// Creates a runner that writes to [lines].
  GreetingRunner(this._greeter, this._lines);

  final Greeter _greeter;
  final List<String> _lines;

  @override
  String get name => 'greeting';

  @override
  Future<void> start(Injector injector) async {
    _lines.add(_greeter.greet('grund'));
  }

  @override
  Future<void> stop() async {
    _lines.add('Goodbye.');
  }
}

/// The root module: a [Greeter] and the [GreetingRunner] that uses it.
///
/// `dependsOn` lists the keys a factory resolves; the application checks
/// them before any factory runs.
final class GreetingModule extends Module {
  /// Creates the module; the runner writes to [lines].
  GreetingModule(this.lines);

  /// Where the runner writes.
  final List<String> lines;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeter>((i) => Greeter('Hello'), dependsOn: const []),
    Singleton<GreetingRunner>(
      (i) => GreetingRunner(i<Greeter>(), lines),
      dependsOn: const [Key<Greeter>()],
    ),
  ];
}

/// Starts the application, lets the runner greet, and closes it again.
///
/// A real program calls `App.run`, which serves until `SIGINT` or `SIGTERM`.
Future<List<String>> greetOnce() async {
  final lines = <String>[];
  final app = App(root: GreetingModule(lines));
  await app.start();
  await app.close();
  return lines;
}

Future<void> main() async {
  (await greetOnce()).forEach(print);
}
