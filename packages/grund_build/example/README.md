# grund_build example

Generate the grund files with build_runner, next to other builders
such as `json_serializable`.

```yaml
# pubspec.yaml
name: shop
environment:
  sdk: ^3.13.0
dependencies:
  grund: ^0.1.0
  grund_http: ^0.2.0
dev_dependencies:
  build_runner: ^2.16.0
  grund_build: ^0.1.0
```

No `build.yaml` is needed.

```dart
// lib/src/catalog.dart
import 'package:grund/annotations.dart';
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'catalog.g.dart';

/// The products on sale.
@Injectable()
final class Catalog {
  /// The product names.
  List<String> names() => const ['tea', 'coffee'];
}

/// `GET /products`.
@Api('/products')
final class ProductsApi {
  /// Creates the API.
  ProductsApi(this.catalog);

  /// The catalog.
  final Catalog catalog;

  /// Lists the products.
  @Get('/')
  List<String> list() => catalog.names();
}
```

```dart
// lib/src/shop_module.dart
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'catalog.dart';
import 'shop_module.g.dart';

/// The root module.
@Module(providers: [Catalog, ProductsApi])
final class ShopModule extends grund.Module with $ShopModule {
  /// Creates the module.
  const ShopModule();
}
```

```sh
dart run build_runner build
# writes lib/src/catalog.g.dart (the part of catalog.dart) and
# lib/src/shop_module.g.dart (the mixin $ShopModule)
```

The output is byte-identical to `dart run grund_cli gen`, so a package can
switch between the two without a diff.
