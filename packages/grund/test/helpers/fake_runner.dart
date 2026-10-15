import 'package:grund/grund.dart';

/// A runner that records what is done to it.
base class FakeRunner extends Runner {
  FakeRunner(
    this.name,
    this.log, {
    this.prepareFailure,
    this.startFailure,
    this.stopFailure,
    this.reassembleReport = ReassembleReport.none,
  });

  @override
  final String name;

  final List<String> log;
  final Object? prepareFailure;
  final Object? startFailure;
  final Object? stopFailure;
  final ReassembleReport reassembleReport;

  /// How often [reassemble] ran.
  int reassembled = 0;

  @override
  Future<void> prepare(Injector injector) async {
    log.add('prepare $name');
    if (prepareFailure case final failure?) throw failure;
  }

  @override
  Future<void> start(Injector injector) async {
    log.add('start $name');
    if (startFailure case final failure?) throw failure;
  }

  @override
  Future<void> stop() async {
    log.add('stop $name');
    if (stopFailure case final failure?) throw failure;
  }

  @override
  Future<ReassembleReport> reassemble(Injector injector) async {
    log.add('reassemble $name');
    reassembled++;
    return reassembleReport;
  }
}

/// The binding of [runner] under its own name, so `all<Runner>()` finds it.
Binding<Object> runnerBinding(FakeRunner runner) => Singleton<FakeRunner>(
  (i) => runner,
  name: runner.name,
  dependsOn: const [],
);
