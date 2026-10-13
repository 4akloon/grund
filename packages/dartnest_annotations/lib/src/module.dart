/// Declares a module; the generator writes a function that returns the
/// explicit `Module` (`UsersModule` → `Module usersModule()`).
///
/// ```dart
/// @Module(
///   imports: [DatabaseModule],
///   providers: [UsersService, Bind<Clock, SystemClock>(), Value(appConfig)],
///   controllers: [UsersController],
///   exports: [UsersService],
/// )
/// class UsersModule {}
/// ```
///
/// [imports] takes classes annotated with [Module] and tear-offs of
/// functions that return an explicit `Module` and need no arguments
/// (`imports: [metricsModule]`); the generator calls them. [providers]
/// takes classes annotated with `Injectable`, [Bind] and [Value].
/// [exports] takes provider classes, `Token` constants, and imported
/// modules (re-export).
final class Module {
  /// Creates the annotation. [id] defaults to the class name.
  const Module({
    this.id,
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.global = false,
  });

  /// Module id; `null` means the class name.
  final String? id;

  /// Imported modules.
  final List<Object> imports;

  /// Providers declared by the module.
  final List<Object> providers;

  /// Classes annotated with `Controller`.
  final List<Type> controllers;

  /// What importers of the module can see.
  final List<Object> exports;

  /// Whether the exports are visible to every module.
  final bool global;
}
