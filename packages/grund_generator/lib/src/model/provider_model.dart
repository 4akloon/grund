import 'binding_key.dart';
import 'injectable_model.dart';

/// One entry of `@Module(providers: ...)`: a class bound as itself, or
/// `Bind<I, C>()` (the interface `I` bound to the class `C`).
final class ProviderModel {
  /// Creates the provider; [key] is the interface for a `Bind`.
  const ProviderModel(this.key, this.injectable);

  /// What the provider is looked up by.
  final BindingKey key;

  /// The class that is created.
  final InjectableModel injectable;
}
