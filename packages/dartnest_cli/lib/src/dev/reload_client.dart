import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'reload_result.dart';
import 'reload_timeouts.dart';

/// Drives the application process through its VM service: hot reload
/// followed by the `ext.dartnest.reassemble` extension, and the
/// `ext.dartnest.close` extension before a restart.
final class ReloadClient {
  ReloadClient._(this._service, this._timeouts);

  /// The extension `Application` registers to reassemble after a reload.
  static const reassembleMethod = 'ext.dartnest.reassemble';

  /// The extension `Application` registers to close before a restart.
  static const closeMethod = 'ext.dartnest.close';

  final VmService _service;
  final ReloadTimeouts _timeouts;

  /// Connects to the VM service at [serviceUri] (the `http://` URI the
  /// child printed); `null` when the child is already gone or does not
  /// answer within [ReloadTimeouts.connect].
  static Future<ReloadClient?> connect(
    Uri serviceUri, {
    ReloadTimeouts timeouts = const ReloadTimeouts(),
  }) async {
    // The banner URI ends with `/`, so `ws` resolves below its token.
    final webSocket = serviceUri.resolve('ws').replace(scheme: 'ws');
    final connecting = vmServiceConnectUri('$webSocket');
    try {
      return ReloadClient._(
        await connecting.timeout(timeouts.connect),
        timeouts,
      );
    } on SocketException {
      return null;
    } on WebSocketException {
      return null;
    } on TimeoutException {
      // A connection that completes late is not used by anyone: close it.
      unawaited(
        connecting.then((service) => service.dispose(), onError: (Object _) {}),
      );
      return null;
    }
  }

  /// Reloads the changed sources of the process, then reassembles its
  /// dartnest applications; a service that does not answer within
  /// [ReloadTimeouts.reload] is a [ReloadFailed].
  Future<ReloadResult> reload() async {
    try {
      return await _reload().timeout(_timeouts.reload);
    } on TimeoutException {
      return const ReloadFailed(
        'The VM service did not answer; the reload timed out.',
      );
    } on RPCError catch (error) {
      return ReloadFailed('The VM service failed: ${error.message}.');
    } on SentinelException catch (error) {
      return ReloadFailed('The VM service failed: $error.');
    }
  }

  Future<ReloadResult> _reload() async {
    final stopwatch = Stopwatch()..start();
    final isolates = await _isolateIds();
    final dartnest = await _isolateWith(reassembleMethod, isolates);
    final target = dartnest ?? await _isolateNamed('main', isolates);
    if (target == null) return const ReloadFailed('No isolate to reload.');
    final report = await _service.reloadSources(target);
    if (report.success != true) return _failure(report);
    final (changedRoutes, error) = dartnest == null
        ? (null, null)
        : await _reassemble(dartnest);
    return Reloaded(
      libraries: _loadedLibraries(report),
      elapsed: stopwatch.elapsed,
      changedRoutes: changedRoutes,
      reassembleError: error,
    );
  }

  /// Closes the dartnest applications of the process (they finish their
  /// requests in flight), waiting up to [ReloadTimeouts.close] for the
  /// whole exchange; any failure is left to the restart, which ends the
  /// process anyway.
  Future<void> closeApplications() async {
    try {
      await _close().timeout(_timeouts.close);
    } on RPCError {
      return;
    } on SentinelException {
      return;
    } on TimeoutException {
      return;
    }
  }

  Future<void> _close() async {
    final isolate = await _isolateWith(closeMethod, await _isolateIds());
    if (isolate == null) return;
    await _service.callServiceExtension(closeMethod, isolateId: isolate);
  }

  /// Closes the connection; a service that does not answer is dropped
  /// after [ReloadTimeouts.close].
  Future<void> dispose() =>
      _service.dispose().timeout(_timeouts.close, onTimeout: () {});

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

  Future<String?> _isolateNamed(String name, List<String> isolates) async {
    for (final id in isolates) {
      if ((await _service.getIsolate(id)).name == name) return id;
    }
    return null;
  }

  /// The changed routes, or the error, of the reassemble in [isolate]. The
  /// reload itself succeeded, so a failure here is the reassemble's.
  Future<(int?, String?)> _reassemble(String isolate) async {
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
    } on SentinelException catch (error) {
      return (null, 'The VM service failed: $error.');
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
