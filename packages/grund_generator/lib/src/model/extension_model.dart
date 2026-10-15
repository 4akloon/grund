/// What a construct collected from a package for itself, kept in
/// `PackageModel.extensions`.
///
/// A construct reads its own annotations into a class of its own that
/// implements this interface; the core never looks inside.
abstract interface class ExtensionModel {
  /// Whether nothing was collected, so the construct generates nothing.
  bool get isEmpty;
}
