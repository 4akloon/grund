import 'dart:async';

import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'provider.dart';
import 'resolution_trace.dart';
import 'token.dart';

/// One provider's lifecycle inside a module.
final class _Slot {
  _Slot(this.provider, this.owner);

  final ProviderSpec provider;
  final ModuleInjector owner;
  Object? instance;
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
    final key = _keyFor<T>(token);
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
    final slot = _resolveSlot(_keyFor<T>(token));
    if (slot == null) return null;
    return slot.owner._createSync(slot) as T;
  }

  Object _keyFor<T extends Object>(Token<T>? token) {
    final key = token ?? T;
    if (key == Object) {
      throw ArgumentError(
        'Type argument for get() could not be inferred; call get<MyType>().',
      );
    }
    return key;
  }

  /// The instances of this module's own providers created so far, by key.
  Map<Object, Object> get instances => {
    for (final MapEntry(:key, value: slot) in _own.entries)
      if (slot.instance case final instance?) key: instance,
  };

  /// Takes over the [instances] whose keys this module still declares, so
  /// that [instantiateAll] does not create them again. Called by
  /// `Container.reassemble` before [wire].
  void adopt(Map<Object, Object> instances) {
    for (final MapEntry(:key, value: slot) in _own.entries) {
      slot.instance = instances[key] ?? slot.instance;
    }
  }

  /// Creates every own provider in declaration order, awaiting async ones.
  /// Called once by `Container.create` and `Container.reassemble`.
  Future<void> instantiateAll() async {
    for (final slot in _own.values) {
      if (slot.instance == null) {
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
    if (slot.instance case final instance?) return instance;
    if (slot.creating) _rejectReentry(slot);
    if (slot.provider.isAsync) throw _notReady(slot);
    final result = _invoke(slot);
    if (result is Future) {
      // The factory was `async` without Provider.async. A sync caller cannot
      // use the future, so it is discarded (startup invokes the factory
      // again); `ignore` keeps a later failure from becoming unhandled.
      result.ignore();
      slot.creating = false;
      throw _notReady(slot);
    }
    _complete(slot, result);
    return result;
  }

  /// A slot that is still being created was asked for again: a cycle when
  /// its key is on the trace, otherwise an access from outside the sequential
  /// startup (for example an unawaited future), which is a not-ready error.
  Never _rejectReentry(_Slot slot) {
    if (_trace.contains(slot.key)) {
      throw CircularDependencyError(_trace.cycleFrom(slot.key));
    }
    throw _notReady(slot);
  }

  AsyncProviderNotReadyError _notReady(_Slot slot) =>
      AsyncProviderNotReadyError(
        key: slot.key,
        moduleId: slot.owner.module.id,
        chain: _trace.snapshot,
      );

  /// Creates [slot], awaiting an async factory. The key stays on the trace
  /// across the await so that a `get` made after it still sees the chain.
  Future<void> _createAsync(_Slot slot) async {
    if (slot.instance != null) return;
    if (slot.creating) _rejectReentry(slot);
    slot.creating = true;
    _trace.push(slot.key);
    try {
      _complete(slot, await slot.provider.create(this));
    } on Object catch (error, stackTrace) {
      slot.creating = false;
      if (error is DartnestError) rethrow;
      _failCreation(slot, error, stackTrace, _trace.snapshot.skip(1).toList());
    } finally {
      _trace.pop();
    }
  }

  /// Runs the factory with the trace pushed; marks the slot as creating.
  /// Returns the raw factory result (value or Future).
  FutureOr<Object> _invoke(_Slot slot) {
    slot.creating = true;
    _trace.push(slot.key);
    // The factory boundary wraps every failure, including `Error`s from user
    // config code, to annotate it with the chain; the cause and stack trace
    // are preserved and nothing is swallowed.
    try {
      return slot.provider.create(this);
    } on Object catch (error, stackTrace) {
      slot.creating = false;
      if (error is DartnestError) rethrow;
      _failCreation(slot, error, stackTrace, _trace.snapshot.skip(1).toList());
    } finally {
      _trace.pop();
    }
  }

  /// Rethrows with the factory's own stack trace so an uncaught crash points
  /// at the user's frame instead of this wrapper.
  Never _failCreation(
    _Slot slot,
    Object error,
    StackTrace stackTrace,
    List<Object> chain,
  ) {
    Error.throwWithStackTrace(
      ProviderCreationError(
        key: slot.key,
        moduleId: module.id,
        chain: chain,
        error: error,
        stackTrace: stackTrace,
      ),
      stackTrace,
    );
  }

  void _complete(_Slot slot, Object instance) {
    slot.instance = instance;
    slot.creating = false;
  }
}
