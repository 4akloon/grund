import 'package:grund_jaspr/client_components.dart';

import 'src/web/counter.dart';

/// The islands of the home page, shared by the server and the browser bundle.
const clients = ClientComponents([
  ClientComponent<Counter>(
    'counter',
    encode: Counter.toParams,
    decode: Counter.fromParams,
  ),
]);
