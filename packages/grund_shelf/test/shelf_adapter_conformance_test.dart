import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_shelf/grund_shelf.dart';

void main() => AdapterConformance.run(
  'ShelfAdapter',
  (onError, closeTimeout) => AdapterUnderTest.of<ShelfAdapter>(
    ShelfAdapterModule(onError: onError, closeTimeout: closeTimeout),
    port: (adapter) => adapter.port,
  ),
);
