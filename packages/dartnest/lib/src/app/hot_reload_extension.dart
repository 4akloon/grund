import 'dart:convert';
import 'dart:developer';

import 'package:meta/meta.dart';

import '../di/errors.dart';
import 'application.dart';
import 'reassemble_report.dart';

/// The VM service extensions through which `dartnest_cli dev` drives the
/// applications of the process it runs: [reassembleMethod] after a hot
/// reload, [closeMethod] before a hot restart.
///
/// Every `Application` is attached when it is created and detached when it
/// starts closing. The extensions are registered with the VM once, on the
/// first attach, and only when [isEnabled]: a product (AOT) build neither
/// registers them nor keeps any application.
abstract final class HotReloadExtension {
  /// Calls `Application.reassemble` on every attached application and
  /// answers `{"applications": n, "addedRoutes": [...], "removedRoutes":
  /// [...]}`.
  static const reassembleMethod = 'ext.dartnest.reassemble';

  /// Closes every attached application and answers `{"applications": n}`.
  static const closeMethod = 'ext.dartnest.close';

  /// Whether the extensions exist: the process is not a product build.
  static const isEnabled = !bool.fromEnvironment('dart.vm.product');

  static final _applications = <Application>{};
  static var _registered = false;

  /// Makes [application] reachable from the extensions.
  static void attach(Application application) {
    if (!isEnabled) return;
    _applications.add(application);
    if (_registered) return;
    // Set only after both calls succeeded, so a failed registration is
    // tried again by the next application.
    registerExtension(reassembleMethod, handle);
    registerExtension(closeMethod, handle);
    _registered = true;
  }

  /// Makes [application] unreachable from the extensions.
  static void detach(Application application) =>
      _applications.remove(application);

  /// Answers one call of [method]; the handler registered with the VM.
  @visibleForTesting
  static Future<ServiceExtensionResponse> handle(
    String method,
    Map<String, String> parameters,
  ) async {
    final applications = List.of(_applications);
    // Extension boundary: the module functions and provider factories of
    // the user run inside reassemble, and adapters inside close. A failure
    // becomes an extension error with its message (a DartnestError carries
    // its dependency chain; anything else gets its stack trace) and `dev`
    // prints it. A failed reassemble leaves the previous state serving; a
    // failed close leaves that application closed.
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
      error is DartnestError ? '$error' : '$error\n$stackTrace';

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

  static Future<ServiceExtensionResponse> _reassemble(
    List<Application> applications,
  ) async {
    final added = <String>[];
    final removed = <String>[];
    for (final (index, application) in applications.indexed) {
      final outcome = await _settle(application.reassemble());
      final failure = outcome.failure;
      if (failure != null) {
        final (error, stackTrace) = failure;
        return _failure(_named(index, applications.length, error, stackTrace));
      }
      final report = outcome.report;
      if (report == null) continue;
      added.addAll(report.addedRoutes);
      removed.addAll(report.removedRoutes);
    }
    final report = ReassembleReport(
      addedRoutes: added..sort(),
      removedRoutes: removed..sort(),
    );
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': applications.length, ...report.toJson()}),
    );
  }

  /// Closes every application, also when one fails, and reports all the
  /// failures in application order.
  static Future<ServiceExtensionResponse> _close(
    List<Application> applications,
  ) async {
    final outcomes = await Future.wait([
      for (final application in applications)
        _settle(application.close().then((_) => null)),
    ]);
    final failures = [
      for (final (index, outcome) in outcomes.indexed)
        if (outcome.failure case (final error, final stackTrace))
          _named(index, applications.length, error, stackTrace),
    ];
    if (failures.isNotEmpty) return _failure(failures.join('\n'));
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': applications.length}),
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
