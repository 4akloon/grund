## 0.1.0

Initial release.

- `PackageCollector` and `GrundGenerator.core()`: turn the annotations of
  a package into one `X_module.g.dart` per source library with modules
  (a `mixin $X on Module` per module) on the explicit API, with
  static validation of the module graph and diagnostics with a location and
  a code.
- Deterministic, formatted output; custom `Construct`s.
- The emitters (`BindingEmitter`, `ConstantEmitter`, `TypeEmitter`,
  `DartString`, `CoreReferences`, `OverrideGetter`) are public for
  constructs of other packages; a `PartUnit` must belong to a source
  library of the package (`PackageModel.libraryPaths`) or to another
  generated file.
