import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import '../model/provides_model.dart';
import '../model/type_model.dart';

/// Checks that every provider class and `@Provides` method can be called by
/// generated code and that its names are usable.
abstract final class BindingCheck {
  /// The problems of the providers of [package].
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    final checked = <TypeModel>{};
    for (final module in package.modules) {
      yield* _providers(module, checked);
      for (final provides in module.provides) {
        yield* _provides(provides);
      }
    }
    for (final injectable in package.injectables) {
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
    for (final provides in package.strayProvides) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        '@Provides method ${provides.owner}.${provides.methodName} is in a '
        'class that is not annotated with @Module; it is never called.',
      );
    }
  }

  static Iterable<Diagnostic> _providers(
    ModuleModel module,
    Set<TypeModel> checked,
  ) sync* {
    for (final provider in module.providers) {
      final injectable = provider.injectable;
      if (!injectable.isAnnotated) {
        yield Diagnostic(
          DiagnosticCode.notInjectable,
          injectable.location,
          '${injectable.type} is a provider of module ${module.type} but is '
          'not annotated with @Injectable().',
        );
      }
      yield* _name(provider.key, injectable.location);
      yield* _objectKey(module, provider);
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
  }

  // `Bind<Object, C>()` would make C the answer to every `Object` lookup.
  static Iterable<Diagnostic> _objectKey(
    ModuleModel module,
    ProviderModel provider,
  ) sync* {
    final type = provider.key.type;
    if (!type.isDeclaredAs('Object', 'dart:core')) return;
    if (provider.injectable.type == type) return;
    yield Diagnostic(
      DiagnosticCode.invalidBind,
      provider.injectable.location,
      'Module ${module.type} binds ${provider.injectable.type} to Object, '
      'which every untyped lookup would resolve to; bind it to the interface '
      'it implements.',
    );
  }

  static Iterable<Diagnostic> _injectable(InjectableModel injectable) sync* {
    if (injectable.scopeProblem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidScope,
        injectable.location,
        '${injectable.type}: $problem Use Scope.singleton, Scope.call or '
        'Scope.transient.',
      );
    }
    if (injectable.constructor.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidConstructor,
        injectable.location,
        problem,
      );
    }
    yield* _dependencies(injectable.constructor.dependencies);
  }

  static Iterable<Diagnostic> _provides(ProvidesModel provides) sync* {
    if (provides.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        problem,
      );
    }
    if (provides.key case final key?) yield* _name(key, provides.location);
    yield* _dependencies(provides.dependencies);
  }

  static Iterable<Diagnostic> _dependencies(
    List<DependencyModel> dependencies,
  ) sync* {
    for (final dependency in dependencies) {
      if (dependency.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidDependency,
          dependency.location,
          problem,
        );
      }
      if (dependency.key case final key?) {
        yield* _name(key, dependency.location);
      }
    }
  }

  static Iterable<Diagnostic> _name(
    BindingKey key,
    SourceLocation location,
  ) sync* {
    if (key.name != '') return;
    yield Diagnostic(
      DiagnosticCode.invalidName,
      location,
      'The name of ${key.type} is empty; give @Named a non-empty name.',
    );
  }
}
