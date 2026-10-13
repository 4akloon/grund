# dartnest Core DI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `dartnest` core DI: modules as values, providers with inferred types, typed tokens, Nest-style scoping (imports/exports/global), module deduplication, eager async-aware instantiation, and typed fail-fast errors with resolution chains.

**Architecture:** `Module` and `Provider` are plain immutable descriptions. `ModuleGraph` validates structure (ids, cycles, exports, duplicate keys) and orders modules imports-first. `Container.create` builds one `ModuleInjector` per module and instantiates every provider in module order, awaiting async factories; `Injector.get<T>()` is synchronous and creates sync dependencies on demand, so declaration order inside a module matters only for async providers.

**Tech Stack:** Dart SDK ^3.8.0, pub workspace, `package:test`, `package:lints`, `package:meta`. No `dart:mirrors`, no `dart:io` server code in this package.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (sections 2 "Структура пакетів", 3 "DI та модулі", 7 "Помилки", 8 "Тестування").

## Global Constraints

- Dart SDK constraint `^3.8.0` in every pubspec; monorepo is a pub workspace (`resolution: workspace`).
- Package `dartnest` depends only on the Dart SDK and `package:meta`; never on `dart:mirrors`, `dart:io` servers, shelf, or analyzer.
- Public API, dartdoc and commit messages are in English (public OSS package).
- Every public class and member has a dartdoc comment.
- All providers are singletons, created eagerly at `Container.create`; no request scope, no lifecycle hooks (spec: "Поза межами v1").
- Spec deviations locked in by this plan: module `id` is a `String` (not `Symbol`) for readable diagnostics; `Token` equality is by `name` + type parameter (no `Token.byName` switch); the spec's `NotExportedError` is folded into `MissingProviderError.definedIn` (the hint names modules that declare the key).
- `lints/recommended.yaml` must pass (`dart analyze` reports no issues) before every commit.

## Review Focus

1. A provider factory that throws an ordinary exception during startup: expected a `ProviderCreationError` naming the key, module and chain, with the original error and stack trace preserved, and no half-started container. Pinned in Task 5 (`factory exception is wrapped`).
2. `get()` called with no inferable type argument (e.g. `Object x = i.get();`): expected an `ArgumentError` telling the caller to write `get<MyType>()`, never a silent lookup of `Object`. Pinned in Task 5 (`get without type argument`).
3. The same provider key declared in two unrelated modules: expected both allowed, each module resolving its own instance (Nest scoping), not a duplicate error. Pinned in Task 5 (`same key in two modules`).
4. A dynamic module imported twice with different configuration but the same id: expected `DuplicateModuleIdError`, not silent use of whichever came first. Pinned in Task 4 (`same id, different shape`).
5. An async factory written as `Provider((i) async => ...)` without `Provider.async`: expected the container still awaits it during startup, and a sync `get()` of it before creation still fails with `AsyncProviderNotReadyError` rather than a type cast crash. Pinned in Task 5 (`plain async closure`).

---

## File Structure

```
pubspec.yaml                                  # workspace root
analysis_options.yaml                         # lints/recommended
packages/dartnest/
  pubspec.yaml
  analysis_options.yaml
  README.md
  lib/dartnest.dart                           # barrel: exports src/di/*
  lib/src/di/token.dart                       # Token<T>
  lib/src/di/provider.dart                    # Provider<T>, ProviderFactory
  lib/src/di/module.dart                      # Module
  lib/src/di/errors.dart                      # DartnestError hierarchy (DI part)
  lib/src/di/module_graph.dart                # ModuleGraph: dedupe, cycles, order, structural validation
  lib/src/di/injector.dart                    # Injector interface, ModuleInjector, resolution trace
  lib/src/di/container.dart                   # Container.create: wiring + eager instantiation
  test/di/token_test.dart
  test/di/provider_test.dart
  test/di/module_test.dart
  test/di/module_graph_test.dart
  test/di/container_test.dart
```

Responsibilities: `module_graph.dart` knows nothing about instances; `injector.dart` knows nothing about graph building; `container.dart` is the only place that sequences startup.

Prerequisite for every task: Dart SDK ≥ 3.8 on PATH (`dart --version`). It is not installed on the development machine as of 2026-10-13. Install per https://dart.dev/get-dart (Debian/Ubuntu: the official apt repository; or extract the SDK zip and add `bin/` to PATH). Stop and ask the user if installation needs sudo.

---

### Task 1: Workspace scaffolding and `Token<T>`

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `packages/dartnest/pubspec.yaml`
- Create: `packages/dartnest/analysis_options.yaml`
- Create: `packages/dartnest/README.md`
- Create: `packages/dartnest/lib/dartnest.dart`
- Create: `packages/dartnest/lib/src/di/token.dart`
- Test: `packages/dartnest/test/di/token_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `final class Token<T extends Object> { const Token(String name); String name; Type get type; }` with `==`/`hashCode` by `name` and `T`.

- [ ] **Step 1: Create the workspace and package manifests**

`pubspec.yaml` (repo root):

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
```

`analysis_options.yaml` (repo root):

```yaml
include: package:lints/recommended.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

`packages/dartnest/pubspec.yaml`:

```yaml
name: dartnest
description: NestJS-style modular backend framework for Dart without dart:mirrors.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  meta: ^1.16.0
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

`packages/dartnest/README.md`:

```markdown
# dartnest

NestJS-style modular backend framework for Dart without `dart:mirrors`.

Status: core DI under construction. See `docs/superpowers/ROADMAP.md`.
```

`packages/dartnest/lib/dartnest.dart`:

```dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/di/token.dart';
```

- [ ] **Step 2: Resolve dependencies**

Run from repo root: `dart pub get`
Expected: "Resolving dependencies... Got dependencies!" and `packages/dartnest/.dart_tool/` exists.

- [ ] **Step 3: Write the failing Token tests**

`packages/dartnest/test/di/token_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

void main() {
  group('Token', () {
    test('equal when name and type match', () {
      expect(const Token<String>('db.url'), equals(const Token<String>('db.url')));
      expect(Token<String>('db.url'), equals(Token<String>('db.url')));
      expect(
        Token<String>('db.url').hashCode,
        equals(Token<String>('db.url').hashCode),
      );
    });

    test('different name is a different token', () {
      expect(const Token<String>('a'), isNot(equals(const Token<String>('b'))));
    });

    test('different type parameter is a different token', () {
      expect(const Token<String>('a'), isNot(equals(const Token<int>('a'))));
    });

    test('exposes its type and a readable toString', () {
      const token = Token<int>('port');
      expect(token.type, int);
      expect(token.toString(), 'Token<int>(port)');
    });
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/token_test.dart`
Expected: compilation error, `Token` is not defined.

- [ ] **Step 5: Implement Token**

`packages/dartnest/lib/src/di/token.dart`:

