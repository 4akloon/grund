import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_io/dartnest_io.dart';

void main() => AdapterConformance.run('IoAdapter', (_, _) {
  final adapter = IoAdapter();
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
