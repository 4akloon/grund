/// Why a parameter cannot be filled.
enum InvalidSourceReason {
  /// No `@Path`, `@Query`, ... and not a call scope class.
  missing,

  /// More than one of `@Path`, `@Query`, `@Header`, `@Cookie` and `@Body`.
  ambiguous,

  /// The parameter type is not one the annotation supports.
  unsupportedType,
}