```dart
import 'package:meta/meta.dart';

/// Typed identifier for a provider whose value is not uniquely identified by
/// its Dart type: primitives (`String`, `int`), or several implementations of
/// one interface.
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
/// Provider.value('postgres://...', token: dbUrl);
/// injector.get(dbUrl); // String
/// ```
///
/// Two tokens are equal when they have the same [name] and the same type
/// parameter [T]. String tokens without a type do not exist on purpose.
@immutable
final class Token<T extends Object> {
  /// Creates a token named [name] for values of type [T].
  const Token(this.name);

  /// Human-readable name, used in diagnostics and for equality.
  final String name;

  /// The value type this token identifies.
  Type get type => T;

  @override
  bool operator ==(Object other) => other is Token<T> && other.name == name;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'Token<$T>($name)';
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run from `packages/dartnest`: `dart test test/di/token_test.dart`
Expected: 4 tests pass.

- [ ] **Step 7: Analyze and commit**

Run from repo root: `dart analyze`
Expected: "No issues found!"

```bash
git add pubspec.yaml analysis_options.yaml packages/dartnest
git commit -m "feat(core): scaffold workspace and add Token<T>"
```

---

### Task 2: `Provider<T>`

**Files:**
- Create: `packages/dartnest/lib/src/di/provider.dart`
- Create: `packages/dartnest/lib/src/di/injector.dart` (interface only in this task)
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/di/provider_test.dart`

**Interfaces:**
- Consumes: `Token<T>` from Task 1.
- Produces:
  - `abstract interface class Injector { T get<T extends Object>([Token<T>? token]); T? maybeGet<T extends Object>([Token<T>? token]); String get moduleId; }`
  - `typedef ProviderFactory<T extends Object> = FutureOr<T> Function(Injector injector);`
  - `final class Provider<T extends Object> { Provider(ProviderFactory<T> create, {Token<T>? token}); Provider.value(T value, {Token<T>? token}); Provider.async(Future<T> Function(Injector) create, {Token<T>? token}); Object get key; bool get isAsync; Type get type; FutureOr<T> create(Injector injector); }`
  - `key` is `T` (a `Type`) when no token is given, otherwise the `Token<T>`.

- [ ] **Step 1: Write the failing Provider tests**

`packages/dartnest/test/di/provider_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

abstract class Ticker {}

class SystemTicker implements Ticker {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

/// Minimal injector double: returns pre-registered instances by key.
class FakeInjector implements Injector {
  FakeInjector(this.values);
  final Map<Object, Object> values;

  @override
  String get moduleId => 'fake';

  @override
  T get<T extends Object>([Token<T>? token]) => values[token ?? T] as T;

