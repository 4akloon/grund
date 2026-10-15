import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_io/grund_io.dart';

void main() => AdapterConformance.run(
  'IoAdapter',
  (onError, closeTimeout) => AdapterUnderTest.of<IoAdapter>(
    IoAdapterModule(onError: onError, closeTimeout: closeTimeout),
    port: (adapter) => adapter.port,
  ),
);
