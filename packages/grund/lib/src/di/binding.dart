import 'dart:async';

import 'injector.dart';
import 'key.dart';

/// Creates the value of a [Binding]; [injector] sees what the owning module
/// sees.
typedef BindingFactory<T extends Object> =
    FutureOr<T> Function(Injector injector);

/// How long the instances of a binding live.
enum BindingScope {
  /// One instance per application.
  singleton,

  /// One instance per call.
  scoped,

  /// A new instance on every resolution.
  transient,
}

/// How one value of type [T] is created and shared.
///
/// Always write the type argument (`Singleton<Clock>(...)`): where only a
/// `List<Binding<Object>>` is expected Dart infers `Object`, which is
/// rejected.
sealed class Binding<T extends Object> {
  Binding._(this.create, {String? name, required this.dependsOn})
    : key = Key<T>(name) {
    if (T == Object) {
      throw ArgumentError(
        'A binding needs an explicit type argument, e.g. '
        'Singleton<Clock>(...); got Object.',
      );
    }
  }

  /// The key under which the value is visible.
  final Key<T> key;

  /// Creates the value.
  final BindingFactory<T> create;

  /// Keys the factory resolves; `null` means "not declared" and is checked
  /// when the factory runs.
  final List<Key<Object>>? dependsOn;

  /// How long the instances live.
  BindingScope get scope;
}

/// One instance per application, created eagerly at startup in dependency
/// order.
final class Singleton<T extends Object> extends Binding<T> {
  /// Creates a singleton whose dependencies are declared in [dependsOn].
  Singleton(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  /// Creates a singleton without declared dependencies: the escape hatch for
  /// third-party types.
  Singleton.factory(super.create, {super.name}) : super._(dependsOn: null);

  @override
  BindingScope get scope => BindingScope.singleton;
}

/// One instance per call (an HTTP request, a job run), created on first use.
final class Scoped<T extends Object> extends Binding<T> {
  /// Creates a call-scoped binding whose dependencies are declared in
  /// [dependsOn].
  Scoped(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  @override
  BindingScope get scope => BindingScope.scoped;
}

/// A new instance on every resolution.
final class Transient<T extends Object> extends Binding<T> {
  /// Creates a transient binding whose dependencies are declared in
  /// [dependsOn].
  Transient(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  @override
  BindingScope get scope => BindingScope.transient;
}
