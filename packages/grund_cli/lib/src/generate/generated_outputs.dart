import 'package:grund_generator/grund_generator.dart';

/// How the CLI recognises the files the generator wrote: a file name the
/// generator uses, and its header.
abstract final class GeneratedOutputs {
  /// Whether [path] is named like a generated file; a file of that name
  /// may still be hand-written, [hasHeader] decides.
  static bool hasGeneratedName(String path) =>
      path.endsWith(GeneratedNames.outputSuffix);

  /// Whether [content] starts with the header of the generator.
  static bool hasHeader(String content) =>
      content.startsWith(LibraryWriter.header);
}
