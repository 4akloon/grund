## 0.1.0

Initial release.

- `ShelfAdapter`: serves an application through `shelf_io`.
- `ShelfAdapterModule`: global module that binds a `ShelfAdapter` as the `HttpAdapter`.
- `shelfHandler(App)`: embeds a started application (`only: const {}`) in an existing shelf pipeline.
