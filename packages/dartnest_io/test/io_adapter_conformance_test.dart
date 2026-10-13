import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_io/dartnest_io.dart';

void main() => AdapterConformance.run('IoAdapter', (onError, closeTimeout) {
  final adapter = IoAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
