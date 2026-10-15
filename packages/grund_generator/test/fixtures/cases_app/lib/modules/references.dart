// Function tear-offs in `imports`: which ones are modules.
import 'package:grund/grund.dart' as core;
import 'package:grund_annotations/grund_annotations.dart';

/// Static module factories.
abstract final class ModuleFactories {
  /// A usable static factory.
  static core.Module create() => core.Module(id: 'static');

  /// Needs an argument, so it cannot be called without one.
  static core.Module withArgument(int count) => core.Module(id: 'count');
}

/// A private holder: its factories are not reachable from generated code.
abstract final class _PrivateFactories {
  /// A static factory of a private class.
  static core.Module create() => core.Module(id: 'private');
}

/// Extension members are not reachable as `Holder.name` either.
extension ModuleExtension on int {
  /// A static factory of an extension.
  static core.Module create() => core.Module(id: 'extension');
}

core.Module _hidden() => core.Module(id: 'hidden');

/// Takes a required argument.
core.Module needsArgument(String name) => core.Module(id: name);

/// Has only an optional argument.
core.Module optionalArgument([int count = 0]) => core.Module(id: '$count');

/// Does not return a module.
String notAModule() => '';

/// Imports one usable and several unusable tear-offs.
@Module(
  imports: [
    ModuleFactories.create,
    ModuleFactories.withArgument,
    _hidden,
    needsArgument,
    optionalArgument,
    notAModule,
    _PrivateFactories.create,
    ModuleExtension.create,
  ],
)
class ReferencesModule {}