  @override
  T? maybeGet<T extends Object>([Token<T>? token]) => values[token ?? T] as T?;
}

void main() {
  group('Provider', () {
    test('infers T from the factory return type and keys by Type', () {
      final provider = Provider((i) => Clock());
      expect(provider.type, Clock);
      expect(provider.key, Clock);
      expect(provider.isAsync, isFalse);
    });

    test('infers i.get() type from the constructor parameter', () {
      final clock = Clock();
      final provider = Provider((i) => Repo(i.get()));
      final repo = provider.create(FakeInjector({Clock: clock})) as Repo;
      expect(repo.clock, same(clock));
    });

    test('uses the token as key when given', () {
      const dbUrl = Token<String>('db.url');
      final provider = Provider.value('postgres://x', token: dbUrl);
      expect(provider.key, dbUrl);
      expect(provider.create(FakeInjector({})), 'postgres://x');
    });

    test('explicit type parameter binds an abstraction to an implementation', () {
      final provider = Provider<Ticker>((i) => SystemTicker());
      expect(provider.key, Ticker);
      expect(provider.type, Ticker);
    });

    test('rejects a type parameter that could not be inferred', () {
      expect(() => Provider<Object>((i) => Clock()), throwsArgumentError);
    });

    test('Provider.async is flagged and returns a Future', () async {
      final provider = Provider.async((i) async => Clock());
      expect(provider.isAsync, isTrue);
      expect(provider.type, Clock);
      expect(await provider.create(FakeInjector({})), isA<Clock>());
    });

    test('a plain async closure infers T through FutureOr', () {
      final provider = Provider((i) async => Clock());
      expect(provider.type, Clock);
      expect(provider.isAsync, isFalse);
      expect(provider.create(FakeInjector({})), isA<Future<Clock>>());
    });

    test('toString names the type and token', () {
      expect(Provider((i) => Clock()).toString(), 'Provider<Clock>');
      expect(
        Provider.value(1, token: const Token<int>('port')).toString(),
        'Provider<int>(Token<int>(port))',
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/provider_test.dart`
Expected: compilation error, `Provider` and `Injector` are not defined.

- [ ] **Step 3: Implement the Injector interface and Provider**

`packages/dartnest/lib/src/di/injector.dart` (interface only for now; the implementation is added in Task 5 in this same file):

```dart
import 'token.dart';

/// Resolves provider instances inside one module's scope.
///
/// Lookups are synchronous and see: the module's own providers, providers
/// exported by its direct imports (including re-exported modules), and
/// providers exported by global modules. The container is immutable after
/// startup, so `get` is cheap and never creates request-scoped state.
abstract interface class Injector {
  /// Id of the module this injector belongs to.
  String get moduleId;

  /// Returns the singleton for [T], or for [token] when given.
  ///
  /// Throws `MissingProviderError` when nothing in scope provides the key and
  /// `AsyncProviderNotReadyError` when the provider is async and has not been
  /// created yet. Throws [ArgumentError] when [T] could not be inferred.
  T get<T extends Object>([Token<T>? token]);

  /// Like [get] but returns `null` instead of throwing `MissingProviderError`.
  T? maybeGet<T extends Object>([Token<T>? token]);
}
```

`packages/dartnest/lib/src/di/provider.dart`:

```dart
import 'dart:async';

import 'injector.dart';
import 'token.dart';

/// Builds a provider instance. Receives the injector of the module that
/// declares the provider, so it can resolve its own dependencies.
typedef ProviderFactory<T extends Object> = FutureOr<T> Function(
  Injector injector,
);

/// Declares how a module creates one singleton of type [T].
///
/// ```dart
/// Provider((i) => UsersRepo(i.get()));        // T inferred, key = UsersRepo
/// Provider<Clock>((i) => SystemClock());      // key = Clock
/// Provider.value(config);                     // constant
/// Provider.async((i) async => Db.connect());  // awaited at startup
/// Provider.value(url, token: dbUrl);          // keyed by a Token
/// ```
final class Provider<T extends Object> {
  /// Synchronous (or implicitly async) factory provider.
  Provider(ProviderFactory<T> create, {Token<T>? token})
      : this._(create, token: token, isAsync: false);

  /// Provides an already-built [value].
  Provider.value(T value, {Token<T>? token})
      : this._((_) => value, token: token, isAsync: false);

  /// Factory that must be awaited. The container awaits it during startup;
  /// a synchronous `get` of this key before that fails with
  /// `AsyncProviderNotReadyError`.
  Provider.async(Future<T> Function(Injector injector) create, {Token<T>? token})
      : this._(create, token: token, isAsync: true);

  Provider._(this._create, {Token<T>? token, required this.isAsync})
      : key = token ?? T {
    if (T == Object) {
      throw ArgumentError(
        'Provider type could not be inferred. '
        'Write Provider<MyType>(...) or return a concrete type from the factory.',
      );
    }
  }

  /// Lookup key: the [Type] `T`, or the [Token] when one was given.
  final Object key;

  /// Whether this provider was declared with [Provider.async].
  final bool isAsync;

  final ProviderFactory<T> _create;

  /// The provided type.
  Type get type => T;

  /// Invokes the factory. Callers must handle a returned [Future].
  FutureOr<T> create(Injector injector) => _create(injector);

  @override
  String toString() => key is Token ? 'Provider<$T>($key)' : 'Provider<$T>';
}
```

Update `packages/dartnest/lib/dartnest.dart`:

```dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/di/injector.dart' show Injector;
export 'src/di/provider.dart';
export 'src/di/token.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run from `packages/dartnest`: `dart test test/di/provider_test.dart`
Expected: 8 tests pass. If `infers T from the factory return type` fails with `type` being `Object`, Dart did not infer `T` from the closure; stop and report, because the public API must then change to require `Provider<X>(...)` (see roadmap risk list).

- [ ] **Step 5: Analyze and commit**

Run from repo root: `dart analyze`
Expected: "No issues found!"

```bash
git add packages/dartnest
git commit -m "feat(core): add Provider<T> and Injector interface"
```

---

### Task 3: `Module` and the DI error hierarchy

**Files:**
- Create: `packages/dartnest/lib/src/di/module.dart`
- Create: `packages/dartnest/lib/src/di/errors.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/di/module_test.dart`

**Interfaces:**
- Consumes: `Provider`, `Token`.
- Produces:
  - `final class Module { Module({required String id, List<Module> imports = const [], List<Provider<Object>> providers = const [], List<Object> exports = const [], bool global = false}); }` — `exports` entries are a `Type`, a `Token`, or a `Module` from `imports`.
  - Errors (all `implements Exception`, all with `String get message`): `DartnestError` (sealed root), `InjectionError` (sealed), `DuplicateModuleIdError(id)`, `CircularModuleImportError(cycle: List<String>)`, `DuplicateProviderError(key, moduleId)`, `InvalidExportError(export, moduleId)`, `MissingProviderError(key, moduleId, chain: List<Object>, definedIn: List<String>)`, `CircularDependencyError(cycle: List<Object>)`, `AsyncProviderNotReadyError(key, chain: List<Object>)`, `ProviderCreationError(key, moduleId, chain, error, stackTrace)`, `UnknownModuleError(id)`.
  - Helper `String describeKey(Object key)` → `'UsersRepo'` for a `Type`, `'Token<String>(db.url)'` for a token.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/di/module_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

void main() {
  group('Module', () {
    test('has sensible defaults', () {
      final m = Module(id: 'app');
      expect(m.id, 'app');
      expect(m.imports, isEmpty);
      expect(m.providers, isEmpty);
      expect(m.exports, isEmpty);
      expect(m.global, isFalse);
    });

    test('dynamic modules are plain functions returning a Module', () {
      Module database({required String url}) => Module(
            id: 'database',
            providers: [Provider.value(url, token: const Token<String>('db.url'))],
            exports: [const Token<String>('db.url')],
          );
      final m = database(url: 'postgres://x');
      expect(m.providers.single.key, const Token<String>('db.url'));
    });

    test('toString shows the id', () {
      expect(Module(id: 'users').toString(), 'Module(users)');
    });
  });

  group('errors', () {
    test('MissingProviderError message contains chain and hint', () {
      final e = MissingProviderError(
        key: Clock,
        moduleId: 'users',
        chain: [Clock, String],
        definedIn: ['core'],
      );
      expect(e.message, contains('No provider for Clock in module "users"'));
      expect(e.message, contains('Clock <- String'));
      expect(e.message, contains('declared in module(s) [core]'));
      expect(e.toString(), startsWith('MissingProviderError: '));
    });

    test('CircularDependencyError lists the cycle', () {
      final e = CircularDependencyError([Clock, String, Clock]);
      expect(e.message, contains('Clock -> String -> Clock'));
    });

    test('describeKey formats types and tokens', () {
      expect(describeKey(Clock), 'Clock');
      expect(describeKey(const Token<int>('port')), 'Token<int>(port)');
    });

    test('errors are Exceptions under the sealed roots', () {
      expect(const DuplicateModuleIdError('x'), isA<InjectionError>());
      expect(const DuplicateModuleIdError('x'), isA<DartnestError>());
      expect(const DuplicateModuleIdError('x'), isA<Exception>());
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/module_test.dart`
Expected: compilation error, `Module` and the error classes are not defined.

- [ ] **Step 3: Implement Module and errors**

`packages/dartnest/lib/src/di/module.dart`:

```dart
import 'provider.dart';
import 'token.dart';

/// Declarative description of a module: what it provides, what it imports,
/// and what it exposes to importers.
///
/// A module is a value, not a class. Dynamic modules are therefore plain
/// functions that return a [Module]. Two modules with the same [id] are
/// treated as one; importing the same dynamic module twice with different
/// configuration is an error (see `DuplicateModuleIdError`).
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
  Module({
    required this.id,
    this.imports = const [],
    this.providers = const [],
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
  final List<Provider<Object>> providers;

  /// What importers of this module can see: a [Type] or [Token] of one of
  /// [providers], or a [Module] from [imports] (re-export).
  final List<Object> exports;

  /// When true, this module's exports are visible to every module without
  /// an explicit import.
  final bool global;

  /// Whether [key] (a [Type] or [Token]) is declared by this module.
  bool declares(Object key) => providers.any((p) => p.key == key);

  /// Whether [key] is exported directly (not via a re-exported module).
  bool exportsKey(Object key) =>
      exports.any((e) => e is! Module && e == key);

  /// Ids of modules re-exported by this module.
  Iterable<String> get reexportedModuleIds =>
      exports.whereType<Module>().map((m) => m.id);

  @override
  String toString() => 'Module($id)';
}

/// Formats a provider key ([Type] or [Token]) for diagnostics.
String describeKey(Object key) => key is Token ? key.toString() : '$key';
```

`packages/dartnest/lib/src/di/errors.dart`:

```dart
import 'module.dart';

/// Root of every error raised by dartnest itself.
sealed class DartnestError implements Exception {
  const DartnestError();

  /// Human-readable explanation, suitable for logs.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Errors raised while building the module graph or resolving providers.
sealed class InjectionError extends DartnestError {
  const InjectionError();
}

/// Two different modules (by structure) share one id.
final class DuplicateModuleIdError extends InjectionError {
  const DuplicateModuleIdError(this.id);

  /// The conflicting id.
  final String id;

  @override
  String get message =>
      'Two different modules share the id "$id". A dynamic module imported '
      'in several places must be configured identically everywhere.';
}

/// Module imports form a cycle.
final class CircularModuleImportError extends InjectionError {
  const CircularModuleImportError(this.cycle);

  /// Module ids forming the cycle; first and last are the same module.
  final List<String> cycle;

  @override
  String get message =>
      'Module imports form a cycle: ${cycle.join(' -> ')}. '
      'Move the shared providers into a third module imported by both.';
}

/// One module declares the same key twice.
final class DuplicateProviderError extends InjectionError {
  const DuplicateProviderError({required this.key, required this.moduleId});

  /// The duplicated key.
  final Object key;

  /// The module that declares it twice.
  final String moduleId;

  @override
  String get message =>
      'Module "$moduleId" declares ${describeKey(key)} more than once.';
}

/// An `exports` entry is neither an own provider nor an imported module.
final class InvalidExportError extends InjectionError {
  const InvalidExportError({required this.export, required this.moduleId});

  /// The offending export entry.
  final Object export;

  /// The exporting module.
  final String moduleId;

  @override
  String get message {
    final e = export; // local copy: public fields do not promote
    final what = e is Module ? 'module "${e.id}"' : describeKey(e);
    return 'Module "$moduleId" exports $what, which is neither one of its '
        'providers nor one of its imports.';
  }
}

/// Nothing in scope provides the requested key.
final class MissingProviderError extends InjectionError {
  const MissingProviderError({
    required this.key,
    required this.moduleId,
    required this.chain,
    this.definedIn = const [],
  });

  /// The key that could not be resolved.
  final Object key;

  /// The module whose injector was asked.
  final String moduleId;

  /// Keys being resolved when the lookup failed, innermost first
  /// (`[UsersRepo, UsersService]` means UsersService needed UsersRepo,
  /// which needed [key]).
  final List<Object> chain;

  /// Modules that declare [key] but do not expose it to [moduleId].
  final List<String> definedIn;

  @override
  String get message {
    final buffer = StringBuffer(
      'No provider for ${describeKey(key)} in module "$moduleId"',
    );
    if (chain.isNotEmpty) {
      buffer.write(' (resolving: ${chain.map(describeKey).join(' <- ')})');
    }
    buffer.write('.');
    if (definedIn.isNotEmpty) {
      buffer.write(
        ' It is declared in module(s) [${definedIn.join(', ')}]; export it '
        'there and import that module into "$moduleId".',
      );
    }
    return buffer.toString();
  }
}

/// Providers depend on each other in a cycle.
final class CircularDependencyError extends InjectionError {
  const CircularDependencyError(this.cycle);

  /// Keys forming the cycle; first and last are the same key.
  final List<Object> cycle;

  @override
  String get message =>
      'Circular dependency: ${cycle.map(describeKey).join(' -> ')}.';
}

/// A synchronous `get` asked for an async provider before the container
/// had awaited it.
final class AsyncProviderNotReadyError extends InjectionError {
  const AsyncProviderNotReadyError({required this.key, required this.chain});

  /// The async key.
  final Object key;

  /// Keys being resolved, innermost first.
  final List<Object> chain;

  @override
  String get message {
    final who = chain.isEmpty
        ? 'it was requested'
        : '${describeKey(chain.first)} asked for it';
    return 'Provider ${describeKey(key)} is async and was not created yet '
        'when $who. Declare it earlier in the module, or in an imported module.';
  }
}

/// A provider factory threw.
final class ProviderCreationError extends InjectionError {
  const ProviderCreationError({
    required this.key,
    required this.moduleId,
    required this.chain,
    required this.error,
    required this.stackTrace,
  });

  /// The provider whose factory threw.
  final Object key;

  /// The module that declares it.
  final String moduleId;

  /// Keys being resolved, innermost first.
  final List<Object> chain;

  /// The original error.
  final Object error;

  /// The original stack trace.
  final StackTrace stackTrace;

  @override
  String get message =>
      'Factory for ${describeKey(key)} in module "$moduleId" threw: $error'
      '${chain.isEmpty ? '' : ' (resolving: ${chain.map(describeKey).join(' <- ')})'}';
}

/// No module with the given id exists in the container.
final class UnknownModuleError extends InjectionError {
  const UnknownModuleError(this.id);

  /// The requested id.
  final String id;

  @override
  String get message => 'No module with id "$id" in this container.';
}
```

Update `packages/dartnest/lib/dartnest.dart`:

```dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/di/errors.dart';
export 'src/di/injector.dart' show Injector;
export 'src/di/module.dart';
export 'src/di/provider.dart';
export 'src/di/token.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run from `packages/dartnest`: `dart test test/di/module_test.dart`
Expected: 7 tests pass.

- [ ] **Step 5: Analyze and commit**

Run from repo root: `dart analyze`
Expected: "No issues found!"

```bash
git add packages/dartnest
git commit -m "feat(core): add Module and DI error hierarchy"
```

---

### Task 4: `ModuleGraph` — deduplication, cycles, order, structural validation

**Files:**
- Create: `packages/dartnest/lib/src/di/module_graph.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/di/module_graph_test.dart`

**Interfaces:**
- Consumes: `Module`, errors from Task 3.
- Produces: `final class ModuleGraph { static ModuleGraph build(Module root); Module get root; List<Module> get ordered; Module byId(String id); bool contains(String id); List<String> modulesDeclaring(Object key); }` — `ordered` lists each distinct module once, imports before importers, root last.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/di/module_graph_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class A {}

class B {}

void main() {
  group('ModuleGraph.build', () {
    test('orders imports before importers, root last, each module once', () {
      final shared = Module(id: 'shared');
      final users = Module(id: 'users', imports: [shared]);
      final orders = Module(id: 'orders', imports: [shared]);
      final app = Module(id: 'app', imports: [users, orders]);

      final graph = ModuleGraph.build(app);

      final ids = graph.ordered.map((m) => m.id).toList();
      expect(ids, ['shared', 'users', 'orders', 'app']);
      expect(graph.root, same(app));
      expect(graph.byId('shared'), same(shared));
      expect(graph.contains('nope'), isFalse);
    });

    test('a dynamic module imported twice with the same shape is one module', () {
      Module database({required String url}) => Module(
            id: 'database',
            providers: [Provider.value(url, token: const Token<String>('url'))],
            exports: [const Token<String>('url')],
          );
      final users = Module(id: 'users', imports: [database(url: 'x')]);
      final orders = Module(id: 'orders', imports: [database(url: 'x')]);
      final app = Module(id: 'app', imports: [users, orders]);

      final graph = ModuleGraph.build(app);

      expect(graph.ordered.where((m) => m.id == 'database'), hasLength(1));
    });

    test('same id, different shape is an error', () {
      final one = Module(id: 'database', providers: [Provider((i) => A())]);
      final two = Module(id: 'database', providers: [Provider((i) => B())]);
      final app = Module(id: 'app', imports: [one, two]);

      expect(
        () => ModuleGraph.build(app),
        throwsA(isA<DuplicateModuleIdError>().having((e) => e.id, 'id', 'database')),
      );
    });

    test('import cycle is an error listing the cycle', () {
      final a = Module(id: 'a', imports: []); // growable list, so the test can close the cycle
      final b = Module(id: 'b', imports: [a]);
      a.imports.add(b);

      expect(
        () => ModuleGraph.build(Module(id: 'app', imports: [a])),
        throwsA(
          isA<CircularModuleImportError>()
              .having((e) => e.cycle, 'cycle', ['a', 'b', 'a']),
        ),
      );
    });

    test('duplicate provider key in one module is an error', () {
      final m = Module(
        id: 'app',
        providers: [Provider((i) => A()), Provider((i) => A())],
      );
      expect(
        () => ModuleGraph.build(m),
        throwsA(isA<DuplicateProviderError>().having((e) => e.key, 'key', A)),
      );
    });

    test('exporting a key the module does not declare is an error', () {
      final m = Module(id: 'app', exports: [A]);
      expect(
        () => ModuleGraph.build(m),
        throwsA(isA<InvalidExportError>().having((e) => e.export, 'export', A)),
      );
    });

    test('re-exporting a module that is not imported is an error', () {
      final other = Module(id: 'other');
      final m = Module(id: 'app', exports: [other]);
      expect(
        () => ModuleGraph.build(m),
        throwsA(isA<InvalidExportError>()),
      );
    });

    test('re-exporting an imported module is allowed', () {
      final db = Module(id: 'db', providers: [Provider((i) => A())], exports: [A]);
      final shared = Module(id: 'shared', imports: [db], exports: [db]);
      expect(ModuleGraph.build(shared).ordered.map((m) => m.id), ['db', 'shared']);
    });

    test('modulesDeclaring finds every module with the key', () {
      final x = Module(id: 'x', providers: [Provider((i) => A())]);
      final y = Module(id: 'y', providers: [Provider((i) => A())]);
      final graph = ModuleGraph.build(Module(id: 'app', imports: [x, y]));
      expect(graph.modulesDeclaring(A), ['x', 'y']);
      expect(graph.modulesDeclaring(B), isEmpty);
    });
  });
}
```

Note on the cycle test: `Module.imports` defaults to `const []`, which is immutable, so the test passes a growable `[]` for module `a` and adds `b` afterwards. The implementation must not rely on lists being immutable.

- [ ] **Step 2: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/module_graph_test.dart`
Expected: compilation error, `ModuleGraph` is not defined.

- [ ] **Step 3: Implement ModuleGraph**

`packages/dartnest/lib/src/di/module_graph.dart`:

```dart
import 'errors.dart';
import 'module.dart';

/// The deduplicated, validated, topologically ordered set of modules
/// reachable from a root module.
///
/// Building the graph performs every structural check that does not need
/// provider instances: duplicate ids with different shape, import cycles,
/// duplicate provider keys, invalid exports.
final class ModuleGraph {
  ModuleGraph._(this.root, this.ordered, this._byId);

  /// The module `build` was called with.
  final Module root;

  /// Every distinct module once, imports before importers, [root] last.
  final List<Module> ordered;

  final Map<String, Module> _byId;

  /// Builds and validates the graph reachable from [root].
  static ModuleGraph build(Module root) {
    final byId = <String, Module>{};
    final ordered = <Module>[];
    final path = <String>[]; // current DFS path, for cycle reporting

    void visit(Module module) {
      final seen = byId[module.id];
      if (seen != null) {
        // Already finished: only check that it is the same module.
        if (!identical(seen, module) && !_sameShape(seen, module)) {
          throw DuplicateModuleIdError(module.id);
        }
        return;
      }
      if (path.contains(module.id)) {
        final start = path.indexOf(module.id);
        throw CircularModuleImportError([...path.sublist(start), module.id]);
      }
      _validateProviders(module);
      _validateExports(module);
      path.add(module.id);
      for (final import in module.imports) {
        visit(import);
      }
      path.removeLast();
      byId[module.id] = module;
      ordered.add(module);
    }

    visit(root);
    return ModuleGraph._(root, List.unmodifiable(ordered), byId);
  }

  /// The module with [id]; throws [UnknownModuleError] if absent.
  Module byId(String id) => _byId[id] ?? (throw UnknownModuleError(id));

  /// Whether a module with [id] is in the graph.
  bool contains(String id) => _byId.containsKey(id);

  /// Ids of every module that declares [key], in [ordered] order.
  List<String> modulesDeclaring(Object key) =>
      [for (final m in ordered) if (m.declares(key)) m.id];

  static void _validateProviders(Module module) {
    final keys = <Object>{};
    for (final provider in module.providers) {
      if (!keys.add(provider.key)) {
        throw DuplicateProviderError(key: provider.key, moduleId: module.id);
      }
    }
  }

  static void _validateExports(Module module) {
    for (final export in module.exports) {
      final valid = export is Module
          ? module.imports.any((m) => m.id == export.id)
          : module.declares(export);
      if (!valid) {
        throw InvalidExportError(export: export, moduleId: module.id);
      }
    }
  }

  /// Structural equality used to accept the same dynamic module imported
  /// from several places.
  static bool _sameShape(Module a, Module b) {
    if (a.id != b.id || a.global != b.global) return false;
    if (!_sameList(a.imports.map((m) => m.id), b.imports.map((m) => m.id))) {
      return false;
    }
    if (!_sameList(a.providers.map((p) => p.key), b.providers.map((p) => p.key))) {
      return false;
    }
    Object exportKey(Object e) => e is Module ? 'module:${e.id}' : e;
    return _sameList(a.exports.map(exportKey), b.exports.map(exportKey));
  }

  static bool _sameList(Iterable<Object> a, Iterable<Object> b) {
    final la = a.toList();
    final lb = b.toList();
    if (la.length != lb.length) return false;
    for (var i = 0; i < la.length; i++) {
      if (la[i] != lb[i]) return false;
    }
    return true;
  }
}
```

Note: a module id in `byId` has finished its DFS, so it is never on `path`; the `path.contains` check before validation is the cycle check.

Update `packages/dartnest/lib/dartnest.dart` by adding `export 'src/di/module_graph.dart';` in alphabetical position.

- [ ] **Step 4: Run the test to verify it passes**

Run from `packages/dartnest`: `dart test test/di/module_graph_test.dart`
Expected: 9 tests pass.

- [ ] **Step 5: Analyze and commit**

Run from repo root: `dart analyze`
Expected: "No issues found!"

```bash
git add packages/dartnest
git commit -m "feat(core): add ModuleGraph with dedupe, cycle and export validation"
```

---

### Task 5: `ModuleInjector` and `Container` — resolution and eager startup

**Files:**
- Modify: `packages/dartnest/lib/src/di/injector.dart` (add `ModuleInjector`, `ResolutionTrace`)
- Create: `packages/dartnest/lib/src/di/container.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/di/container_test.dart`

**Interfaces:**
- Consumes: `ModuleGraph`, `Module`, `Provider`, errors.
- Produces:
  - `final class Container { static Future<Container> create(Module root); ModuleGraph get graph; Injector get root; Injector injectorFor(String moduleId); }`
  - `final class ModuleInjector implements Injector` (public for later tasks that need `module`, but constructed only by `Container`).
  - Resolution rules: own providers → exports of direct imports (following re-exported modules) → exports of global modules. A factory always receives the injector of the module that declares the provider.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/di/container_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Clock {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

class Service {
  Service(this.repo);
  final Repo repo;
}

class Db {}

class Secret {}

class Config {}

class UsesSecret {
  UsesSecret(Secret secret);
}

class UsesDb {
  UsesDb(Db db);
}

class NeedsA {
  NeedsA(NeedsB b);
}

class NeedsB {
  NeedsB(NeedsA a);
}

void main() {
  group('Container.create', () {
    test('resolves sync providers regardless of declaration order', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => Service(i.get())),
          Provider((i) => Repo(i.get())),
          Provider((i) => Clock()),
        ],
      );

      final c = await Container.create(app);

      final service = c.root.get<Service>();
      expect(service.repo.clock, same(c.root.get<Clock>()));
      expect(c.root.moduleId, 'app');
    });

    test('providers are singletons created exactly once', () async {
      var created = 0;
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created++;
            return Clock();
          }),
          Provider((i) => Repo(i.get())),
          Provider((i) => Service(i.get())),
        ],
      );

      final c = await Container.create(app);
      c.root.get<Clock>();
      c.root.get<Service>();

      expect(created, 1);
      expect(c.root.get<Clock>(), same(c.root.get<Repo>().clock));
    });

    test('token providers resolve by token', () async {
      const url = Token<String>('db.url');
      final c = await Container.create(
        Module(id: 'app', providers: [Provider.value('pg://x', token: url)]),
      );
      expect(c.root.get(url), 'pg://x');
      expect(c.root.maybeGet<String>(), isNull);
    });

    test('missing provider reports module and chain', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => Service(i.get())),
          Provider((i) => Repo(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', Clock)
              .having((e) => e.moduleId, 'moduleId', 'app')
              .having((e) => e.chain, 'chain', [Repo, Service]),
        ),
      );
    });

    test('circular dependency is detected', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => NeedsA(i.get())),
          Provider((i) => NeedsB(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<CircularDependencyError>()
              .having((e) => e.cycle, 'cycle', [NeedsA, NeedsB, NeedsA]),
        ),
      );
    });

    test('exports of imported modules are visible', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Db())],
        exports: [Db],
      );
      final app = Module(
        id: 'app',
        imports: [database],
        providers: [Provider((i) => UsesDb(i.get()))],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), same(c.injectorFor('database').get<Db>()));
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
    });

