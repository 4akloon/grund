import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/provider_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(providers: [...])`: a class or `Bind<I, C>()`.
final class ProviderEntryReader {
  /// Creates the reader.
  ProviderEntryReader(this.injectables);

  /// Reads provider classes.
  final InjectableReader injectables;

  /// The provider [entry] declares.
  EntryRead<ProviderModel> read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType provided) {
      final injectable = injectables.read(provided.element);
      return ReadEntry(ProviderModel(injectable.key, injectable));
    }
    final type = entry.type;
    if (type is InterfaceType &&
        Annotations.core.isAnnotation(type, const {'Bind'})) {
      return _bind(type);
    }
    return InvalidEntry(
      'providers: ${Annotations.describe(entry)} is not a class or '
      'Bind<I, C>().',
    );
  }

  EntryRead<ProviderModel> _bind(InterfaceType bind) {
    final [interface, implementation] = bind.typeArguments;
    if (interface is! InterfaceType || implementation is! InterfaceType) {
      return InvalidEntry(
        'providers: ${bind.getDisplayString()} must bind a class to a class.',
      );
    }
    final injectable = injectables.read(implementation.element);
    return ReadEntry(
      ProviderModel(
        BindingKey(TypeReader.read(interface), injectable.name),
        injectable,
      ),
    );
  }
}
