import 'package:code_builder/code_builder.dart';

import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/injection_emitter.dart';
import '../emit/type_emitter.dart';
import '../model/generated_names.dart';
import '../model/injectable_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import '../model/type_model.dart';
import 'constructor_check.dart';

/// Checks the constructors of injectable classes and generates one private
/// factory per class a module provides:
/// `Repo _createRepo(Injector i) => Repo(i.get<Clock>())`.
final class ProviderConstruct implements Construct {
  /// Creates the construct.
  const ProviderConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) sync* {
    final checked = <TypeModel>{};
    for (final (injectable, moduleId) in _provided(package)) {
      if (!checked.add(injectable.type)) continue;
      if (!injectable.isAnnotated) {
        yield Diagnostic(
          DiagnosticCode.notInjectable,
          injectable.location,
          '${injectable.type} is a provider of module "$moduleId" but is not '
          'annotated with @Injectable().',
        );
      }
      yield* _constructor(injectable);
    }
    for (final injectable in package.injectables) {
      if (checked.add(injectable.type)) yield* _constructor(injectable);
    }
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) sync* {
    final generated = <TypeModel>{};
    for (final (injectable, _) in _provided(package)) {
      if (generated.add(injectable.type)) yield _factory(injectable);
    }
  }

  static Iterable<Diagnostic> _constructor(InjectableModel injectable) =>
      ConstructorCheck.check(
        injectable.type,
        injectable.constructor,
        injectable.location,
      );

  /// Each class provider of every module with the id of its module, in
  /// module order.
  static List<(InjectableModel, String)> _provided(PackageModel package) => [
    for (final module in package.modules)
      for (final provider in module.providers)
        if (provider case ClassProvider(:final injectable))
          (injectable, module.id),
  ];

  static DartUnit _factory(InjectableModel injectable) {
    final name = GeneratedNames.factory(injectable.type.name);
    return DartUnit(
      name: name,
      spec: Method(
        (b) => b
          ..name = name
          ..returns = TypeEmitter.reference(injectable.type)
          ..requiredParameters.add(InjectionEmitter.injector)
          ..lambda = true
          ..body = InjectionEmitter.create(
            injectable.type,
            injectable.constructor,
          ).code,
      ),
      origin: injectable.location,
    );
  }
}
