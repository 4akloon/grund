import '../di/injector.dart';
import 'pipeline_component.dart';

/// A pipeline component taken from dependency injection.
///
/// `Use<AuthGuard>()` is replaced at startup by the `AuthGuard` provider
/// visible in the module that declares the controller (the root module for
/// application-level components), so a guard can inject services. A missing
/// provider fails `Application.create` with `MissingProviderError`.
final class Use<T extends PipelineComponent> implements PipelineComponent {
  /// Creates the reference.
  const Use();

  /// The referenced component type.
  Type get type => T;

  /// Resolves the component through [injector].
  T resolve(Injector injector) => injector.get<T>();

  @override
  String toString() => 'Use<$T>';
}
