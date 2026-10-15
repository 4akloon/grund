/// Serves grund applications through shelf: [ShelfAdapter] runs a
/// server, [ShelfAdapterModule] provides it to an application and
/// [shelfHandler] embeds an application in an existing shelf pipeline.
library;

export 'src/shelf_adapter.dart';
export 'src/shelf_adapter_module.dart';
export 'src/shelf_handler.dart';
