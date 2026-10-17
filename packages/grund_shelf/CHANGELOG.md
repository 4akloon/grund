## 0.2.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).

## 0.1.1

- Requires `grund_http` ^0.2.0.

## 0.1.0

Initial release.

- `ShelfAdapter`: serves an application through `shelf_io`.
- `ShelfAdapterModule`: global module that binds a `ShelfAdapter` as the
  `HttpAdapter`.
- `shelfHandler(App)`: embeds a started application (`only: const {}`) in an
  existing shelf pipeline.
