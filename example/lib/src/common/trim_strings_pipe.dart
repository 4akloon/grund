import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

/// Trims surrounding whitespace from string arguments and from the string
/// fields of a JSON object body, before they are converted or decoded.
///
/// Pipes in `Enhancers` (or `@UsePipes`) see every argument of every
/// handler they apply to, so this one passes other values through.
@Injectable()
final class TrimStringsPipe implements Pipe<Object?, Object?> {
  @override
  Object? transform(Object? value, ArgumentMeta meta) => switch (value) {
    final String text => text.trim(),
    final Map<String, Object?> json => {
      for (final MapEntry(:key, :value) in json.entries)
        key: value is String ? value.trim() : value,
    },
    _ => value,
  };
}
