/// Declares a module; the generator writes the mixin `$X` that implements
/// `imports`, `bindings` and `exports` of the class `X`.
///
/// The class extends the core `Module` (imported with a prefix, because the
/// names are the same) and mixes in the generated half. It declares a
/// `const` constructor itself.
///
/// ```dart
/// import 'package:grund/grund.dart' as grund;
///
/// @Module(
///   imports: [AuthModule()],
///   providers: [TasksService, TasksApi, Bind<TaskStore, InMemoryTaskStore>()],
///   exports: [TasksService],
/// )
/// final class TasksModule extends grund.Module with $TasksModule {
///   const TasksModule();
/// }
/// ```
///
/// [imports] takes `const` module instances. [providers] takes classes
/// annotated with `Injectable` or `Api`, and `Bind<I, C>()`. [exports] takes
/// types (the binding of that type), `Key<T>('name')` constants (a named
/// binding) and the types of imported modules (re-export).
final class Module {
  /// Creates the annotation.
  const Module({
    this.imports = const [],
    this.providers = const [],
    this.exports = const [],
    this.global = false,
  });

  /// Imported modules, as `const` instances.
  final List<Object> imports;

  /// Classes and `Bind`s the module owns.
  final List<Object> providers;

  /// What importers of the module can see.
  final List<Object> exports;

  /// Whether the exports are visible to every module; the generated mixin
  /// overrides `Module.global`.
  final bool global;
}
