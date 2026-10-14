import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'reload_result.dart';

/// Drives the application process through its VM service: hot reload
/// followed by the `ext.dartnest.reassemble` extension, and the
/// `ext.dartnest.close` extension before a restart.
final class ReloadClient {
  ReloadClient._(this._service);

  /// The extension `Application` registers to reassemble after a reload.
  static const reassembleMethod = 'ext.dartnest.reassemble';

  /// The extension `Application` registers to close before a restart.
  static const closeMethod = 'ext.dartnest.close';

  final VmService _service;

  /// Connects to the VM service at [serviceUri] (the `http://` URI the
  /// child printed); `null` when the child is already gone.
  static Future<ReloadClient?> connect(Uri serviceUri) async {
    final webSocket = serviceUri.resolve('ws').replace(scheme: 'ws');
    try {
      return ReloadClient._(await vmServiceConnectUri('$webSocket'));
    } on SocketException {
      return null;
    } on WebSocketException {
      return null;
    }
  }

  /// Reloads the changed sources of the process, then reassembles its
  /// dartnest applications.
  Future<ReloadResult> reload() async {
    final stopwatch = Stopwatch()..start();
    try {
      final isolates = await _isolateIds();
      if (isolates.isEmpty) return const ReloadFailed('No isolate to reload.');
      final report = await _service.reloadSources(isolates.first);
      if (report.success != true) return _failure(report);
      final (changedRoutes, error) = await _reassemble(isolates);
      return Reloaded(
        libraries: _loadedLibraries(report),
        elapsed: stopwatch.elapsed,
        changedRoutes: changedRoutes,
        reassembleError: error,
      );
    } on RPCError catch (error) {
      return ReloadFailed('The VM service failed: ${error.message}.');
    } on SentinelException catch (error) {
      return ReloadFailed('The VM service failed: $error.');
    }
  }

  /// Closes the dartnest applications of the process (they finish their
  /// requests in flight), waiting up to [timeout]; any failure is left to
  /// the restart, which ends the process anyway.
  Future<void> closeApplications({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final isolate = await _isolateWith(closeMethod, await _isolateIds());
      if (isolate == null) return;
      await _service
          .callServiceExtension(closeMethod, isolateId: isolate)
          .timeout(timeout);
    } on RPCError {
      return;
    } on SentinelException {
      return;
    } on TimeoutException {
      return;
    }
  }

  /// Closes the connection.
  Future<void> dispose() => _service.dispose();

  Future<List<String>> _isolateIds() async => [
    for (final isolate in (await _service.getVM()).isolates ?? <IsolateRef>[])
      if (isolate.id case final id?) id,
  ];

  Future<String?> _isolateWith(String method, List<String> isolates) async {
    for (final id in isolates) {
      final isolate = await _service.getIsolate(id);
      if (isolate.extensionRPCs?.contains(method) ?? false) return id;
    }
    return null;
  }

  /// The changed routes, or the error, of the reassemble; `(null, null)`
  /// when no isolate has a dartnest application.
  Future<(int?, String?)> _reassemble(List<String> isolates) async {
    final isolate = await _isolateWith(reassembleMethod, isolates);
    if (isolate == null) return (null, null);
    try {
      final response = await _service.callServiceExtension(
        reassembleMethod,
        isolateId: isolate,
      );
      return switch (response.json) {
        {
          'addedRoutes': final List<Object?> added,
          'removedRoutes': final List<Object?> removed,
        } =>
          (added.length + removed.length, null),
        _ => (0, null),
      };
    } on RPCError catch (error) {
      return (null, error.details ?? error.message);
    }
  }

  static int _loadedLibraries(ReloadReport report) =>
      switch (report.json?['details']) {
        {'loadedLibraryCount': final int count} => count,
        _ => 0,
      };

  /// A failed reload: notices of type `ReasonForCancellingReload` are
  /// limitations of hot reload, any other notice is a compile error.
  static ReloadResult _failure(ReloadReport report) {
    final notices = switch (report.json?['notices']) {
      final List<Object?> list => list.whereType<Map<String, Object?>>(),
      _ => const <Map<String, Object?>>[],
    };
    final message = [
      for (final notice in notices)
        if (notice['message'] case final String text) text,
    ].join('\n');
    final isLimitation = notices.any(
      (notice) => notice['type'] == 'ReasonForCancellingReload',
    );
    return isLimitation ? ReloadRejected(message) : ReloadFailed(message);
  }
}
