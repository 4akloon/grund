# grund_admin: адмінка в стилі Django на basalt і Jaspr — дизайн

Дата: 2026-10-16. Стан: чернетка на перегляд. Рамка:
`2026-10-15-grund-platform-design.md` (модулі, роадмап G3/G4/G7),
`2026-10-16-grund-jaspr-design.md` (G7a, SSR-зріз), ядро й HTTP:
`2026-10-15-grund-core-design.md`.

## 1. Мета й межі

Мета: публічний пакет для будь-якого застосунку на grund — адмінка в стилі
`django.contrib.admin`, яку збирають як конструктор: моделі basalt реєструються
типізованим Dart-конфігом, а поля, дії, сторінки й частини макета розширюються
компонентами Jaspr — і з самого застосунку, і зі сторонніх пакетів.

Ухвалені рішення (брейншторм 2026-10-16):

| Питання | Рішення |
|---|---|
| Для кого | Публічний пакет: стабільне API розширення, semver, документація. |
| Шар даних | Лише basalt, без власної абстракції джерела даних. |
| Опис адмінки | Типізований runtime Dart-конфіг (`ModelAdmin`), без codegen адмінки. Моделі реєструються явно. |
| Рендер | Jaspr із SSR першого екрана й гідратацією; навігація на клієнті. |
| Клієнтський бандл | Збирає застосунок користувача (`grund dev` / `grund build`): адмінка, плагіни й кастомні віджети компілюються разом. |
| Користувачі й права | Ядро не володіє користувачами — лише контракт `AdminPolicy` над `CurrentUser`; готові таблиці користувачів/ролей — окремий пакет `grund_admin_auth` (пізніше). |
| Межа сервер/клієнт | Розділена конфігурація, зв'язана типізованими ключами зі спільного web-safe коду. |

### 1.1. У зрізі v0.1

- Головна сторінка: список ресурсів, згрупованих за `group`, навігація.
- Список записів: колонки (зокрема обчислювані), сортування, пагінація, пошук,
  фільтри (bool, enum, дата, FK) і кастомні фільтри.
- Форма створення/редагування: поля за типами basalt, макет із секцій і рядків,
  readonly-поля, серверна валідація з помилками біля полів, FK з autocomplete.
- Видалення з підтвердженням.
- Bulk-дії: вбудоване масове видалення й кастомні дії.
- `AdminPolicy` на кожну дію; перевірка на рівні окремого рядка.
- Точки розширення: віджети полів, дії, фільтри, обчислювані колонки, сторінки,
  пункти меню, слоти макета, тема.
- Тема через CSS custom properties, світла й темна.

### 1.2. Поза зрізом (наступні версії)

