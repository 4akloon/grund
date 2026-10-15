import 'dart:async';

import 'binding.dart';
import 'injector.dart';

/// A unit of the application: it declares bindings, says which of them
/// other modules may use, and which modules it builds on.
///
/// Write one by hand (override the getters you need) or annotate it with
/// `@Module` and mix in the generated `$Name`, which overrides them for you.
///
/// Instances with one identity (class and [qualifier]) are one module: when
/// two of them reach the graph with different declarations, the first one
/// found wins.
abstract class Module {
  /// Creates the module.
  const Module();

  /// Modules whose exports this module sees.
  List<Module> get imports => const [];

  /// What this module provides.
  List<Binding<Object>> get bindings => const [];

  /// What other modules may use: keys of [bindings], and modules from
  /// [imports] whose exports are passed on.
  List<Object> get exports => const [];

  /// Tells apart several instances of one module class, e.g. two database
  /// connections; compared with `==`.
  Object? get qualifier => null;

  /// Whether the exports of this module are visible to every module without
  /// importing it.
  bool get global => false;

  /// Runs once the whole graph is created, modules in import order.
  FutureOr<void> onInit(Injector injector) {}

  /// Runs when the application closes, modules in reverse import order,
  /// before any value is disposed.
  FutureOr<void> onShutdown(Injector injector) {}
}
