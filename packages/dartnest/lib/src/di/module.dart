import '../controller/controller.dart';
import 'provider.dart';
import 'token.dart';

/// Declarative description of a module: what it provides, what it imports,
/// and what it exposes to importers.
///
/// A module is a value, not a class. Dynamic modules are therefore plain
/// functions that return a [Module]. Two modules with the same [id] are
/// treated as one: their shape (imports, provider keys, controller types,
/// exports, [global]) must match or `ModuleGraph.build` throws
/// `DuplicateModuleIdError`.
/// Configuration captured inside factories is not compared and the first-seen
/// instance wins, so a dynamic module that can be configured differently in
/// one application must encode it in its [id] (for example `'database:$name'`).
///
/// ```dart
/// final usersModule = Module(
///   id: 'users',
///   imports: [databaseModule(url: env('DB_URL'))],
///   providers: [
///     Provider((i) => UsersRepo(i.get())),
///     Provider((i) => UsersService(i.get())),
///   ],
///   exports: [UsersService],
/// );
/// ```
final class Module {
  /// Creates a module. [id] must be unique per configuration.
  ///
  /// Has six named parameters, one over the usual limit of five, by spec: a
  /// module is a declarative value, so there is no parameter object.
  Module({
    required this.id,
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.global = false,
  });

  /// Identity used for deduplication and diagnostics.
  final String id;

  /// Modules whose exports become visible to this module's providers.
  final List<Module> imports;

  /// Providers declared by this module. Within one module, declaration order
  /// matters only for async providers: a provider may only use an async
  /// provider that is declared before it (or in an imported module).
  final List<ProviderSpec> providers;

  /// Controllers whose instances are created with this module's injector
  /// after its providers, and whose routes the application serves.
  final List<ControllerSpec> controllers;

  /// What importers of this module can see: a [Type] or [Token] of one of
  /// [providers], or a [Module] from [imports] (re-export).
  final List<Object> exports;

  /// When true, this module's exports are visible to every module without
  /// an explicit import.
  final bool global;

  /// Whether [key] (a [Type] or [Token]) is declared by this module.
  bool declares(Object key) => providers.any((p) => p.key == key);

  /// Whether [key] is exported directly (not via a re-exported module).
  bool exportsKey(Object key) => exports.any((e) => e is! Module && e == key);

  /// Ids of modules re-exported by this module.
  Iterable<String> get reexportedModuleIds =>
      exports.whereType<Module>().map((m) => m.id);

  @override
  String toString() => 'Module($id)';
}

/// Formats a provider key ([Type] or [Token]) for diagnostics.
String describeKey(Object key) => key is Token ? key.toString() : '$key';