    test('non-exported providers are invisible, with a hint', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Secret()), Provider((i) => Db())],
        exports: [Db],
      );
      final app = Module(
        id: 'app',
        imports: [database],
        providers: [Provider((i) => UsesSecret(i.get()))],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', Secret)
              .having((e) => e.chain, 'chain', [UsesSecret])
              .having((e) => e.definedIn, 'definedIn', ['database']),
        ),
      );
    });

    test('re-exported modules pass their exports through', () async {
      final database = Module(
        id: 'database',
        providers: [Provider((i) => Db())],
        exports: [Db],
      );
      final shared = Module(id: 'shared', imports: [database], exports: [database]);
      final app = Module(
        id: 'app',
        imports: [shared],
        providers: [Provider((i) => UsesDb(i.get()))],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), same(c.injectorFor('database').get<Db>()));
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
    });

    test('global module exports are visible without import', () async {
      final config = Module(
        id: 'config',
        global: true,
        providers: [Provider((i) => Config())],
        exports: [Config],
      );
      final deep = Module(id: 'deep', providers: [Provider((i) => Clock())]);
      final app = Module(id: 'app', imports: [config, deep]);

      final c = await Container.create(app);

      expect(c.injectorFor('deep').get<Config>(), same(c.root.get<Config>()));
    });

    test('factory receives the injector of its own module', () async {
      final database = Module(
        id: 'database',
        providers: [
          Provider((i) => Secret()),
          Provider((i) {
            expect(i.moduleId, 'database');
            i.get<Secret>(); // visible only inside database
            return Db();
          }),
        ],
        exports: [Db],
      );
      final app = Module(id: 'app', imports: [database]);

      final c = await Container.create(app);

      expect(c.root.get<Db>(), isA<Db>());
      expect(c.root.maybeGet<Secret>(), isNull);
    });

    test('async providers are awaited during startup', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider.async((i) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return Db();
          }),
          Provider((i) => UsesDb(i.get())), // declared after Db: allowed
          Provider((i) => Repo(i.get())),
          Provider((i) => Clock()),
        ],
      );

      final c = await Container.create(app);

      expect(c.root.get<Db>(), isA<Db>());
      expect(c.root.get<UsesDb>(), isA<UsesDb>());
    });

    test('async provider requested before creation fails clearly', () async {
      // UsesDb is created first (declaration order) and asks for Db, which
      // is async and still pending.
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) => UsesDb(i.get())),
          Provider.async((i) async => Db()),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<AsyncProviderNotReadyError>()
              .having((e) => e.key, 'key', Db)
              .having((e) => e.chain, 'chain', [UsesDb]),
        ),
      );
    });

    test('plain async closure is awaited at startup and guarded in sync get',
        () async {
      final ok = await Container.create(
        Module(id: 'app', providers: [Provider((i) async => Db())]),
      );
      expect(ok.root.get<Db>(), isA<Db>());

      final tooEarly = Module(
        id: 'app',
        providers: [
          Provider((i) => UsesDb(i.get())),
          Provider((i) async => Db()),
        ],
      );
      await expectLater(
        Container.create(tooEarly),
        throwsA(
          isA<AsyncProviderNotReadyError>().having((e) => e.key, 'key', Db),
        ),
      );
    });

    test('same key in two unrelated modules gives two instances', () async {
      final x = Module(id: 'x', providers: [Provider((i) => Clock())]);
      final y = Module(id: 'y', providers: [Provider((i) => Clock())]);
      final c = await Container.create(Module(id: 'app', imports: [x, y]));

      expect(
        c.injectorFor('x').get<Clock>(),
        isNot(same(c.injectorFor('y').get<Clock>())),
      );
      expect(c.root.maybeGet<Clock>(), isNull); // neither exports it
    });

    test('factory exception is wrapped with context', () async {
      final app = Module(
        id: 'app',
        providers: [
          Provider<Clock>((i) => throw StateError('boom')),
          Provider((i) => Repo(i.get())),
        ],
      );

      await expectLater(
        Container.create(app),
        throwsA(
          isA<ProviderCreationError>()
              .having((e) => e.key, 'key', Clock)
              .having((e) => e.moduleId, 'moduleId', 'app')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.chain, 'chain', isEmpty),
        ),
      );
    });

    test('get without type argument throws ArgumentError', () async {
      final c = await Container.create(
        Module(id: 'app', providers: [Provider((i) => Clock())]),
      );
      expect(() {
        Object value = c.root.get();
        return value;
      }, throwsArgumentError);
    });

    test('unknown module id', () async {
      final c = await Container.create(Module(id: 'app'));
      expect(() => c.injectorFor('nope'), throwsA(isA<UnknownModuleError>()));
    });

    test('structural errors surface before any factory runs', () async {
      var ran = false;
      final app = Module(
        id: 'app',
        providers: [
          Provider((i) {
            ran = true;
            return Clock();
          }),
          Provider((i) => Clock()),
        ],
      );

      await expectLater(Container.create(app), throwsA(isA<DuplicateProviderError>()));
      expect(ran, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/container_test.dart`
Expected: compilation error, `Container` is not defined.

- [ ] **Step 3: Implement ModuleInjector and ResolutionTrace**

Append to `packages/dartnest/lib/src/di/injector.dart` (keep the `Injector` interface from Task 2 at the top; add these imports: `dart:async`, `errors.dart`, `module.dart`, `provider.dart`):

```dart
/// Stack of keys currently being resolved. Shared by all injectors of one
/// container so that chains crossing module boundaries stay complete.
final class ResolutionTrace {
  final List<Object> _stack = [];

  /// Keys being resolved, innermost first.
  List<Object> get snapshot => List.unmodifiable(_stack.reversed);

  void _push(Object key) => _stack.add(key);

  void _pop() => _stack.removeLast();

  /// The cycle starting at [key], for `CircularDependencyError`. When [key]
  /// is not on the stack (a factory re-entered itself after an `await`), the
  /// cycle is reported as `[key, key]`.
  List<Object> cycleFrom(Object key) {
    final start = _stack.indexOf(key);
    if (start < 0) return [key, key];
    return [..._stack.sublist(start), key];
  }
}

/// One provider's lifecycle inside a module.
final class _Slot {
  _Slot(this.provider, this.owner);

  final Provider<Object> provider;
  final ModuleInjector owner;
  Object? instance;
  bool created = false;
  bool creating = false;

  Object get key => provider.key;
}

/// [Injector] implementation for one module. Constructed by `Container`.
final class ModuleInjector implements Injector {
  /// Creates the injector for [module]; call [wire] before resolving.
  ModuleInjector(this.module, this._trace, this._modulesDeclaring) {
    for (final provider in module.providers) {
      _own[provider.key] = _Slot(provider, this);
    }
  }

  /// The module this injector serves.
  final Module module;

  final ResolutionTrace _trace;
  final List<String> Function(Object key) _modulesDeclaring;
  final Map<Object, _Slot> _own = {};
  List<ModuleInjector> _imports = const [];
  List<ModuleInjector> _globals = const [];

  @override
  String get moduleId => module.id;

  /// Connects this injector to the injectors of its imports and to the
  /// global modules (excluding itself).
  void wire({
    required List<ModuleInjector> imports,
    required List<ModuleInjector> globals,
  }) {
    _imports = imports;
    _globals = globals;
  }

  @override
  T get<T extends Object>([Token<T>? token]) {
    final key = token ?? T;
    if (key == Object) {
      throw ArgumentError(
        'Type argument for get() could not be inferred; call get<MyType>().',
      );
    }
    final slot = _resolveSlot(key);
    if (slot == null) {
      throw MissingProviderError(
        key: key,
        moduleId: module.id,
        chain: _trace.snapshot,
        definedIn: _modulesDeclaring(key),
      );
    }
    return slot.owner._createSync(slot) as T;
  }

  @override
  T? maybeGet<T extends Object>([Token<T>? token]) {
    try {
      return get<T>(token);
    } on MissingProviderError {
      return null;
    }
  }

  /// Creates every own provider in declaration order, awaiting async ones.
  /// Called once by `Container.create`.
  Future<void> instantiateAll() async {
    for (final slot in _own.values) {
      if (!slot.created) {
        await _createAsync(slot);
      }
    }
  }

  _Slot? _resolveSlot(Object key) {
    final own = _own[key];
    if (own != null) return own;
    for (final import in _imports) {
      final slot = import._exported(key);
      if (slot != null) return slot;
    }
    for (final global in _globals) {
      final slot = global._exported(key);
      if (slot != null) return slot;
    }
    return null;
  }

  /// The slot for [key] if this module exports it directly or through a
  /// re-exported module.
  _Slot? _exported(Object key) {
    if (module.exportsKey(key)) return _own[key];
    for (final import in _imports) {
      if (module.reexportedModuleIds.contains(import.module.id)) {
        final slot = import._exported(key);
        if (slot != null) return slot;
      }
    }
    return null;
  }

  Object _createSync(_Slot slot) {
    if (slot.created) return slot.instance!;
    if (slot.creating) {
      throw CircularDependencyError(_trace.cycleFrom(slot.key));
    }
    if (slot.provider.isAsync) {
      throw AsyncProviderNotReadyError(key: slot.key, chain: _trace.snapshot);
    }
    final result = _invoke(slot);
    if (result is Future) {
      // The factory was `async` without Provider.async. Keep the future so
      // startup can still await it, but a sync caller cannot use it.
      slot.creating = false;
      throw AsyncProviderNotReadyError(key: slot.key, chain: _trace.snapshot);
    }
    _complete(slot, result);
    return result;
  }

  Future<void> _createAsync(_Slot slot) async {
    if (slot.created) return;
    if (slot.creating) {
      throw CircularDependencyError(_trace.cycleFrom(slot.key));
    }
    final result = _invoke(slot);
    if (result is Future<Object>) {
      try {
        _complete(slot, await result);
      } catch (error, stackTrace) {
        slot.creating = false;
        if (error is DartnestError) rethrow;
        throw ProviderCreationError(
          key: slot.key,
          moduleId: module.id,
          chain: const [],
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else {
      _complete(slot, result);
    }
  }

  /// Runs the factory with the trace pushed; marks the slot as creating.
  /// Returns the raw factory result (value or Future).
  FutureOr<Object> _invoke(_Slot slot) {
    slot.creating = true;
    _trace._push(slot.key);
    try {
      return slot.provider.create(this);
    } catch (error, stackTrace) {
      slot.creating = false;
      if (error is DartnestError) rethrow;
      throw ProviderCreationError(
        key: slot.key,
        moduleId: module.id,
        chain: _trace.snapshot.skip(1).toList(),
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _trace._pop();
    }
  }

  void _complete(_Slot slot, Object instance) {
    slot.instance = instance;
    slot.created = true;
    slot.creating = false;
  }
}
```

Behavioural notes the implementer must preserve:
- `_invoke` pops the trace in `finally`, so the chain captured by `ProviderCreationError` is taken before popping (`snapshot.skip(1)` drops the failing key itself; the test expects an empty chain for a root-level failure).
- A sync `get` of a plain-async closure invokes the factory once and discards the future. The container's later `_createAsync` of that slot invokes it again. This double invocation only happens on the error path (startup fails anyway), so it is acceptable; document it in the dartdoc of `Provider`.
- `Future<Object>` check: `result is Future<Object>` matches `Future<Db>` because `Future` is covariant.

- [ ] **Step 4: Implement Container**

`packages/dartnest/lib/src/di/container.dart`:

```dart
import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'module_graph.dart';

/// The started dependency graph: one [ModuleInjector] per module, every
/// provider instantiated.
///
/// ```dart
/// final container = await Container.create(appModule);
/// final users = container.root.get<UsersService>();
/// ```
final class Container {
  Container._(this.graph, this._injectors);

  /// The validated module graph.
  final ModuleGraph graph;

  final Map<String, ModuleInjector> _injectors;

  /// Builds, validates and starts the graph rooted at [root].
  ///
  /// Order of work:
  /// 1. [ModuleGraph.build] — structural validation, nothing is created.
  /// 2. One injector per module, wired to its imports and to global modules.
  /// 3. Modules in imports-first order; inside a module, providers in
  ///    declaration order. Async factories are awaited; sync factories may
  ///    pull sync dependencies on demand in any order.
  ///
  /// Throws an `InjectionError` subtype on the first problem; no partially
  /// started container is ever returned.
  static Future<Container> create(Module root) async {
    final graph = ModuleGraph.build(root);
    final trace = ResolutionTrace();
    final injectors = <String, ModuleInjector>{
      for (final module in graph.ordered)
        module.id: ModuleInjector(module, trace, graph.modulesDeclaring),
    };
    for (final module in graph.ordered) {
      injectors[module.id]!.wire(
        imports: [for (final import in module.imports) injectors[import.id]!],
        globals: [
          for (final other in graph.ordered)
            if (other.global && other.id != module.id) injectors[other.id]!,
        ],
      );
    }
    for (final module in graph.ordered) {
      await injectors[module.id]!.instantiateAll();
    }
    return Container._(graph, injectors);
  }

  /// Injector of the root module.
  Injector get root => injectorFor(graph.root.id);

  /// Injector of the module with [moduleId]; throws `UnknownModuleError`.
  Injector injectorFor(String moduleId) =>
      _injectors[moduleId] ?? (throw UnknownModuleError(moduleId));
}
```

Update `packages/dartnest/lib/dartnest.dart`:

```dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/di/container.dart';
export 'src/di/errors.dart';
export 'src/di/injector.dart' show Injector, ModuleInjector, ResolutionTrace;
export 'src/di/module.dart';
export 'src/di/module_graph.dart';
export 'src/di/provider.dart';
export 'src/di/token.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test`
Expected: all tests in `test/di/` pass (token 4, provider 8, module 7, module_graph 9, container 18).

If `missing provider reports module and chain` fails on the chain order, check `ResolutionTrace.snapshot`: it must be innermost first (`[Repo, Service]` when Service's factory asked for Repo, whose factory asked for Clock).

- [ ] **Step 6: Analyze and commit**

Run from repo root: `dart analyze`
Expected: "No issues found!"

```bash
git add packages/dartnest
git commit -m "feat(core): add ModuleInjector and Container with eager async-aware startup"
```

---

### Task 6: Package README and usage example

**Files:**
- Modify: `packages/dartnest/README.md`
- Create: `packages/dartnest/example/di_example.dart`
- Test: `packages/dartnest/test/di/example_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: a runnable example that doubles as documentation; later plans extend it with HTTP.

- [ ] **Step 1: Write the example as a test first**

`packages/dartnest/test/di/example_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../../example/di_example.dart' as example;

void main() {
  test('README example starts and resolves the greeting service', () async {
    final container = await Container.create(example.appModule);
    final greeter = container.root.get<example.Greeter>();
    expect(greeter.greet('dartnest'), 'Hello, dartnest! (via pg://localhost)');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `packages/dartnest`: `dart test test/di/example_test.dart`
Expected: compilation error, `example/di_example.dart` does not exist.

- [ ] **Step 3: Write the example**

`packages/dartnest/example/di_example.dart`:

```dart
import 'package:dartnest/dartnest.dart';

/// A typed token for a primitive value.
const dbUrl = Token<String>('db.url');

/// A dynamic module: a plain function returning a Module.
Module databaseModule({required String url}) => Module(
      id: 'database',
      providers: [
        Provider.value(url, token: dbUrl),
        Provider.async((i) async => Db.connect(i.get(dbUrl))),
      ],
      exports: [Db],
    );

class Db {
  Db._(this.url);
  final String url;
  static Future<Db> connect(String url) async => Db._(url);
}

class Greeter {
  Greeter(this.db);
  final Db db;
  String greet(String name) => 'Hello, $name! (via ${db.url})';
}

final greetingModule = Module(
  id: 'greeting',
  imports: [databaseModule(url: 'pg://localhost')],
  providers: [Provider((i) => Greeter(i.get()))],
  exports: [Greeter],
);

final appModule = Module(id: 'app', imports: [greetingModule]);

Future<void> main() async {
  final container = await Container.create(appModule);
  print(container.root.get<Greeter>().greet('dartnest'));
}
```

- [ ] **Step 4: Run the test and the example**

Run from `packages/dartnest`: `dart test test/di/example_test.dart`
Expected: 1 test passes.

Run from `packages/dartnest`: `dart run example/di_example.dart`
Expected output: `Hello, dartnest! (via pg://localhost)`

- [ ] **Step 5: Update the README**

Replace `packages/dartnest/README.md` with:

````markdown
# dartnest

NestJS-style modular backend framework for Dart without `dart:mirrors`.

Modules are values, providers are typed factories, and the dependency graph
is validated before anything starts. Annotations and code generation are an
optional layer on top (coming in later milestones); everything works without
them.

## Dependency injection

```dart
const dbUrl = Token<String>('db.url');

Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);

final greetingModule = Module(
  id: 'greeting',
  imports: [databaseModule(url: 'pg://localhost')],
  providers: [Provider((i) => Greeter(i.get()))],   // types are inferred
  exports: [Greeter],
);

final container = await Container.create(Module(id: 'app', imports: [greetingModule]));
container.root.get<Greeter>();
```

Rules:

- A provider is visible inside its module and, when listed in `exports`, in
  modules that import it. `global: true` makes exports visible everywhere.
- Every provider is a singleton created at `Container.create`, in
  imports-first module order. Sync providers may be declared in any order;
  an async provider must be declared before the providers that use it.
- Problems fail fast with a typed `InjectionError`: missing provider (with
  the resolution chain and the modules that declare it), circular
  dependency, duplicate module id with a different configuration, invalid
  export.

See `example/di_example.dart` and `docs/superpowers/ROADMAP.md`.
````

- [ ] **Step 6: Analyze and commit**

Run from repo root: `dart analyze && cd packages/dartnest && dart test`
Expected: "No issues found!" and all tests pass.

```bash
git add packages/dartnest
git commit -m "docs(core): add DI example and README"
```
