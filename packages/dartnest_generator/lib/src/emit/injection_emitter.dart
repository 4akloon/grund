import 'package:code_builder/code_builder.dart';

import '../model/constructor_model.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';
import 'constant_emitter.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes how dependency injection creates a class: its constructor call
/// with one `injector.get` per parameter.
abstract final class InjectionEmitter {
  /// The `Injector` parameter of a factory: `dartnest.Injector i`.
  static final injector = Parameter(
    (b) => b
      ..name = 'i'
      ..type = refer('Injector', ImportAllocator.dartnest),
  );

  /// `Type(i.get<A>(), i.get(token), name: i.get<B>())` for [type] created
  /// through [constructor].
  static Expression create(TypeModel type, ConstructorModel constructor) {
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final dependency in constructor.dependencies) {
      final key = dependency.key;
      if (key == null) {
        throw StateError('An invalid dependency reached generation.');
      }
      if (dependency.isNamed) {
        named[dependency.name] = get(key);
      } else {
        positional.add(get(key));
      }
    }
    return TypeEmitter.reference(type).newInstance(positional, named);
  }

  /// `i.get<T>()` for a type key, `i.get(token)` for a token key.
  static Expression get(ProviderKey key) => switch (key) {
    TypeKey(:final type) => refer(
      'i',
    ).property('get').call(const [], const {}, [TypeEmitter.reference(type)]),
    TokenKey(:final expression) => refer(
      'i',
    ).property('get').call([ConstantEmitter.expression(expression)]),
  };
}
