# grund_annotations

Annotations for [grund](https://github.com/4akLoon/grund) applications. The
package has no dependencies and the annotations have no runtime behavior:
`grund_generator` (run by `grund_cli` or `grund_build`) reads them and writes
ordinary code on the explicit `grund` and `grund_http` API into
`lib/<package>.grund.dart`.

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class TasksService {
  Future<String> find(int id) async => 'task $id';
}

@Api('/tasks')
final class TasksApi {
  TasksApi(this.service);
  final TasksService service;

  @Get('/:id')
  Future<String> find(@Path() int id) => service.find(id);
}

@Module(providers: [TasksService, TasksApi])
final class TasksModule extends grund.Module with $TasksModule {
  const TasksModule();
}
```

## Annotations

- `@Module(imports, providers, exports, global)`: a module; the generator
  writes the mixin `$X` with `imports`, `bindings` and `exports`.
- `@Injectable({scope})` and `@Provides({scope})` (a `static` method of a
  module): bindings; `Scope` is `singleton`, `call` or `transient`.
  `Bind<I, C>()` binds the interface `I` to the implementation `C`.
  `@Named(name)` qualifies a binding or selects one for a parameter.
- `@Api(path, {use})`: an HTTP API class; methods annotated with `Get`,
  `Post`, `Put`, `Patch` or `Delete` (`path`, `status`, `use`) are routes.
- Route parameters: `Path`, `Query`, `Header`, `Cookie` (optional `name`) and
  `Body`; constraints `Range`, `Length`, `Pattern` and `OneOf`.

`Module` shares its name with the explicit API, so a library that uses both
imports the core with a prefix (`as grund`).
