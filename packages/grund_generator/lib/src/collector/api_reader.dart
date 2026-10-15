import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/api_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'hook_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads an `@Api` class into an [ApiModel].
final class ApiReader {
  /// Creates the reader.
  ApiReader(this.locations) : _routes = RouteReader(locations);

  /// Locations of declarations.
  final SourceLocations locations;

  final RouteReader _routes;

  /// The API declared by [element], whose `@Api` is [annotation].
  ApiModel read(ClassElement element, DartObject annotation) {
    final hooks = HookReader.read(annotation);
    return ApiModel(
      type: TypeReader.read(element.thisType),
      path: Annotations.field(annotation, 'path')?.toStringValue() ?? '',
      location: locations.of(element),
      use: EntryRead.values(hooks),
      routes: _routes.read(element),
      invalidEntries: EntryRead.problems(hooks),
      documentation: element.documentationComment,
    );
  }
}
