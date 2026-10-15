import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_shelf/grund_shelf.dart';

void main() => AdapterConformance.run('ShelfAdapter', (onError, closeTimeout) {
  final adapter = ShelfAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
