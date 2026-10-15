# Example

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class HelloService {
  String greet(String name) => 'Hello, $name!';
}

@Api('/hello')
final class HelloApi {
  HelloApi(this.service);
  final HelloService service;

  @Get('/:name')
  String hello(@Path() String name) => service.greet(name);
}

@Module(providers: [HelloService, HelloApi])
final class AppModule extends grund.Module with $AppModule {
  const AppModule();
}
```

Run `dart run grund_cli gen` to write `lib/<package>.grund.dart`, which
defines `$AppModule`.
