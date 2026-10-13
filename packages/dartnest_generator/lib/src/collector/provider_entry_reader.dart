import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../model/provider_key.dart';
import '../model/provider_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(providers: [...])`: a class, `Bind<K, I>()`
/// or `Value(v, token: t)`.
final class ProviderEntryReader {
  /// Creates the reader; [typeSystem] checks `Value` against its token.
  ProviderEntryReader(this.injectables, this.typeSystem);

  /// Reads provider classes.
  final InjectableReader injectables;

  /// The type system of the library being read.
  final TypeSystem typeSystem;

  /// The provider [entry] declares.
  EntryRead<ProviderModel> read(DartObject entry) {
    final type = entry.type;
    if (entry.toTypeValue() case final InterfaceType provided) {
      final key = TypeKey(TypeReader.read(provided));
      return ReadEntry(ClassProvider(key, injectables.read(provided.element)));
    }
    if (type is InterfaceType &&
        Annotations.isAnnotation(type, const {'Bind'})) {
      return _bind(type);
    }
    if (type is InterfaceType &&
        Annotations.isAnnotation(type, const {'Value'})) {
      return _value(entry);
    }
    return InvalidEntry(
      'providers: ${Annotations.describe(entry)} is not a class, Bind<K, I>() or '
      'Value(v).',
    );
  }

  EntryRead<ProviderModel> _bind(InterfaceType bind) {
    final [key, implementation] = bind.typeArguments;
    if (key is! InterfaceType || implementation is! InterfaceType) {
      return InvalidEntry(
        'providers: ${bind.getDisplayString()} must bind a class to a class.',
      );
    }
    return ReadEntry(
      ClassProvider(
        TypeKey(TypeReader.read(key)),
        injectables.read(implementation.element),
      ),
    );
  }

  EntryRead<ProviderModel> _value(DartObject entry) {
    final value = Annotations.field(entry, 'value');
    final valueType = value?.type;
    final tokenObject = Annotations.field(entry, 'token');
    if (value == null || valueType is! InterfaceType) {
      return const InvalidEntry(
        'providers: the value of Value(...) is not an object.',
      );
    }
    final expression = ConstantReader.read(value);
    if (tokenObject == null || tokenObject.isNull) {
      return ReadEntry(
        ValueProvider(TypeKey(TypeReader.read(valueType)), expression),
      );
    }
    final token = TokenReader.read(tokenObject);
    if (token == null) {
      return const InvalidEntry(
        'providers: the token of Value(...) is not a Token.',
      );
    }
    final (key, tokenType) = token;
    if (!typeSystem.isAssignableTo(valueType, tokenType)) {
      return InvalidEntry(
        'providers: Value(...) of type ${valueType.getDisplayString()} '
        'cannot be provided as ${key.display}.',
      );
    }
    return ReadEntry(ValueProvider(key, expression));
  }
}
