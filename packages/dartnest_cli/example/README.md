# dartnest_cli example

Create an application, generate its code and run it with hot reload:

```sh
dart run dartnest_cli init my_app     # or `dartnest init my_app` when activated
cd my_app
dart pub get
dart run dartnest_cli gen             # writes lib/my_app.dartnest.dart
dart run dartnest_cli dev             # runs bin/main.dart, reloads on every save
```

`dev` prints one line per change (timings and library counts vary):

```text
Reloaded 7 libraries in 82 ms, 0 routes changed.
Reloaded 7 libraries in 95 ms, 1 route changed.
Restarting bin/main.dart: lib/src/hello.dart changed a field, a constructor or a top-level variable.
```

- A changed method body or a new route is a hot reload: the providers keep
  their state and the route table is rebuilt.
- A changed field, constructor or top-level variable restarts the process;
  `dev` tells you which file caused it.
- A problem in the annotations is printed as
  `lib/src/hello.dart:12:3: error: ... [code]`; the application keeps
  running the previous code until the problem is fixed.

Check in CI that the committed library matches the sources:

```sh
dart run dartnest_cli gen && git diff --exit-code lib/my_app.dartnest.dart
```

The repository's `example/` directory is an application developed this
way; its README walks through a hot reload session.
