// A private hook class and a public constant of it, used by another library.
import 'package:grund_http/grund_http.dart';

final class _PrivHook extends HttpHook {
  const _PrivHook();
}

/// A public constant whose class is private.
const privHook = _PrivHook();
