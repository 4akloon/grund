import 'dart:convert';
import 'dart:developer';

import 'package:meta/meta.dart';

import '../errors/grund_error.dart';
import 'app.dart';
import 'reassemble_report.dart';

/// The VM service extensions through which `grund_cli dev` drives the
/// applications of the process it runs: [reassembleMethod] after a hot
/// reload, [closeMethod] before a hot restart.
///
/// Every `App` is attached when it has started and detached when it starts
/// closing. The extensions are registered with the VM once, on the first
/// attach, and only when [isEnabled]: a product (AOT) build neither registers
/// them nor keeps any application.
abstract final class HotReloadExtension {
  /// Calls `App.reassemble` on every attached application and answers
  /// `{"applications": n, "added": [...], "removed": [...]}`.
  static const reassembleMethod = 'ext.grund.reassemble';

  /// Closes every attached application and answers `{"applications": n}`.
  static const closeMethod = 'ext.grund.close';

  /// Whether the extensions exist: the process is not a product build.
  static const isEnabled = !bool.fromEnvironment('dart.vm.product');

  static final _applications = <App>{};
  static var _registered = false;

  /// Makes [app] reachable from the extensions.
  static void attach(App app) {
    if (!isEnabled) return;
    _applications.add(app);
    if (_registered) return;
    // Set only after both calls succeeded, so a failed registration is
    // tried again by the next application.
    registerExtension(reassembleMethod, handle);
    registerExtension(closeMethod, handle);
    _registered = true;
  }

  /// Makes [app] unreachable from the extensions.
  static void detach(App app) => _applications.remove(app);

  /// Answers one call of [method]; the handler registered with the VM.
  @visibleForTesting
  static Future<ServiceExtensionResponse> handle(
    String method,
    Map<String, String> parameters,
  ) async {
    final applications = List.of(_applications);
    // Extension boundary: the module getters, factories and runners of the
    // user run inside reassemble, and their shutdown inside close. A failure
    // becomes an extension error with its message (a GrundError carries its
    // own context; anything else gets its stack trace) and `dev` prints it.
    // A failed reassemble leaves the previous state serving; a failed close
    // leaves that application closed.
    try {
      return method == closeMethod
          ? await _close(applications)
          : await _reassemble(applications);
    } on Object catch (error, stackTrace) {
      return _failure(_describe(error, stackTrace));
    }
  }

  static ServiceExtensionResponse _failure(String detail) =>
      ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        detail,
      );

  static String _describe(Object error, StackTrace stackTrace) =>
      error is GrundError ? '$error' : '$error\n$stackTrace';

  // Names the application when there are several, so the failure of one of
  // them is not mistaken for the failure of another.
  static String _named(
    int index,
    int count,
    Object error,
    StackTrace stackTrace,
  ) {
    final text = _describe(error, stackTrace);
    return count > 1 ? 'application ${index + 1} of $count: $text' : text;
  }

  static Future<ServiceExtensionResponse> _reassemble(List<App> apps) async {
    var merged = ReassembleReport.none;
    for (final (index, app) in apps.indexed) {
      final outcome = await _settle(app.reassemble());
      final failure = outcome.failure;
      if (failure != null) {
        final (error, stackTrace) = failure;
        return _failure(_named(index, apps.length, error, stackTrace));
      }
      merged = merged.merge(outcome.report ?? ReassembleReport.none);
    }
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': apps.length, ...merged.toJson()}),
    );
  }

  /// Closes every application, also when one fails, and reports all the
  /// failures in application order.
  static Future<ServiceExtensionResponse> _close(List<App> apps) async {
    final outcomes = await Future.wait([
      for (final app in apps) _settle(app.close().then((_) => null)),
    ]);
    final failures = [
      for (final (index, outcome) in outcomes.indexed)
        if (outcome.failure case (final error, final stackTrace))
          _named(index, apps.length, error, stackTrace),
    ];
    if (failures.isNotEmpty) return _failure(failures.join('\n'));
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': apps.length}),
    );
  }

  // Turns the failure of [future] into a value, so the caller sees every
  // failure instead of the first one that happens to finish.
  static Future<_Outcome> _settle(Future<ReassembleReport?> future) =>
      future.then(
        _Outcome.new,
        onError: (Object error, StackTrace stackTrace) =>
            _Outcome(null, (error, stackTrace)),
      );
}

final class _Outcome {
  _Outcome(this.report, [this.failure]);

  final ReassembleReport? report;
  final (Object, StackTrace)? failure;
}
