import 'package:code_builder/code_builder.dart';

import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import '../model/lifetime.dart';
import '../model/provider_model.dart';
import '../model/provides_model.dart';
import 'core_references.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes the `Singleton`, `Scoped` or `Transient` expression of one binding
/// the module construct writes itself.
///
/// The factory is a lambda over the module's `Injector` (`i`) that calls the
/// constructor or the `@Provides` method; `dependsOn` lists the keys it
/// resolves, sorted, so the container validates them before any factory
/// runs.
abstract final class BindingEmitter {
  /// The binding of the injectable class behind [provider], keyed by the
  /// provider's key (the interface of a `Bind<I, C>`).
  static Expression provider(ProviderModel provider) {
    final injectable = provider.injectable;
    final dependencies = injectable.constructor.dependencies;
    return binding(
      key: provider.key,
      lifetime: injectable.lifetime,
      dependencies: dependencies,
      create: TypeEmitter.reference(
        injectable.type,
      ).newInstance(_positional(dependencies), _named(dependencies)),
    );
  }

  /// The binding of a `@Provides` method; [provided] must have a key.
  static Expression provides(ProvidesModel provided, BindingKey key) => binding(
    key: key,
    lifetime: provided.lifetime,
    dependencies: provided.dependencies,
    create: TypeEmitter.reference(provided.owner)
        .property(provided.methodName)
        .call(
          _positional(provided.dependencies),
          _named(provided.dependencies),
        ),
  );

  /// The binding of [key] with [lifetime] whose factory is [create], a
  /// lambda body over the module's `Injector` (see [inject]), and
  /// [dependencies] are what it resolves.
  static Expression binding({
    required BindingKey key,
    required Lifetime lifetime,
    required List<DependencyModel> dependencies,
    required Expression create,
  }) {
    final name = key.name;
    return CoreReferences.grund(switch (lifetime) {
      Lifetime.singleton => 'Singleton',
      Lifetime.scoped => 'Scoped',
      Lifetime.transient => 'Transient',
    }).newInstance(
      [_lambda(create)],
      {
        if (name != null) 'name': DartString.expression(name),
        'dependsOn': _dependsOn([
          for (final dependency in dependencies)
            if (dependency.key case final key?) key,
        ]),
      },
      [TypeEmitter.reference(key.type)],
    );
  }

  static Expression _lambda(Expression body) => Method(
    (b) => b
      ..requiredParameters.add(Parameter((p) => p..name = 'i'))
      ..lambda = true
      ..body = body.code,
  ).closure;

  static Expression _dependsOn(List<BindingKey> keys) {
    final sorted = {...keys}.toList()..sort();
    return literalConstList([
      for (final key in sorted)
        CoreReferences.key(TypeEmitter.reference(key.type), key.name),
    ]);
  }

  /// The expression that resolves [key] from the injector `i`.
  static Expression inject(BindingKey key) => refer('i').call(
    [if (key.name case final name?) DartString.expression(name)],
    const {},
    [TypeEmitter.reference(key.type)],
  );

  static List<Expression> _positional(List<DependencyModel> dependencies) => [
    for (final dependency in dependencies)
      if (!dependency.isNamed)
        if (dependency.key case final key?) inject(key),
  ];

  static Map<String, Expression> _named(List<DependencyModel> dependencies) => {
    for (final dependency in dependencies)
      if (dependency.isNamed)
        if (dependency.key case final key?) dependency.name: inject(key),
  };
}
