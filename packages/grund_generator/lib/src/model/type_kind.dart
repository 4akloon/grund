/// What kind of Dart type a `TypeModel` describes.
enum TypeKind {
  /// A class, mixin or other interface type.
  interface,

  /// An enum type.
  enumeration,

  /// `void`.
  voidType,

  /// `dynamic`.
  dynamicType,

  /// A function, record, type parameter or other type the generator does
  /// not reference by name.
  unsupported,
}
