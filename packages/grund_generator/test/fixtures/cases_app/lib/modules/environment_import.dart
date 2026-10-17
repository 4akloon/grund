// Two modules that read Environment, both importing the global
// EnvironmentModule themselves; the generator must accept the repeat import.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

/// A setting read from the environment.
final class Greeting {
  /// Creates it.
  const Greeting(this.text);

  /// The greeting.
  final String text;
}

/// Reads the environment.
@Module(imports: [grund.EnvironmentModule()], exports: [Greeting])
final class GreetingModule extends grund.Module {
  /// Creates the module.
  const GreetingModule();

  /// Reads `GREETING`.
  @Provides()
  static Greeting greeting(grund.Environment environment) =>
      Greeting(environment.string('GREETING', fallback: 'hello'));
}

/// Imports the same global module as [GreetingModule].
@Module(imports: [grund.EnvironmentModule(), GreetingModule()])
final class SecondModule extends grund.Module {
  /// Creates the module.
  const SecondModule();

  /// Reads `NAME`.
  @Provides()
  static String name(grund.Environment environment) =>
      environment.string('NAME', fallback: 'world');
}
