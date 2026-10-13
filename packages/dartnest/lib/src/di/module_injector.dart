import 'dart:async';

import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'provider_spec.dart';
import 'resolution_trace.dart';
import 'token.dart';

/// One provider's lifecycle inside a module.
final class _Slot {
  _Slot(this.provider, this.owner);

  final ProviderSpec provider;
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
    final instance = slot.instance;
    if (slot.created && instance != null) return instance;
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
    _trace.push(slot.key);
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
      _trace.pop();
    }
  }

  void _complete(_Slot slot, Object instance) {
    slot.instance = instance;
    slot.created = true;
    slot.creating = false;
  }
}
