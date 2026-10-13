import 'constant_value.dart';
import 'injectable_model.dart';
import 'provider_key.dart';

/// One entry of `@Module(providers: ...)`.
sealed class ProviderModel {
  /// Creates the provider.
  const ProviderModel(this.key);

  /// What the provider is looked up by.
  final ProviderKey key;
}

/// A class created through its constructor: `UsersService` or
/// `Bind<Clock, SystemClock>()`.
final class ClassProvider extends ProviderModel {
  /// Creates the provider.
  const ClassProvider(super.key, this.injectable);

  /// The class that is created.
  final InjectableModel injectable;
}

/// An already built constant: `Value(appConfig)`.
final class ValueProvider extends ProviderModel {
  /// Creates the provider.
  const ValueProvider(super.key, this.value);

  /// The provided constant.
  final ConstantValue value;
}
