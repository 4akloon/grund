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
    _registered = true;
    registerExtension(reassembleMethod, handle);
    registerExtension(closeMethod, handle);
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
    // its dependency chain; anything else gets its stack trace), the
    // previous application state keeps serving and `dev` prints the error.
    try {
      return method == closeMethod
          ? await _close(applications)
          : await _reassemble(applications);
    } on Object catch (error, stackTrace) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        error is DartnestError ? '$error' : '$error\n$stackTrace',
      );
    }
  }

  static Future<ServiceExtensionResponse> _reassemble(
    List<Application> applications,
  ) async {
    final added = <String>[];
    final removed = <String>[];
    for (final application in applications) {
      final report = await application.reassemble();
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

  static Future<ServiceExtensionResponse> _close(
    List<Application> applications,
  ) async {
    await Future.wait([
      for (final application in applications) application.close(),
    ]);
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': applications.length}),
    );
  }
}
