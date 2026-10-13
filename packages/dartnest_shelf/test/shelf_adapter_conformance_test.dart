import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';

void main() => AdapterConformance.run('ShelfAdapter', (onError, closeTimeout) {
  final adapter = ShelfAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
