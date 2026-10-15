/// A piece of generator output destined for the file at [path].
///
/// The generator writes the kinds of this package: `LibraryUnit`s of one
/// path join into one library, `PartUnit`s of one path into one part file,
/// and a `FileUnit` is a file of its own. A construct of another package
/// builds these; a subclass the generator does not know is a programming
/// error it reports by throwing.
abstract base class GeneratedUnit {
  /// Creates the unit.
  const GeneratedUnit();

  /// The output file, relative to the package root, with `/` separators.
  String get path;
}
