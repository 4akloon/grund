import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_io/grund_io.dart';

void main() => AdapterConformance.run('IoAdapter', (onError, closeTimeout) {
  final adapter = IoAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