Inlines (редагування пов'язаних записів у формі батька), M2M-віджети, журнал
змін та історія запису, віджети дашборда, попередній перегляд каскадного
видалення, експорт/імпорт CSV, поля завантаження файлів, i18n (у v0.1 рядки
англійською, але зібрані в одному місці), `grund_admin_auth`, виявлення
конфліктів одночасного редагування (у v0.1 перемагає останній запис),
автоматична реєстрація всіх моделей.

## 2. Вхідні факти (перевірено 2026-10-16)

- Плагін у grund — це `Module` (`packages/grund/lib/src/di/module.dart`);
  модуль може мати параметри (як `HttpModule(use:, middleware:, codecs:)`).
- `Injector.all<T>()` (`packages/grund/lib/src/di/injector.dart`) повертає всі
  синглтони графа підтипу `T` — так `HttpServer` збирає `HttpApi`. Цим самим
  механізмом адмінка збирає внески інших модулів.
- `HttpHook` (guard/interceptor/filter) і `c.set<T>` дають місце для перевірки
  доступу й передачі `CurrentUser`.
- basalt `generate-schema` генерує маркери `final class X extends TableRef<X>`
  зі `static const` колонками `PrimaryKey` / `Ref(references:)` / `ValueColumn`
  і `SqlType`; nullable — `NullableSqlType`. Колонки доступні в runtime через
  геттер `columns`. Ядро `basalt` не залежить від драйверів.
- У basalt немає: реєстру всіх таблиць, ознак default/unique/довжини в колонці,
  enum-типу колонки (є в `docs/grund-roadmap.md` basalt).
- `grund_jaspr` G7a — лише SSR, без гідратації; гідратація й dev-цикл
  віднесені до G7b. `grund_auth` G7a дає `CurrentUser`, сесії, `SameOriginHook`.
- `grund_basalt` (G3) ще не існує.

## 3. Пакети й потік даних

```
grund_admin            спільний, web-safe: AdminSpec, протокол API, ключі, FieldMeta
├── grund_admin_server ModelAdmin, AdminModule, AdminPolicy, JSON API, SSR-оболонка
└── grund_admin_client AdminClient, runAdmin, компоненти, реєстр віджетів, тема
grund_admin_auth       пізніше: таблиці користувачів/ролей + реалізація AdminPolicy
```

`grund_admin` не імпортує нічого, що не компілюється для web (`dart:io`,
драйвери). Від basalt він бере лише `package:basalt/basalt.dart` (маркери
таблиць і колонки), щоб колонки могли бути ключами на обох сторонах.

Потік:

1. **SSR.** `AdminModule` обслуговує `<path>/*`. На запит він перевіряє
   `AdminPolicy.canEnter`, будує `AdminSpec` для поточного користувача
   (ресурси й дії без прав `view` до нього не потрапляють), завантажує дані
   першого екрана і рендерить Jaspr-сторінку. `AdminSpec` і дані вбудовуються
   в HTML як початковий стан.
2. **Гідратація.** Клієнтський бандл застосунку підхоплює розмітку; далі
   навігація на клієнті.
3. **Дані** — JSON API `<path>/api/...` (§5.6). Кожен запит проходить
   `AdminPolicy`; запити до БД будує сервер із `ModelAdmin` через basalt.
4. **Кастомні віджети.** Сервер знає лише ключ віджета й серіалізовані
   параметри; реалізацію клієнт шукає в реєстрі `AdminClient` за ключем.

Файли в проєкті користувача:

| Файл | Платформа | Вміст |
|---|---|---|
| `lib/admin/admin.dart` | обидві | ключі віджетів, дій, сторінок; імпорти таблиць basalt |
| `lib/admin/server.dart` | сервер | `ModelAdmin`-конфіги, обробники дій і сторінок |
| `web/admin.dart` | клієнт | `runAdmin(AdminClient(...))` |

Без кастомних віджетів `web/admin.dart` — один рядок:
`void main() => runAdmin(AdminClient());`.

## 4. Типізовані ключі (спільний пакет)

Ключ — константа, що зв'язує серверне використання з клієнтською реалізацією
і несе типи:

```dart
const richText = FieldWidgetKey<String>('richText');
const publish  = ActionKey('publish');
const statsKey = PageKey<StatsData>('stats', decode: StatsData.fromJson);
```

- `FieldWidgetKey<T>` — `T` збігається з `T` колонки, тому
  `Posts.body.widget(richText)` компілюється лише для `String`-колонок.
- `PageKey<D>` несе декодер даних сторінки для клієнта; сервер кодує `D` через
  `toJson`.
- Рядковий id ключа унікальний у межах адмінки; дублікати — помилка старту
  з назвами обох джерел. Ключі вбудованих частин мають префікс `admin.`,
  зарезервований за пакетом.

## 5. Сервер

### 5.1. `ModelAdmin`

```dart
final postsAdmin = ModelAdmin<Posts>(
  Posts.table,
  label: 'Posts',
  group: 'Blog',
  display: Posts.title,
  list: ListConfig(
    columns: [Posts.title, Posts.authorId, Posts.publishedAt, wordCount],
    search: [Posts.title, Posts.body],
    filters: [BoolFilter(Posts.isPublished), RefFilter(Posts.authorId), DateFilter(Posts.publishedAt)],
    ordering: [Posts.publishedAt.desc()],
    pageSize: 50,
  ),
  form: FormLayout([
    Section('Main', [Row([Posts.title, Posts.slug]), Posts.body.widget(richText)]),
    Section('Meta', [Posts.authorId, Posts.publishedAt], collapsed: true),
  ], readonly: [Posts.createdAt]),
  scope: (q, ctx) => q.filter(Posts.tenantId.eq(ctx.user.tenantId)),
  validate: (changes, ctx) => [...],
  actions: [publish.handle((rows, ctx) async => ActionResult.message('Published ${rows.length}'))],
);

final wordCount = ComputedColumn<Posts, int>('Words', (row) => row[Posts.body].split(' ').length);
```

- `display` — колонка-підпис запису (аналог `__str__`) для FK, autocomplete,
  заголовків і підтверджень. За замовчуванням — PK.
- Значення за замовчуванням: без `list` — усі колонки, крім PK; без `form` —
  усі колонки, крім PK, з віджетами за `SqlType`. `ModelAdmin(Posts.table)` —
  робоча адмінка.
- `ListConfig.columns` приймає колонки basalt і `ComputedColumn` (лише
  сервер; значення серіалізується; не сортується й не фільтрується).
- `search` — case-insensitive `LIKE` по перелічених колонках, об'єднаних `|`.
- `scope` — обмеження вибірки для всіх операцій ресурсу (список, get, update,
  delete, дії, autocomplete): запис поза `scope` не існує для адмінки (`404`).
- `validate` повертає `List<FieldError>`; додається до автоматичних перевірок
  (обов'язковість за nullable/default, розбір типу, довжина varchar).
- Хуки: `beforeSave(changes, ctx)`, `afterSave(row, ctx)`, `beforeDelete(row, ctx)`.
  Виключення з хука переривають операцію (транзакція відкочується).
- Конфіг перевіряється на старті `AdminModule`: колонки з чужої таблиці,
  невідомі ключі, порожні `search` по нерядкових колонках — помилка старту
  з назвою ресурсу й поля.

### 5.2. Рядок

`AdminRow<Tbl>` читає значення за колонкою з повним типом:
`row[Posts.title]` → `String`. Під капотом — `RowReader` basalt. Адмінка
ніде не віддає користувачу `Map<String, dynamic>`.

### 5.3. Розширювані інтерфейси

- `AdminFilter<Tbl>`: `key`, серіалізовані `options` (для клієнта),
  `apply(query, value) → query`. Вбудовані: `BoolFilter`, `EnumFilter`,
  `DateFilter` (діапазон, «сьогодні/7 днів/місяць»), `RefFilter` (з
  autocomplete).
- `ComputedColumn<Tbl, T>`: підпис + функція від `AdminRow`.
- `AdminAction`: ключ, підпис, `confirm` (текст підтвердження або вимкнено),
  обробник `(List<AdminRow>, AdminContext) → ActionResult`
  (`message` / `error` / `redirect`). Вбудована `admin.delete`.
- `AdminPage`: ключ, підпис, пункт меню, обробник
  `(AdminContext) → D` для `PageKey<D>`; право — `AdminPermission.page(key)`.
- `AdminMenuItem`: зовнішнє посилання або посилання на сторінку.

### 5.4. `AdminContext`

Доступний у кожному callback'у: `injector`, `user` (`CurrentUser`),
`connection` (з `grund_basalt`, у транзакції запиту), `request`.

### 5.5. `AdminModule` і внески інших модулів

```dart
AdminModule(
  path: '/admin',
  policy: AdminPolicy.staffWhen((u) => u.role == 'admin'),
  resources: [postsAdmin, usersAdmin],
  pages: [AdminPage(statsKey, label: 'Stats', handler: loadStats)],
)
```

Інший модуль (сторонній плагін, `grund_admin_auth`) робить внесок,
зв'язавши `AdminResource`, `AdminPage` чи `AdminMenuItem` у своїх
`bindings`; `AdminModule` збирає їх через `Injector.all<T>()` на `onInit`.
Плагін підключається імпортом його модуля. Конфлікт: два ресурси на одну
таблицю — помилка старту з назвами обох модулів.

`AdminModule` залежить від модулів `grund_basalt`, `grund_auth` і
`grund_jaspr` через `imports`.

### 5.6. JSON API

Під `<path>/api/`, усі відповіді — JSON протоколу зі спільного пакета:

| Метод і шлях | Призначення | Право |
|---|---|---|
| `GET spec` | `AdminSpec` для користувача | `canEnter` |
| `GET r/:res?q=&f.<key>=&o=&p=` | сторінка списку + `total` | `view` |
| `GET r/:res/:id` | запис для форми | `view` (+ рядок) |
| `POST r/:res` | створити | `add` |
| `PATCH r/:res/:id` | змінити | `change` (+ рядок) |
| `DELETE r/:res/:id` | видалити | `delete` (+ рядок) |
| `POST r/:res/actions/:key` | дія над `ids` | `action(key)` (+ кожен рядок) |
| `GET r/:res/lookup?q=` | autocomplete за `display` | `view` цільового ресурсу |
| `GET p/:page` | дані сторінки | `page(key)` |

Мутації виконуються в одній транзакції basalt. Тіла форм декодуються за
`SqlType` колонки; помилка декодування — `FieldError`, не `500`.

Коди помилок: `400` — некоректний запит; `403` — немає права; `404` —
ресурс, запис чи запис поза `scope`; `422` — помилки валідації
(`{fieldErrors: [...], formErrors: [...]}`); `500` — решта, без деталей
у відповіді, з логом.

### 5.7. `AdminPolicy`

```dart
abstract interface class AdminPolicy {
  FutureOr<bool> canEnter(CurrentUser user);
  FutureOr<bool> can(CurrentUser user, AdminPermission p, AdminResource r, {AdminRow? row});
}
// AdminPermission: view | add | change | delete | action(key) | page(key)
```

- Викликається на кожен API-запит, на SSR і при побудові `AdminSpec`.
- Для `row`-перевірок політика отримує запис уже після `scope`.
- Вбудовані: `AdminPolicy.staffWhen(predicate)` (усе дозволено, якщо
  предикат істинний), `AdminPolicy.roles(roleOf: ..., grants: {...})`.
- Незалогінений користувач на SSR — редирект на URL логіну з `grund_auth`;
  у API — `401`.

## 6. Клієнт

### 6.1. Точка входу

```dart
void main() => runAdmin(AdminClient(
  widgets: [richText.render((p) => RichEditor(value: p.value, onChange: p.onChange))],
  pages:   [statsKey.render((data) => StatsPage(data))],
  slots:   [AdminSlot.header((ctx) => MyLogoHeader())],
  theme:   AdminTheme(primary: '#4f46e5', radius: '6px'),
));
```

Плагіни постачають свої реєстрації списками (`widgets: [...myPlugin.widgets]`).

### 6.2. Віджети полів

```dart
final class FieldProps<T> {
  final T value;
  final void Function(T) onChange;
  final String? error;
  final bool readonly;
  final FieldMeta meta;   // тип, nullable, label, help, enum-варіанти, maxLength
  final Object? options;  // серіалізовані параметри з .widget(key, options: ...)
}
```

Вбудовані віджети за `SqlType`: text, textarea, int, decimal, bool, date,
datetime, enum-select, FK-autocomplete, json (textarea з перевіркою JSON).
Nullable-обгортка додає «порожнє значення». Невідомий ключ віджета в
`AdminSpec` — видима помилка в місці поля з назвою ключа і підказкою
зареєструвати його в `AdminClient`, а не порожнє місце.

### 6.3. Слоти макета

Фіксований, версіонований набір: `header`, `sidebar`, `footer`, `emptyState`,
`listToolbar`, `forbidden`. Слот замінює вбудований компонент. Повна заміна
сторінок списку й форми не передбачена — для цього кастомні сторінки.

### 6.4. Маршрутизація

Спільна для SSR і клієнта, щоб розмітка гідратації збігалася:
`<path>`, `<path>/:res`, `<path>/:res/new`, `<path>/:res/:id`,
`<path>/p/:page`. Пошук, фільтри, сортування й сторінка — у query URL, тож
посилання на відфільтрований список відкривається через SSR в тому ж стані.

### 6.5. Стан і дані

Стан сторінки — у `StatefulComponent`, без глобального store. `AdminApi` —
типізований клієнт протоколу зі спільного пакета. Помилки: `422` — біля
полів; дії й мережа — toast; `403` — слот `forbidden`; `401` — редирект на
логін.

### 6.6. Тема

`AdminTheme` генерує CSS custom properties на `:root`; адмінка постачає один
готовий stylesheet без Tailwind і без збірки CSS. Темний режим —
`prefers-color-scheme` плюс перемикач (вибір у `localStorage`).

## 7. Вимоги до залежностей

Кожен пункт — вхід для окремого spec'у; реалізація знизу вгору: A → B → C → D → `grund_admin`.

### A. basalt

1. `generate-schema` генерує реєстр усіх таблиць (`const schemaTables = [...]`).
2. Метадані колонки: наявність default (поле необов'язкове при створенні),
   unique, довжина varchar, enum-тип колонки з варіантами.
3. Динамічні запити без втрати типів: вибірка довільного списку колонок;
   `set` зі значенням, перевіреним у runtime через `SqlType`; case-insensitive
   `LIKE`, однаковий для SQLite і Postgres; `count` для пагінації.
4. `package:basalt/basalt.dart` компілюється для web; smoke-перевірка
   `dart compile js` у CI.

### B. `grund_basalt` (G3)

`Connection` у DI; транзакція на запит, доступна в `AdminContext`.

### C. `grund_auth`

`CurrentUser` у контексті запиту, cookie-сесії (є в G7a); налаштовуваний URL
логіну для редиректу; захист мутацій від CSRF — щонайменше `SameOriginHook`
з G7a на `<path>/api/*`, токени — якщо G4 їх додасть.

### D. `grund_jaspr` (G7b)

SSR із гідратацією й передачею початкового стану в HTML; клієнтська збірка
в `grund dev` (з перезбиранням) і `grund build`; роздача статичних файлів із
хешованими іменами; спільний роутер для сервера й клієнта. Принцип G7a «без
збірки в проєкті користувача» лишається для проєктів без клієнтських
компонентів.

## 8. Тестування

- **Спільний пакет:** round-trip протоколу й DTO (`AdminSpec`, запити,
  помилки).
- **Сервер:** unit-тести перетворення `ModelAdmin` у запити basalt (SQL і
  параметри); інтеграційні тести JSON API на in-memory SQLite; перевірка
  конфігу на старті.
- **Табличний тест політики:** кожен ендпоінт × кожне право при забороні —
  `403`, при `scope`-фільтрі — `404`. Новий ендпоінт без рядка в таблиці
  тесту — падіння тесту.
- **Клієнт:** компонентні тести через `jaspr_test`; реєстр віджетів (знайдено,
  невідомий ключ, дублікат).
- **E2E:** приклад-застосунок у Playwright: логін → список → фільтр →
  створення → редагування → видалення → дія → гідратація кастомного віджета.
- **CI:** `dart compile js` для `grund_admin` і `grund_admin_client`.

## 9. Відкриті питання

- Точна форма API динамічних запитів basalt (A.3) визначається в spec'і A;
  тут зафіксовано лише потрібні можливості.
- Механізм клієнтської збірки (через `jaspr_builder` чи напряму
  `dart compile js`) визначається в spec'і D.
