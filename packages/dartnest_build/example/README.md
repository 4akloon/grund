# dartnest_build example

Generate the dartnest library with build_runner, next to other builders
such as `json_serializable`.

```yaml
# pubspec.yaml
name: shop
environment:
  sdk: ^3.8.0
dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0
dev_dependencies:
  build_runner: ^2.10.5
  dartnest_build: ^0.1.0
```

```yaml
# build.yaml
targets:
  $default:
    builders:
      dartnest_build:
        options:
          package: shop
```

```dart
// lib/src/catalog.dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The products on sale.
@Injectable()
final class Catalog {
  /// The product names.
  List<String> names() => const ['tea', 'coffee'];
}

/// `GET /products`.
@Controller('/products')
final class ProductsController {
  /// Creates the controller.
  ProductsController(this.catalog);

  /// The catalog.
  final Catalog catalog;

  /// Lists the products.
  @Get()
  List<String> list() => catalog.names();
}

/// The root module.
@Module(id: 'shop', providers: [Catalog], controllers: [ProductsController])
final class ShopModule {}
```

```sh
dart run build_runner build    # writes lib/shop.dartnest.dart with shopModule()
```

`Application.create(shopModule)` then starts the application. The output
is byte-identical to `dart run dartnest_cli gen`, so a package can switch
between the two without a diff.
