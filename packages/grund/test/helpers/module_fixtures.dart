import 'dart:async';

import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/injector.dart';
import 'package:grund/src/di/module.dart';

/// A module whose declarations are constructor arguments.
///
/// Subclasses give it a class, hence an identity.
base class StubModule extends Module {
  const StubModule({
    this.imports = const [],
    this.bindings = const [],
    this.exports = const [],
    this.global = false,
    this.qualifier,
    this.log,
  });

  @override
  final List<Module> imports;

  @override
  final List<Binding<Object>> bindings;

  @override
  final List<Object> exports;

  @override
  final bool global;

  @override
  final Object? qualifier;

  /// Receives `init <module>` and `shutdown <module>` entries.
  final List<String>? log;

  @override
  FutureOr<void> onInit(Injector injector) {
    log?.add('init $runtimeType');
  }

  @override
  FutureOr<void> onShutdown(Injector injector) {
    log?.add('shutdown $runtimeType');
  }
}

final class AppModule extends StubModule {
  const AppModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class DbModule extends StubModule {
  const DbModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class AuthModule extends StubModule {
  const AuthModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class ConfigModule extends StubModule {
  const ConfigModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}
