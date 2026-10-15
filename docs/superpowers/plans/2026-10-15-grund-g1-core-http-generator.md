# grund G1: ядро, HTTP і генератор — план реалізації

> **Для виконавців-агентів:** ОБОВ'ЯЗКОВИЙ піднавик: `superpowers:subagent-driven-development` (рекомендовано) або `superpowers:executing-plans`. Кроки мають чекбокси (`- [ ]`) для відстеження.

**Мета:** Переписати публічний API dartnest на модель grund: модулі як основа, явні bindings, HTTP винесений у `grund_http`, генератор на новій моделі, приклад `tasks_api` у двох формах на обох адаптерах.

**Архітектура:** Ядро (`grund`) знає лише модулі, bindings (`Singleton`/`Scoped`/`Transient`), інжектор, lifecycle і `Runner`; нічого про HTTP. `grund_http` будує класи `@Api` у `HttpApi`-підкласи, одним `HttpHook` замінює Guard/Interceptor/Pipe/ExceptionFilter і віддає помилки як RFC 9457. Адаптери (`IoAdapterModule`, `ShelfAdapterModule`) — звичайні глобальні модулі. Генератор читає анотації й емітить рівно ту явну форму, яку можна написати руками.

**Стек:** Dart `^3.8.0` (pub workspace), `package:meta`, `analyzer`/`code_builder`/`dart_style` лише в генераторі, `build` лише в `grund_build`, `shelf` лише в `grund_shelf`.

**Spec:** `docs/superpowers/specs/2026-10-15-grund-core-design.md` (етап G1), рамка `docs/superpowers/specs/2026-10-15-grund-platform-design.md`. Старий spec `2026-10-13-dartnest-design.md` чинний лише там, де новий на нього посилається (адаптери, помилки ядра, hot reload, тестування).

**Як цей план перевірено.** Код у задачах не вигаданий: ядро (задачі 2–6) і `grund_http` (7–11) прототипувалися в scratch-пакетах і пройшли `dart analyze` та тести (ядро 166 тестів, `grund_http` 206); адаптери, conformance і приклад (12, 20) перевірені проти цих прототипів; анотації й генератор (13–18) реалізовані в копії репозиторію (згенерований `users_app.grund.dart` компілюється й проходить e2e). Блоки «файл цілком» вставлені скриптом із перевіреного коду. **Не перевірялося** (див. кінцеві розділи «Не перевірено»): повний прогін плану «з нуля» одним проходом (кожна частина перевірена окремо, на копіях), CI на Dart 3.8.0 (локально 3.11), `grund_cli`/`grund_build`/інтеграційні тести (задача 19: залежать від генератора), документація (задача 21). Тож виконавець чекає на невеликі розбіжності на стиках частин і виправляє їх у межах своєї задачі.

---

## Глобальні обмеження

Кожна задача неявно містить цей розділ. Значення скопійовано з `CLAUDE.md` репозиторію та зі spec.

- Мова: код, `///`-коментарі, діагностики, README, CHANGELOG, повідомлення комітів — **англійською**. Документи в `docs/superpowers/` (цей план) — українською. Користувачеві (в чаті) — лише українською.
- SDK: `^3.8.0`, Dart 3.8-фічі (patterns, switch-вирази, records, `final`/`sealed`/`interface`/`base`, extension types). **Не** використовувати dot shorthands і null-aware elements (Dart 3.10). Primary constructors не використовувати.
- Залежності ядра: пакет `grund` залежить лише від Dart SDK і `package:meta`. `dart:io` у ядрі — лише `ProcessSignal` (сигнали зупинки); сервера немає. `dart:developer` — лише для hot reload (`registerExtension`, поза product-режимом). `analyzer` — лише `grund_generator`/`grund_cli`/`grund_build`; `vm_service` — лише `grund_cli`; `build` — лише `grund_build`; `shelf` — лише `grund_shelf`. `grund_annotations` — без залежностей.
- Ліміти: файл у `lib/` ≤ 300 рядків (`wc -l`), тестовий файл ≤ 500, метод ≤ 40, параметрів ≤ 5 (далі — об'єкт параметрів), вкладеність ≤ 3 рівнів `if/for/switch/try`, клас ~15 членів і одна відповідальність, один публічний клас (або sealed-родина) на файл. **Перед тим як писати: `wc -l` файла, який розширюєш; якщо після зміни буде понад ліміт — спершу виділити (окремий коміт), потім додати.** (`main()` тестових файлів із багатьма `group`/`test` звільнені від ліміту методу, як і в наявних тестах репозиторію.)
- Декомпозиція — композицією (колаборатори в окремих файлах). `part`/`part of`, міксини лише для розтягування класу, файли `utils`/`helpers`/`common` — не декомпозиція. Клас, зроблений публічним лише щоб вийти з файла, не потрапляє в barrel (`show`-списки).
- Класи, не голі функції, у `lib/src`; константи — у класі, якому належать. Винятки: `main`; функції, яких вимагає build.yaml (`grundBuilder`).
- Кожен публічний член має `///` (`public_member_api_docs` у всіх опублікованих пакетах; перший рядок — одне речення; булеві починаються з «Whether»; `[ідентифікатори]` у квадратних дужках; без `@param`). Жодних `// ignore:` без коментаря-причини; жодного правила не прибирати з `analysis_options.yaml`.
- Помилки: типізовані (`GrundError`-підкласи) або діагностики генератора зі стабільним кодом і `path:line:col`. Ніякого `catch` без `on`; `Error` не ловити (крім названих точних підтипів). Єдині дозволені `on Object` — межі, де виконується код користувача; кожна має коментар з назвою межі й ніколи не ковтає помилку мовчки (перелік меж — у задачі 21, оновлення `CLAUDE.md`).
- Без `dynamic`; без `!`, де можна патерн/ранній return; `late` лише з коментарем; позиційних `bool`-параметрів немає; назви без `2`/`Impl`/`Helper`/`Manager`.
- Тести йдуть **в тому самому коміті**, що й код; нова гілка логіки має тест, який без неї падає. Тести не ходять у мережу; HTTP-тести — ефемерні порти на loopback; тимчасові файли — лише через `TempDir`. `grund_cli`-тести працюють in-process (`CliRun`), `dev` — виняток (дочірній процес). Фікстури генератора (`packages/grund_generator/test/fixtures/*`) — непубліковані члени workspace; `users_app.grund.dart` — golden, генерується й коміситься, руками не редагується.
- Детермінований генератор: однакові джерела → побайтово однакові файли; усе сортується; рядки з джерел екранувати `DartString.literal`.
- Коміти — Conventional Commits (`feat(core): …`, `refactor(http): …`, `test(…)`, `docs: …`), англійською; **до кожного повідомлення додавати рядок атрибуції, який дає харнес** (`Co-Authored-By: …`). Не пушити, не публікувати, не міняти нічого поза `~/projects/grund`.
- Перевірка кожної задачі (до коміту): `dart analyze` (для пакета/пакетів задачі) без жодного повідомлення; `dart test` пакета зелений; `dart format packages example` змінює 0 файлів; `wc -l` усіх змінених файлів у межах лімітів.
- Dart: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"` (кожен виклик `Bash` стартує з чистою оболонкою — додавати на початку команди).

## Рішення, ухвалені цим планом (відхилення від ілюстративних фрагментів spec)

Фрагменти коду в spec — ілюстрація; там, де вони не компілюються або двозначні, план фіксує таке (перевірено компіляцією у прототипах). Нічого з «заборонених змін» (список рішень у завданні) це не змінює.

1. **`Singleton<T>(…)` завжди з явним `T`.** У контексті `List<Binding>` Dart виводить `Singleton<Object>`, тож конструктор кидає `ArgumentError` при `T == Object`; генератор завжди емітить `Singleton<Тип>`. `dependsOn` обов'язковий (`List<Key<Object>>`; `strict-raw-types` забороняє голі `Key`/`Binding`, тому `List<Binding<Object>>` і `List<Key<Object>>`); `Singleton.factory(create, {name})` — escape hatch для сторонніх типів: `dependsOn == null` («невідомо», перевіряється при резолвленні).
2. **Читачі параметрів не можуть мати метод `int`** (клас з членом `int` ламає тип `int` у власному тілі). Імена: `string`, `integer`, `decimal`, `boolean`, `dateTime`, `uri`, `enumOf`, кожен з варіантом `…OrNull`; обмеження `@Range/@Length/@Pattern/@OneOf` — named-аргументи читачів (`min`, `max`, `minLength`, `maxLength`, `pattern`, `oneOf`).
3. **Анотація `@Module` і базовий клас `Module` мають однакове ім'я**, тож у файлі модуля ядро імпортується з префіксом: `import 'package:grund/grund.dart' as grund;` + `extends grund.Module with $X`; анотації — без префікса. Замінює правило `hide Controller, Module`.
4. **Клас модуля з `with` не має const-конструктора за замовчуванням.** Користувач оголошує `const X();`, генератор емітить екземпляри модулів в `imports` як non-const (`X()`).
5. **`HookRef<T extends HttpHook>`** — generic-клас (`HookRef<ApiKeyHook>.type()`, `HookRef<RolesHook>.instance(const RolesHook(…))`): конструктори не мають type-параметрів, а `Type`-значення без mirrors не резолвиться з графа.
6. **`Runner`** — абстрактний клас (spec: інтерфейс) з методами за замовчуванням: `prepare(Injector)` (валідація й побудова структур; `App.start()` викликає в усіх раннерів — звідси fail-fast навіть без `listen`) і `reassemble(Injector)` → `ReassembleReport` (за замовчуванням `stop → prepare → start`; `HttpServer` перевизначає атомарною підміною таблиці роутів). `ReassembleReport` — `added`/`removed` (не «routes»): ядро не знає слів HTTP; JSON-ключі `added`/`removed` (раніше `addedRoutes`/`removedRoutes` — клієнт `dev` оновлюється в задачі 19).
7. **`Injector`** має `all<T>()` (усі singleton-и графа з binding-ом-підтипом `T`, видимість не застосовується — так транспорти збирають внески) і `openCall()` (call-скоуп для модуля цього інжектора). `Container.all<T>()` з spec делегує йому.
8. **Глобальний модуль** (`global == true`) видимий усім **через свої `exports`**, а не через усі bindings.
9. **«Незмінні фабрики» при hot reload** = той самий модуль (identity) + той самий ключ: ідентичність замикання між перезавантаженнями неспостережна. Зміна тіла фабрики застосовується після рестарту. Видалені модулі/singleton-и при reassemble не зупиняються (лише dev).
10. **Root-модуль — екземпляр** (`App(root: AppModule())`): після hot reload getter-и екземпляра виконують нові тіла.
11. **`@Injectable({scope})`** (додано до spec): `Scope.singleton` / `Scope.call` / `Scope.transient`. У `exports` анотації можна писати `const Key<T>('name')`. `Module.exports` у ядрі — `List<Object>` (ключі або модулі для реекспорту), а не `List<Key>` зі spec.
12. **`HttpHook.onError`** повертає `HttpResponse?`; `Middleware` — `abstract interface class` з методом `handle(request, next)` (`Next` без аргументів); `HttpModule(config:)` + `App(overrides:)` — рантайм-конфігурація; адаптерні модулі `global: true` і експортують `Key<HttpAdapter>`; `shelfHandler(App)` вимагає `ShelfAdapterModule` у графі.
13. **`HttpApi(injector)`**: API-клас отримує інжектор модуля, що його оголошує; через нього відкриваються call-скоупи й резолвляться хуки-типи (глобальні хуки з `HttpModule(use:)` — теж у скоупі модуля API). `HttpServer(HttpModule, {adapter, config, log})` бере `use`/`middleware`/`codecs` з модуля, тому вони змінюються лише рестартом.
14. **Асинхронними можуть бути лише `Singleton`-и.** `@Provides(scope: Scope.call)` з `Future<T>` генератор відхиляє діагностикою `invalid_provides`; `Future<T>` у singleton емітиться без `Singleton.factory`.
15. **Overrides потребують точного `Key`** (явний type-аргумент); `onInit` модулів виконується після створення всіх singleton-ів; `CallScope.set<T>` реєструє значення під статичним `T`.
16. **`TestApp.start(root:, overrides:)`** стартує з `only: const {}`: раннери підготовлені (роути збудовані, конфлікти виявлені), але не слухають порт; `TestClient.of(TestApp)` бере `HttpServer` з графа.
17. **Помилка читання тіла** (`fromJson` кинув `FormatException` або `TypeError`) → 400 `body_invalid` (точні підтипи, меж-запис у `CLAUDE.md`). `HttpServer.stop` після `adapter.close` чекає in-flight і скасовує `CancelSignal` залишкових контекстів.
18. **`ErrorLogger` (typedef колбека `onError` адаптерів) лишається в `grund_http`** (створюється в задачі 1, не видаляється); `ErrorLog` (задача 7) — окремий binding для логування помилок запиту, а не заміна.

## Робоча гілка і «червоне вікно»

Гілка: `grund-g1` від `grund-rename` (`git switch -c grund-g1 grund-rename`; **не** від `master`: перейменування туди ще не влито). Після виконання `grund-g1` зливається в `master` разом із `grund-rename` (порядок і злиття — рішення користувача).

Переписування ядра неможливо зробити так, щоб увесь workspace був зеленим після кожного коміту. Тому кожна задача перевіряється **по своїх пакетах**. Стан дерева (задачі 1–6 зняті фактично у копії репозиторію; далі — за послідовністю задач):

| Після задачі | Зелені пакети | Червоні (очікувано) |
|---|---|---|
| 1 | `grund` (старий DI, 80 тестів), `grund_http` (69), `grund_annotations` (6) | `grund_io`, `grund_shelf`, `grund_conformance`, `grund_generator` (+фікстури), `grund_cli`, `grund_build`, `example` |
| 2–5 | те саме (новий DI живе поряд, старий — в `legacy_di`); `grund` 109 → 130 → 144 → 189 | те саме |
| 6 | `grund` (нове ядро, 166), `grund_http` (69), `grund_annotations` | решта |
| 7–11 | + `grund_http` зростає до 206 тестів | `grund_io`, `grund_shelf`, `grund_conformance`, генератор, cli, build, example |
| 12 | + `grund_io`, `grund_shelf`, `grund_conformance` | генератор, cli, build, example |
| 13 | + `grund_annotations` (новий набір) | генератор і далі |
| 14–18 | + `grund_generator` (+ фікстури) | cli, build, example |
| 19 | + `grund_cli`, `grund_build` | example |
| 20–21 | **весь workspace**: `dart analyze` з кореня — «No issues found!», усі тести зелені | — |

Червоні пакети задачею не чіпаються, крім тих, що є її предметом. Корінь-перевірка (`dart analyze` у `~/projects/grund`) стає обов'язковою лише з задачі 20. Старий код доступний для порівняння: `git show 71a4726:<шлях>` (HEAD гілки `grund-rename`).

## Структура файлів (підсумок)

Повні списки файлів — у блоках **Files** кожної задачі.

- **`packages/grund` (ядро)** — `lib/src/`: `errors/` (родини помилок), `di/` (ключі, bindings, модулі, граф, валідація, runtime, контейнер, call-скоупи), `call/` (`CallContext`, `CancelSignal`), `app/` (`App`, `Runner`, `RunnerSet`, `Runners`, `StopSignals`, hot reload), `testing/` (`TestApp`); barrels `lib/grund.dart`, `lib/testing.dart`; (тимчасово, задачі 2–5) `legacy_di/`.
- **`packages/grund_http`** (новий) — `lib/src/`: `http/` (значення запиту/відповіді, `HttpException`, `Problem`), `routing/`, `adapter/`, `ctx/` (`HttpCtx`, `Params`), `hook/`, `api/` (`HttpApi`, `Route`), `server/` (`HttpServer`, `HttpModule`, `HttpConfig`, таблиця роутів, диспетчер), `serialize/`, `testing/` (`TestClient`, `TestResponse`).
- **`packages/grund_annotations`** — нові анотації; видаляються `Controller`, `Param`, `Inject`, `Value`, `RouteMetadata`, `UseGuards…`.
- **`packages/grund_generator`** — переписуються `model/`, `collector/`, `constructs/`, `emit/`; лишаються каркас `construct/`, `diagnostic/`, `LibraryWriter`, `ImportAllocator`, `DartString`, `ConstantReader` (з доповненнями).
- **Решта** — `grund_io`/`grund_shelf` (модулі адаптерів), `grund_conformance`, `grund_cli`/`grund_build`, `example/`, документація.

## Нумерація задач

| № | Задача |
|---|---|
| 1 | Виокремити `grund_http`, вирізати HTTP з ядра (механічно) |
| 2 | `Key`, `Binding`, `Injector`, `Disposable`, помилки |
| 3 | `Module`, ідентичність, колектор, `ModuleGraph`, видимість |
| 4 | Валідатор залежностей, `CreationPlan` |
| 5 | `Container`: старт, call-скоупи, lifecycle, reassemble, `CallContext` |
| 6 | `App`, `Runner`, hot reload, `TestApp`; перемикання barrel |
| 7–11 | `grund_http`: помилки RFC 9457, `Params`/`HttpCtx`, хуки, `HttpApi`/роутинг/диспетчер, `HttpServer`/`HttpModule`/`TestClient` |
| 12 | Адаптери `IoAdapterModule`/`ShelfAdapterModule`, `shelfHandler`, conformance |
| 13–18 | Анотації; генератор: модель/колектор, перевірки, емісія модулів, емісія `HttpApi`, golden |
| 19 | `grund_cli` і `grund_build` |
| 20 | Приклад `tasks_api` |
| 21 | Документація, `CLAUDE.md`, CHANGELOG, фінальна перевірка |

## Review Focus

Класи входів і відмов, які spec мовчки припускає, але жодна функціональна задача явно не описує. Кожен рядок має тест у задачі-власнику (позначено «RF-n» у коді тестів; перелік тестів — у кінцевих розділах «Review Focus» частин).

1. **RF-1 · Відмова хука посеред ланцюга.** Хук №2 кидає у `before` → `after` не викликається ні в кого, `onError` у зворотному порядку, перший не-null результат відповідає; без жодного — `HttpException` дає свій статус, решта — 500 `problem+json` без внутрішніх деталей. (Задачі 9, 10, 20.)
2. **RF-2 · Ізоляція call-скоупу.** Паралельні запити не бачать значень один одного (`c.set`), `Scoped`-інстанси створюються по одному на виклик і `dispose()`-яться після запиту навіть коли handler кинув. (Задачі 5, 11.)
3. **RF-3 · Погані вхідні дані → 4xx, не 500.** Зламаний JSON, JSON не-об'єкт, відсутнє поле, невалідне число/enum/дата в path/query, надто велике тіло (413), неіснуючий шлях (404 `problem+json`), метод не дозволено (405 + `Allow`), зайві слеші/percent-encoding. (Задачі 7, 8, 10, 18.)
4. **RF-4 · Збої старту й `--only`.** Невідоме ім'я в `--only` → помилка **до** старту будь-якого раннера; раннер, що впав на `start`, відкочує вже запущені; відсутній `HttpAdapter` → `MissingProviderError`; конфлікт роутів ловиться в `App.start()` без `listen`. (Задачі 6, 11, 12.)
5. **RF-5 · Зупинка під навантаженням.** `close()` під час in-flight запитів чекає їх, другий `close()` ідемпотентний, помилки `onShutdown`/`dispose` збираються в `ShutdownError` і не зупиняють решту кроків. (Задачі 5, 6, 11, 12.)

## Попередній крок (виконує контролер, не імплементер)

- [ ] **Створити гілку і зафіксувати базу**

```bash
cd ~/projects/grund
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
git status --short            # має бути порожньо
git switch -c grund-g1 grund-rename
dart pub get
dart analyze                  # No issues found!
for d in packages/*/ example/; do (cd "$d" && dart test 2>&1 | tail -1); done
```

Очікувано: аналізатор чистий, у кожного пакета рядок `All tests passed!`. Записати кількість тестів кожного пакета (baseline: `grund` 276) — вона потрібна для порівняння в задачі 21.

---


## Частина A: задачі 1–6 (виокремлення `grund_http`, нове ядро `grund`)

> **Як перевірено.** Кожну задачу цієї частини виконано послідовно в копії репозиторію (`/tmp/.../scratchpad/repo_a`, гілка `grund-g1` від `grund-rename`): команди з кроків запущено, файли з блоків коду створено дослівно, `dart analyze`/`dart test` запущено після кожної задачі. Усі блоки «файл цілком» нижче збігаються з перевіреним прототипом ядра байт-в-байт (звіряє скрипт збирання плану). Кількості тестів у кроках «очікувано» — фактичні.

**Угоди частини A.**

- Блок коду з підписом `**\`шлях\`**` — **повний вміст файла**; шлях відносно кореня репозиторію (`~/projects/grund`). Файл створюється або замінюється цілком.
- Усі блоки `bash` стартують з `export PATH=…` і `cd` у потрібний пакет (кожен виклик `Bash` має чисту оболонку).
- Тести нового ядра імпортують `package:grund/src/…` (внутрішні імпорти тестів дозволені); до задачі 6 barrel `lib/grund.dart` експортує старий DI, після задачі 6 — нове ядро.
- Файли кожного нового пакета/каталогу складаються так, щоб **кожна задача компілювалася й мала зелені тести на момент свого коміту** (перевірено: таблиця «Стан дерева» в кінці).
- Коміти — англійською, Conventional Commits; рядок атрибуції додає виконавець за інструкцією харнеса.

---

### Задача 1: Виокремити `grund_http`, вирізати HTTP з ядра (механічне перенесення)

**Мета:** після задачі в `packages/grund` лишається лише **старий** DI без жодного HTTP; у новому пакеті `packages/grund_http` лежать ті частини HTTP, що переживають переписування: значення запиту/відповіді, роутинг, інфраструктура адаптерів, JSON-серіалізатор, `TestResponse`. Поведінка перенесеного не змінюється, нічого нового не пишеться; решта старого HTTP-коду (контролери, конвеєр, `Application`, `HotReloadExtension`, `TestClient`) видаляється — її буде написано заново в задачах 6–11 (тести портуються з `git show 71a4726:<шлях>`). Це механічна задача: нового коду, що потребує падаючого тесту, тут немає; роль «тесту» виконують наявні тести, що мають лишитися зеленими у двох пакетах.

**Files:**
- Create: `packages/grund_http/{pubspec.yaml,analysis_options.yaml,LICENSE,CHANGELOG.md,README.md}`, `packages/grund_http/lib/{grund_http,adapter,testing}.dart`, `packages/grund_http/lib/src/adapter/error_logger.dart`, `packages/grund_http/lib/src/serialize/serialization_error.dart`
- Move (`git mv`, зберігає історію) із `packages/grund/lib/src/…` у `packages/grund_http/lib/src/…`: `http/*.dart` (9 файлів) → `http/`; `routing/*.dart` (5) → `routing/`; `app/{http_adapter,adapter_lifecycle,in_flight_requests}.dart` → `adapter/`; `pipeline/{response_serializer,serializer_registry}.dart` → `serialize/`; `testing/test_response.dart` → `testing/`; `lib/adapter.dart` лишається на місці в `grund`, але **видаляється** (новий — у `grund_http`)
- Move тестів: `test/http/*_test.dart` (4), `test/routing/*_test.dart` (2) → однойменні каталоги `packages/grund_http/test/`; `test/app/{adapter_lifecycle,in_flight_requests}_test.dart` → `grund_http/test/adapter/`; `test/pipeline/response_serializer_test.dart` → `grund_http/test/serialize/`; `test/helpers/{http_fixtures,fake_adapter}.dart` → `grund_http/test/helpers/`
- Delete (див. крок 5): решта `packages/grund/lib/src/{app,controller,pipeline,testing}/` (32 файли), `lib/adapter.dart`, `lib/testing.dart`, `example/`, `test/{app,controller,pipeline,e2e}/` (залишки), `test/example_test.dart`, `test/helpers/{app_fixtures,pipeline_fixtures}.dart`
- Modify: корінь `pubspec.yaml` (workspace), `packages/grund/lib/grund.dart`, `packages/grund/lib/src/di/{module,module_graph}.dart` (відрізати `controllers`), `routing_error.dart` і `response_serializer.dart` у `grund_http` (імпорти), перенесені тести (імпорти), `grund_http/test/helpers/http_fixtures.dart`

**Interfaces:**
- Consumes: `GrundError` з `package:grund/grund.dart` (старий, `lib/src/di/errors.dart`; `abstract base class`) — від нього успадковуються `RoutingError` і новий `SerializationError`.
- Produces: `package:grund_http/grund_http.dart` (перенесені `HttpRequest`, `HttpResponse`, `HeaderMap`, `RequestBody`, `ResponseBody`/`BytesBody`/`StreamBody`, `ResponseHead`, `StatusCode`, `ConnectionInfo`, `HttpException`-родина, `RoutingError`-родина, `HttpAdapter` + `RequestHandler`, `SerializerRegistry`, а також нові `ErrorLogger`, `SerializationError`), `package:grund_http/adapter.dart` (`AdapterLifecycle`, `InFlightRequests`), `package:grund_http/testing.dart` (`TestResponse`).

  ```dart
  // adapter/error_logger.dart
  typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);
  // serialize/serialization_error.dart
  final class SerializationError extends GrundError {
    const SerializationError({required Type valueType, Object? cause});
  }
  ```
  `ErrorLogger` раніше жив у видаленому `pipeline/http_error_responder.dart`, `SerializationError` — у видаленому `pipeline/pipeline_error.dart` (як член sealed `PipelineError`); тепер вони самостійні файли. Інші пакети (`grund_io`, `grund_shelf`, `grund_conformance`) цими типами користуються, тож вони мають лишитися експортованими.

**Базові кількості тестів** (до задачі, фактично зняті на `71a4726`): `grund` 276, `grund_annotations` 6, `grund_build` 18, `grund_cli` 136, `grund_conformance` 14, `grund_generator` 172, `grund_io` 47, `grund_shelf` 68, `example` 56. Розподіл 276 тестів ядра: старий DI 80 (`container_errors` 16, `container_reassemble` 7, `container_startup` 13, `module_graph` 22, `module` 9, `provider` 8, `token` 5), переноситься в `grund_http` 69 (`adapter_lifecycle` 10, `in_flight_requests` 3, `header_map` 5, `http_exception` 5, `http_request` 8, `http_response` 9, `response_serializer` 11, `route_pattern` 7, `router` 11), **видаляється 127** (див. нижче, які задачі їх повертають).

| Видалені тести (файл у `71a4726`) | К-сть | Повертається в задачі |
|---|---|---|
| `app/application_test.dart` 9, `app/application_lifecycle_test.dart` 13, `app/application_reassemble_test.dart` 9 | 31 | 6 (App), 11 (HttpServer) |
| `app/hot_reload_extension_test.dart` | 8 | 6 |
| `app/request_dispatcher_test.dart` 13, `app/route_table_builder_test.dart` 7 | 20 | 10 |
| `controller/controller_test.dart` | 10 | 10 (Route/HttpApi) |
| `pipeline/{argument_binding 19, execution_context 6, resolved_enhancers 5, pipeline 9, http_error_responder 5}_test.dart` | 44 | 7, 8, 9 (помилки, `Params`, хуки) |
| `e2e/users_app_test.dart` | 11 | 11 |
| `example_test.dart` | 3 | 6 (новий приклад ядра), 20 |

- [ ] **Крок 1: Створити гілку-основу і записати стан** (виконує контролер, якщо ще не зроблено; тут для самодостатності)

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
git status --short                  # порожньо
git branch --show-current           # grund-g1
cd packages/grund && dart test 2>&1 | tail -1
```

Очікувано: `+276: All tests passed!`.

- [ ] **Крок 2: Створити пакет `grund_http`**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
P=packages/grund_http
mkdir -p $P/lib/src/{http,routing,adapter,serialize,testing} $P/test/{http,routing,adapter,serialize,helpers}
cp LICENSE $P/LICENSE
cp packages/grund/analysis_options.yaml $P/analysis_options.yaml
sed -i 's#^  - packages/grund_generator/test/fixtures/users_app$#&\n  - packages/grund_http#' pubspec.yaml
grep -n "grund_http" pubspec.yaml
```

Очікувано: рядок `  - packages/grund_http` одразу після `…/fixtures/users_app` (за алфавітом перед `grund_io`).

**`packages/grund_http/pubspec.yaml`**

````yaml
name: grund_http
description: >-
  HTTP for grund: request and response values, routing, the adapter contract
  and the JSON serializer.
version: 0.1.0
repository: https://github.com/4akLoon/grund/tree/master/packages/grund_http
issue_tracker: https://github.com/4akLoon/grund/issues
topics: [server, http, framework]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  grund: ^0.1.0
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
````

**`packages/grund_http/CHANGELOG.md`**

````markdown
## 0.1.0

- Initial release.
````

**`packages/grund_http/README.md`**

````markdown
# grund_http

HTTP layer of grund: request and response values, routing and the adapter
contract. The full documentation arrives with the `HttpApi` work.
````

- [ ] **Крок 3: Перенести файли** (`git mv`)

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
G=packages/grund/lib/src; H=packages/grund_http/lib/src
T=packages/grund/test; U=packages/grund_http/test
git mv $G/http/*.dart $H/http/
git mv $G/routing/*.dart $H/routing/
git mv $G/app/http_adapter.dart $G/app/adapter_lifecycle.dart $G/app/in_flight_requests.dart $H/adapter/
git mv $G/pipeline/response_serializer.dart $G/pipeline/serializer_registry.dart $H/serialize/
git mv $G/testing/test_response.dart $H/testing/
git mv $T/http/*.dart $U/http/
git mv $T/routing/*.dart $U/routing/
git mv $T/app/adapter_lifecycle_test.dart $T/app/in_flight_requests_test.dart $U/adapter/
git mv $T/pipeline/response_serializer_test.dart $U/serialize/
git mv $T/helpers/http_fixtures.dart $T/helpers/fake_adapter.dart $U/helpers/
rmdir $G/http $G/routing
git status --short | grep -c '^R'
```

Очікувано: `31` перейменування (20 файлів `lib` + 11 тестів і фікстур). Каталоги `$G/http` і `$G/routing` порожні й видаляються `rmdir`.

- [ ] **Крок 4: Нові файли `error_logger.dart` і `serialization_error.dart`**

**`packages/grund_http/lib/src/adapter/error_logger.dart`**

````dart
/// Receives errors that become 500 responses, with their stack traces.
///
/// It must not throw: a throwing logger is reported to the adapter's own
/// error callback and the response is still sent.
typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);
````

**`packages/grund_http/lib/src/serialize/serialization_error.dart`**

````dart
import 'package:grund/grund.dart' show GrundError;

/// A handler result cannot be encoded as JSON.
final class SerializationError extends GrundError {
  /// Creates the error.
  const SerializationError({required this.valueType, this.cause});

  /// Runtime type of the value that could not be encoded.
  final Type valueType;

  /// What the JSON encoder reported, if anything.
  final Object? cause;

  @override
  String get message {
    final failure = cause;
    // The encoder reports a value without toJson() as a NoSuchMethodError
    // cause; any other cause is a toJson() that threw.
    if (failure != null && failure is! NoSuchMethodError) {
      return 'Cannot serialize $valueType to JSON: its toJson() or the JSON '
          'encoder failed with $failure. Registered serializers do not apply '
          'to values inside the result of a toJson().';
    }
    return 'Cannot serialize $valueType to JSON. Give it a toJson() method, '
        'return an HttpResponse, or register a serializer with '
        'app.serializers.register<$valueType>(...). Registered serializers '
        'do not apply to values inside the result of a toJson().';
  }
}
````

(Текст повідомлення `SerializationError` лишається дослівним — він ще згадує `app.serializers.register`; задача 10 перепише його під `ResponseCodec`.)

- [ ] **Крок 5: Видалити те, що буде переписано** (точні шляхи, без придушення помилок)

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
G=packages/grund/lib/src; T=packages/grund/test
git rm -r -q $G/app $G/controller $G/pipeline $G/testing \
  packages/grund/lib/adapter.dart packages/grund/lib/testing.dart packages/grund/example \
  $T/app $T/controller $T/pipeline $T/e2e $T/example_test.dart \
  $T/helpers/app_fixtures.dart $T/helpers/pipeline_fixtures.dart
find packages/grund -type f -not -path '*/.dart_tool/*' | sort
```

Очікувано: у `packages/grund` лишаються лише `analysis_options.yaml`, `CHANGELOG.md`, `LICENSE`, `README.md`, `pubspec.yaml`, `lib/grund.dart`, `lib/src/di/{container,errors,injector,module,module_graph,module_injector,provider,resolution_trace,token}.dart`, `test/di/{container_errors,container_reassemble,container_startup,module_graph,module,provider,token}_test.dart`, `test/helpers/di_fixtures.dart`.

- [ ] **Крок 6: Відрізати `Module.controllers` у старому DI та звузити barrel**

Старий `Module` тягне `ControllerSpec` із видаленого `controller/controller.dart`. Правки точні (скрипт падає, якщо шматок не знайдено); тести старого DI про `controllers` не згадують, тож змінювати їх не треба.

```bash
cd ~/projects/grund/packages/grund
python3 - <<'PY'
def edit(path, old, new):
    text = open(path).read()
    assert old in text, (path, old)
    open(path, 'w').write(text.replace(old, new, 1))

module = 'lib/src/di/module.dart'
edit(module, "import '../controller/controller.dart';\n", '')
edit(module,
     "/// treated as one: their shape (imports, provider keys, controller types,\n"
     "/// exports, [global]) must match or `ModuleGraph.build` throws\n"
     "/// `DuplicateModuleIdError`.\n",
     "/// treated as one: their shape (imports, provider keys, exports, [global])\n"
     "/// must match or `ModuleGraph.build` throws `DuplicateModuleIdError`.\n")
edit(module,
     "  ///\n"
     "  /// Has six named parameters, one over the usual limit of five, by spec: a\n"
     "  /// module is a declarative value, so there is no parameter object.\n", '')
edit(module, "    this.controllers = const [],\n", '')
edit(module,
     "  /// Controllers whose instances are created with this module's injector\n"
     "  /// after its providers, and whose routes the application serves.\n"
     "  final List<ControllerSpec> controllers;\n\n", '')

graph = 'lib/src/di/module_graph.dart'
edit(graph,
     "/// compared by shape only (id, `global`, import ids, provider keys,\n"
     "/// controller types and export keys); the first-seen instance wins.\n",
     "/// compared by shape only (id, `global`, import ids, provider keys and\n"
     "/// export keys); the first-seen instance wins.\n")
edit(graph,
     "    if (!_sameList(\n"
     "      a.controllers.map((c) => c.type),\n"
     "      b.controllers.map((c) => c.type),\n"
     "    )) {\n"
     "      return false;\n"
     "    }\n", '')
edit(graph,
     "  /// Structural equality (id, `global`, import ids, provider keys, controller\n"
     "  /// types and export keys; not factory configuration) used\n"
     "  /// to accept the same dynamic module imported from several places.\n",
     "  /// Structural equality (id, `global`, import ids, provider keys and export\n"
     "  /// keys; not factory configuration) used to accept the same dynamic module\n"
     "  /// imported from several places.\n")
PY
grep -rn "ontroller" lib test || echo "no controller left"
```

Очікувано: `no controller left`.

**`packages/grund/lib/grund.dart`**

````dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/di/container.dart';
export 'src/di/errors.dart';
export 'src/di/injector.dart';
export 'src/di/module.dart';
export 'src/di/module_graph.dart';
export 'src/di/provider.dart';
export 'src/di/token.dart';
````

- [ ] **Крок 7: Barrel-и `grund_http` і правки імпортів**

**`packages/grund_http/lib/grund_http.dart`**

````dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/http/connection_info.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
````

**`packages/grund_http/lib/adapter.dart`**

````dart
/// Building blocks for `HttpAdapter` implementations such as `grund_io`
/// and `grund_shelf`. Applications do not need this library.
library;

export 'src/adapter/adapter_lifecycle.dart';
export 'src/adapter/in_flight_requests.dart';
````

**`packages/grund_http/lib/testing.dart`**

````dart
/// Helpers for testing HTTP code without a server.
library;

export 'src/testing/test_response.dart';
````

`RoutingError` і новий `SerializationError` залежать від `GrundError` старого ядра; `response_serializer.dart` тепер бере `SerializationError` із сусіднього файла. Тести перенесеного коду переходять на `package:grund_http/…`; з `http_fixtures.dart` зникає `contextFor` (він будував `ExecutionContext` видаленого конвеєра).

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
H=packages/grund_http/lib/src; U=packages/grund_http/test
sed -i "s#^import '../di/errors.dart';#import 'package:grund/grund.dart' show GrundError;#" $H/routing/routing_error.dart
sed -i "s#^import 'pipeline_error.dart';#import 'serialization_error.dart';#" $H/serialize/response_serializer.dart
grep -rl "package:grund/" $U | xargs sed -i \
  -e "s#package:grund/grund.dart#package:grund_http/grund_http.dart#" \
  -e "s#package:grund/adapter.dart#package:grund_http/adapter.dart#" \
  -e "s#package:grund/src/pipeline/response_serializer.dart#package:grund_http/src/serialize/response_serializer.dart#" \
  -e "s#package:grund/src/routing/#package:grund_http/src/routing/#"
sed -i "1i import 'package:grund/grund.dart' show GrundError;" $U/routing/route_pattern_test.dart
python3 - <<'PY'
path = 'packages/grund_http/test/helpers/http_fixtures.dart'
text = open(path).read()
start = text.index('/// An HTTP context for')
end = text.index('/// The JSON value in')
text = text[:start] + text[end:]
text = text.replace('// Shared builders for pipeline and HTTP tests.', '// Shared builders for HTTP tests.')
open(path, 'w').write(text)
PY
grep -rn "package:grund/" $U $H || true
```

Очікувано: рядки лише з `package:grund/grund.dart' show GrundError` (у `routing_error.dart`, `serialization_error.dart`, `route_pattern_test.dart`).

- [ ] **Крок 8: Перевірити обидва пакети**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
dart pub get 2>&1 | tail -1
dart format packages/grund packages/grund_http | tail -1
(cd packages/grund && dart analyze | tail -1 && dart test 2>&1 | tail -1)
(cd packages/grund_http && dart analyze | tail -1 && dart test 2>&1 | tail -1)
(cd packages/grund_annotations && dart analyze | tail -1 && dart test 2>&1 | tail -1)
```

Очікувано: `Formatted … (0 changed)`; `grund`: `No issues found!` і `+80: All tests passed!`; `grund_http`: `No issues found!` і `+69: All tests passed!`; `grund_annotations`: `No issues found!`, `+6`. Інші пакети (`grund_io`, `grund_shelf`, `grund_conformance`, `grund_generator`, `grund_cli`, `grund_build`, `example`) відтепер **червоні** — це очікувано (таблиця «Стан дерева» в кінці частини); їх цією задачею не чіпають.

Ліміти: `wc -l` кожного файла з `git status` у межах (найбільший — `grund/test/di/container_errors_test.dart`, 319 рядків ≤ 500; `grund/lib/src/di/errors.dart` 244 ≤ 300). Нового коду — два невеликі файли.

- [ ] **Крок 9: Коміт**

```bash
cd ~/projects/grund
git add -A packages/grund packages/grund_http pubspec.yaml
git commit -m "refactor!: move HTTP out of grund into grund_http

The core keeps only the (old) DI; reusable HTTP value types, routing, adapter
infrastructure and the serializer move to the new grund_http package.
Controllers, the pipeline, Application and TestClient are removed and are
rewritten in the following commits."
```

---

### Задача 2: Примітиви нового ядра — `Key`, `Binding`, `Injector`, `Disposable`, помилки (поряд зі старим DI)

**Мета:** нові типи ядра з тестами; старий DI паркується в `lib/src/legacy_di` + `test/legacy_di` і далі живе (його barrel-експорти не змінюються), доки задача 6 не перемкне barrel. Нічого з нового ще не експортується з `lib/grund.dart`. Помилки лежать у `lib/src/errors/` — одне sealed-сімейство на файл (`graph_errors`, `resolution_errors`, `app_errors`) над спільним `GrundError`.

**Files:**
- Move: `packages/grund/lib/src/di` → `lib/src/legacy_di`; `test/di` → `test/legacy_di`; `test/helpers/di_fixtures.dart` → `test/legacy_di/di_fixtures.dart` (нові тести задачі 3 мають власний `test/helpers/di_fixtures.dart`)
- Modify: `lib/grund.dart` (шляхи `src/di/` → `src/legacy_di/`), `test/legacy_di/container_{errors,reassemble,startup}_test.dart` (імпорт фікстури)
- Create: `lib/src/errors/{grund_error,graph_errors,resolution_errors,app_errors}.dart`, `lib/src/di/{key,binding,injector,call_scope,disposable}.dart`
- Test: `test/di/{key,binding}_test.dart`, `test/errors/errors_test.dart`

**Interfaces:**
- Consumes: `package:meta` (`@immutable`).
- Produces (у `package:grund/src/…`; публічними стануть у задачі 6):

```dart
// errors/grund_error.dart
abstract base class GrundError implements Exception {
  const GrundError();
  String get message;
  String toString() => '$runtimeType: $message';
}
// di/key.dart
@immutable final class Key<T extends Object> {
  const Key([String? name]);
  final String? name;
  Type get type;                       // T; ==/hashCode: type + name; toString: `T` або `T('name')`
}
// di/binding.dart
typedef BindingFactory<T extends Object> = FutureOr<T> Function(Injector injector);
enum BindingScope { singleton, scoped, transient }
sealed class Binding<T extends Object> {
  final Key<T> key; final BindingFactory<T> create; final List<Key<Object>>? dependsOn;
  BindingScope get scope;              // T == Object -> ArgumentError
}
final class Singleton<T extends Object> extends Binding<T> {
  Singleton(BindingFactory<T> create, {String? name, required List<Key<Object>> dependsOn});
  Singleton.factory(BindingFactory<T> create, {String? name});   // dependsOn == null
}
final class Scoped<T extends Object> extends Binding<T> { Scoped(create, {name, required dependsOn}); }
final class Transient<T extends Object> extends Binding<T> { Transient(create, {name, required dependsOn}); }
// di/injector.dart, di/call_scope.dart
abstract interface class Injector {
  T call<T extends Object>([String? name]);
  T? maybe<T extends Object>([String? name]);
  List<T> all<T extends Object>();
  CallScope openCall();
}
abstract interface class CallScope implements Injector {
  void set<T extends Object>(T value, {String? name});
  Future<void> close();
}
// di/disposable.dart
abstract interface class Disposable { FutureOr<void> dispose(); }
```

Помилки (усі `final class … extends <Sealed>` з `const`-конструктором; рядкові `module`-поля містять `ModuleIdentity.toString()`):
- `GraphError` (sealed): `CircularModuleImportError(List<String> cycle)`, `ConflictingModuleError(String module)`, `DuplicateBindingError({key, module})`, `InvalidExportError({export, module})`, `AmbiguousProviderError({key, module, owners})`, `MissingProviderError({key, module, requiredBy})`, `ProviderNotVisibleError({key, module, requiredBy, declaredIn, importChain})`, `CircularDependencyError(List<Key<Object>> cycle)`, `CaptiveDependencyError({singleton, scoped, path})`, `UnusedOverrideError(Key<Object> key)`.
- `ResolutionError` (sealed): `AsyncProviderNotReadyError({key, module, chain})`, `ProviderCreationError({key, module, chain, error, stackTrace})`, `ScopedOutsideCallError({key, module})`, `ModuleLifecycleError({module, phase, error, stackTrace})`, `ShutdownError(List<ShutdownFailure> failures)` з `typedef ShutdownFailure = ({String step, Object error, StackTrace stackTrace})`, `StartupRollbackError({cause, causeStackTrace, failures})`.
- `AppError` (sealed): `ApplicationStateError({operation, reason})` (message `Cannot $operation: $reason.`), `UnknownRunnerError({unknown, available})`, `DuplicateRunnerError(String name)`, `RunnerError({runner, phase, error, stackTrace})`.
- Кожне повідомлення читабельне й містить підказку: `ProviderNotVisibleError` називає ключ, модуль, де його оголошено, і ланцюжок імпортів (`AppModule -> TasksModule -> DbModule`) або «import X into Y»; `ConflictingModuleError` радить різні `qualifier`; `Binding` з `T == Object` кидає `ArgumentError`, що радить писати `Singleton<Clock>(...)`. Підказку про відсутній `HttpAdapter` дає `HttpModule` (задача 11), а не ядро.

> **Відхилення від чернетки плану.** `CallScope` винесено у власний файл `call_scope.dart` (правило «один публічний клас на файл»). `BindingId` живе у `visible_binding.dart` (задача 3), а не в окремому `binding_id.dart`. Додано `StartupRollbackError` (відкат невдалого старту, який сам не вдався) і `DuplicateRunnerError` (два раннери з одним ім'ям) — їх вимагає RF-4. `MissingProviderError` не має поля `chain`: валідація залежностей працює над `dependsOn` і називає `requiredBy`.

- [ ] **Крок 1: Запаркувати старий DI**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
git mv lib/src/di lib/src/legacy_di
git mv test/di test/legacy_di
git mv test/helpers/di_fixtures.dart test/legacy_di/di_fixtures.dart
sed -i "s#'../helpers/di_fixtures.dart'#'di_fixtures.dart'#" test/legacy_di/*.dart
sed -i "s#'src/di/#'src/legacy_di/#" lib/grund.dart
dart analyze | tail -1
dart test 2>&1 | tail -1
git add -A . && git commit -q -m "refactor(core): park the old DI in legacy_di"
```

Очікувано: `No issues found!`, `+80: All tests passed!` (нічого не змінилося, окрім шляхів).

- [ ] **Крок 2: Падаючі тести**

Тести нових примітивів. Ключ і binding: рівність, `toString`, відмова `Singleton<Object>`; помилки: кожне повідомлення містить те, що обіцяє doc-коментар.

**`packages/grund/test/di/key_test.dart`**

````dart
import 'package:grund/src/di/key.dart';
import 'package:test/test.dart';

class _Repo {}

void main() {
  group('Key', () {
    test('equals a key with the same type and name', () {
      expect(const Key<_Repo>(), const Key<_Repo>());
      expect(const Key<_Repo>('a'), const Key<_Repo>('a'));
      expect(const Key<_Repo>().hashCode, const Key<_Repo>().hashCode);
      expect(const Key<_Repo>('a').hashCode, const Key<_Repo>('a').hashCode);
    });

    test('differs by type', () {
      expect(const Key<_Repo>(), isNot(const Key<String>()));
    });

    test('differs by name', () {
      expect(const Key<_Repo>('a'), isNot(const Key<_Repo>('b')));
      expect(const Key<_Repo>('a'), isNot(const Key<_Repo>()));
    });

    test('is usable as a map key', () {
      final map = {const Key<_Repo>('a'): 1};

      expect(map[const Key<_Repo>('a')], 1);
      expect(map[const Key<_Repo>()], isNull);
    });

    test('exposes its type as a value', () {
      expect(const Key<_Repo>().type, _Repo);
    });

    test('prints the type, and the name when there is one', () {
      expect(const Key<_Repo>().toString(), '_Repo');
      expect(const Key<_Repo>('primary').toString(), "_Repo('primary')");
    });
  });
}
````

**`packages/grund/test/di/binding_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/key.dart';
import 'package:test/test.dart';

class _Clock {}

void main() {
  group('Binding', () {
    test('Singleton keeps its key, scope and declared dependencies', () {
      final binding = Singleton<_Clock>(
        (i) => _Clock(),
        name: 'utc',
        dependsOn: const [Key<String>()],
      );

      expect(binding.key, const Key<_Clock>('utc'));
      expect(binding.scope, BindingScope.singleton);
      expect(binding.dependsOn, const [Key<String>()]);
    });

    test('Singleton.factory does not declare its dependencies', () {
      final binding = Singleton<_Clock>.factory((i) => _Clock());

      expect(binding.dependsOn, isNull);
    });

    test('Scoped and Transient have their own scopes', () {
      final scoped = Scoped<_Clock>((i) => _Clock(), dependsOn: const []);
      final transient = Transient<_Clock>((i) => _Clock(), dependsOn: const []);

      expect(scoped.scope, BindingScope.scoped);
      expect(transient.scope, BindingScope.transient);
    });

    test('a missing type argument is inferred as Object and rejected', () {
      // In a `List<Binding<Object>>` Dart infers `Object` for the type
      // argument that was left out.
      expect(
        () => <Binding<Object>>[
          Singleton((i) => _Clock(), dependsOn: const []),
        ],
        throwsArgumentError,
      );
    });

    test('Singleton<Object> throws an ArgumentError naming the fix', () {
      expect(
        () => Singleton<Object>((i) => _Clock(), dependsOn: const []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Singleton<Clock>(...)'),
          ),
        ),
      );
    });

    test('Scoped<Object> and Transient<Object> throw as well', () {
      expect(
        () => Scoped<Object>((i) => _Clock(), dependsOn: const []),
        throwsArgumentError,
      );
      expect(
        () => Transient<Object>((i) => _Clock(), dependsOn: const []),
        throwsArgumentError,
      );
    });
  });
}
````

**`packages/grund/test/errors/errors_test.dart`**

````dart
import 'package:grund/src/di/key.dart';
import 'package:grund/src/errors/app_errors.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/grund_error.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

class _Repo {}

class _Clock {}

void main() {
  group('GrundError', () {
    test('prints its class name and message', () {
      const error = UnusedOverrideError(Key<_Repo>());

      expect(error, isA<GrundError>());
      expect(error.toString(), startsWith('UnusedOverrideError: '));
      expect(error.toString(), contains(error.message));
    });
  });

  group('graph errors', () {
    test('a missing provider names the key, the module and the requirer', () {
      const error = MissingProviderError(
        key: Key<_Repo>(),
        module: 'AppModule',
        requiredBy: Key<_Clock>(),
      );

      expect(error.message, contains('_Repo'));
      expect(error.message, contains('AppModule'));
      expect(error.message, contains('required by _Clock'));
    });

    test(
      'an invisible provider says what to import when it is not reachable',
      () {
        const error = ProviderNotVisibleError(
          key: Key<_Repo>(),
          module: 'AppModule',
          requiredBy: Key<_Clock>(),
          declaredIn: ['DbModule'],
          importChain: [],
        );

        expect(error.message, contains('import DbModule into AppModule'));
      },
    );

    test(
      'an invisible provider prints the import chain when it is indirect',
      () {
        const error = ProviderNotVisibleError(
          key: Key<_Repo>(),
          module: 'AppModule',
          requiredBy: Key<_Clock>(),
          declaredIn: ['DbModule'],
          importChain: ['AppModule', 'TasksModule', 'DbModule'],
        );

        expect(error.message, contains('AppModule -> TasksModule -> DbModule'));
      },
    );

    test('a conflicting module advises different qualifiers', () {
      const error = ConflictingModuleError('DbModule');

      expect(error.message, contains('qualifiers'));
    });

    test('a dependency cycle prints the keys with arrows', () {
      const error = CircularDependencyError([
        Key<_Repo>(),
        Key<_Clock>(),
        Key<_Repo>(),
      ]);

      expect(error.message, contains('_Repo -> _Clock -> _Repo'));
    });

    test('a captive dependency prints the path from the singleton', () {
      const error = CaptiveDependencyError(
        singleton: Key<_Repo>(),
        scoped: Key<_Clock>(),
        path: [Key<_Repo>(), Key<_Clock>()],
      );

      expect(error.message, contains('_Repo -> _Clock'));
      expect(error.message, contains('call-scoped'));
    });

    test('an ambiguous provider lists the owners', () {
      const error = AmbiguousProviderError(
        key: Key<_Repo>(),
        module: 'AppModule',
        owners: ['AuthModule', 'DbModule'],
      );

      expect(error.message, contains('AuthModule and DbModule'));
    });
  });

  group('resolution errors', () {
    test('a failed factory names the key, the chain and the cause', () {
      final error = ProviderCreationError(
        key: const Key<_Repo>(),
        module: 'DbModule',
        chain: const [Key<_Clock>()],
        error: StateError('boom'),
        stackTrace: StackTrace.current,
      );

      expect(error.message, contains('_Repo'));
      expect(error.message, contains('required by _Clock'));
      expect(error.message, contains('boom'));
    });

    test('a scoped key outside a call explains how to open one', () {
      const error = ScopedOutsideCallError(
        key: Key<_Repo>(),
        module: 'AppModule',
      );

      expect(error.message, contains('openCall'));
    });

    test('a shutdown error lists every failed step', () {
      final error = ShutdownError([
        (
          step: 'dispose a',
          error: StateError('a'),
          stackTrace: StackTrace.empty,
        ),
        (
          step: 'onShutdown B',
          error: StateError('b'),
          stackTrace: StackTrace.empty,
        ),
      ]);

      expect(error.message, contains('2 step(s)'));
      expect(error.message, contains('dispose a'));
      expect(error.message, contains('onShutdown B'));
    });

    test('a rollback error keeps the original cause next to the failures', () {
      final error = StartupRollbackError(
        cause: StateError('factory'),
        causeStackTrace: StackTrace.empty,
        failures: [
          (
            step: 'dispose a',
            error: StateError('a'),
            stackTrace: StackTrace.empty,
          ),
        ],
      );

      expect(error.message, contains('factory'));
      expect(error.message, contains('dispose a'));
    });
  });

  group('app errors', () {
    test('a state error reads as a sentence', () {
      const error = ApplicationStateError(
        operation: 'start',
        reason: 'the application is already running',
      );

      expect(
        error.message,
        'Cannot start: the application is already running.',
      );
    });

    test('an unknown runner lists what exists', () {
      const error = UnknownRunnerError(
        unknown: ['nope'],
        available: ['http', 'jobs'],
      );

      expect(error.message, contains('nope'));
      expect(error.message, contains('http, jobs'));
    });

    test('an unknown runner with an empty graph says "none"', () {
      const error = UnknownRunnerError(unknown: ['nope'], available: []);

      expect(error.message, contains('none'));
    });

    test('a runner error names the runner, the phase and the cause', () {
      final error = RunnerError(
        runner: 'http',
        phase: 'start',
        error: StateError('port in use'),
        stackTrace: StackTrace.empty,
      );

      expect(error.message, contains('"http"'));
      expect(error.message, contains('start'));
      expect(error.message, contains('port in use'));
    });

    test('a duplicate runner names the shared name', () {
      const error = DuplicateRunnerError('http');

      expect(error.message, contains('"http"'));
    });
  });
}
````

- [ ] **Крок 3: Запустити — очікуваний збій**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart test test/di test/errors 2>&1 | tail -8
```

Очікувано: `Some tests failed.`, усі три файли «loading … failed» з помилками компіляції на кшталт `Not found: 'package:grund/src/di/key.dart'` / `Method not found: 'RunnerError'`.

- [ ] **Крок 4: Реалізація — помилки**

**`packages/grund/lib/src/errors/grund_error.dart`**

````dart
/// Root of every error that grund throws on its own.
///
/// Packages add their own families by extending it; the class name is the
/// stable identifier of a failure.
abstract base class GrundError implements Exception {
  /// Creates the error.
  const GrundError();

  /// Human-readable description, with a hint where one exists.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}
````

**`packages/grund/lib/src/errors/graph_errors.dart`**

````dart
import '../di/key.dart';
import 'grund_error.dart';

/// A module graph that is invalid, found before any factory runs.
sealed class GraphError extends GrundError {
  /// Creates the error.
  const GraphError();
}

/// Modules import each other in a cycle.
final class CircularModuleImportError extends GraphError {
  /// Creates the error for [cycle], the modules from the first repeated one
  /// back to itself.
  const CircularModuleImportError(this.cycle);

  /// The modules of the cycle, the first one repeated at the end.
  final List<String> cycle;

  @override
  String get message =>
      'Modules import each other in a cycle: ${cycle.join(' -> ')}.';
}

/// One module identity is imported twice with a different shape.
final class ConflictingModuleError extends GraphError {
  /// Creates the error for [module].
  const ConflictingModuleError(this.module);

  /// The identity of the module.
  final String module;

  @override
  String get message =>
      'Module $module is imported twice with a different shape. Instances of '
      'one module class must declare the same imports, bindings and exports; '
      'give them different qualifiers if they are meant to be different '
      'modules.';
}

/// A module declares one key twice.
final class DuplicateBindingError extends GraphError {
  /// Creates the error for [key] declared twice in [module].
  const DuplicateBindingError({required this.key, required this.module});

  /// The key declared twice.
  final Key<Object> key;

  /// The module that declares it.
  final String module;

  @override
  String get message =>
      'Module $module declares $key more than once. Give one of the bindings '
      'a name.';
}

/// A module exports something it neither declares nor imports.
final class InvalidExportError extends GraphError {
  /// Creates the error for [export] of [module].
  const InvalidExportError({required this.export, required this.module});

  /// The offending entry: a key, a module, or something else.
  final Object export;

  /// The exporting module.
  final String module;

  @override
  String get message =>
      'Module $module exports $export, which it neither declares nor '
      'imports. Exports are keys of its own bindings or modules from its '
      'imports.';
}

/// Several imported modules export the same key.
final class AmbiguousProviderError extends GraphError {
  /// Creates the error for [key] seen from [module].
  const AmbiguousProviderError({
    required this.key,
    required this.module,
    required this.owners,
  });

  /// The ambiguous key.
  final Key<Object> key;

  /// The module that sees it twice.
  final String module;

  /// The modules that provide it, sorted.
  final List<String> owners;

  @override
  String get message =>
      '$key is exported by ${owners.join(' and ')}, so module $module cannot '
      'tell which one it means. Declare $key in $module to choose, or name '
      'the bindings.';
}

/// Nothing in the graph provides a key that is required.
final class MissingProviderError extends GraphError {
  /// Creates the error for [key] required in [module].
  const MissingProviderError({
    required this.key,
    required this.module,
    this.requiredBy,
  });

  /// The missing key.
  final Key<Object> key;

  /// The module that needs it.
  final String module;

  /// The binding that needs it, when known.
  final Key<Object>? requiredBy;

  @override
  String get message {
    final by = requiredBy == null ? '' : ', required by $requiredBy';
    return 'No provider for $key is visible in module $module$by. Declare '
        'it there, or import a module that exports it.';
  }
}

/// A key exists in the graph but the requiring module cannot see it.
final class ProviderNotVisibleError extends GraphError {
  /// Creates the error for [key] required in [module].
  const ProviderNotVisibleError({
    required this.key,
    required this.module,
    required this.requiredBy,
    required this.declaredIn,
    required this.importChain,
  });

  /// The invisible key.
  final Key<Object> key;

  /// The module that needs it.
  final String module;

  /// The binding that needs it.
  final Key<Object> requiredBy;

  /// The modules that declare it.
  final List<String> declaredIn;

  /// Modules from [module] down to a declaring one when it is imported
  /// indirectly; empty when it is not imported at all.
  final List<String> importChain;

  @override
  String get message {
    final where = declaredIn.join(' and ');
    final hint = importChain.isEmpty
        ? 'import $where into $module and export $key from it'
        : 'it is only reachable through ${importChain.join(' -> ')}; '
              'export $key from the module that imports $where';
    return '$key (required by $requiredBy) is declared in $where but module '
        '$module cannot see it: $hint.';
  }
}

/// Bindings depend on each other in a cycle.
final class CircularDependencyError extends GraphError {
  /// Creates the error for [cycle], the first key repeated at the end.
  const CircularDependencyError(this.cycle);

  /// The keys of the cycle.
  final List<Key<Object>> cycle;

  @override
  String get message =>
      'Bindings depend on each other in a cycle: ${cycle.join(' -> ')}.';
}

/// A singleton holds on to something that lives only for one call.
final class CaptiveDependencyError extends GraphError {
  /// Creates the error for [singleton] reaching [scoped] along [path].
  const CaptiveDependencyError({
    required this.singleton,
    required this.scoped,
    required this.path,
  });

  /// The singleton that would capture the instance.
  final Key<Object> singleton;

  /// The call-scoped key it reaches.
  final Key<Object> scoped;

  /// The keys from [singleton] to [scoped].
  final List<Key<Object>> path;

  @override
  String get message =>
      'Singleton $singleton depends on the call-scoped $scoped '
      '(${path.join(' -> ')}). A singleton outlives a call and would keep a '
      'stale instance; make it Scoped, or resolve $scoped from a call '
      'context.';
}

/// An override replaces a key that no module declares.
final class UnusedOverrideError extends GraphError {
  /// Creates the error for [key].
  const UnusedOverrideError(this.key);

  /// The key of the override.
  final Key<Object> key;

  @override
  String get message =>
      'The override for $key matches no binding of the module graph.';
}
````

**`packages/grund/lib/src/errors/resolution_errors.dart`**

````dart
import '../di/key.dart';
import 'grund_error.dart';

/// A failure while creating or releasing values.
sealed class ResolutionError extends GrundError {
  /// Creates the error.
  const ResolutionError();
}

/// An asynchronous binding was asked for before it was ready.
final class AsyncProviderNotReadyError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const AsyncProviderNotReadyError({
    required this.key,
    required this.module,
    required this.chain,
  });

  /// The key that is not ready.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  /// The keys being created at the time, innermost first.
  final List<Key<Object>> chain;

  @override
  String get message =>
      '$key of module $module is asynchronous and not created yet. Only '
      'singletons may be asynchronous, and they must be declared in '
      'dependsOn so that they are created first.';
}

/// A factory threw.
final class ProviderCreationError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const ProviderCreationError({
    required this.key,
    required this.module,
    required this.chain,
    required this.error,
    required this.stackTrace,
  });

  /// The key whose factory failed.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  /// The keys being created at the time, innermost first.
  final List<Key<Object>> chain;

  /// What the factory threw.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message {
    final via = chain.isEmpty ? '' : ' (required by ${chain.join(' <- ')})';
    return 'Creating $key of module $module failed$via: $error';
  }
}

/// A call-scoped binding was resolved outside a call.
final class ScopedOutsideCallError extends ResolutionError {
  /// Creates the error for [key] owned by [module].
  const ScopedOutsideCallError({required this.key, required this.module});

  /// The call-scoped key.
  final Key<Object> key;

  /// The module that owns it.
  final String module;

  @override
  String get message =>
      '$key of module $module is call-scoped and can only be resolved inside '
      'a call (Injector.openCall, or the context of a request).';
}

/// A module lifecycle method threw.
final class ModuleLifecycleError extends ResolutionError {
  /// Creates the error for [phase] of [module].
  const ModuleLifecycleError({
    required this.module,
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  /// The module.
  final String module;

  /// `onInit`.
  final String phase;

  /// What was thrown.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message => '$phase of module $module failed: $error';
}

/// One step that failed while shutting down.
typedef ShutdownFailure = ({String step, Object error, StackTrace stackTrace});

/// Some shutdown steps failed; all of them were still tried.
final class ShutdownError extends ResolutionError {
  /// Creates the error for [failures].
  const ShutdownError(this.failures);

  /// The failed steps in the order they ran.
  final List<ShutdownFailure> failures;

  @override
  String get message =>
      'Shutdown failed in ${failures.length} step(s): ${[for (final f in failures) '${f.step}: ${f.error}'].join('; ')}';
}

/// A startup failed and undoing it failed too.
final class StartupRollbackError extends ResolutionError {
  /// Creates the error for [cause] and the [failures] of the rollback.
  const StartupRollbackError({
    required this.cause,
    required this.causeStackTrace,
    required this.failures,
  });

  /// The failure that stopped the startup.
  final Object cause;

  /// Where [cause] was thrown.
  final StackTrace causeStackTrace;

  /// The steps of the rollback that failed.
  final List<ShutdownFailure> failures;

  @override
  String get message =>
      'Startup failed: $cause. Undoing it failed in ${failures.length} '
      'step(s): ${[for (final f in failures) '${f.step}: ${f.error}'].join('; ')}';
}
````

**`packages/grund/lib/src/errors/app_errors.dart`**

````dart
import 'grund_error.dart';

/// A failure of the application as a whole.
sealed class AppError extends GrundError {
  /// Creates the error.
  const AppError();
}

/// An operation was attempted in a state that does not allow it.
final class ApplicationStateError extends AppError {
  /// Creates the error for [operation] refused because of [reason].
  const ApplicationStateError({required this.operation, required this.reason});

  /// What was attempted.
  final String operation;

  /// Why it cannot be done now.
  final String reason;

  @override
  String get message => 'Cannot $operation: $reason.';
}

/// `only` names runners the graph does not provide.
final class UnknownRunnerError extends AppError {
  /// Creates the error for the [unknown] names.
  const UnknownRunnerError({required this.unknown, required this.available});

  /// The names that match no runner.
  final List<String> unknown;

  /// The runners the graph provides, sorted.
  final List<String> available;

  @override
  String get message =>
      'Unknown runner(s): ${unknown.join(', ')}. The graph provides: '
      '${available.isEmpty ? 'none' : available.join(', ')}.';
}

/// Two runners of the graph answer to the same name.
final class DuplicateRunnerError extends AppError {
  /// Creates the error for the [name] that is taken twice.
  const DuplicateRunnerError(this.name);

  /// The name two runners share.
  final String name;

  @override
  String get message =>
      'Two runners are named "$name"; `only` could not tell them apart. '
      'Give each runner its own name.';
}

/// A runner failed in one of its phases.
final class RunnerError extends AppError {
  /// Creates the error for [phase] of [runner].
  const RunnerError({
    required this.runner,
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  /// The runner's name.
  final String runner;

  /// `prepare`, `start`, `stop` or `reassemble`.
  final String phase;

  /// What the runner threw.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  String get message => 'Runner "$runner" failed to $phase: $error';
}
````

- [ ] **Крок 5: Реалізація — `Key`, `Binding`, `Injector`, `CallScope`, `Disposable`**

**`packages/grund/lib/src/di/key.dart`**

````dart
import 'package:meta/meta.dart';

/// Identifies a binding: its type plus an optional [name].
@immutable
final class Key<T extends Object> {
  /// Creates the key of type [T], qualified by [name] when several bindings
  /// share the type.
  const Key([this.name]);

  /// Qualifier of the binding, or `null`.
  final String? name;

  /// The type argument, as a runtime value.
  Type get type => T;

  @override
  bool operator ==(Object other) =>
      other is Key<Object> && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => name == null ? '$T' : "$T('$name')";
}
````

**`packages/grund/lib/src/di/binding.dart`**

````dart
import 'dart:async';

import 'injector.dart';
import 'key.dart';

/// Creates the value of a [Binding]; [injector] sees what the owning module
/// sees.
typedef BindingFactory<T extends Object> =
    FutureOr<T> Function(Injector injector);

/// How long the instances of a binding live.
enum BindingScope {
  /// One instance per application.
  singleton,

  /// One instance per call.
  scoped,

  /// A new instance on every resolution.
  transient,
}

/// How one value of type [T] is created and shared.
///
/// Always write the type argument (`Singleton<Clock>(...)`): where only a
/// `List<Binding<Object>>` is expected Dart infers `Object`, which is
/// rejected.
sealed class Binding<T extends Object> {
  Binding._(this.create, {String? name, required this.dependsOn})
    : key = Key<T>(name) {
    if (T == Object) {
      throw ArgumentError(
        'A binding needs an explicit type argument, e.g. '
        'Singleton<Clock>(...); got Object.',
      );
    }
  }

  /// The key under which the value is visible.
  final Key<T> key;

  /// Creates the value.
  final BindingFactory<T> create;

  /// Keys the factory resolves; `null` means "not declared" and is checked
  /// when the factory runs.
  final List<Key<Object>>? dependsOn;

  /// How long the instances live.
  BindingScope get scope;
}

/// One instance per application, created eagerly at startup in dependency
/// order.
final class Singleton<T extends Object> extends Binding<T> {
  /// Creates a singleton whose dependencies are declared in [dependsOn].
  Singleton(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  /// Creates a singleton without declared dependencies: the escape hatch for
  /// third-party types.
  Singleton.factory(super.create, {super.name}) : super._(dependsOn: null);

  @override
  BindingScope get scope => BindingScope.singleton;
}

/// One instance per call (an HTTP request, a job run), created on first use.
final class Scoped<T extends Object> extends Binding<T> {
  /// Creates a call-scoped binding whose dependencies are declared in
  /// [dependsOn].
  Scoped(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  @override
  BindingScope get scope => BindingScope.scoped;
}

/// A new instance on every resolution.
final class Transient<T extends Object> extends Binding<T> {
  /// Creates a transient binding whose dependencies are declared in
  /// [dependsOn].
  Transient(super.create, {super.name, required List<Key<Object>> dependsOn})
    : super._(dependsOn: dependsOn);

  @override
  BindingScope get scope => BindingScope.transient;
}
````

**`packages/grund/lib/src/di/injector.dart`**

````dart
import 'call_scope.dart';

/// Resolves bindings as one module sees them.
abstract interface class Injector {
  /// The value of type [T] (and [name], when given) visible to this injector.
  ///
  /// Throws a `MissingProviderError` when nothing visible matches.
  T call<T extends Object>([String? name]);

  /// Like [call], but `null` when nothing visible matches.
  T? maybe<T extends Object>([String? name]);

  /// Every singleton of the whole graph whose binding type is a subtype of
  /// [T], in creation order.
  ///
  /// Visibility is not applied: transports collect their contributions this
  /// way. Called while the graph is still starting, it sees only the
  /// singletons created so far.
  List<T> all<T extends Object>();

  /// Opens a call scope that resolves what this injector's module sees.
  CallScope openCall();
}
````

**`packages/grund/lib/src/di/call_scope.dart`**

````dart
import 'injector.dart';

/// An [Injector] bound to one call: an HTTP request, a message, a job run.
///
/// `Scoped` bindings are created at most once per call scope and disposed by
/// [close].
abstract interface class CallScope implements Injector {
  /// Makes [value] resolvable as `T` (and [name]) for the rest of the call.
  ///
  /// Hooks use it to hand over what they computed, e.g. the current user.
  void set<T extends Object>(T value, {String? name});

  /// Disposes the call's `Scoped` instances in reverse creation order.
  ///
  /// Throws a `ShutdownError` after trying all of them when some failed.
  Future<void> close();
}
````

**`packages/grund/lib/src/di/disposable.dart`**

````dart
import 'dart:async';

/// A value that releases resources when its owner goes away.
///
/// Singletons are disposed when the container closes, `Scoped` instances when
/// their call scope closes, in reverse creation order.
abstract interface class Disposable {
  /// Releases the resources of this value.
  FutureOr<void> dispose();
}
````

- [ ] **Крок 6: Запустити — зелено; перевірити ліміти**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart format . | tail -1
dart analyze | tail -1
dart test test/di test/errors 2>&1 | tail -1
dart test 2>&1 | tail -1
find lib -name '*.dart' | xargs wc -l | awk '$1 > 300 && $2 != "total"'
find test -name '*.dart' | xargs wc -l | awk '$1 > 500 && $2 != "total"'
(cd ../grund_http && dart analyze | tail -1 && dart test 2>&1 | tail -1)
```

Очікувано: `0 changed`; `No issues found!`; `+29: All tests passed!` (key 6, binding 6, errors 17); весь пакет `+109` (80 старих + 29); два `awk` нічого не друкують (найбільший файл — `graph_errors.dart`, 215 рядків: один sealed-каталог без логіки; найдовший метод — геттер `message` `ProviderNotVisibleError`, 12 рядків); `grund_http` лишається зеленим (`+69`).

- [ ] **Крок 7: Коміт**

```bash
cd ~/projects/grund
git add -A packages/grund
git commit -m "feat(core): Key, Binding, Injector and the error families

The new core primitives live next to the parked old DI; nothing is exported
yet."
```

---

### Задача 3: `Module`, ідентичність, колектор, `ModuleGraph` і видимість

**Мета:** граф модулів, який читається один раз і перевіряється ще до першої фабрики: ідентичність модуля (клас + `qualifier`), обхід імпортів з виявленням циклів і конфліктів форми, порядок «глобальні першими», перевизначення (`overrides`), індекс видимості «власні > exports прямих імпортів (з реекспортом) > exports `global`-модулів» з `AmbiguousProviderError`. Перевірка залежностей `dependsOn` (відсутній/невидимий/цикл/captive) — окремий крок, задача 4: `ModuleGraph.build` у цій задачі ще не викликає валідатор.

**Files:**
- Create: `lib/src/di/{module,module_identity,module_exports,module_shape,module_node,module_collector,module_order,visible_binding,visibility_index,override_applier,module_graph}.dart`
- Test: `test/di/module_graph_test.dart`; допоміжні `test/helpers/{di_fixtures,module_fixtures}.dart` (у чернетці `di_fixtures` стояв у задачі 5, але на нього спираються й тести графа — переїхав сюди)

**Interfaces:**
- Consumes: `Key`, `Binding`, `BindingScope`, `Injector` (задача 2); `GraphError`-сімейство.
- Produces:

```dart
abstract class Module {
  const Module();
  List<Module> get imports => const [];
  List<Binding<Object>> get bindings => const [];
  List<Object> get exports => const [];   // Key<T>(...) або Module з imports
  Object? get qualifier => null;
  bool get global => false;
  FutureOr<void> onInit(Injector injector) {}
  FutureOr<void> onShutdown(Injector injector) {}
}
final class ModuleIdentity { const ModuleIdentity(Type type, [Object? qualifier]); factory ModuleIdentity.of(Module m); }
typedef BindingId = (ModuleIdentity module, Key<Object> key);                 // visible_binding.dart
final class VisibleBinding { const VisibleBinding(ModuleIdentity owner, Binding<Object> binding); BindingId get id; }
final class ModuleNode { /* identity, module, imports, bindings, exports: ModuleExports, global, shape, replacing(...) */ }
final class ModuleExports { const ModuleExports({required List<Key<Object>> keys, required List<ModuleIdentity> modules}); }
final class VisibilityIndex { factory VisibilityIndex.build(List<ModuleNode> nodes); VisibleBinding? lookup(ModuleIdentity from, Key<Object> key); }
final class ModuleGraph {
  factory ModuleGraph.build(Module root, {List<Binding<Object>> overrides = const []});
  final List<ModuleNode> nodes;          // глобальні й їхні імпорти першими, далі кожен імпорт перед імпортером
  final VisibilityIndex visibility;
  final ModuleNode root;
  ModuleNode? nodeOf(ModuleIdentity identity);
}
```

Правила, які фіксують тести цієї задачі: клас модуля + `qualifier` — це ідентичність (один клас у двох місцях — один вузол; два `qualifier` — два вузли); той самий клас з різною формою (імпорти, ключі binding-ів зі scope, exports, `global`) — `ConflictingModuleError`, а фабрики не порівнюються; цикл імпортів — `CircularModuleImportError` зі шляхом; дубль ключа в одному модулі — `DuplicateBindingError`, той самий тип під різними іменами дозволений; export не-ключа/не-імпорту — `InvalidExportError`; ключ, який експортують два імпорти, — `AmbiguousProviderError`, а той самий binding двома шляхами — ні; власний binding затінює імпорт; override без жодного збігу — `UnusedOverrideError`.

> **Файли на межі розбиття.** `ModuleNode` отримує `ModuleExports` (власний файл), щоб приватний конструктор мав ≤ 5 параметрів. `module_graph.dart` у цій задачі — **без** `DependencyValidator`; у задачі 4 файл замінюється повною версією.

- [ ] **Крок 1: Падаючі тести**

Фікстури: `StubModule` — модуль, чиї декларації є аргументами конструктора (підкласи `AppModule`/`DbModule`/`AuthModule`/`ConfigModule` дають різні ідентичності); `di_fixtures` — прості класи для binding-ів.

**`packages/grund/test/helpers/di_fixtures.dart`**

````dart
// Shared provider classes for the container tests.

class Clock {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

class Service {
  Service(this.repo);
  final Repo repo;
}

class Db {}

class Secret {}

class Config {}

class UsesSecret {
  UsesSecret(Secret secret);
}

class UsesDb {
  UsesDb(Db db);
}

class NeedsA {
  NeedsA(NeedsB b);
}

class NeedsB {
  NeedsB(NeedsA a);
}
````

**`packages/grund/test/helpers/module_fixtures.dart`**

````dart
import 'dart:async';

import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/injector.dart';
import 'package:grund/src/di/module.dart';

/// A module whose declarations are constructor arguments.
///
/// Subclasses give it a class, hence an identity.
base class StubModule extends Module {
  const StubModule({
    this.imports = const [],
    this.bindings = const [],
    this.exports = const [],
    this.global = false,
    this.qualifier,
    this.log,
  });

  @override
  final List<Module> imports;

  @override
  final List<Binding<Object>> bindings;

  @override
  final List<Object> exports;

  @override
  final bool global;

  @override
  final Object? qualifier;

  /// Receives `init <module>` and `shutdown <module>` entries.
  final List<String>? log;

  @override
  FutureOr<void> onInit(Injector injector) {
    log?.add('init $runtimeType');
  }

  @override
  FutureOr<void> onShutdown(Injector injector) {
    log?.add('shutdown $runtimeType');
  }
}

final class AppModule extends StubModule {
  const AppModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class DbModule extends StubModule {
  const DbModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class AuthModule extends StubModule {
  const AuthModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}

final class ConfigModule extends StubModule {
  const ConfigModule({
    super.imports,
    super.bindings,
    super.exports,
    super.global,
    super.qualifier,
    super.log,
  });
}
````

**`packages/grund/test/di/module_graph_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/di/module_identity.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Singleton<Clock> clock() =>
    Singleton<Clock>((i) => Clock(), dependsOn: const []);

Singleton<Db> db({String? name}) =>
    Singleton<Db>((i) => Db(), name: name, dependsOn: const []);

List<String> names(ModuleGraph graph) => [
  for (final node in graph.nodes) '${node.identity}',
];

void main() {
  group('ModuleGraph structure', () {
    test('orders imports before importers, the root last', () {
      const root = AppModule(
        imports: [
          AuthModule(imports: [DbModule()]),
          DbModule(),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        'DbModule',
        'AuthModule',
        'AppModule',
      ]);
    });

    test('puts global modules and their imports first', () {
      const root = AppModule(
        imports: [
          AuthModule(),
          ConfigModule(global: true, imports: [DbModule()]),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        'DbModule',
        'ConfigModule',
        'AuthModule',
        'AppModule',
      ]);
    });

    test('a module imported from two places is one node', () {
      const root = AppModule(
        imports: [
          AuthModule(imports: [DbModule()]),
          DbModule(),
        ],
      );

      expect(
        names(ModuleGraph.build(root)).where((n) => n == 'DbModule'),
        hasLength(1),
      );
    });

    test('qualifiers make two instances of one class two modules', () {
      const root = AppModule(
        imports: [
          DbModule(qualifier: 'a'),
          DbModule(qualifier: 'b'),
        ],
      );

      expect(names(ModuleGraph.build(root)), [
        "DbModule('a')",
        "DbModule('b')",
        'AppModule',
      ]);
      expect(
        ModuleGraph.build(root).nodeOf(const ModuleIdentity(DbModule, 'a')),
        isNotNull,
      );
    });

    test('rejects one identity imported with two shapes', () {
      final root = AppModule(
        imports: [
          const DbModule(),
          AuthModule(
            imports: [
              DbModule(bindings: [db()]),
            ],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ConflictingModuleError>().having(
            (e) => e.module,
            'module',
            'DbModule',
          ),
        ),
      );
    });

    test(
      'accepts one identity imported with the same shape and other factories',
      () {
        final root = AppModule(
          imports: [
            DbModule(bindings: [db()]),
            AuthModule(
              imports: [
                DbModule(bindings: [db()]),
              ],
            ),
          ],
        );

        expect(() => ModuleGraph.build(root), returnsNormally);
      },
    );

    test('rejects an import cycle with the path', () {
      // The cycle cannot be written with const values, so build it lazily.
      final a = _Cyclic('a');
      final b = _Cyclic('b');
      a.next = b;
      b.next = a;

      expect(
        () => ModuleGraph.build(a),
        throwsA(
          isA<CircularModuleImportError>().having(
            (e) => e.cycle,
            'cycle',
            hasLength(3),
          ),
        ),
      );
    });

    test('rejects a key declared twice in one module', () {
      final root = AppModule(bindings: [db(), db()]);

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<DuplicateBindingError>().having(
            (e) => e.key,
            'key',
            const Key<Db>(),
          ),
        ),
      );
    });

    test('allows the same type under different names', () {
      final root = AppModule(
        bindings: [
          db(name: 'a'),
          db(name: 'b'),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('rejects an export that is not declared', () {
      const root = AppModule(exports: [Key<Db>()]);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });

    test('rejects an exported module that is not imported', () {
      const root = AppModule(exports: [DbModule()]);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });

    test('rejects an export that is neither a key nor a module', () {
      const root = AppModule(exports: ['Db']);

      expect(() => ModuleGraph.build(root), throwsA(isA<InvalidExportError>()));
    });
  });

  group('ModuleGraph visibility', () {
    test('a module sees its own bindings and the exports of its imports', () {
      final root = AppModule(
        bindings: [clock()],
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      final graph = ModuleGraph.build(root);
      const app = ModuleIdentity(AppModule);

      expect(graph.visibility.lookup(app, const Key<Clock>()), isNotNull);
      expect(
        graph.visibility.lookup(app, const Key<Db>())?.owner,
        const ModuleIdentity(DbModule),
      );
    });

    test('what a module does not export stays private', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [db()]),
        ],
      );

      expect(
        ModuleGraph.build(
          root,
        ).visibility.lookup(const ModuleIdentity(AppModule), const Key<Db>()),
        isNull,
      );
    });

    test('a re-exported module passes its exports through', () {
      final root = AppModule(
        imports: [
          AuthModule(
            imports: [
              DbModule(bindings: [db()], exports: const [Key<Db>()]),
            ],
            exports: const [DbModule()],
          ),
        ],
      );

      expect(
        ModuleGraph.build(
          root,
        ).visibility.lookup(const ModuleIdentity(AppModule), const Key<Db>()),
        isNotNull,
      );
    });

    test('a global module is visible without being imported', () {
      final root = AppModule(
        imports: [
          ConfigModule(
            global: true,
            bindings: [clock()],
            exports: const [Key<Clock>()],
          ),
          const AuthModule(),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility.lookup(
          const ModuleIdentity(AuthModule),
          const Key<Clock>(),
        ),
        isNotNull,
      );
    });

    test('an own binding shadows an import', () {
      final root = AppModule(
        bindings: [db()],
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      expect(
        ModuleGraph.build(root).visibility
            .lookup(const ModuleIdentity(AppModule), const Key<Db>())
            ?.owner,
        const ModuleIdentity(AppModule),
      );
    });

    test('rejects a key exported by two imports', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [db()], exports: const [Key<Db>()]),
          AuthModule(bindings: [db()], exports: const [Key<Db>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<AmbiguousProviderError>().having((e) => e.owners, 'owners', [
            'AuthModule',
            'DbModule',
          ]),
        ),
      );
    });

    test('one provider reachable by two paths is not ambiguous', () {
      final shared = DbModule(bindings: [db()], exports: const [Key<Db>()]);
      final root = AppModule(
        imports: [
          shared,
          AuthModule(imports: [shared], exports: [shared]),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });
  });

  group('ModuleGraph overrides', () {
    test('replaces the binding of the key', () {
      final replacement = Singleton<Clock>((i) => Clock(), dependsOn: const []);
      final root = AppModule(bindings: [clock()]);

      final graph = ModuleGraph.build(root, overrides: [replacement]);

      expect(graph.root.bindings, hasLength(1));
      expect(graph.root.bindings[const Key<Clock>()], same(replacement));
    });

    test('rejects an override that matches nothing', () {
      final root = AppModule(bindings: [clock()]);

      expect(
        () => ModuleGraph.build(root, overrides: [db()]),
        throwsA(
          isA<UnusedOverrideError>().having(
            (e) => e.key,
            'key',
            const Key<Db>(),
          ),
        ),
      );
    });
  });
}

final class _Cyclic extends StubModule {
  _Cyclic(this.label);

  final String label;
  late Object next;

  @override
  Object? get qualifier => label;

  @override
  List<StubModule> get imports => [next as StubModule];
}
````

- [ ] **Крок 2: Запустити — очікуваний збій**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart test test/di/module_graph_test.dart 2>&1 | tail -6
```

Очікувано: `Some tests failed.`, `loading test/di/module_graph_test.dart` з помилкою компіляції (`Not found: 'package:grund/src/di/module.dart'`).

- [ ] **Крок 3: Реалізація — `Module`, ідентичність, форма**

**`packages/grund/lib/src/di/module.dart`**

````dart
import 'dart:async';

import 'binding.dart';
import 'injector.dart';

/// A unit of the application: it declares bindings, says which of them
/// other modules may use, and which modules it builds on.
///
/// Write one by hand (override the getters you need) or annotate it with
/// `@Module` and mix in the generated `$Name`, which overrides them for you.
abstract class Module {
  /// Creates the module.
  const Module();

  /// Modules whose exports this module sees.
  List<Module> get imports => const [];

  /// What this module provides.
  List<Binding<Object>> get bindings => const [];

  /// What other modules may use: keys of [bindings], and modules from
  /// [imports] whose exports are passed on.
  List<Object> get exports => const [];

  /// Tells apart several instances of one module class, e.g. two database
  /// connections; compared with `==`.
  Object? get qualifier => null;

  /// Whether the exports of this module are visible to every module without
  /// importing it.
  bool get global => false;

  /// Runs once the whole graph is created, modules in import order.
  FutureOr<void> onInit(Injector injector) {}

  /// Runs when the application closes, modules in reverse import order,
  /// before any value is disposed.
  FutureOr<void> onShutdown(Injector injector) {}
}
````

**`packages/grund/lib/src/di/module_identity.dart`**

````dart
import 'package:meta/meta.dart';

import 'module.dart';

/// What makes two module instances the same module: the class and the
/// qualifier.
@immutable
final class ModuleIdentity {
  /// Creates the identity of the module class [type] with [qualifier].
  const ModuleIdentity(this.type, [this.qualifier]);

  /// The identity of [module].
  factory ModuleIdentity.of(Module module) =>
      ModuleIdentity(module.runtimeType, module.qualifier);

  /// The module class.
  final Type type;

  /// The qualifier, or `null`.
  final Object? qualifier;

  @override
  bool operator ==(Object other) =>
      other is ModuleIdentity &&
      other.type == type &&
      other.qualifier == qualifier;

  @override
  int get hashCode => Object.hash(type, qualifier);

  @override
  String toString() => qualifier == null ? '$type' : "$type('$qualifier')";
}
````

**`packages/grund/lib/src/di/module_exports.dart`**

````dart
import 'key.dart';
import 'module_identity.dart';

/// What a module offers to the modules that import it.
final class ModuleExports {
  /// Creates the exports from [keys] and [modules].
  const ModuleExports({required this.keys, required this.modules});

  /// Keys of the module's own bindings that importers may use.
  final List<Key<Object>> keys;

  /// Imported modules whose exports are passed on.
  final List<ModuleIdentity> modules;
}
````

**`packages/grund/lib/src/di/module_shape.dart`**

````dart
import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';

/// What a module declares, compared when one identity is imported twice.
///
/// Factories are never compared: two instances may carry different
/// configuration as long as they declare the same keys.
final class ModuleShape {
  /// Creates the shape.
  const ModuleShape({
    required this.imports,
    required this.bindings,
    required this.exports,
    required this.global,
  });

  /// Identities of the imports.
  final Set<ModuleIdentity> imports;

  /// Keys of the bindings with their scope.
  final Set<(Key<Object>, BindingScope)> bindings;

  /// Exported keys and re-exported module identities.
  final Set<Object> exports;

  /// Whether the module is global.
  final bool global;

  @override
  bool operator ==(Object other) =>
      other is ModuleShape &&
      other.global == global &&
      _sameSet(other.imports, imports) &&
      _sameSet(other.bindings, bindings) &&
      _sameSet(other.exports, exports);

  @override
  int get hashCode => Object.hash(global, imports.length, bindings.length);

  static bool _sameSet(Set<Object> a, Set<Object> b) =>
      a.length == b.length && a.containsAll(b);
}
````

**`packages/grund/lib/src/di/module_node.dart`**

````dart
import '../errors/graph_errors.dart';
import 'binding.dart';
import 'key.dart';
import 'module.dart';
import 'module_exports.dart';
import 'module_identity.dart';
import 'module_shape.dart';

/// A module of the graph with its declarations read once and checked.
final class ModuleNode {
  const ModuleNode._({
    required this.identity,
    required this.module,
    required this.imports,
    required this.bindings,
    required this.exports,
  });

  /// Reads and checks [module], whose [imports] were already read.
  ///
  /// Throws [DuplicateBindingError] and [InvalidExportError].
  factory ModuleNode.of(Module module, List<Module> imports) {
    final identity = ModuleIdentity.of(module);
    final importIdentities = [for (final m in imports) ModuleIdentity.of(m)];
    final bindings = <Key<Object>, Binding<Object>>{};
    for (final binding in module.bindings) {
      if (bindings.containsKey(binding.key)) {
        throw DuplicateBindingError(key: binding.key, module: '$identity');
      }
      bindings[binding.key] = binding;
    }
    final keys = <Key<Object>>[];
    final reexports = <ModuleIdentity>[];
    for (final export in module.exports) {
      switch (export) {
        case Key<Object>() when bindings.containsKey(export):
          keys.add(export);
        case Module() when importIdentities.contains(ModuleIdentity.of(export)):
          reexports.add(ModuleIdentity.of(export));
        default:
          throw InvalidExportError(export: export, module: '$identity');
      }
    }
    return ModuleNode._(
      identity: identity,
      module: module,
      imports: importIdentities,
      bindings: bindings,
      exports: ModuleExports(keys: keys, modules: reexports),
    );
  }

  /// Who this module is.
  final ModuleIdentity identity;

  /// The instance the declarations were read from.
  final Module module;

  /// Identities of the imported modules, in declaration order.
  final List<ModuleIdentity> imports;

  /// The bindings in declaration order.
  final Map<Key<Object>, Binding<Object>> bindings;

  /// What importers of this module may use.
  final ModuleExports exports;

  /// Whether the exports are visible everywhere.
  bool get global => module.global;

  /// What this module declares, for comparing two instances of one identity.
  ModuleShape get shape => ModuleShape(
    imports: imports.toSet(),
    bindings: {for (final b in bindings.values) (b.key, b.scope)},
    exports: {...exports.keys, ...exports.modules},
    global: global,
  );

  /// This node with [replacement] in place of the binding of its key.
  ModuleNode replacing(Binding<Object> replacement) => ModuleNode._(
    identity: identity,
    module: module,
    imports: imports,
    bindings: {...bindings, replacement.key: replacement},
    exports: exports,
  );
}
````

- [ ] **Крок 4: Реалізація — обхід, порядок, перевизначення, видимість, граф**

**`packages/grund/lib/src/di/module_collector.dart`**

````dart
import '../errors/graph_errors.dart';
import 'module.dart';
import 'module_identity.dart';
import 'module_node.dart';

/// Reads a module and everything it imports into nodes, imports first.
final class ModuleCollector {
  final Map<ModuleIdentity, ModuleNode> _nodes = {};
  final List<ModuleIdentity> _path = [];

  /// The nodes reachable from [root], each import before its importers and
  /// [root] last.
  ///
  /// Throws [CircularModuleImportError] and [ConflictingModuleError], and
  /// what [ModuleNode.of] throws.
  List<ModuleNode> collect(Module root) {
    _visit(root);
    return _nodes.values.toList();
  }

  void _visit(Module module) {
    final identity = ModuleIdentity.of(module);
    final known = _nodes[identity];
    if (known != null) {
      _requireSameShape(known, module);
      return;
    }
    final start = _path.indexOf(identity);
    if (start >= 0) {
      throw CircularModuleImportError([
        for (final step in [..._path.sublist(start), identity]) '$step',
      ]);
    }
    final imports = module.imports;
    _path.add(identity);
    imports.forEach(_visit);
    _path.removeLast();
    _nodes[identity] = ModuleNode.of(module, imports);
  }

  void _requireSameShape(ModuleNode known, Module other) {
    if (identical(known.module, other)) return;
    if (ModuleNode.of(other, other.imports).shape != known.shape) {
      throw ConflictingModuleError('${known.identity}');
    }
  }
}
````

**`packages/grund/lib/src/di/module_order.dart`**

````dart
import 'module_identity.dart';
import 'module_node.dart';

/// Puts the global modules, and what they import, ahead of the rest.
abstract final class ModuleOrder {
  /// [nodes] (imports before importers) with the globals first, keeping the
  /// relative order within both halves.
  static List<ModuleNode> globalsFirst(List<ModuleNode> nodes) {
    final byIdentity = {for (final n in nodes) n.identity: n};
    final early = <ModuleIdentity>{};
    void include(ModuleIdentity identity) {
      if (!early.add(identity)) return;
      final node = byIdentity[identity];
      if (node != null) node.imports.forEach(include);
    }

    for (final node in nodes.where((n) => n.global)) {
      include(node.identity);
    }
    return [
      ...nodes.where((n) => early.contains(n.identity)),
      ...nodes.where((n) => !early.contains(n.identity)),
    ];
  }
}
````

**`packages/grund/lib/src/di/override_applier.dart`**

````dart
import '../errors/graph_errors.dart';
import 'binding.dart';
import 'module_node.dart';

/// Replaces bindings by key, for tests and development.
abstract final class OverrideApplier {
  /// [nodes] with every binding whose key an override names replaced by it.
  ///
  /// Throws [UnusedOverrideError] for an override that matches no binding.
  static List<ModuleNode> apply(
    List<ModuleNode> nodes,
    List<Binding<Object>> overrides,
  ) {
    var result = nodes;
    for (final override in overrides) {
      if (!result.any((n) => n.bindings.containsKey(override.key))) {
        throw UnusedOverrideError(override.key);
      }
      result = [
        for (final node in result)
          node.bindings.containsKey(override.key)
              ? node.replacing(override)
              : node,
      ];
    }
    return result;
  }
}
````

**`packages/grund/lib/src/di/visible_binding.dart`**

````dart
import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';

/// Names one binding of the graph: the module that declares it and its key.
typedef BindingId = (ModuleIdentity module, Key<Object> key);

/// A binding together with the module that declares it.
final class VisibleBinding {
  /// Creates the pair.
  const VisibleBinding(this.owner, this.binding);

  /// The declaring module.
  final ModuleIdentity owner;

  /// The binding.
  final Binding<Object> binding;

  /// Identifies the binding in the whole graph.
  BindingId get id => (owner, binding.key);
}
````

**`packages/grund/lib/src/di/visibility_index.dart`**

````dart
import '../errors/graph_errors.dart';
import 'key.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'visible_binding.dart';

/// What every module of the graph can resolve.
///
/// A module sees its own bindings, then the exports of the modules it
/// imports (following re-exports), then the exports of global modules. An
/// earlier tier shadows a later one; two owners in one tier are ambiguous.
final class VisibilityIndex {
  VisibilityIndex._(this._visible);

  /// Builds the index for [nodes].
  ///
  /// Throws [AmbiguousProviderError].
  factory VisibilityIndex.build(List<ModuleNode> nodes) {
    final builder = _VisibilityBuilder(nodes);
    return VisibilityIndex._({
      for (final node in nodes) node.identity: builder.visibleTo(node),
    });
  }

  final Map<ModuleIdentity, Map<Key<Object>, VisibleBinding>> _visible;

  /// What [module] can resolve for [key], or `null`.
  VisibleBinding? lookup(ModuleIdentity module, Key<Object> key) =>
      _visible[module]?[key];
}

final class _VisibilityBuilder {
  _VisibilityBuilder(this._nodes)
    : _byIdentity = {for (final n in _nodes) n.identity: n};

  final List<ModuleNode> _nodes;
  final Map<ModuleIdentity, ModuleNode> _byIdentity;
  final Map<ModuleIdentity, Map<Key<Object>, VisibleBinding>> _exports = {};

  Map<Key<Object>, VisibleBinding> visibleTo(ModuleNode node) {
    final own = {
      for (final entry in node.bindings.entries)
        entry.key: VisibleBinding(node.identity, entry.value),
    };
    final imported = _pick(node, [
      for (final identity in node.imports) _exportsOf(identity),
    ], own);
    final fromGlobals = _pick(
      node,
      [
        for (final other in _nodes)
          if (other.global && other.identity != node.identity)
            _exportsOf(other.identity),
      ],
      {...imported, ...own},
    );
    return {...fromGlobals, ...imported, ...own};
  }

  Map<Key<Object>, VisibleBinding> _exportsOf(ModuleIdentity identity) {
    final cached = _exports[identity];
    if (cached != null) return cached;
    final node = _byIdentity[identity];
    if (node == null) return const {};
    final exported = {
      for (final MapEntry(:key, :value) in node.bindings.entries)
        if (node.exports.keys.contains(key))
          key: VisibleBinding(identity, value),
      for (final reexported in node.exports.modules) ..._exportsOf(reexported),
    };
    return _exports[identity] = exported;
  }

  /// The candidates of one tier, minus what [shadowing] already defines.
  Map<Key<Object>, VisibleBinding> _pick(
    ModuleNode node,
    List<Map<Key<Object>, VisibleBinding>> tier,
    Map<Key<Object>, VisibleBinding> shadowing,
  ) {
    final candidates = <Key<Object>, List<VisibleBinding>>{};
    for (final exports in tier) {
      for (final MapEntry(:key, :value) in exports.entries) {
        if (shadowing.containsKey(key)) continue;
        final owners = candidates.putIfAbsent(key, () => []);
        if (!owners.any((o) => o.owner == value.owner)) owners.add(value);
      }
    }
    return {
      for (final MapEntry(:key, :value) in candidates.entries)
        key: value.length == 1 ? value.single : _ambiguous(node, key, value),
    };
  }

  Never _ambiguous(
    ModuleNode node,
    Key<Object> key,
    List<VisibleBinding> owners,
  ) => throw AmbiguousProviderError(
    key: key,
    module: '${node.identity}',
    owners: ([for (final o in owners) '${o.owner}']..sort()),
  );
}
````

**`packages/grund/lib/src/di/module_graph.dart`**

````dart
import 'binding.dart';
import 'module.dart';
import 'module_collector.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'module_order.dart';
import 'override_applier.dart';
import 'visibility_index.dart';

/// A validated module graph: every module, what it sees, nothing created yet.
final class ModuleGraph {
  ModuleGraph._(this.nodes, this.visibility, this._byIdentity, this.root);

  /// Reads and validates the graph below [root], with [overrides] applied.
  ///
  /// Every problem of structure and visibility is a `GraphError` thrown
  /// here, before any factory runs.
  factory ModuleGraph.build(
    Module root, {
    List<Binding<Object>> overrides = const [],
  }) {
    final nodes = OverrideApplier.apply(
      ModuleOrder.globalsFirst(ModuleCollector().collect(root)),
      overrides,
    );
    final visibility = VisibilityIndex.build(nodes);
    final rootIdentity = ModuleIdentity.of(root);
    return ModuleGraph._(nodes, visibility, {
      for (final node in nodes) node.identity: node,
    }, nodes.firstWhere((n) => n.identity == rootIdentity));
  }

  /// The modules: globals and their imports first, then each import before
  /// its importers.
  final List<ModuleNode> nodes;

  /// What every module can resolve.
  final VisibilityIndex visibility;

  final Map<ModuleIdentity, ModuleNode> _byIdentity;

  /// The node of [identity], or `null` when the graph has no such module.
  ModuleNode? nodeOf(ModuleIdentity identity) => _byIdentity[identity];

  /// The module the graph was built from.
  final ModuleNode root;
}
````

- [ ] **Крок 5: Запустити — зелено; ліміти**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart format . | tail -1
dart analyze | tail -1
dart test test/di/module_graph_test.dart 2>&1 | tail -1
dart test 2>&1 | tail -1
find lib -name '*.dart' | xargs wc -l | awk '$1 > 300 && $2 != "total"'
find test -name '*.dart' | xargs wc -l | awk '$1 > 500 && $2 != "total"'
```

Очікувано: `0 changed`; `No issues found!`; `+21: All tests passed!`; пакет `+130`; `awk` порожні (найбільший тест — `module_graph_test.dart`, 355 ≤ 500; найдовший метод — `ModuleNode.of`, 31 рядок ≤ 40, вкладеність ≤ 3).

- [ ] **Крок 6: Коміт**

```bash
cd ~/projects/grund
git add -A packages/grund
git commit -m "feat(core): Module, identity, collector, ModuleGraph and visibility

Reads the module graph once and checks its structure and visibility before
any factory runs."
```

---

### Задача 4: Валідатор залежностей (cycle/captive/visibility) і `CreationPlan`

**Мета:** усе, що можна знати про залежності **до** запуску фабрик, `ModuleGraph.build` перевіряє за декларованим `dependsOn`: відсутній ключ (`MissingProviderError`), ключ, що існує, але невидимий (`ProviderNotVisibleError` з ланцюжком імпортів), цикл (`CircularDependencyError`), singleton, що через `Scoped` (навіть крізь `Transient`) тримає запит (`CaptiveDependencyError`). `Singleton.factory` (без `dependsOn`) пропускається — його перевіряє рантайм у задачі 5. `CreationPlan` дає порядок створення singleton-ів: залежності першими, інакше — порядок модулів і оголошень.

**Files:**
- Create: `lib/src/di/{dependency_validator,creation_plan}.dart`
- Modify: `lib/src/di/module_graph.dart` (викликає валідатор)
- Test: `test/di/dependency_validator_test.dart`

**Interfaces:**
- Consumes: `ModuleNode`, `VisibilityIndex`, `VisibleBinding`, `BindingId` (задача 3), `GraphError`-сімейство (задача 2).
- Produces:

```dart
final class DependencyValidator {
  DependencyValidator(List<ModuleNode> nodes, VisibilityIndex visibility);
  void validate();   // MissingProviderError | ProviderNotVisibleError | CircularDependencyError | CaptiveDependencyError
}
final class CreationPlan {
  factory CreationPlan.of(ModuleGraph graph);
  final List<BindingId> order;   // лише singleton-и
}
```

- [ ] **Крок 1: Падаючий тест**

**`packages/grund/test/di/dependency_validator_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/creation_plan.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/di/module_identity.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Singleton<Clock> clock() =>
    Singleton<Clock>((i) => Clock(), dependsOn: const []);

Singleton<Repo> repo() =>
    Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]);

void main() {
  group('dependency validation', () {
    test('accepts dependencies in any declaration order', () {
      final root = AppModule(bindings: [repo(), clock()]);

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('rejects a dependency nothing provides', () {
      final root = AppModule(bindings: [repo()]);

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', const Key<Clock>())
              .having((e) => e.requiredBy, 'requiredBy', const Key<Repo>())
              .having((e) => e.module, 'module', 'AppModule'),
        ),
      );
    });

    test('names the module that declares a key which is not exported', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          DbModule(bindings: [clock()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>()
              .having((e) => e.declaredIn, 'declaredIn', ['DbModule'])
              .having((e) => e.importChain, 'importChain', [
                'AppModule',
                'DbModule',
              ]),
        ),
      );
    });

    test('shows the import chain when the declaring module is indirect', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          AuthModule(
            imports: [
              DbModule(bindings: [clock()]),
            ],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>().having(
            (e) => e.importChain,
            'importChain',
            ['AppModule', 'AuthModule', 'DbModule'],
          ),
        ),
      );
    });

    test('has no chain when the declaring module cannot be reached', () {
      final root = AppModule(
        imports: [
          DbModule(bindings: [repo()]),
          AuthModule(bindings: [clock()], exports: const [Key<Clock>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<ProviderNotVisibleError>()
              .having((e) => e.module, 'module', 'DbModule')
              .having((e) => e.declaredIn, 'declaredIn', ['AuthModule'])
              .having((e) => e.importChain, 'importChain', isEmpty),
        ),
      );
    });

    test('rejects a dependency cycle and prints it', () {
      final root = AppModule(
        bindings: [
          Singleton<NeedsA>(
            (i) => NeedsA(i()),
            dependsOn: const [Key<NeedsB>()],
          ),
          Singleton<NeedsB>(
            (i) => NeedsB(i()),
            dependsOn: const [Key<NeedsA>()],
          ),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<CircularDependencyError>().having((e) => e.cycle, 'cycle', [
            const Key<NeedsA>(),
            const Key<NeedsB>(),
            const Key<NeedsA>(),
          ]),
        ),
      );
    });

    test('rejects a binding that depends on itself', () {
      final root = AppModule(
        bindings: [
          Transient<Clock>((i) => Clock(), dependsOn: const [Key<Clock>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(isA<CircularDependencyError>()),
      );
    });

    test('rejects a singleton that depends on a scoped binding', () {
      final root = AppModule(
        bindings: [
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Singleton<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
        ],
      );

      expect(
        () => ModuleGraph.build(root),
        throwsA(
          isA<CaptiveDependencyError>()
              .having((e) => e.singleton, 'singleton', const Key<UsesDb>())
              .having((e) => e.scoped, 'scoped', const Key<Db>()),
        ),
      );
    });

    test(
      'rejects a singleton that reaches a scoped binding through a transient',
      () {
        final root = AppModule(
          bindings: [
            Scoped<Db>((i) => Db(), dependsOn: const []),
            Transient<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
            Singleton<Repo>(
              (i) => Repo(Clock()),
              dependsOn: const [Key<UsesDb>()],
            ),
          ],
        );

        expect(
          () => ModuleGraph.build(root),
          throwsA(
            isA<CaptiveDependencyError>().having((e) => e.path, 'path', [
              const Key<Repo>(),
              const Key<UsesDb>(),
              const Key<Db>(),
            ]),
          ),
        );
      },
    );

    test('lets scoped and transient bindings depend on scoped ones', () {
      final root = AppModule(
        bindings: [
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Scoped<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
          Transient<Repo>(
            (i) => Repo(Clock()),
            dependsOn: const [Key<UsesDb>()],
          ),
        ],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });

    test('skips bindings whose dependencies are not declared', () {
      final root = AppModule(
        bindings: [Singleton<Repo>.factory((i) => Repo(i()))],
      );

      expect(() => ModuleGraph.build(root), returnsNormally);
    });
  });

  group('CreationPlan', () {
    test('creates dependencies first, across modules', () {
      final root = AppModule(
        bindings: [repo()],
        imports: [
          DbModule(bindings: [clock()], exports: const [Key<Clock>()]),
        ],
      );

      final order = CreationPlan.of(ModuleGraph.build(root)).order;

      expect(order, [
        (const ModuleIdentity(DbModule), const Key<Clock>()),
        (const ModuleIdentity(AppModule), const Key<Repo>()),
      ]);
    });

    test('follows declared dependencies through transient bindings', () {
      final root = AppModule(
        bindings: [
          Singleton<Repo>(
            (i) => Repo(Clock()),
            dependsOn: const [Key<UsesDb>()],
          ),
          Transient<UsesDb>(
            (i) => UsesDb(i()),
            dependsOn: const [Key<Clock>()],
          ),
          clock(),
        ],
      );

      final keys = [
        for (final (_, key) in CreationPlan.of(ModuleGraph.build(root)).order)
          key,
      ];

      expect(keys, [const Key<Clock>(), const Key<Repo>()]);
    });

    test('lists singletons only', () {
      final root = AppModule(
        bindings: [
          clock(),
          Scoped<Db>((i) => Db(), dependsOn: const []),
          Transient<Config>((i) => Config(), dependsOn: const []),
        ],
      );

      expect(CreationPlan.of(ModuleGraph.build(root)).order, hasLength(1));
    });
  });
}
````

- [ ] **Крок 2: Запустити — очікуваний збій**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart test test/di/dependency_validator_test.dart 2>&1 | tail -6
```

Очікувано: `Some tests failed.`, помилка компіляції `Not found: 'package:grund/src/di/creation_plan.dart'`.

- [ ] **Крок 3: Реалізація**

**`packages/grund/lib/src/di/dependency_validator.dart`**

````dart
import '../errors/graph_errors.dart';
import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'visibility_index.dart';
import 'visible_binding.dart';

/// Checks the declared dependencies of a graph before any factory runs.
///
/// Bindings without `dependsOn` are skipped: they are checked when their
/// factory resolves something.
final class DependencyValidator {
  /// Creates a validator for [nodes] and what they see.
  DependencyValidator(this._nodes, this._visibility)
    : _byIdentity = {for (final n in _nodes) n.identity: n};

  final List<ModuleNode> _nodes;
  final VisibilityIndex _visibility;
  final Map<ModuleIdentity, ModuleNode> _byIdentity;
  final Map<BindingId, _Mark> _marks = {};

  /// Throws [MissingProviderError], [ProviderNotVisibleError],
  /// [CircularDependencyError] or [CaptiveDependencyError].
  void validate() {
    for (final node in _nodes) {
      for (final binding in node.bindings.values) {
        _requireVisible(node, binding);
      }
    }
    for (final ref in _allBindings()) {
      _findCycle(ref, const []);
    }
    for (final ref in _allBindings()) {
      if (ref.binding.scope == BindingScope.singleton) _findCaptive(ref);
    }
  }

  Iterable<VisibleBinding> _allBindings() sync* {
    for (final node in _nodes) {
      for (final binding in node.bindings.values) {
        yield VisibleBinding(node.identity, binding);
      }
    }
  }

  List<VisibleBinding> _dependenciesOf(VisibleBinding ref) {
    final dependencies = <VisibleBinding>[];
    for (final key in ref.binding.dependsOn ?? const <Key<Object>>[]) {
      final visible = _visibility.lookup(ref.owner, key);
      if (visible != null) dependencies.add(visible);
    }
    return dependencies;
  }

  void _requireVisible(ModuleNode node, Binding<Object> binding) {
    for (final key in binding.dependsOn ?? const <Key<Object>>[]) {
      if (_visibility.lookup(node.identity, key) != null) continue;
      final declaring = [
        for (final other in _nodes)
          if (other.bindings.containsKey(key)) other.identity,
      ];
      if (declaring.isEmpty) {
        throw MissingProviderError(
          key: key,
          module: '${node.identity}',
          requiredBy: binding.key,
        );
      }
      throw ProviderNotVisibleError(
        key: key,
        module: '${node.identity}',
        requiredBy: binding.key,
        declaredIn: [for (final d in declaring) '$d'],
        importChain: _importChain(node.identity, declaring),
      );
    }
  }

  List<String> _importChain(ModuleIdentity from, List<ModuleIdentity> targets) {
    final parents = <ModuleIdentity, ModuleIdentity>{};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      if (targets.contains(current) && current != from) {
        final chain = [current];
        while (chain.first != from) {
          final parent = parents[chain.first];
          if (parent == null) break;
          chain.insert(0, parent);
        }
        return [for (final step in chain) '$step'];
      }
      for (final next
          in _byIdentity[current]?.imports ?? const <ModuleIdentity>[]) {
        if (next != from &&
            parents.putIfAbsent(next, () => current) == current) {
          queue.add(next);
        }
      }
    }
    return const [];
  }

  void _findCycle(VisibleBinding ref, List<VisibleBinding> path) {
    switch (_marks[ref.id]) {
      case _Mark.done:
        return;
      case _Mark.active:
        final start = path.indexWhere((p) => p.id == ref.id);
        throw CircularDependencyError([
          for (final step in [...path.sublist(start), ref]) step.binding.key,
        ]);
      case null:
        _marks[ref.id] = _Mark.active;
        for (final dependency in _dependenciesOf(ref)) {
          _findCycle(dependency, [...path, ref]);
        }
        _marks[ref.id] = _Mark.done;
    }
  }

  void _findCaptive(VisibleBinding singleton) {
    final seen = <BindingId>{};
    void walk(VisibleBinding ref, List<Key<Object>> path) {
      for (final dependency in _dependenciesOf(ref)) {
        if (!seen.add(dependency.id)) continue;
        final trail = [...path, dependency.binding.key];
        switch (dependency.binding.scope) {
          case BindingScope.scoped:
            throw CaptiveDependencyError(
              singleton: singleton.binding.key,
              scoped: dependency.binding.key,
              path: trail,
            );
          case BindingScope.transient:
            walk(dependency, trail);
          case BindingScope.singleton:
            break;
        }
      }
    }

    walk(singleton, [singleton.binding.key]);
  }
}

enum _Mark { active, done }
````

**`packages/grund/lib/src/di/creation_plan.dart`**

````dart
import 'binding.dart';
import 'key.dart';
import 'module_graph.dart';
import 'visible_binding.dart';

/// The order in which singletons are created: every singleton after the
/// ones its factory declares in `dependsOn`, otherwise in the order of the
/// modules and of the declarations.
final class CreationPlan {
  CreationPlan._(this.order);

  /// Plans the singletons of [graph].
  factory CreationPlan.of(ModuleGraph graph) {
    final builder = _PlanBuilder(graph);
    for (final node in graph.nodes) {
      for (final binding in node.bindings.values) {
        builder.visit(VisibleBinding(node.identity, binding));
      }
    }
    return CreationPlan._(builder.order);
  }

  /// The singletons to create, first to last.
  final List<BindingId> order;
}

final class _PlanBuilder {
  _PlanBuilder(this._graph);

  final ModuleGraph _graph;
  final Set<BindingId> _visited = {};
  final List<BindingId> order = [];

  void visit(VisibleBinding ref) {
    if (!_visited.add(ref.id)) return;
    for (final key in ref.binding.dependsOn ?? const <Key<Object>>[]) {
      final dependency = _graph.visibility.lookup(ref.owner, key);
      if (dependency != null) visit(dependency);
    }
    if (ref.binding.scope == BindingScope.singleton) order.add(ref.id);
  }
}
````

`ModuleGraph.build` тепер викликає валідатор (повна версія файла замінює версію задачі 3: додано імпорт, рядок `DependencyValidator(nodes, visibility).validate();` і доповнено doc-коментар):

**`packages/grund/lib/src/di/module_graph.dart`**

````dart
import 'binding.dart';
import 'dependency_validator.dart';
import 'module.dart';
import 'module_collector.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'module_order.dart';
import 'override_applier.dart';
import 'visibility_index.dart';

/// A validated module graph: every module, what it sees, nothing created yet.
final class ModuleGraph {
  ModuleGraph._(this.nodes, this.visibility, this._byIdentity, this.root);

  /// Reads and validates the graph below [root], with [overrides] applied.
  ///
  /// Every problem of structure, visibility and declared dependencies is a
  /// `GraphError` thrown here, before any factory runs.
  factory ModuleGraph.build(
    Module root, {
    List<Binding<Object>> overrides = const [],
  }) {
    final nodes = OverrideApplier.apply(
      ModuleOrder.globalsFirst(ModuleCollector().collect(root)),
      overrides,
    );
    final visibility = VisibilityIndex.build(nodes);
    DependencyValidator(nodes, visibility).validate();
    final rootIdentity = ModuleIdentity.of(root);
    return ModuleGraph._(nodes, visibility, {
      for (final node in nodes) node.identity: node,
    }, nodes.firstWhere((n) => n.identity == rootIdentity));
  }

  /// The modules: globals and their imports first, then each import before
  /// its importers.
  final List<ModuleNode> nodes;

  /// What every module can resolve.
  final VisibilityIndex visibility;

  final Map<ModuleIdentity, ModuleNode> _byIdentity;

  /// The node of [identity], or `null` when the graph has no such module.
  ModuleNode? nodeOf(ModuleIdentity identity) => _byIdentity[identity];

  /// The module the graph was built from.
  final ModuleNode root;
}
````

- [ ] **Крок 4: Запустити — зелено; ліміти**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart format . | tail -1
dart analyze | tail -1
dart test test/di/dependency_validator_test.dart 2>&1 | tail -1
dart test 2>&1 | tail -1
find lib -name '*.dart' | xargs wc -l | awk '$1 > 300 && $2 != "total"'
find test -name '*.dart' | xargs wc -l | awk '$1 > 500 && $2 != "total"'
```

Очікувано: `0 changed`; `No issues found!`; `+14: All tests passed!` (з них 3 — `CreationPlan`); пакет `+144`; ліміти в нормі (`dependency_validator.dart` 148 рядків, найдовший метод 24; `module_graph_test` не змінювався).

- [ ] **Крок 5: Коміт**

```bash
cd ~/projects/grund
git add -A packages/grund
git commit -m "feat(core): dependency validation and the creation plan

ModuleGraph.build now rejects missing, invisible, circular and captive
dependencies declared in dependsOn before any factory runs."
```

---

### Задача 5: `Container`, call-скоупи, lifecycle, reassemble, `CallContext`

**Мета:** середовище виконання графа: створення singleton-ів у порядку `CreationPlan` (асинхронні фабрики очікуються), `Scoped` — по одному на call-скоуп і `dispose` при `close()`, `Transient` — щоразу новий, `onInit`/`onShutdown` модулів, відкат невдалого старту, `Container.reassemble` (singleton-и з незмінними модулем і ключем переходять у новий контейнер), `CallContext` і `CancelSignal` для транспортів.

**Files:**
- Create: `lib/src/di/{shutdown_steps,call_state,injection_runtime,module_view,call_view,container_lifecycle,container}.dart`, `lib/src/call/{cancel_signal,call_context}.dart`
- Test: `test/di/container_{startup,scopes,lifecycle,reassemble}_test.dart`, `test/call/{cancel_signal,call_context}_test.dart`, `test/helpers/tracked.dart`

**Interfaces:**
- Consumes: `ModuleGraph`, `CreationPlan`, `VisibleBinding`, `Injector`, `CallScope`, `Disposable`, помилки `ResolutionError`-сімейства.
- Produces:

```dart
final class Container {
  static Future<Container> create(ModuleGraph graph, {Container? previous});
  Injector get root;
  List<T> all<T extends Object>();
  Future<Container> reassemble(ModuleGraph newGraph);
  Future<void> abandon();
  Future<void> close();            // ідемпотентний; ShutdownError збирає всі збої
}
final class CancelSignal { bool get isCancelled; Future<void> get whenCancelled; void cancel(); }
base class CallContext {
  CallContext(CallScope scope, {CancelSignal? cancel});
  final CallScope scope; final CancelSignal cancel;
  T call<T extends Object>([String? name]); T? maybe<T extends Object>([String? name]);
  void set<T extends Object>(T value, {String? name}); Future<void> close();
}
```

Review Focus: **RF-2** — `container_scopes_test.dart`: «calls that overlap keep their values and instances apart» (паралельні виклики не бачать `set` один одного), «a call that failed halfway still disposes what it created» (`Scoped` dispose після кидка), «a value set on the call is resolvable in it only»; **RF-5** — `container_lifecycle_test.dart`: «close is idempotent», «close tries every step and reports all failures»; **RF-4** (рівень контейнера) — «a failing factory disposes what was already created», «a failing rollback is reported next to the original cause».

- [ ] **Крок 1: Падаючі тести**

**`packages/grund/test/helpers/tracked.dart`**

````dart
import 'dart:async';

import 'package:grund/src/di/disposable.dart';

/// A [Disposable] that writes to a log, optionally failing.
final class Tracked implements Disposable {
  Tracked(this.name, this.log, {this.failure});

  final String name;
  final List<String> log;
  final Object? failure;

  @override
  FutureOr<void> dispose() {
    log.add('dispose $name');
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}
````

**`packages/grund/test/call/cancel_signal_test.dart`**

````dart
import 'dart:async';

import 'package:grund/src/call/cancel_signal.dart';
import 'package:test/test.dart';

void main() {
  group('CancelSignal', () {
    test('is not cancelled at first', () {
      expect(CancelSignal().isCancelled, isFalse);
    });

    test('cancel completes whenCancelled and flips isCancelled', () async {
      final signal = CancelSignal();
      var notified = false;
      unawaited(signal.whenCancelled.then((_) => notified = true));

      signal.cancel();
      await signal.whenCancelled;

      expect(signal.isCancelled, isTrue);
      expect(notified, isTrue);
    });

    test('a second cancel does nothing', () async {
      final signal = CancelSignal()
        ..cancel()
        ..cancel();

      await signal.whenCancelled;

      expect(signal.isCancelled, isTrue);
    });
  });
}
````

**`packages/grund/test/call/call_context_test.dart`**

````dart
import 'package:grund/src/call/call_context.dart';
import 'package:grund/src/call/cancel_signal.dart';
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Future<CallContext> openContext(
  List<Binding<Object>> bindings, {
  CancelSignal? cancel,
}) async {
  final container = await Container.create(
    ModuleGraph.build(AppModule(bindings: bindings)),
  );
  return CallContext(container.root.openCall(), cancel: cancel);
}

void main() {
  group('CallContext', () {
    test('resolves singletons and scoped bindings of its module', () async {
      final context = await openContext([
        Singleton<Clock>((i) => Clock(), dependsOn: const []),
        Scoped<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
      ]);

      expect(context<Repo>().clock, same(context<Clock>()));
      expect(context.maybe<Secret>(), isNull);
    });

    test('a value set by a hook is found by type', () async {
      final context = await openContext(const []);
      final secret = Secret();

      context.set<Secret>(secret);

      expect(context<Secret>(), same(secret));
    });

    test('a named value does not answer for the unnamed one', () async {
      final context = await openContext(const []);

      context.set<Secret>(Secret(), name: 'admin');

      expect(context.maybe<Secret>(), isNull);
      expect(context.maybe<Secret>('admin'), isNotNull);
    });

    test('close disposes the scoped instances of the call', () async {
      final log = <String>[];
      final context = await openContext([
        Scoped<Tracked>((i) => Tracked('tx', log), dependsOn: const []),
      ]);
      context<Tracked>();

      await context.close();

      expect(log, ['dispose tx']);
    });

    test('has its own cancel signal unless one is given', () async {
      final own = await openContext(const []);
      final given = CancelSignal();
      final shared = await openContext(const [], cancel: given);

      expect(own.cancel.isCancelled, isFalse);
      expect(shared.cancel, same(given));
    });
  });
}
````

**`packages/grund/test/di/container_startup_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';

Future<Container> start(
  StubModule root, {
  List<Binding<Object>> overrides = const [],
}) => Container.create(ModuleGraph.build(root, overrides: overrides));

void main() {
  group('Container startup', () {
    test('creates singletons in dependency order, once', () async {
      final created = <String>[];
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Service>((i) {
              created.add('Service');
              return Service(i());
            }, dependsOn: const [Key<Repo>()]),
            Singleton<Repo>((i) {
              created.add('Repo');
              return Repo(i());
            }, dependsOn: const [Key<Clock>()]),
            Singleton<Clock>((i) {
              created.add('Clock');
              return Clock();
            }, dependsOn: const []),
          ],
        ),
      );

      final service = container.root<Service>();

      expect(created, ['Clock', 'Repo', 'Service']);
      expect(service.repo.clock, same(container.root<Clock>()));
      expect(container.root<Service>(), same(service));
    });

    test(
      'resolves undeclared dependencies of a factory when it runs',
      () async {
        var clocks = 0;
        final container = await start(
          AppModule(
            bindings: [
              Singleton<Repo>.factory((i) => Repo(i())),
              Singleton<Clock>((i) {
                clocks++;
                return Clock();
              }, dependsOn: const []),
            ],
          ),
        );

        expect(container.root<Repo>().clock, same(container.root<Clock>()));
        expect(clocks, 1);
      },
    );

    test('waits for an asynchronous singleton declared in dependsOn', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<UsesDb>((i) => UsesDb(i()), dependsOn: const [Key<Db>()]),
            Singleton<Db>((i) async {
              await Future<void>.delayed(Duration.zero);
              return Db();
            }, dependsOn: const []),
          ],
        ),
      );

      expect(container.root<UsesDb>(), isA<UsesDb>());
    });

    test(
      'rejects an asynchronous singleton that was not declared first',
      () async {
        final graph = ModuleGraph.build(
          AppModule(
            bindings: [
              Singleton<UsesDb>.factory((i) => UsesDb(i())),
              Singleton<Db>((i) async => Db(), dependsOn: const []),
            ],
          ),
        );

        await expectLater(
          Container.create(graph),
          throwsA(
            isA<AsyncProviderNotReadyError>().having(
              (e) => e.key,
              'key',
              const Key<Db>(),
            ),
          ),
        );
      },
    );

    test('detects a cycle that only the factories reveal', () async {
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            Singleton<NeedsA>.factory((i) => NeedsA(i())),
            Singleton<NeedsB>.factory((i) => NeedsB(i())),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<CircularDependencyError>().having((e) => e.cycle, 'cycle', [
            const Key<NeedsA>(),
            const Key<NeedsB>(),
            const Key<NeedsA>(),
          ]),
        ),
      );
    });

    test('wraps a failing factory with the key, module and cause', () async {
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            Singleton<Clock>(
              (i) => throw StateError('no clock'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<ProviderCreationError>()
              .having((e) => e.key, 'key', const Key<Clock>())
              .having((e) => e.module, 'module', 'AppModule')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.stackTrace, 'stackTrace', isNotNull),
        ),
      );
    });

    test('lets a grund error from a factory through unwrapped', () async {
      final graph = ModuleGraph.build(
        AppModule(bindings: [Singleton<Repo>.factory((i) => Repo(i()))]),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<MissingProviderError>().having(
            (e) => e.requiredBy,
            'requiredBy',
            const Key<Repo>(),
          ),
        ),
      );
    });

    test(
      'a module sees the exports of its imports, not their private bindings',
      () async {
        final container = await start(
          AppModule(
            imports: [
              DbModule(
                bindings: [
                  Singleton<Db>((i) => Db(), dependsOn: const []),
                  Singleton<Secret>((i) => Secret(), dependsOn: const []),
                ],
                exports: const [Key<Db>()],
              ),
            ],
          ),
        );

        expect(container.root<Db>(), isA<Db>());
        expect(container.root.maybe<Secret>(), isNull);
        expect(
          () => container.root<Secret>(),
          throwsA(isA<MissingProviderError>()),
        );
      },
    );

    test(
      'a factory sees what its own module sees, not what its caller sees',
      () async {
        final container = await start(
          AppModule(
            imports: [
              DbModule(
                bindings: [
                  Singleton<Secret>((i) => Secret(), dependsOn: const []),
                  Transient<UsesSecret>(
                    (i) => UsesSecret(i()),
                    dependsOn: const [Key<Secret>()],
                  ),
                ],
                exports: const [Key<UsesSecret>()],
              ),
            ],
          ),
        );

        expect(container.root<UsesSecret>(), isA<UsesSecret>());
      },
    );

    test('resolves a name', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<String>((i) => 'a', name: 'first', dependsOn: const []),
            Singleton<String>((i) => 'b', name: 'second', dependsOn: const []),
          ],
        ),
      );

      expect(container.root<String>('second'), 'b');
      expect(container.root.maybe<String>(), isNull);
    });

    test('a transient binding is a new instance each time', () async {
      final container = await start(
        AppModule(
          bindings: [Transient<Clock>((i) => Clock(), dependsOn: const [])],
        ),
      );

      expect(container.root<Clock>(), isNot(same(container.root<Clock>())));
    });

    test('all collects singletons whose binding type is a subtype', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Repo>((i) => Repo(Clock()), dependsOn: const []),
            Singleton<Clock>((i) => Clock(), dependsOn: const []),
            Transient<Service>(
              (i) => Service(Repo(Clock())),
              dependsOn: const [],
            ),
          ],
        ),
      );

      expect(container.all<Object>(), hasLength(2));
      expect(container.all<Clock>(), hasLength(1));
      expect(container.all<Service>(), isEmpty);
    });

    test('overrides replace a binding for the whole start', () async {
      final container = await start(
        AppModule(
          bindings: [
            Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
            Singleton<Clock>((i) => Clock(), dependsOn: const []),
          ],
        ),
        overrides: [
          Singleton<Clock>((i) => _FixedClock(), dependsOn: const []),
        ],
      );

      expect(container.root<Repo>().clock, isA<_FixedClock>());
    });
  });
}

final class _FixedClock extends Clock {}
````

**`packages/grund/test/di/container_scopes_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Future<Container> start(List<Binding<Object>> bindings) =>
    Container.create(ModuleGraph.build(AppModule(bindings: bindings)));

void main() {
  group('Call scopes', () {
    test('a scoped binding is one instance per call', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      final first = container.root.openCall();
      final second = container.root.openCall();

      expect(first<Clock>(), same(first<Clock>()));
      expect(first<Clock>(), isNot(same(second<Clock>())));
    });

    test('a scoped binding cannot be resolved outside a call', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      expect(
        () => container.root<Clock>(),
        throwsA(
          isA<ScopedOutsideCallError>().having(
            (e) => e.key,
            'key',
            const Key<Clock>(),
          ),
        ),
      );
    });

    test(
      'closing a call disposes its scoped instances in reverse order',
      () async {
        final log = <String>[];
        final container = await start([
          Scoped<Tracked>(
            (i) => Tracked('first', log),
            name: 'first',
            dependsOn: const [],
          ),
          Scoped<Tracked>(
            (i) => Tracked('second', log),
            name: 'second',
            dependsOn: const [],
          ),
        ]);
        final call = container.root.openCall();
        call<Tracked>('first');
        call<Tracked>('second');

        await call.close();
        await call.close();

        expect(log, ['dispose second', 'dispose first']);
      },
    );

    test('closing a call collects every failure of its disposals', () async {
      final log = <String>[];
      final container = await start([
        Scoped<Tracked>(
          (i) => Tracked('a', log, failure: StateError('a')),
          name: 'a',
          dependsOn: const [],
        ),
        Scoped<Tracked>(
          (i) => Tracked('b', log, failure: StateError('b')),
          name: 'b',
          dependsOn: const [],
        ),
      ]);
      final call = container.root.openCall();
      call<Tracked>('a');
      call<Tracked>('b');

      await expectLater(
        call.close(),
        throwsA(
          isA<ShutdownError>().having(
            (e) => e.failures,
            'failures',
            hasLength(2),
          ),
        ),
      );
      expect(log, ['dispose b', 'dispose a']);
    });

    // RF-2: calls that overlap in time never share state.
    test('calls that overlap keep their values and instances apart', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      Future<(Clock, Secret)> serve(Secret secret, int delayMs) async {
        final call = container.root.openCall();
        call.set<Secret>(secret);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        return (call<Clock>(), call<Secret>());
      }

      final first = Secret();
      final second = Secret();
      final results = await Future.wait([serve(first, 20), serve(second, 1)]);

      expect(results[0].$2, same(first));
      expect(results[1].$2, same(second));
      expect(results[0].$1, isNot(same(results[1].$1)));
    });

    // RF-2: a handler that throws must not leak the call's scoped instances.
    test('a call that failed halfway still disposes what it created', () async {
      final log = <String>[];
      final container = await start([
        Scoped<Tracked>(
          (i) => Tracked('tx', log),
          name: 'tx',
          dependsOn: const [],
        ),
        Scoped<Repo>(
          (i) => throw StateError('handler failed'),
          dependsOn: const [],
        ),
      ]);
      final call = container.root.openCall();

      try {
        call<Tracked>('tx');
        call<Repo>();
      } on ProviderCreationError {
        // The request handler failed; the transport closes the call anyway.
      } finally {
        await call.close();
      }

      expect(log, ['dispose tx']);
    });

    test('a value set on the call is resolvable in it only', () async {
      final container = await start([
        Singleton<Clock>((i) => Clock(), dependsOn: const []),
      ]);
      final call = container.root.openCall();
      final other = container.root.openCall();
      final secret = Secret();

      call.set<Secret>(secret);

      expect(call<Secret>(), same(secret));
      expect(call.maybe<Secret>(), same(secret));
      expect(other.maybe<Secret>(), isNull);
    });

    test(
      'a transient binding depending on a scoped one lives in the call',
      () async {
        final container = await start([
          Scoped<Clock>((i) => Clock(), dependsOn: const []),
          Transient<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
        ]);
        final call = container.root.openCall();

        expect(call<Repo>().clock, same(call<Clock>()));
      },
    );

    test(
      'a scoped factory sees singletons and call values of its own module',
      () async {
        final container = await start([
          Singleton<Clock>((i) => Clock(), dependsOn: const []),
          Scoped<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
        ]);
        final call = container.root.openCall();

        expect(call<Repo>().clock, same(container.root<Clock>()));
      },
    );

    test('a singleton that depends on a scoped binding fails at build', () {
      expect(
        () => ModuleGraph.build(
          AppModule(
            bindings: [
              Scoped<Clock>((i) => Clock(), dependsOn: const []),
              Singleton<Repo>(
                (i) => Repo(i()),
                dependsOn: const [Key<Clock>()],
              ),
            ],
          ),
        ),
        throwsA(isA<CaptiveDependencyError>()),
      );
    });
  });
}
````

**`packages/grund/test/di/container_lifecycle_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/injector.dart';
import 'package:grund/src/di/module.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Singleton<Tracked> tracked(
  String name,
  List<String> log, {
  Object? failure,
  List<String> after = const [],
}) => Singleton<Tracked>(
  (i) {
    log.add('create $name');
    return Tracked(name, log, failure: failure);
  },
  name: name,
  dependsOn: const [],
);

void main() {
  group('Container lifecycle', () {
    test('runs onInit of every module after all singletons exist', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          log: log,
          imports: [
            DbModule(log: log, bindings: [tracked('db', log)]),
          ],
          bindings: [tracked('app', log)],
        ),
      );

      await Container.create(graph);

      expect(log, [
        'create db',
        'create app',
        'init DbModule',
        'init AppModule',
      ]);
    });

    // RF-5: a second close does nothing.
    test(
      'close runs onShutdown in reverse, then disposes singletons in reverse',
      () async {
        final log = <String>[];
        final container = await Container.create(
          ModuleGraph.build(
            AppModule(
              log: log,
              imports: [
                DbModule(log: log, bindings: [tracked('db', log)]),
              ],
              bindings: [tracked('app', log)],
            ),
          ),
        );
        log.clear();

        await container.close();

        expect(log, [
          'shutdown AppModule',
          'shutdown DbModule',
          'dispose app',
          'dispose db',
        ]);
      },
    );

    // RF-5: every step runs; the failures come back together.
    test('close is idempotent', () async {
      final log = <String>[];
      final container = await Container.create(
        ModuleGraph.build(AppModule(bindings: [tracked('app', log)])),
      );

      await container.close();
      await container.close();

      expect(log.where((e) => e == 'dispose app'), hasLength(1));
    });

    test('close tries every step and reports all failures', () async {
      final log = <String>[];
      final container = await Container.create(
        ModuleGraph.build(
          AppModule(
            bindings: [
              tracked('a', log, failure: StateError('a')),
              tracked('b', log, failure: StateError('b')),
            ],
          ),
        ),
      );

      await expectLater(
        container.close(),
        throwsA(
          isA<ShutdownError>()
              .having((e) => e.failures.map((f) => f.step).toList(), 'steps', [
                'dispose Tracked(\'b\') of AppModule',
                'dispose Tracked(\'a\') of AppModule',
              ]),
        ),
      );
      expect(log.where((e) => e.startsWith('dispose')), hasLength(2));
    });

    test('a failing factory disposes what was already created', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          log: log,
          bindings: [
            tracked('first', log),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(isA<ProviderCreationError>()),
      );

      expect(log, ['create first', 'dispose first']);
    });

    test(
      'a failing onInit shuts down the modules that were initialised',
      () async {
        final log = <String>[];
        final graph = ModuleGraph.build(
          AppModule(
            log: log,
            imports: [const _FailingInitModule()],
            bindings: [tracked('app', log)],
          ),
        );

        await expectLater(
          Container.create(graph),
          throwsA(
            isA<ModuleLifecycleError>()
                .having((e) => e.module, 'module', '_FailingInitModule')
                .having((e) => e.phase, 'phase', 'onInit'),
          ),
        );
        expect(log, ['create app', 'dispose app']);
      },
    );

    test('a failing rollback is reported next to the original cause', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            tracked('first', log, failure: StateError('dispose failed')),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<StartupRollbackError>()
              .having((e) => e.cause, 'cause', isA<ProviderCreationError>())
              .having((e) => e.failures, 'failures', hasLength(1)),
        ),
      );
    });
  });
}

final class _FailingInitModule extends Module {
  const _FailingInitModule();

  @override
  void onInit(Injector injector) => throw StateError('init failed');
}
````

**`packages/grund/test/di/container_reassemble_test.dart`**

````dart
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Singleton<Tracked> tracked(String name, List<String> log) => Singleton<Tracked>(
  (i) {
    log.add('create $name');
    return Tracked(name, log);
  },
  name: name,
  dependsOn: const [],
);

ModuleGraph graphOf(List<Binding<Object>> bindings, {List<String>? log}) =>
    ModuleGraph.build(AppModule(bindings: bindings, log: log));

void main() {
  group('Container.reassemble', () {
    test('takes over a singleton whose module and key are unchanged', () async {
      final log = <String>[];
      final old = await Container.create(graphOf([tracked('db', log)]));
      final before = old.root<Tracked>('db');

      final next = await old.reassemble(graphOf([tracked('db', log)]));

      expect(next.root<Tracked>('db'), same(before));
      expect(log, ['create db']);
    });

    test(
      'creates a singleton that is new and keeps the taken over one',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));

        final next = await old.reassemble(
          graphOf([tracked('db', log), tracked('cache', log)]),
        );

        expect(log, ['create db', 'create cache']);
        expect(next.root<Tracked>('cache'), isA<Tracked>());
      },
    );

    test('does not take over a binding that changed its scope', () async {
      final old = await Container.create(
        graphOf([Singleton<Clock>((i) => Clock(), dependsOn: const [])]),
      );
      final before = old.root<Clock>();

      final next = await old.reassemble(
        graphOf([Transient<Clock>((i) => Clock(), dependsOn: const [])]),
      );

      expect(next.root<Clock>(), isNot(same(before)));
    });

    test('does not init a module that is carried over again', () async {
      final log = <String>[];
      final old = await Container.create(graphOf(const [], log: log));
      log.clear();

      await old.reassemble(graphOf(const [], log: log));

      expect(log, isEmpty);
    });

    test('a failed reassemble leaves the old container working', () async {
      final log = <String>[];
      final old = await Container.create(graphOf([tracked('db', log)]));

      await expectLater(
        old.reassemble(
          graphOf([
            tracked('db', log),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ]),
        ),
        throwsA(isA<ProviderCreationError>()),
      );

      expect(old.root<Tracked>('db'), isA<Tracked>());
      expect(log, ['create db']);
    });

    test(
      'abandon disposes only what the new container created itself',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));
        final next = await old.reassemble(
          graphOf([tracked('db', log), tracked('cache', log)]),
        );
        log.clear();

        await next.abandon();

        expect(log, ['dispose cache']);
      },
    );

    test(
      'closing the new container disposes the taken over singleton once',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));
        final next = await old.reassemble(graphOf([tracked('db', log)]));
        log.clear();

        await next.close();

        expect(log, ['dispose db']);
      },
    );
  });
}
````

- [ ] **Крок 2: Запустити — очікуваний збій**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart test test/di test/call 2>&1 | tail -8
```

Очікувано: `Some tests failed.` — помилки компіляції (`Not found: 'package:grund/src/di/container.dart'`).

- [ ] **Крок 3: Реалізація**

**`packages/grund/lib/src/call/cancel_signal.dart`**

````dart
import 'dart:async';

/// Tells the code of a call that its result is no longer wanted.
final class CancelSignal {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Signals cancellation; further calls do nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
````

**`packages/grund/lib/src/call/call_context.dart`**

````dart
import '../di/call_scope.dart';
import 'cancel_signal.dart';

/// What the code serving one call (a request, a message, a job run) sees.
///
/// Transports extend it with their own parts (`HttpCtx` adds the request).
/// Hooks put values on it with [set]; handlers read them back by type.
base class CallContext {
  /// Creates the context over [scope], which it closes with [close].
  CallContext(this.scope, {CancelSignal? cancel})
    : cancel = cancel ?? CancelSignal();

  /// The call scope that resolves bindings for this call.
  final CallScope scope;

  /// Fires when the call is no longer wanted.
  final CancelSignal cancel;

  /// The value of type [T] (and [name]) for this call: what a hook [set], a
  /// `Scoped` or `Transient` binding, or a singleton.
  T call<T extends Object>([String? name]) => scope<T>(name);

  /// Like [call], but `null` when there is none.
  T? maybe<T extends Object>([String? name]) => scope.maybe<T>(name);

  /// Makes [value] resolvable as [T] for the rest of the call.
  ///
  /// Write the type argument: the value is found under [T], not under its
  /// runtime type.
  void set<T extends Object>(T value, {String? name}) =>
      scope.set<T>(value, name: name);

  /// Ends the call: disposes its `Scoped` instances.
  Future<void> close() => scope.close();
}
````

**`packages/grund/lib/src/di/shutdown_steps.dart`**

````dart
import 'dart:async';

import '../errors/resolution_errors.dart';

/// Runs steps that must all be tried even when some fail, and remembers the
/// failures.
final class ShutdownSteps {
  final List<ShutdownFailure> _failures = [];

  /// The steps that failed so far, in order.
  List<ShutdownFailure> get failures => List.unmodifiable(_failures);

  /// Runs [action], recording its failure as [step].
  Future<void> run(String step, FutureOr<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      // Boundary: dispose and onShutdown are user code; a failure must not
      // stop the steps after it.
      _failures.add((step: step, error: error, stackTrace: stackTrace));
    }
  }

  /// Throws a [ShutdownError] with all failures, if there are any.
  void throwIfFailed() {
    if (_failures.isNotEmpty) throw ShutdownError(failures);
  }
}
````

**`packages/grund/lib/src/di/call_state.dart`**

````dart
import 'dart:async';

import 'disposable.dart';
import 'key.dart';
import 'shutdown_steps.dart';
import 'visible_binding.dart';

/// What one call has accumulated: values set by hooks and `Scoped`
/// instances.
final class CallState {
  /// Values made resolvable with `CallScope.set`.
  final Map<Key<Object>, Object> values = {};

  /// `Scoped` instances in creation order.
  final Map<BindingId, Object> scoped = {};

  Future<void>? _closing;

  /// Disposes the scoped instances in reverse creation order; idempotent.
  Future<void> close() => _closing ??= _dispose();

  Future<void> _dispose() async {
    final steps = ShutdownSteps();
    for (final MapEntry(:key, :value) in scoped.entries.toList().reversed) {
      if (value is Disposable) {
        await steps.run('dispose ${key.$2} of ${key.$1}', value.dispose);
      }
    }
    steps.throwIfFailed();
  }
}
````

**`packages/grund/lib/src/di/injection_runtime.dart`**

````dart
import '../errors/graph_errors.dart';
import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'binding.dart';
import 'call_state.dart';
import 'call_view.dart';
import 'injector.dart';
import 'key.dart';
import 'module_graph.dart';
import 'module_identity.dart';
import 'module_node.dart';
import 'module_view.dart';
import 'visible_binding.dart';

/// Creates and finds the values of one started graph.
final class InjectionRuntime {
  /// Creates the runtime of [graph]; nothing is created yet.
  InjectionRuntime(this.graph);

  /// The graph the values belong to.
  final ModuleGraph graph;

  /// Created singletons in creation order.
  final Map<BindingId, Object> singletons = {};

  /// Singletons taken over from a previous container.
  final Set<BindingId> adopted = {};

  final Map<ModuleIdentity, ModuleView> _views = {};
  final List<BindingId> _creating = [];

  /// The injector of [node].
  Injector viewOf(ModuleNode node) =>
      _views.putIfAbsent(node.identity, () => ModuleView(this, node));

  /// Takes over [instance] for [id] instead of creating it.
  void adopt(BindingId id, Object instance) {
    singletons[id] = instance;
    adopted.add(id);
  }

  /// The binding of [id], or `null`.
  Binding<Object>? bindingOf(BindingId id) =>
      graph.nodeOf(id.$1)?.bindings[id.$2];

  /// Every singleton created so far whose binding type is a subtype of [T].
  List<T> all<T extends Object>() => [
    for (final MapEntry(:key, :value) in singletons.entries)
      if (bindingOf(key) is Binding<T>) value as T,
  ];

  /// The value of [key] as seen from [from], or `null` when nothing visible
  /// matches. Values set on [state] win.
  Object? find(ModuleNode from, Key<Object> key, CallState? state) {
    final set = state?.values[key];
    if (set != null) return set;
    final visible = graph.visibility.lookup(from.identity, key);
    return visible == null ? null : _instance(visible, state);
  }

  /// Like [find], but throws [MissingProviderError] when there is none.
  T resolve<T extends Object>(ModuleNode from, Key<T> key, CallState? state) {
    final value = find(from, key, state);
    if (value != null) return value as T;
    throw MissingProviderError(
      key: key,
      module: '${from.identity}',
      requiredBy: _creating.isEmpty ? null : _creating.last.$2,
    );
  }

  /// Creates the singleton [id], waiting for an asynchronous factory.
  Future<void> createSingleton(BindingId id) async {
    final binding = bindingOf(id);
    final node = graph.nodeOf(id.$1);
    if (binding == null || node == null || singletons.containsKey(id)) return;
    final visible = VisibleBinding(id.$1, binding);
    _enter(visible);
    try {
      singletons[id] = await binding.create(viewOf(node));
    } on Object catch (error, stackTrace) {
      // Boundary: factories are user code.
      _wrap(visible, error, stackTrace);
    } finally {
      _creating.removeLast();
    }
  }

  Object _instance(VisibleBinding visible, CallState? state) {
    final id = visible.id;
    switch (visible.binding) {
      case Singleton():
        return singletons[id] ?? (singletons[id] = _create(visible, null));
      case Transient():
        return _create(visible, state);
      case Scoped():
        if (state == null) {
          throw ScopedOutsideCallError(
            key: visible.binding.key,
            module: '${visible.owner}',
          );
        }
        return state.scoped[id] ?? (state.scoped[id] = _create(visible, state));
    }
  }

  Object _create(VisibleBinding visible, CallState? state) {
    final node = graph.nodeOf(visible.owner);
    if (node == null) throw StateError('Unknown module ${visible.owner}');
    final injector = state == null ? viewOf(node) : CallView(this, node, state);
    _enter(visible);
    try {
      final created = visible.binding.create(injector);
      if (created is Future<Object>) {
        created.ignore();
        throw AsyncProviderNotReadyError(
          key: visible.binding.key,
          module: '${visible.owner}',
          chain: _chain(),
        );
      }
      return created;
    } on Object catch (error, stackTrace) {
      // Boundary: factories are user code.
      _wrap(visible, error, stackTrace);
    } finally {
      _creating.removeLast();
    }
  }

  void _enter(VisibleBinding visible) {
    final start = _creating.indexOf(visible.id);
    if (start >= 0) {
      throw CircularDependencyError([
        for (final id in [..._creating.sublist(start), visible.id]) id.$2,
      ]);
    }
    _creating.add(visible.id);
  }

  List<Key<Object>> _chain() => [
    for (final id in _creating.reversed.skip(1)) id.$2,
  ];

  Never _wrap(VisibleBinding visible, Object error, StackTrace stackTrace) {
    if (error is GrundError) throw error;
    Error.throwWithStackTrace(
      ProviderCreationError(
        key: visible.binding.key,
        module: '${visible.owner}',
        chain: _chain(),
        error: error,
        stackTrace: stackTrace,
      ),
      stackTrace,
    );
  }
}
````

**`packages/grund/lib/src/di/module_view.dart`**

````dart
import 'call_scope.dart';
import 'call_state.dart';
import 'call_view.dart';
import 'injection_runtime.dart';
import 'injector.dart';
import 'key.dart';
import 'module_node.dart';

/// The [Injector] of one module: it resolves what that module sees.
final class ModuleView implements Injector {
  /// Creates the view of [node] over [_runtime].
  ModuleView(this._runtime, this.node);

  final InjectionRuntime _runtime;

  /// The module this view belongs to.
  final ModuleNode node;

  @override
  T call<T extends Object>([String? name]) =>
      _runtime.resolve(node, Key<T>(name), null);

  @override
  T? maybe<T extends Object>([String? name]) =>
      _runtime.find(node, Key<T>(name), null) as T?;

  @override
  List<T> all<T extends Object>() => _runtime.all<T>();

  @override
  CallScope openCall() => CallView(_runtime, node, CallState());
}
````

**`packages/grund/lib/src/di/call_view.dart`**

````dart
import 'call_scope.dart';
import 'call_state.dart';
import 'injection_runtime.dart';
import 'key.dart';
import 'module_node.dart';

/// The [CallScope] of one call, resolving what [node] sees.
final class CallView implements CallScope {
  /// Creates the view of [node] over [_runtime] for the call of [_state].
  CallView(this._runtime, this.node, this._state);

  final InjectionRuntime _runtime;
  final CallState _state;

  /// The module whose visibility applies.
  final ModuleNode node;

  @override
  T call<T extends Object>([String? name]) =>
      _runtime.resolve(node, Key<T>(name), _state);

  @override
  T? maybe<T extends Object>([String? name]) =>
      _runtime.find(node, Key<T>(name), _state) as T?;

  @override
  List<T> all<T extends Object>() => _runtime.all<T>();

  @override
  CallScope openCall() => CallView(_runtime, node, CallState());

  @override
  void set<T extends Object>(T value, {String? name}) {
    _state.values[Key<T>(name)] = value;
  }

  @override
  Future<void> close() => _state.close();
}
````

**`packages/grund/lib/src/di/container_lifecycle.dart`**

````dart
import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'disposable.dart';
import 'injection_runtime.dart';
import 'module_identity.dart';
import 'shutdown_steps.dart';

/// Runs the lifecycle of the modules and singletons of one container.
final class ContainerLifecycle {
  /// Creates the lifecycle over [_runtime].
  ContainerLifecycle(this._runtime);

  final InjectionRuntime _runtime;
  final Set<ModuleIdentity> _initialised = {};
  final Set<ModuleIdentity> _fresh = {};

  /// Calls `onInit` of every module that [carried] does not already hold,
  /// in module order. A carried module counts as initialised.
  Future<void> initModules(Set<ModuleIdentity> carried) async {
    for (final node in _runtime.graph.nodes) {
      final identity = node.identity;
      if (carried.contains(identity)) {
        _initialised.add(identity);
        continue;
      }
      try {
        await node.module.onInit(_runtime.viewOf(node));
      } on Object catch (error, stackTrace) {
        // Boundary: onInit is user code.
        if (error is GrundError) rethrow;
        Error.throwWithStackTrace(
          ModuleLifecycleError(
            module: '$identity',
            phase: 'onInit',
            error: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      _initialised.add(identity);
      _fresh.add(identity);
    }
  }

  /// Calls `onShutdown` in reverse module order, then disposes singletons in
  /// reverse creation order. With [freshOnly] it leaves modules and
  /// singletons that came from a previous container alone.
  Future<ShutdownSteps> shutdown({required bool freshOnly}) async {
    final steps = ShutdownSteps();
    final modules = freshOnly ? _fresh : _initialised;
    for (final node in _runtime.graph.nodes.reversed) {
      if (!modules.contains(node.identity)) continue;
      await steps.run(
        'onShutdown of ${node.identity}',
        () => node.module.onShutdown(_runtime.viewOf(node)),
      );
    }
    for (final MapEntry(:key, :value)
        in _runtime.singletons.entries.toList().reversed) {
      if (value is! Disposable) continue;
      if (freshOnly && _runtime.adopted.contains(key)) continue;
      await steps.run('dispose ${key.$2} of ${key.$1}', value.dispose);
    }
    return steps;
  }

  /// The identities of the modules whose `onInit` this container ran.
  Set<ModuleIdentity> get initialised => _initialised;
}
````

**`packages/grund/lib/src/di/container.dart`**

````dart
import '../errors/resolution_errors.dart';
import 'binding.dart';
import 'container_lifecycle.dart';
import 'creation_plan.dart';
import 'injection_runtime.dart';
import 'injector.dart';
import 'module_graph.dart';

/// The created values of a [ModuleGraph]: singletons exist, modules are
/// initialised.
final class Container {
  Container._(this._runtime) : _lifecycle = ContainerLifecycle(_runtime);

  /// Creates every singleton in dependency order, then runs `onInit` of the
  /// modules.
  ///
  /// With [previous] the singletons whose module and key are unchanged are
  /// taken over instead of created again (hot reload). When a factory or
  /// `onInit` fails, what this call created is disposed again and the error
  /// is rethrown; no partially started container is returned.
  static Future<Container> create(
    ModuleGraph graph, {
    Container? previous,
  }) async {
    final container = Container._(InjectionRuntime(graph));
    try {
      await container._start(previous);
    } on Object catch (error, stackTrace) {
      // Boundary: factories and onInit are user code; undo what was done.
      final undone = await container._lifecycle.shutdown(freshOnly: true);
      if (undone.failures.isEmpty) rethrow;
      throw StartupRollbackError(
        cause: error,
        causeStackTrace: stackTrace,
        failures: undone.failures,
      );
    }
    return container;
  }

  final InjectionRuntime _runtime;
  final ContainerLifecycle _lifecycle;
  Future<void>? _closing;

  /// The injector of the root module.
  Injector get root => _runtime.viewOf(_runtime.graph.root);

  /// Every singleton whose binding type is a subtype of [T], in creation
  /// order.
  List<T> all<T extends Object>() => _runtime.all<T>();

  /// Builds the container of [newGraph], keeping the singletons that stayed
  /// the same. This container is left untouched; if creating the new one
  /// fails, the error is thrown and this one keeps working.
  Future<Container> reassemble(ModuleGraph newGraph) =>
      Container.create(newGraph, previous: this);

  /// Undoes what this container created itself, keeping what it took over
  /// from the container it replaced. For a reassemble that failed after
  /// [create].
  Future<void> abandon() async {
    (await _lifecycle.shutdown(freshOnly: true)).throwIfFailed();
  }

  /// Runs `onShutdown` of the modules in reverse order, then disposes the
  /// singletons in reverse creation order. Idempotent.
  ///
  /// Throws a [ShutdownError] after trying every step when some failed.
  Future<void> close() => _closing ??= _shutdown();

  Future<void> _shutdown() async {
    (await _lifecycle.shutdown(freshOnly: false)).throwIfFailed();
  }

  Future<void> _start(Container? previous) async {
    final kept = previous?._runtime;
    for (final id in CreationPlan.of(_runtime.graph).order) {
      final instance = kept?.singletons[id];
      if (instance != null &&
          kept?.bindingOf(id)?.scope == BindingScope.singleton) {
        _runtime.adopt(id, instance);
      } else {
        await _runtime.createSingleton(id);
      }
    }
    await _lifecycle.initModules(previous?._lifecycle.initialised ?? const {});
  }
}
````

- [ ] **Крок 4: Запустити — зелено; ліміти**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart format . | tail -1
dart analyze | tail -1
dart test test/di test/call 2>&1 | tail -1
dart test 2>&1 | tail -1
find lib -name '*.dart' | xargs wc -l | awk '$1 > 300 && $2 != "total"'
find test -name '*.dart' | xargs wc -l | awk '$1 > 500 && $2 != "total"'
(cd ../grund_http && dart analyze | tail -1 && dart test 2>&1 | tail -1)
```

Очікувано: `No issues found!`; нові тести `+45` (7+7+10+13 контейнер, 3+5 виклики), пакет `+189`; `grund_http` `+69`. Найдовший файл — `injection_runtime.dart` (158), найдовший метод `_create` (23).

- [ ] **Крок 5: Коміт**

```bash
cd ~/projects/grund
git add -A packages/grund
git commit -m "feat(core): Container, call scopes, lifecycle and reassemble"
```

---

### Задача 6: `App`, `Runner`, `RunnerSet`, `Runners`, `StopSignals`, hot reload, `TestApp`; перемикання barrel, видалення `legacy_di`

**Мета:** завершити ядро: `App` (старт з `only`, відкат при збої, ідемпотентний `close`, `reassemble`), `Runner` (`prepare`/`start`/`stop`/`reassemble`), вибір раннерів `--only`, сигнали зупинки, VM service extensions `ext.grund.*`, `TestApp`. Barrel `lib/grund.dart` перемикається на нове ядро, `legacy_di` і `test/legacy_di` видаляються, пакет отримує новий `pubspec`/`CHANGELOG`/`README` і мінімальний приклад ядра.

**Files:**
- Create: `lib/src/app/{app,runner,runner_set,runners,stop_signals,reassemble_report,hot_reload_extension}.dart`, `lib/src/testing/test_app.dart`, `lib/testing.dart`, `example/grund_example.dart`
- Modify (замінити цілком): `lib/grund.dart`, `pubspec.yaml`, `CHANGELOG.md`, `README.md`
- Delete: `lib/src/legacy_di/`, `test/legacy_di/`
- Test: `test/app/{app,app_reassemble,hot_reload_extension,reassemble_report,runner_set,runners,stop_signals}_test.dart`, `test/testing/test_app_test.dart`, `test/example_test.dart`, `test/helpers/fake_runner.dart`

**Interfaces:**
- Consumes: `Container`, `ModuleGraph`, `Module`, `Binding`, `Injector`, помилки `AppError`.
- Produces (за розділом «Рішення» цього плану): `App({required Module root, List<Binding<Object>> overrides})` з `start({Set<String>? only})`, `run({only, signals})`, `reassemble()`, `close()`, `container`, `isRunning`, `isClosed`; `Runner` (`name`, `prepare`, `start`, `stop`, `reassemble`); `Runners.fromArgs(List<String>)`; `StopSignals({sources})`; `ReassembleReport`; `TestApp.start({root, overrides})`. Публічний barrel експортує `App, ReassembleReport, Runner, Runners, StopSignals, CallContext, CancelSignal, Binding/BindingFactory/BindingScope/Scoped/Singleton/Transient, CallScope, Container, Disposable, Injector, Key, Module, GrundError` і три родини помилок; `testing.dart` — `TestApp`.

Review Focus: **RF-4** — `app_test.dart`: unknown `only` до старту будь-якого раннера і закриття контейнера; збій `prepare`/`start` відкочує запущене (`runner_set_test.dart` — те саме на рівні набору); **RF-5** — `app_test.dart`: «is idempotent» (паралельні `close`), «collects the failures of runners and of the container into one error» (`ShutdownError`).

- [ ] **Крок 1: Падаючі тести**

**`packages/grund/test/helpers/fake_runner.dart`**

````dart
import 'package:grund/grund.dart';

/// A runner that records what is done to it.
base class FakeRunner extends Runner {
  FakeRunner(
    this.name,
    this.log, {
    this.prepareFailure,
    this.startFailure,
    this.stopFailure,
    this.reassembleReport = ReassembleReport.none,
  });

  @override
  final String name;

  final List<String> log;
  final Object? prepareFailure;
  final Object? startFailure;
  final Object? stopFailure;
  final ReassembleReport reassembleReport;

  /// How often [reassemble] ran.
  int reassembled = 0;

  @override
  Future<void> prepare(Injector injector) async {
    log.add('prepare $name');
    if (prepareFailure case final failure?) throw failure;
  }

  @override
  Future<void> start(Injector injector) async {
    log.add('start $name');
    if (startFailure case final failure?) throw failure;
  }

  @override
  Future<void> stop() async {
    log.add('stop $name');
    if (stopFailure case final failure?) throw failure;
  }

  @override
  Future<ReassembleReport> reassemble(Injector injector) async {
    log.add('reassemble $name');
    reassembled++;
    return reassembleReport;
  }
}

/// The binding of [runner] under its own name, so `all<Runner>()` finds it.
Binding<Object> runnerBinding(FakeRunner runner) => Singleton<FakeRunner>(
  (i) => runner,
  name: runner.name,
  dependsOn: const [],
);
````

**`packages/grund/test/app/reassemble_report_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('ReassembleReport', () {
    test('between lists what appeared and what disappeared, sorted', () {
      final report = ReassembleReport.between(
        ['GET /a', 'GET /b'],
        ['GET /d', 'GET /b', 'GET /c'],
      );

      expect(report.added, ['GET /c', 'GET /d']);
      expect(report.removed, ['GET /a']);
      expect(report.changed, 3);
    });

    test('merge joins two reports and keeps the lists sorted', () {
      final merged = const ReassembleReport(
        added: ['b'],
        removed: ['x'],
      ).merge(const ReassembleReport(added: ['a'], removed: ['w']));

      expect(merged.added, ['a', 'b']);
      expect(merged.removed, ['w', 'x']);
    });

    test('toJson uses the keys the dev client reads', () {
      expect(const ReassembleReport(added: ['a']).toJson(), {
        'added': ['a'],
        'removed': <String>[],
      });
    });
  });
}
````

**`packages/grund/test/app/runners_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('Runners.fromArgs', () {
    test('is null without the flag, which means "start everything"', () {
      expect(Runners.fromArgs(const ['serve', '--verbose']), isNull);
    });

    test('reads a comma separated list after =', () {
      expect(Runners.fromArgs(const ['--only=http,jobs']), {'http', 'jobs'});
    });

    test('reads the list from the next argument', () {
      expect(Runners.fromArgs(const ['--only', 'http']), {'http'});
    });

    test('trims names and ignores empty ones', () {
      expect(Runners.fromArgs(const ['--only= http ,,jobs,']), {
        'http',
        'jobs',
      });
    });

    test('an empty list selects nothing', () {
      expect(Runners.fromArgs(const ['--only=']), isEmpty);
      expect(Runners.fromArgs(const ['--only']), isEmpty);
    });
  });
}
````

**`packages/grund/test/app/stop_signals_test.dart`**

````dart
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('StopSignals', () {
    test('completes at the first event of any source', () async {
      final first = StreamController<int>();
      final second = StreamController<int>();
      final signals = StopSignals(sources: [first.stream, second.stream]);
      var done = false;

      final waiting = signals.wait().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      second.add(1);
      await waiting;

      expect(done, isTrue);
    });

    test('stops listening once it completed', () async {
      final source = StreamController<int>();
      final waiting = StopSignals(sources: [source.stream]).wait();

      source.add(1);
      await waiting;

      expect(source.hasListener, isFalse);
    });
  });
}
````

**`packages/grund/test/app/runner_set_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:grund/src/app/runner_set.dart';
import 'package:test/test.dart';

import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

Future<Injector> injector() async {
  final app = App(root: const AppModule());
  await app.start(only: const {});
  addTearDown(app.close);
  return app.container.root;
}

void main() {
  group('RunnerSet.select', () {
    test('selects everything without only', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log),
        FakeRunner('b', log),
      ]);

      await set.start(await injector());

      expect(log, ['start a', 'start b']);
    });

    // RF-4: an unknown name is rejected with the names that exist.
    test('selects only the named runners but prepares them all', () async {
      final log = <String>[];
      final set = RunnerSet.select(
        [FakeRunner('a', log), FakeRunner('b', log)],
        only: {'b'},
      );
      final i = await injector();

      await set.prepare(i);
      await set.start(i);

      expect(log, ['prepare a', 'prepare b', 'start b']);
    });

    test('rejects an unknown name and lists what exists', () {
      expect(
        () =>
            RunnerSet.select([FakeRunner('http', [])], only: {'jobs', 'cron'}),
        throwsA(
          isA<UnknownRunnerError>()
              .having((e) => e.unknown, 'unknown', ['cron', 'jobs'])
              .having((e) => e.available, 'available', ['http']),
        ),
      );
    });

    test('rejects two runners with one name', () {
      expect(
        () => RunnerSet.select([FakeRunner('a', []), FakeRunner('a', [])]),
        throwsA(isA<DuplicateRunnerError>().having((e) => e.name, 'name', 'a')),
      );
    });
  });

  group('RunnerSet lifecycle', () {
    test('wraps a failure of a runner with its name and phase', () async {
      final set = RunnerSet.select([
        FakeRunner('a', [], prepareFailure: StateError('bad')),
      ]);

      await expectLater(
        set.prepare(await injector()),
        throwsA(
          isA<RunnerError>()
              .having((e) => e.runner, 'runner', 'a')
              .having((e) => e.phase, 'phase', 'prepare')
              .having((e) => e.error, 'error', isA<StateError>()),
        ),
      );
    });

    // RF-4: runners started before the failing one are stopped again.
    test('lets a GrundError of a runner through unwrapped', () async {
      final set = RunnerSet.select([
        FakeRunner(
          'a',
          [],
          prepareFailure: const ApplicationStateError(
            operation: 'x',
            reason: 'y',
          ),
        ),
      ]);

      await expectLater(
        set.prepare(await injector()),
        throwsA(isA<ApplicationStateError>()),
      );
    });

    test('a failing start stops the runners already started', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log),
        FakeRunner('b', log, startFailure: StateError('bad')),
        FakeRunner('c', log),
      ]);

      await expectLater(
        set.start(await injector()),
        throwsA(isA<RunnerError>().having((e) => e.runner, 'runner', 'b')),
      );

      expect(log, ['start a', 'start b', 'stop a']);
    });

    test('stop goes in reverse and tries every runner', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log, stopFailure: StateError('a')),
        FakeRunner('b', log, stopFailure: StateError('b')),
      ]);
      await set.start(await injector());
      log.clear();

      final failures = await set.stop();

      expect(log, ['stop b', 'stop a']);
      expect(failures.map((f) => f.step), ['stop runner b', 'stop runner a']);
    });

    test('a failed rollback is reported next to the failed start', () async {
      final set = RunnerSet.select([
        FakeRunner('a', [], stopFailure: StateError('stuck')),
        FakeRunner('b', [], startFailure: StateError('bad')),
      ]);

      await expectLater(
        set.start(await injector()),
        throwsA(
          isA<StartupRollbackError>().having(
            (e) => e.failures,
            'failures',
            hasLength(1),
          ),
        ),
      );
    });
  });

  group('RunnerSet.reassembleInto', () {
    test(
      'reassembles a runner both sets share and merges the reports',
      () async {
        final log = <String>[];
        final shared = FakeRunner(
          'a',
          log,
          reassembleReport: const ReassembleReport(added: ['x']),
        );
        final previous = RunnerSet.select([shared]);
        final i = await injector();
        await previous.start(i);
        final next = RunnerSet.select([shared]);

        final report = await previous.reassembleInto(next, i);

        expect(report.added, ['x']);
        expect(shared.reassembled, 1);
        expect(log, ['start a', 'reassemble a']);
      },
    );

    test(
      'prepares and starts a runner that is new, stops one that is gone',
      () async {
        final log = <String>[];
        final old = FakeRunner('old', log);
        final fresh = FakeRunner('fresh', log);
        final previous = RunnerSet.select([old]);
        final i = await injector();
        await previous.start(i);
        log.clear();

        await previous.reassembleInto(RunnerSet.select([fresh]), i);

        expect(log, ['prepare fresh', 'start fresh', 'stop old']);
      },
    );

    test(
      'a failure stops what the new set started and leaves the old running',
      () async {
        final log = <String>[];
        final kept = FakeRunner('kept', log);
        final previous = RunnerSet.select([kept]);
        final i = await injector();
        await previous.start(i);
        log.clear();
        final next = RunnerSet.select([
          FakeRunner('fresh', log),
          FakeRunner('broken', log, prepareFailure: StateError('bad')),
          kept,
        ]);

        await expectLater(
          previous.reassembleInto(next, i),
          throwsA(isA<RunnerError>()),
        );

        expect(log, [
          'prepare fresh',
          'start fresh',
          'prepare broken',
          'stop fresh',
        ]);
        expect(await previous.stop(), isEmpty);
        expect(log.last, 'stop kept');
      },
    );
  });
}
````

**`packages/grund/test/app/app_test.dart`**

````dart
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

AppModule moduleWith(List<FakeRunner> runners, {List<String>? log}) =>
    AppModule(
      log: log,
      bindings: [for (final runner in runners) runnerBinding(runner)],
    );

void main() {
  group('App.start', () {
    test(
      'prepares every runner and starts the selected ones in order',
      () async {
        final log = <String>[];
        final app = App(
          root: moduleWith([FakeRunner('a', log), FakeRunner('b', log)]),
        );

        await app.start(only: {'b'});

        expect(log, ['prepare a', 'prepare b', 'start b']);
        expect(app.isRunning, isTrue);
        await app.close();
      },
    );

    test('an empty only prepares the runners and starts none', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));

      await app.start(only: const {});

      expect(log, ['prepare a']);
      await app.close();
    });

    // RF-4: a name that matches no runner is reported before anything starts.
    test(
      'an unknown name fails before any runner starts and closes the container',
      () async {
        final log = <String>[];
        final app = App(
          root: AppModule(
            bindings: [
              runnerBinding(FakeRunner('a', log)),
              Singleton<Tracked>(
                (i) => Tracked('db', log),
                dependsOn: const [],
              ),
            ],
          ),
        );

        await expectLater(
          app.start(only: {'nope'}),
          throwsA(isA<UnknownRunnerError>()),
        );

        expect(log, ['dispose db']);
        expect(app.isClosed, isTrue);
      },
    );

    test('a structural error surfaces before any factory runs', () async {
      var created = false;
      final app = App(
        root: AppModule(
          bindings: [
            Singleton<Clock>((i) {
              created = true;
              return Clock();
            }, dependsOn: const []),
            Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Config>()]),
          ],
        ),
      );

      await expectLater(app.start(), throwsA(isA<MissingProviderError>()));

      expect(created, isFalse);
      expect(app.isClosed, isTrue);
    });

    // RF-4: a failing start leaves nothing running and nothing open.
    test(
      'a runner that fails to prepare stops the start and releases the container',
      () async {
        final log = <String>[];
        final app = App(
          root: AppModule(
            bindings: [
              runnerBinding(
                FakeRunner('a', log, prepareFailure: StateError('bad')),
              ),
              Singleton<Tracked>(
                (i) => Tracked('db', log),
                dependsOn: const [],
              ),
            ],
          ),
        );

        await expectLater(app.start(), throwsA(isA<RunnerError>()));

        expect(log, ['prepare a', 'dispose db']);
      },
    );

    // RF-4: a failing start rolls back the runners started before it.
    test(
      'a runner that fails to start rolls back the ones started before it',
      () async {
        final log = <String>[];
        final app = App(
          root: moduleWith([
            FakeRunner('a', log),
            FakeRunner('b', log, startFailure: StateError('bad')),
          ]),
        );

        await expectLater(app.start(), throwsA(isA<RunnerError>()));

        expect(log, ['prepare a', 'prepare b', 'start a', 'start b', 'stop a']);
      },
    );

    test('overrides replace a binding of the graph', () async {
      final app = App(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
        overrides: [
          Singleton<Clock>((i) => _FixedClock(), dependsOn: const []),
        ],
      );

      await app.start();

      expect(app.container.root<Clock>(), isA<_FixedClock>());
      await app.close();
    });

    test('cannot start twice or after close', () async {
      final app = App(root: const AppModule());
      await app.start();

      await expectLater(app.start(), throwsA(isA<ApplicationStateError>()));
      await app.close();
      await expectLater(app.start(), throwsA(isA<ApplicationStateError>()));
    });

    test('the container is not available before start', () {
      expect(
        () => App(root: const AppModule()).container,
        throwsA(isA<ApplicationStateError>()),
      );
    });
  });

  group('App.close', () {
    // RF-5: a second (even concurrent) close does nothing.
    test('stops the runners in reverse, then shuts the modules down', () async {
      final log = <String>[];
      final app = App(
        root: moduleWith([
          FakeRunner('a', log),
          FakeRunner('b', log),
        ], log: log),
      );
      await app.start();
      log.clear();

      await app.close();

      expect(log, ['stop b', 'stop a', 'shutdown AppModule']);
    });

    test('is idempotent', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));
      await app.start();

      await Future.wait([app.close(), app.close()]);
      await app.close();

      expect(log.where((e) => e == 'stop a'), hasLength(1));
    });

    // RF-5: failures are collected, not lost.
    test(
      'collects the failures of runners and of the container into one error',
      () async {
        final log = <String>[];
        final app = App(
          root: AppModule(
            bindings: [
              runnerBinding(
                FakeRunner('a', log, stopFailure: StateError('stop')),
              ),
              Singleton<Tracked>(
                (i) => Tracked('db', log, failure: StateError('dispose')),
                dependsOn: const [],
              ),
            ],
          ),
        );
        await app.start();

        await expectLater(
          app.close(),
          throwsA(
            isA<ShutdownError>().having(
              (e) => e.failures,
              'failures',
              hasLength(2),
            ),
          ),
        );
      },
    );

    test('closing an application that never started is allowed', () async {
      final app = App(root: const AppModule());

      await app.close();

      expect(app.isClosed, isTrue);
    });
  });

  group('App.run', () {
    test('serves until a stop signal arrives, then closes', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));
      final stop = StreamController<int>();

      final running = app.run(signals: StopSignals(sources: [stop.stream]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(log, ['prepare a', 'start a']);

      stop.add(1);
      await running;

      expect(log, ['prepare a', 'start a', 'stop a']);
      expect(app.isClosed, isTrue);
    });
  });
}

final class _FixedClock extends Clock {}
````

**`packages/grund/test/app/app_reassemble_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

/// A module whose declarations come from [ReloadableCode], so a test can
/// change them between reassembles the way a hot reload changes method bodies.
final class ReloadableModule extends StubModule {
  const ReloadableModule(this.code);

  final ReloadableCode code;

  @override
  List<Binding<Object>> get bindings => code.bindings();
}

final class ReloadableCode {
  List<Binding<Object>> Function() bindings = () => const [];
}

void main() {
  late List<String> log;
  late ReloadableCode code;

  setUp(() {
    log = [];
    code = ReloadableCode();
  });

  Future<App> started() async {
    final app = App(root: ReloadableModule(code));
    await app.start();
    addTearDown(app.close);
    return app;
  }

  group('App.reassemble', () {
    test('keeps the singletons whose module and key are unchanged', () async {
      code.bindings = () => [
        Singleton<Tracked>((i) => Tracked('db', log), dependsOn: const []),
      ];
      final app = await started();
      final before = app.container.root<Tracked>();

      await app.reassemble();

      expect(app.container.root<Tracked>(), same(before));
      expect(log, isEmpty);
    });

    test('reassembles the running runners and returns their report', () async {
      final runner = FakeRunner(
        'a',
        log,
        reassembleReport: const ReassembleReport(added: ['GET /b']),
      );
      code.bindings = () => [runnerBinding(runner)];
      final app = await started();

      final report = await app.reassemble();

      expect(report.added, ['GET /b']);
      expect(runner.reassembled, 1);
    });

    test(
      'starts a runner that the new code adds and stops one it removes',
      () async {
        code.bindings = () => [runnerBinding(FakeRunner('old', log))];
        final app = await started();
        log.clear();
        code.bindings = () => [runnerBinding(FakeRunner('fresh', log))];

        await app.reassemble();

        expect(log, ['prepare fresh', 'start fresh', 'stop old']);
      },
    );

    test('a failing new graph leaves the previous state serving', () async {
      final runner = FakeRunner('a', log);
      code.bindings = () => [runnerBinding(runner)];
      final app = await started();
      code.bindings = () => [
        runnerBinding(runner),
        Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
      ];

      await expectLater(app.reassemble(), throwsA(isA<MissingProviderError>()));

      expect(app.isRunning, isTrue);
      expect(runner.reassembled, 0);
      expect(app.container.root<FakeRunner>('a'), same(runner));
    });

    test('a failing runner abandons what the new container created', () async {
      code.bindings = () => [runnerBinding(FakeRunner('a', log))];
      final app = await started();
      log.clear();
      code.bindings = () => [
        runnerBinding(FakeRunner('a', log)),
        Singleton<Tracked>((i) => Tracked('cache', log), dependsOn: const []),
        runnerBinding(FakeRunner('b', log, prepareFailure: StateError('bad'))),
      ];

      await expectLater(app.reassemble(), throwsA(isA<RunnerError>()));

      expect(log, contains('dispose cache'));
      expect(app.isRunning, isTrue);
    });

    test('refuses a second reassemble while one is running', () async {
      code.bindings = () => const [];
      final app = await started();

      final first = app.reassemble();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await first;
    });

    test('is refused before start and after close', () async {
      final app = App(root: ReloadableModule(code));
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await app.start();
      await app.close();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
    });

    test(
      'close waits for a running reassemble and then closes what it produced',
      () async {
        code.bindings = () => [runnerBinding(FakeRunner('a', log))];
        final app = await started();
        log.clear();

        final reassembling = app.reassemble();
        final closing = app.close();
        await Future.wait([reassembling, closing]);

        expect(log.last, 'stop a');
      },
    );
  });
}
````

**`packages/grund/test/app/hot_reload_extension_test.dart`**

````dart
import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:grund/src/app/hot_reload_extension.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

/// The code of the application; a test changes it to "reload" the code.
final class Code {
  static String route = 'GET /a';
  static bool isBroken = false;
  static bool isInvalid = false;

  static List<Binding<Object>> bindings() {
    if (isBroken) throw StateError('broken module');
    return [
      runnerBinding(WebRunner()),
      if (isInvalid)
        Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
    ];
  }
}

/// Reports the route of the code that is current when it is reassembled.
final class WebRunner extends FakeRunner {
  WebRunner() : super('web', []);

  @override
  Future<ReassembleReport> reassemble(Injector injector) async =>
      ReassembleReport(added: [Code.route]);
}

final class CodeModule extends StubModule {
  const CodeModule();

  @override
  List<Binding<Object>> get bindings => Code.bindings();
}

Future<App> started() async {
  final app = App(root: const CodeModule());
  await app.start();
  addTearDown(app.close);
  return app;
}

Future<Map<String, Object?>> callExtension(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  final result =
      response.result ??
      fail('error ${response.errorCode}: ${response.errorDetail}');
  return jsonDecode(result) as Map<String, Object?>;
}

Future<String> failureOf(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  return response.errorDetail ??
      fail('expected an error, got ${response.result}');
}

void main() {
  setUp(() {
    Code.route = 'GET /a';
    Code.isBroken = false;
    Code.isInvalid = false;
  });

  test('the extensions exist outside product builds', () {
    expect(HotReloadExtension.isEnabled, isTrue);
  });

  test(
    'reassemble rebuilds every open application and merges the reports',
    () async {
      await started();
      await started();
      Code.route = 'GET /b';

      final result = await callExtension(HotReloadExtension.reassembleMethod);

      expect(result, {
        'applications': 2,
        'added': ['GET /b', 'GET /b'],
        'removed': <String>[],
      });
    },
  );

  test('a closed application is not reassembled', () async {
    final app = await started();
    await app.close();

    expect(await callExtension(HotReloadExtension.reassembleMethod), {
      'applications': 0,
      'added': <String>[],
      'removed': <String>[],
    });
  });

  test(
    'a failing reassemble becomes an extension error with the stack trace',
    () async {
      await started();
      Code.isBroken = true;

      final detail = await failureOf(HotReloadExtension.reassembleMethod);

      expect(detail, contains('broken module'));
      expect(detail, contains('hot_reload_extension_test.dart'));
    },
  );

  test('a GrundError is reported without a stack trace', () async {
    final app = await started();
    await app.close();
    final other = App(root: const CodeModule());

    expect(
      await callExtension(HotReloadExtension.reassembleMethod),
      isNotEmpty,
    );
    await expectLater(
      other.reassemble(),
      throwsA(isA<ApplicationStateError>()),
    );
  });

  test('close closes every open application', () async {
    final first = await started();
    final second = await started();

    final result = await callExtension(HotReloadExtension.closeMethod);

    expect(result, {'applications': 2});
    expect(first.isClosed && second.isClosed, isTrue);
  });
}
````

**`packages/grund/test/testing/test_app_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

void main() {
  group('TestApp', () {
    test('builds the graph without starting any runner', () async {
      final log = <String>[];
      final app = await TestApp.start(
        root: AppModule(bindings: [runnerBinding(FakeRunner('a', log))]),
      );

      expect(log, ['prepare a']);
      await app.close();
    });

    test('resolves bindings of the root module', () async {
      final app = await TestApp.start(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
      );

      expect(app<Clock>(), isA<Clock>());
      await app.close();
    });

    test('takes overrides', () async {
      final replacement = Clock();
      final app = await TestApp.start(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
        overrides: [Singleton<Clock>((i) => replacement, dependsOn: const [])],
      );

      expect(app<Clock>(), same(replacement));
      await app.close();
    });

    test('reports a broken graph like a real start', () async {
      await expectLater(
        TestApp.start(
          root: AppModule(
            bindings: [
              Singleton<Repo>(
                (i) => Repo(i()),
                dependsOn: const [Key<Clock>()],
              ),
            ],
          ),
        ),
        throwsA(isA<MissingProviderError>()),
      );
    });
  });
}
````

**`packages/grund/test/example_test.dart`**

````dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';

import '../example/grund_example.dart';

void main() {
  test('the example greets on start and says goodbye on close', () async {
    expect(await greetOnce(), ['Hello, grund!', 'Goodbye.']);
  });

  test('TestApp resolves the example services without running them', () async {
    final lines = <String>[];
    final app = await TestApp.start(root: GreetingModule(lines));
    addTearDown(app.close);

    expect(app<Greeter>().greet('you'), 'Hello, you!');
    expect(lines, isEmpty);
  });

  test('an override replaces the greeter of the example', () async {
    final app = await TestApp.start(
      root: GreetingModule([]),
      overrides: [
        Singleton<Greeter>((i) => Greeter('Hi'), dependsOn: const []),
      ],
    );
    addTearDown(app.close);

    expect(app<Greeter>().greet('you'), 'Hi, you!');
  });
}
````

- [ ] **Крок 2: Запустити — очікуваний збій**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart test test/app test/testing test/example_test.dart 2>&1 | tail -8
```

Очікувано: `Some tests failed.` (9 файлів не компілюються: ще немає `App`, `Runner`, `TestApp`).

- [ ] **Крок 3: Реалізація — застосунок і раннери**

**`packages/grund/lib/src/app/reassemble_report.dart`**

````dart
/// What a reassemble changed in what the runners serve, as sorted strings a
/// runner chooses (the HTTP server uses `'GET /users/:id'`).
final class ReassembleReport {
  /// Creates the report.
  const ReassembleReport({this.added = const [], this.removed = const []});

  /// Compares the lists [before] and [after] a reassemble.
  factory ReassembleReport.between(List<String> before, List<String> after) {
    final old = before.toSet();
    final current = after.toSet();
    return ReassembleReport(
      added: List.unmodifiable(
        [
          for (final entry in after)
            if (!old.contains(entry)) entry,
        ]..sort(),
      ),
      removed: List.unmodifiable(
        [
          for (final entry in before)
            if (!current.contains(entry)) entry,
        ]..sort(),
      ),
    );
  }

  /// A report of a reassemble that changed nothing.
  static const none = ReassembleReport();

  /// What is served now and was not before, sorted.
  final List<String> added;

  /// What was served before and is not now, sorted.
  final List<String> removed;

  /// How many entries were added or removed.
  int get changed => added.length + removed.length;

  /// This report and [other] as one, sorted.
  ReassembleReport merge(ReassembleReport other) => ReassembleReport(
    added: List.unmodifiable([...added, ...other.added]..sort()),
    removed: List.unmodifiable([...removed, ...other.removed]..sort()),
  );

  /// The report as JSON, for the `ext.grund.reassemble` service extension.
  Map<String, Object> toJson() => {'added': added, 'removed': removed};
}
````

**`packages/grund/lib/src/app/runner.dart`**

````dart
import '../di/injector.dart';
import 'reassemble_report.dart';

/// Something the application runs once the graph exists: an HTTP server, a
/// job worker, a message consumer.
///
/// A module binds its runners as singletons; `App` finds them with
/// `container.all<Runner>()`.
abstract class Runner {
  /// The name `only` selects the runner by.
  String get name;

  /// Validates the runner and builds what [start] needs, without serving.
  ///
  /// Called on every runner when the application starts, also on the ones
  /// that `only` leaves out, so that a broken configuration fails at once.
  Future<void> prepare(Injector injector) async {}

  /// Starts serving.
  Future<void> start(Injector injector);

  /// Stops serving and waits for the work in progress.
  Future<void> stop();

  /// Applies the new graph (hot reload) and returns what changed.
  ///
  /// By default the runner is stopped, prepared again and started. A runner
  /// that can swap its structures without a gap overrides this.
  Future<ReassembleReport> reassemble(Injector injector) async {
    await stop();
    await prepare(injector);
    await start(injector);
    return ReassembleReport.none;
  }
}
````

**`packages/grund/lib/src/app/runners.dart`**

````dart
/// Reads which runners to start from the command line.
abstract final class Runners {
  /// The flag that names the runners to start.
  static const flag = '--only';

  /// The names after `--only=a,b` or `--only a,b`, or `null` when the flag is
  /// absent (start everything).
  ///
  /// An empty list (`--only=`) selects nothing: the runners are prepared but
  /// not started.
  static Set<String>? fromArgs(List<String> args) {
    for (final (index, argument) in args.indexed) {
      if (argument == flag) {
        return _names(index + 1 < args.length ? args[index + 1] : '');
      }
      if (argument.startsWith('$flag=')) {
        return _names(argument.substring(flag.length + 1));
      }
    }
    return null;
  }

  static Set<String> _names(String list) => {
    for (final name in list.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  };
}
````

**`packages/grund/lib/src/app/stop_signals.dart`**

````dart
import 'dart:async';
import 'dart:io';

/// Completes when the process is asked to stop.
final class StopSignals {
  /// Listens to the given [sources]; by default `SIGINT` and, where the
  /// platform has it, `SIGTERM`.
  StopSignals({Iterable<Stream<Object?>>? sources})
    : _sources = List.of(sources ?? _processSignals());

  final List<Stream<Object?>> _sources;

  /// Completes at the first event of any source and stops listening.
  Future<void> wait() {
    final completer = Completer<void>();
    final subscriptions = <StreamSubscription<Object?>>[];
    for (final source in _sources) {
      subscriptions.add(
        source.listen((_) {
          if (!completer.isCompleted) completer.complete();
        }),
      );
    }
    return completer.future.whenComplete(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
  }

  static List<Stream<Object?>> _processSignals() => [
    ProcessSignal.sigint.watch(),
    if (!Platform.isWindows) ProcessSignal.sigterm.watch(),
  ];
}
````

**`packages/grund/lib/src/app/runner_set.dart`**

````dart
import 'dart:async';

import '../di/injector.dart';
import '../di/shutdown_steps.dart';
import '../errors/app_errors.dart';
import '../errors/grund_error.dart';
import '../errors/resolution_errors.dart';
import 'reassemble_report.dart';
import 'runner.dart';

/// The runners of one container: which exist, which `only` selected and
/// which are running.
final class RunnerSet {
  RunnerSet._(this._available, this._selected);

  /// Selects from [available] the runners named in [only] (`null` selects
  /// all).
  ///
  /// Throws [DuplicateRunnerError] when two runners share a name and
  /// [UnknownRunnerError] when [only] names a runner that does not exist.
  factory RunnerSet.select(List<Runner> available, {Set<String>? only}) {
    final names = <String>{};
    for (final runner in available) {
      if (!names.add(runner.name)) throw DuplicateRunnerError(runner.name);
    }
    if (only == null) return RunnerSet._(available, available);
    final unknown = [
      for (final name in only)
        if (!names.contains(name)) name,
    ]..sort();
    if (unknown.isNotEmpty) {
      throw UnknownRunnerError(
        unknown: unknown,
        available: names.toList()..sort(),
      );
    }
    return RunnerSet._(available, [
      for (final runner in available)
        if (only.contains(runner.name)) runner,
    ]);
  }

  final List<Runner> _available;
  final List<Runner> _selected;
  final List<Runner> _running = [];

  /// Prepares every runner, the unselected ones too.
  Future<void> prepare(Injector injector) async {
    for (final runner in _available) {
      await _guard(runner, 'prepare', () => runner.prepare(injector));
    }
  }

  /// Starts the selected runners in order.
  ///
  /// When one fails, the ones already started are stopped again and the
  /// failure is thrown.
  Future<void> start(Injector injector) async {
    try {
      for (final runner in _selected) {
        await _guard(runner, 'start', () => runner.start(injector));
        _running.add(runner);
      }
    } on Object catch (error, stackTrace) {
      // Boundary: runners are user code; undo what was started and let the
      // original failure through.
      final failures = await stop();
      if (failures.isEmpty) rethrow;
      throw StartupRollbackError(
        cause: error,
        causeStackTrace: stackTrace,
        failures: failures,
      );
    }
  }

  /// Stops the running runners in reverse order, trying all of them.
  ///
  /// Returns the failures instead of throwing, so the caller can add the
  /// shutdown of the container to them.
  Future<List<ShutdownFailure>> stop() => _stop(_running.reversed.toList());

  /// Applies a reassemble: this set (of the previous container) hands over to
  /// [next] (of the new one), which gets [injector].
  ///
  /// A runner that is in both is reassembled; a runner only [next] selects is
  /// prepared and started; a running runner [next] no longer has is stopped.
  /// When it fails, what [next] started is stopped again and this set keeps
  /// running.
  Future<ReassembleReport> reassembleInto(
    RunnerSet next,
    Injector injector,
  ) async {
    var report = ReassembleReport.none;
    try {
      for (final runner in next._available) {
        report = report.merge(await next._adopt(runner, this, injector));
      }
    } on Object {
      // Boundary: runners are user code; the previous set keeps serving.
      await next._stop([
        for (final runner in next._running.reversed)
          if (!_running.contains(runner)) runner,
      ]);
      rethrow;
    }
    final dropped = [
      for (final runner in _running.reversed)
        if (!next._running.contains(runner)) runner,
    ];
    final failures = await _stop(dropped);
    if (failures.isNotEmpty) throw ShutdownError(failures);
    return report;
  }

  Future<ReassembleReport> _adopt(
    Runner runner,
    RunnerSet previous,
    Injector injector,
  ) async {
    if (previous._running.contains(runner)) {
      final report = await _guard(
        runner,
        'reassemble',
        () => runner.reassemble(injector),
      );
      _running.add(runner);
      return report;
    }
    await _guard(runner, 'prepare', () => runner.prepare(injector));
    if (_selected.contains(runner)) {
      await _guard(runner, 'start', () => runner.start(injector));
      _running.add(runner);
    }
    return ReassembleReport.none;
  }

  Future<List<ShutdownFailure>> _stop(List<Runner> runners) async {
    final steps = ShutdownSteps();
    for (final runner in runners) {
      await steps.run('stop runner ${runner.name}', runner.stop);
      _running.remove(runner);
    }
    return steps.failures;
  }

  // Boundary: runners are user code. A GrundError keeps its type, anything
  // else is wrapped with the runner and the phase.
  Future<T> _guard<T>(
    Runner runner,
    String phase,
    FutureOr<T> Function() action,
  ) async {
    try {
      return await action();
    } on GrundError {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RunnerError(
          runner: runner.name,
          phase: phase,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}
````

**`packages/grund/lib/src/app/app.dart`**

````dart
import 'dart:async';

import '../di/binding.dart';
import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../errors/app_errors.dart';
import '../errors/resolution_errors.dart';
import 'hot_reload_extension.dart';
import 'reassemble_report.dart';
import 'runner.dart';
import 'runner_set.dart';
import 'stop_signals.dart';

enum _AppState { created, started, closed }

/// The application: a root module, the container built from it and the
/// runners it finds there.
///
/// ```dart
/// Future<void> main(List<String> args) =>
///     App(root: AppModule()).run(only: Runners.fromArgs(args));
/// ```
final class App {
  /// Creates the application over [root]. Nothing is built until [start] or
  /// [run].
  ///
  /// [overrides] replace the bindings with the same key, wherever they are
  /// declared (tests, development).
  App({required this.root, this.overrides = const []});

  /// The root module.
  final Module root;

  /// Bindings that replace the ones with the same key.
  final List<Binding<Object>> overrides;

  _AppState _state = _AppState.created;
  _Running? _running;
  Future<ReassembleReport>? _reassembling;
  Future<void>? _closing;

  /// Whether [start] succeeded and [close] was not called yet.
  bool get isRunning => _state == _AppState.started;

  /// Whether the application was closed, or failed to start.
  bool get isClosed => _state == _AppState.closed;

  /// The container of the started application.
  Container get container => _started('use the container').container;

  /// Builds the graph, creates the singletons, prepares every runner and
  /// starts those that [only] selects (`null` selects all, `const {}` none).
  ///
  /// Every structural problem surfaces here, before any runner serves. When
  /// it fails, what was created is undone and the application is closed.
  Future<void> start({Set<String>? only}) async {
    _expect(_AppState.created, 'start');
    final Container container;
    try {
      container = await Container.create(
        ModuleGraph.build(root, overrides: overrides),
      );
    } on Object {
      // The graph or a factory is user code; nothing was left running.
      _state = _AppState.closed;
      rethrow;
    }
    try {
      final runners = RunnerSet.select(container.all<Runner>(), only: only);
      await runners.prepare(container.root);
      await runners.start(container.root);
      _running = _Running(container, runners, only);
      _state = _AppState.started;
    } on Object catch (error, stackTrace) {
      // Boundary: runners are user code; undo the container and report the
      // original failure.
      _state = _AppState.closed;
      await _undo(container, error, stackTrace);
      rethrow;
    }
    HotReloadExtension.attach(this);
  }

  /// Starts, then waits for `SIGINT`/`SIGTERM` (or [signals]) and closes.
  Future<void> run({Set<String>? only, StopSignals? signals}) async {
    await start(only: only);
    await (signals ?? StopSignals()).wait();
    await close();
  }

  /// Rebuilds the graph from [root] and applies it to the running
  /// application (hot reload).
  ///
  /// Singletons whose module and key are unchanged are kept. When anything
  /// fails the previous state keeps serving and the error is thrown.
  Future<ReassembleReport> reassemble() async {
    _started('reassemble');
    if (_reassembling != null) {
      throw const ApplicationStateError(
        operation: 'reassemble',
        reason: 'another reassemble is running',
      );
    }
    final pending = _reassemble();
    _reassembling = pending;
    try {
      return await pending;
    } finally {
      _reassembling = null;
    }
  }

  /// Stops the runners in reverse order, then runs the shutdown of the
  /// modules and singletons. Idempotent.
  ///
  /// Every step is tried; a [ShutdownError] lists those that failed.
  Future<void> close() => _closing ??= _close();

  Future<ReassembleReport> _reassemble() async {
    final current = _started('reassemble');
    final graph = ModuleGraph.build(root, overrides: overrides);
    final next = await current.container.reassemble(graph);
    try {
      final runners = RunnerSet.select(next.all<Runner>(), only: current.only);
      final report = await current.runners.reassembleInto(runners, next.root);
      _running = _Running(next, runners, current.only);
      return report;
    } on Object {
      // Boundary: runners are user code; the previous state keeps serving.
      await next.abandon();
      rethrow;
    }
  }

  Future<void> _close() async {
    HotReloadExtension.detach(this);
    _state = _AppState.closed;
    final pending = _reassembling;
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // The caller of reassemble gets this failure; here only the end of
        // the reassemble matters.
      }
    }
    final running = _running;
    final failures = [...?await running?.runners.stop()];
    try {
      await running?.container.close();
    } on ShutdownError catch (error) {
      failures.addAll(error.failures);
    }
    if (failures.isNotEmpty) throw ShutdownError(failures);
  }

  Future<void> _undo(
    Container container,
    Object cause,
    StackTrace causeStackTrace,
  ) async {
    try {
      await container.close();
    } on ShutdownError catch (error) {
      throw StartupRollbackError(
        cause: cause,
        causeStackTrace: causeStackTrace,
        failures: error.failures,
      );
    }
  }

  _Running _started(String operation) {
    _expect(_AppState.started, operation);
    return switch (_running) {
      final running? => running,
      null => throw StateError('a started application has a container'),
    };
  }

  void _expect(_AppState expected, String operation) {
    if (_state == expected) return;
    throw ApplicationStateError(
      operation: operation,
      reason: switch (_state) {
        _AppState.created => 'the application is not started',
        _AppState.started => 'the application is already started',
        _AppState.closed => 'the application is closed',
      },
    );
  }
}

final class _Running {
  _Running(this.container, this.runners, this.only);

  final Container container;
  final RunnerSet runners;
  final Set<String>? only;
}
````

**`packages/grund/lib/src/app/hot_reload_extension.dart`**

````dart
import 'dart:convert';
import 'dart:developer';

import 'package:meta/meta.dart';

import '../errors/grund_error.dart';
import 'app.dart';
import 'reassemble_report.dart';

/// The VM service extensions through which `grund_cli dev` drives the
/// applications of the process it runs: [reassembleMethod] after a hot
/// reload, [closeMethod] before a hot restart.
///
/// Every `App` is attached when it has started and detached when it starts
/// closing. The extensions are registered with the VM once, on the first
/// attach, and only when [isEnabled]: a product (AOT) build neither registers
/// them nor keeps any application.
abstract final class HotReloadExtension {
  /// Calls `App.reassemble` on every attached application and answers
  /// `{"applications": n, "added": [...], "removed": [...]}`.
  static const reassembleMethod = 'ext.grund.reassemble';

  /// Closes every attached application and answers `{"applications": n}`.
  static const closeMethod = 'ext.grund.close';

  /// Whether the extensions exist: the process is not a product build.
  static const isEnabled = !bool.fromEnvironment('dart.vm.product');

  static final _applications = <App>{};
  static var _registered = false;

  /// Makes [app] reachable from the extensions.
  static void attach(App app) {
    if (!isEnabled) return;
    _applications.add(app);
    if (_registered) return;
    // Set only after both calls succeeded, so a failed registration is
    // tried again by the next application.
    registerExtension(reassembleMethod, handle);
    registerExtension(closeMethod, handle);
    _registered = true;
  }

  /// Makes [app] unreachable from the extensions.
  static void detach(App app) => _applications.remove(app);

  /// Answers one call of [method]; the handler registered with the VM.
  @visibleForTesting
  static Future<ServiceExtensionResponse> handle(
    String method,
    Map<String, String> parameters,
  ) async {
    final applications = List.of(_applications);
    // Extension boundary: the module getters, factories and runners of the
    // user run inside reassemble, and their shutdown inside close. A failure
    // becomes an extension error with its message (a GrundError carries its
    // own context; anything else gets its stack trace) and `dev` prints it.
    // A failed reassemble leaves the previous state serving; a failed close
    // leaves that application closed.
    try {
      return method == closeMethod
          ? await _close(applications)
          : await _reassemble(applications);
    } on Object catch (error, stackTrace) {
      return _failure(_describe(error, stackTrace));
    }
  }

  static ServiceExtensionResponse _failure(String detail) =>
      ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        detail,
      );

  static String _describe(Object error, StackTrace stackTrace) =>
      error is GrundError ? '$error' : '$error\n$stackTrace';

  // Names the application when there are several, so the failure of one of
  // them is not mistaken for the failure of another.
  static String _named(
    int index,
    int count,
    Object error,
    StackTrace stackTrace,
  ) {
    final text = _describe(error, stackTrace);
    return count > 1 ? 'application ${index + 1} of $count: $text' : text;
  }

  static Future<ServiceExtensionResponse> _reassemble(List<App> apps) async {
    var merged = ReassembleReport.none;
    for (final (index, app) in apps.indexed) {
      final outcome = await _settle(app.reassemble());
      final failure = outcome.failure;
      if (failure != null) {
        final (error, stackTrace) = failure;
        return _failure(_named(index, apps.length, error, stackTrace));
      }
      merged = merged.merge(outcome.report ?? ReassembleReport.none);
    }
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': apps.length, ...merged.toJson()}),
    );
  }

  /// Closes every application, also when one fails, and reports all the
  /// failures in application order.
  static Future<ServiceExtensionResponse> _close(List<App> apps) async {
    final outcomes = await Future.wait([
      for (final app in apps) _settle(app.close().then((_) => null)),
    ]);
    final failures = [
      for (final (index, outcome) in outcomes.indexed)
        if (outcome.failure case (final error, final stackTrace))
          _named(index, apps.length, error, stackTrace),
    ];
    if (failures.isNotEmpty) return _failure(failures.join('\n'));
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': apps.length}),
    );
  }

  // Turns the failure of [future] into a value, so the caller sees every
  // failure instead of the first one that happens to finish.
  static Future<_Outcome> _settle(Future<ReassembleReport?> future) =>
      future.then(
        _Outcome.new,
        onError: (Object error, StackTrace stackTrace) =>
            _Outcome(null, (error, stackTrace)),
      );
}

final class _Outcome {
  _Outcome(this.report, [this.failure]);

  final ReassembleReport? report;
  final (Object, StackTrace)? failure;
}
````

**`packages/grund/lib/src/testing/test_app.dart`**

````dart
import '../app/app.dart';
import '../di/binding.dart';
import '../di/injector.dart';
import '../di/module.dart';

/// An application for tests: the graph is built and validated and the
/// singletons exist, but no runner serves, so no port is opened.
final class TestApp {
  TestApp._(this.app);

  /// Starts [root] with [overrides] and no runner running.
  static Future<TestApp> start({
    required Module root,
    List<Binding<Object>> overrides = const [],
  }) async {
    final app = App(root: root, overrides: overrides);
    await app.start(only: const {});
    return TestApp._(app);
  }

  /// The started application.
  final App app;

  /// The injector of the root module.
  Injector get injector => app.container.root;

  /// Resolves a [T] visible to the root module.
  T call<T extends Object>([String? name]) => injector<T>(name);

  /// Closes the application.
  Future<void> close() => app.close();
}
````

- [ ] **Крок 4: Перемкнути barrel, видалити `legacy_di`, приклад, метадані пакета**

**`packages/grund/lib/grund.dart`**

````dart
/// Modules, dependency injection and the application lifecycle of grund.
///
/// A module declares what it imports, which bindings it owns and which it
/// exports; `App` builds the graph, creates the singletons and starts the
/// runners (an HTTP server, a worker) the modules provide.
library;

export 'src/app/app.dart' show App;
export 'src/app/reassemble_report.dart' show ReassembleReport;
export 'src/app/runner.dart' show Runner;
export 'src/app/runners.dart' show Runners;
export 'src/app/stop_signals.dart' show StopSignals;
export 'src/call/call_context.dart' show CallContext;
export 'src/call/cancel_signal.dart' show CancelSignal;
export 'src/di/binding.dart'
    show Binding, BindingFactory, BindingScope, Scoped, Singleton, Transient;
export 'src/di/call_scope.dart' show CallScope;
export 'src/di/container.dart' show Container;
export 'src/di/disposable.dart' show Disposable;
export 'src/di/injector.dart' show Injector;
export 'src/di/key.dart' show Key;
export 'src/di/module.dart' show Module;
export 'src/errors/app_errors.dart';
export 'src/errors/graph_errors.dart';
export 'src/errors/grund_error.dart' show GrundError;
export 'src/errors/resolution_errors.dart';
````

**`packages/grund/lib/testing.dart`**

````dart
/// Test support for applications built on grund.
library;

export 'src/testing/test_app.dart' show TestApp;
````

**`packages/grund/example/grund_example.dart`**

````dart
import 'package:grund/grund.dart';

/// A service the example module provides.
final class Greeter {
  /// Creates a greeter that opens with [salutation].
  Greeter(this.salutation);

  /// How every greeting starts.
  final String salutation;

  /// The greeting for [name].
  String greet(String name) => '$salutation, $name!';
}

/// Greets when the application starts: a stand-in for an HTTP server or a
/// job worker, which are runners too.
final class GreetingRunner extends Runner {
  /// Creates a runner that writes to [lines].
  GreetingRunner(this._greeter, this._lines);

  final Greeter _greeter;
  final List<String> _lines;

  @override
  String get name => 'greeting';

  @override
  Future<void> start(Injector injector) async {
    _lines.add(_greeter.greet('grund'));
  }

  @override
  Future<void> stop() async {
    _lines.add('Goodbye.');
  }
}

/// The root module: a [Greeter] and the [GreetingRunner] that uses it.
///
/// `dependsOn` lists the keys a factory resolves; the application checks
/// them before any factory runs.
final class GreetingModule extends Module {
  /// Creates the module; the runner writes to [lines].
  GreetingModule(this.lines);

  /// Where the runner writes.
  final List<String> lines;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeter>((i) => Greeter('Hello'), dependsOn: const []),
    Singleton<GreetingRunner>(
      (i) => GreetingRunner(i<Greeter>(), lines),
      dependsOn: const [Key<Greeter>()],
    ),
  ];
}

/// Starts the application, lets the runner greet, and closes it again.
///
/// A real program calls `App.run`, which serves until `SIGINT` or `SIGTERM`.
Future<List<String>> greetOnce() async {
  final lines = <String>[];
  final app = App(root: GreetingModule(lines));
  await app.start();
  await app.close();
  return lines;
}

Future<void> main() async {
  (await greetOnce()).forEach(print);
}
````

**`packages/grund/pubspec.yaml`**

````yaml
name: grund
description: >-
  Modular backend framework for Dart without dart:mirrors: modules, typed
  dependency injection, call scopes and runners.
version: 0.1.0
repository: https://github.com/4akLoon/grund/tree/master/packages/grund
issue_tracker: https://github.com/4akLoon/grund/issues
topics: [server, backend, framework, dependency-injection]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  meta: ^1.16.0
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
````

**`packages/grund/CHANGELOG.md`**

````markdown
## 0.1.0

Initial release.

- Modules as classes (`Module`) with imports, `exports`, `qualifier` and
  `global`; explicit typed bindings (`Singleton`, `Scoped`, `Transient`) and a
  graph that is validated before any factory runs: every failure is a typed
  `GrundError` with a hint.
- `Injector`, call scopes (`openCall`, `CallContext`) and `Disposable`.
- `App`, `Runner` and `Runners`: runners are found in the graph, selected with
  `--only`, prepared, started and stopped in order; `close` is idempotent and
  collects every failure in a `ShutdownError`.
- `App.reassemble()` and the `ext.grund.*` VM service extensions that
  `grund_cli dev` uses for hot reload.
- `TestApp` in `package:grund/testing.dart`.
- HTTP lives in `grund_http`.
````

**`packages/grund/README.md`**

````markdown
# grund

Modular backend framework core for Dart, without `dart:mirrors`: modules,
typed dependency injection, call scopes and runners. It has no code
generation, no server and no HTTP; those are separate packages.

```dart
// Excerpt: Clock and Greeter are your classes.
import 'package:grund/grund.dart';

final class AppModule extends Module {
  const AppModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Clock>((i) => Clock(), dependsOn: const []),
    Singleton<Greeter>(
      (i) => Greeter(i<Clock>()),
      dependsOn: const [Key<Clock>()],
    ),
  ];
}

Future<void> main(List<String> args) =>
    App(root: const AppModule()).run(only: Runners.fromArgs(args));
```

A complete runnable version is `example/grund_example.dart`; tests use
`TestApp` from `package:grund/testing.dart`. HTTP is the separate package
`grund_http`; the repository's `docs/` directory has the guides.
````

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
git rm -r -q lib/src/legacy_di test/legacy_di
dart pub get | tail -1
```

- [ ] **Крок 5: Запустити — зелено; ліміти; решта пакетів**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund
dart format . | tail -1
dart analyze | tail -1
dart test 2>&1 | tail -1
find lib -name '*.dart' | xargs wc -l | awk '$1 > 300 && $2 != "total"'
find test -name '*.dart' | xargs wc -l | awk '$1 > 500 && $2 != "total"'
(cd ../grund_http && dart analyze | tail -1 && dart test 2>&1 | tail -1)
(cd ../grund_annotations && dart analyze | tail -1 && dart test 2>&1 | tail -1)
```

Очікувано: `No issues found!` ×3; `grund` `+166`; `grund_http` `+69` (перенесений код залежить лише від `GrundError`, який у новому ядрі так само `abstract base class`); `grund_annotations` `+6`. Решта workspace червона.

- [ ] **Крок 6: Коміт і dry-run публікації**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
git add -A packages/grund pubspec.yaml
git commit -m "feat(core)!: App, Runner, hot reload, TestApp; switch the barrel to the new core

The old DI is removed. HTTP is served by grund_http."
cd packages/grund && dart pub publish --dry-run 2>&1 | tail -2
```

Очікувано: `Package has 0 warnings.`

---

## Частина B: задачі 7–11 (`grund_http`)

> **Як перевірено.** Увесь код нижче пройшов послідовно в прототипі `S/proto/http` (пакет `grund_http` над прототипом ядра `S/proto/core`): після кожної задачі `dart analyze` чистий, тести зелені (82 → 112 → 129 → 164 → 206). Блоки коду вставлені скриптом `S/parts/build_b.py` з файлів прототипу; скрипт звіряє кожен вставлений блок із файлом (diff порожній).
>
> **Угоди.** Блок із підписом `**\`шлях\`**` — повний вміст файла (створюється або замінюється цілком). Файли `http/*`, `routing/*`, `adapter/*`, `testing/test_response` з `71a4726` перенесені в задачі 1 і тут змінюються лише там, де перелічено. Для змінених файлів блок — файл цілком (усі ≤150 рядків).

### Задача 7: Помилки як RFC 9457 (`HttpException.code/pointer`, `Problem`, `ProblemResponder`, `ErrorLog`)

**Мета.** Помилки HTTP стають RFC 9457 `application/problem+json`: `HttpException` отримує `code` і `pointer`, з'являються `Problem`, `ProblemError`, `ProblemCode`, `ErrorLog`/`PrintErrorLog` і `ProblemResponder`; форма помилки v1.0 зникає (`ErrorLogger` лишається).

Файли `http/*` з `71a4726` уже в пакеті після задачі 1. `adapter/error_logger.dart` (typedef `ErrorLogger`, callback `onError` адаптерів) **лишається** і далі експортується: `ErrorLog` — інша річ (binding сервера для логування помилок запиту).

**Files** (усі шляхи відносно `packages/grund_http/`):

- Modify/Create `lib/src/http/http_exception.dart`
- Modify/Create `lib/src/http/status_code.dart`
- Modify/Create `lib/src/http/request_body.dart`
- Modify/Create `lib/src/http/problem_code.dart`
- Modify/Create `lib/src/http/problem_error.dart`
- Modify/Create `lib/src/http/problem.dart`
- Modify/Create `lib/src/http/error_log.dart`
- Modify/Create `lib/src/http/print_error_log.dart`
- Modify/Create `lib/src/http/problem_responder.dart`
- Modify `lib/grund_http.dart`
- Test `test/helpers/recording_error_log.dart`
- Test `test/helpers/http_fixtures.dart`
- Test `test/http/http_exception_test.dart`
- Test `test/http/problem_test.dart`
- Test `test/http/problem_responder_test.dart`
- Test `test/http/http_request_test.dart`

Після задачі існують у `packages/grund_http/lib/src/`: `adapter/adapter_lifecycle.dart`, `adapter/error_logger.dart`, `adapter/http_adapter.dart`, `adapter/in_flight_requests.dart`, `http/connection_info.dart`, `http/error_log.dart`, `http/header_map.dart`, `http/http_exception.dart`, `http/http_request.dart`, `http/http_response.dart`, `http/print_error_log.dart`, `http/problem.dart`, `http/problem_code.dart`, `http/problem_error.dart`, `http/problem_responder.dart`, `http/request_body.dart`, `http/response_body.dart`, `http/response_head.dart`, `http/status_code.dart`, `routing/pattern_segment.dart`, `routing/route_match.dart`, `routing/route_pattern.dart`, `routing/router.dart`, `routing/routing_error.dart`, `serialize/response_serializer.dart`, `serialize/serialization_error.dart`, `serialize/serializer_registry.dart`, `testing/test_response.dart`.

**Interfaces.**

- Consumes: `StatusCode`, `HeaderMap`, `RequestBody`, `ResponseBody`, `HttpResponse` (задача 1); `GrundError` (ядро).
- Produces: `HttpException(status, {message, code, pointer, details, headers})` + підкласи; `Problem`, `ProblemError`, `ProblemCode`, `ErrorLog`, `PrintErrorLog`, `ProblemResponder({required bool debug, required ErrorLog log}).respond(error, stack, {instance})`.

Рішення, що фіксує задача:

- `ProblemResponder` не показує внутрішніх деталей 500 (`detail: "Internal server error"`); у `debug` додає `detail` і `stack`.
- `HttpException` не логується; будь-що інше логується через `ErrorLog` (за замовчуванням stderr).
- Список `ProblemError` у `details` перетворюється на `errors`; `pointer` виняткa стає одним елементом `errors`.
- `JsonUnsupportedObjectError` при кодуванні `details` — відповідь без `details` (остання лінія оборони).

**Крок 1: падаючі тести.** Створити такі тести та допоміжні файли (цілком):

**`packages/grund_http/test/helpers/recording_error_log.dart`**

```dart
import 'package:grund_http/grund_http.dart';

/// An [ErrorLog] that keeps what it was given.
final class RecordingErrorLog implements ErrorLog {
  /// The reported errors, oldest first.
  final List<Object> errors = [];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
```

**`packages/grund_http/test/helpers/http_fixtures.dart`**

```dart
// Shared builders for pipeline and HTTP tests.
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

/// A request for [method] and [target] with an optional JSON or raw body.
HttpRequest requestFor(
  String method,
  String target, {
  Map<String, String> headers = const {},
  String? body,
}) => HttpRequest(
  method: method,
  uri: Uri.parse(target),
  headers: HeaderMap.of(headers),
  body: body == null ? null : RequestBody.bytes(utf8.encode(body)),
);

/// The JSON value in the body of [response].
Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));

/// The body of [response] as text.
Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());
```

**`packages/grund_http/test/http/http_exception_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

class PaymentRequiredException extends HttpException {
  const PaymentRequiredException() : super(402, message: 'Pay first');
}

void main() {
  group('HttpException', () {
    test('message defaults to the reason phrase', () {
      expect(const HttpException(404).message, 'Not Found');
      expect(const HttpException(499).message, 'Unknown Status');
      expect(const HttpException(409, message: 'Taken').message, 'Taken');
    });

    test('built-in subclasses carry their status', () {
      expect(const BadRequestException().status, 400);
      expect(const UnauthorizedException().status, 401);
      expect(const ForbiddenException().status, 403);
      expect(const NotFoundException().status, 404);
      expect(MethodNotAllowedException(const ['GET']).status, 405);
      expect(const PayloadTooLargeException().status, 413);
      expect(const UnprocessableContentException().status, 422);
      expect(const ServiceUnavailableException().status, 503);
    });

    test('code and pointer are kept for the problem body', () {
      const error = BadRequestException(
        code: 'parameter_invalid',
        pointer: '/query/page',
      );
      const unprocessable = UnprocessableContentException(
        code: 'title_taken',
        pointer: '/body/title',
      );

      expect(error.code, 'parameter_invalid');
      expect(error.pointer, '/query/page');
      expect(unprocessable.pointer, '/body/title');
      expect(const NotFoundException().code, isNull);
    });

    test('405 lists the allowed methods in the allow header', () {
      final error = MethodNotAllowedException(const ['GET', 'HEAD', 'POST']);

      expect(error.allowed, ['GET', 'HEAD', 'POST']);
      expect(error.headers, {'allow': 'GET, HEAD, POST'});
    });

    test('applications can extend it and keep details', () {
      const error = PaymentRequiredException();
      const withDetails = BadRequestException(details: {'field': 'name'});

      expect(error.status, 402);
      expect(error.toString(), 'PaymentRequiredException(402): Pay first');
      expect(withDetails.details, {'field': 'name'});
    });
  });

  group('StatusCode', () {
    test('knows reason phrases of common codes', () {
      expect(StatusCode.reasonPhrase(StatusCode.ok), 'OK');
      expect(
        StatusCode.reasonPhrase(StatusCode.methodNotAllowed),
        'Method Not Allowed',
      );
      expect(
        StatusCode.reasonPhrase(StatusCode.payloadTooLarge),
        'Content Too Large',
      );
    });
  });
}
```

**`packages/grund_http/test/http/problem_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

void main() {
  group('Problem', () {
    test('uses the RFC 9457 member names and skips absent ones', () {
      const problem = Problem(title: 'Not Found', status: 404);

      expect(problem.toJson(), {
        'type': 'about:blank',
        'title': 'Not Found',
        'status': 404,
      });
    });

    test('lists detail, instance, code, errors and extensions', () {
      const problem = Problem(
        type: 'https://example.com/probs/out-of-credit',
        title: 'Out of credit',
        status: 403,
        detail: 'Balance is 30.',
        instance: '/account/12345',
        code: 'out_of_credit',
        errors: [ProblemError(detail: 'too low', pointer: '/body/amount')],
        extensions: {'balance': 30},
      );

      expect(problem.toJson(), {
        'type': 'https://example.com/probs/out-of-credit',
        'title': 'Out of credit',
        'status': 403,
        'detail': 'Balance is 30.',
        'instance': '/account/12345',
        'code': 'out_of_credit',
        'errors': [
          {'detail': 'too low', 'pointer': '/body/amount'},
        ],
        'balance': 30,
      });
    });

    test('an extension never replaces a standard member', () {
      const problem = Problem(
        title: 'Bad Request',
        status: 400,
        extensions: {'status': 200, 'extra': true},
      );

      expect(problem.toJson()['status'], 400);
      expect(problem.toJson()['extra'], true);
    });
  });

  group('ProblemError', () {
    test('keeps the detail and only the members that are set', () {
      expect(const ProblemError(detail: 'x').toJson(), {'detail': 'x'});
      expect(
        const ProblemError(
          detail: 'x',
          pointer: '/query/a',
          code: 'parameter_invalid',
        ).toJson(),
        {'detail': 'x', 'pointer': '/query/a', 'code': 'parameter_invalid'},
      );
    });
  });
}
```

**`packages/grund_http/test/http/problem_responder_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';
import '../helpers/recording_error_log.dart';

final class Unprintable {
  @override
  String toString() => 'unprintable';
}

void main() {
  group('ProblemResponder', () {
    final log = RecordingErrorLog();
    final responder = ProblemResponder(debug: false, log: log);

    setUp(log.errors.clear);

    test('HttpException keeps status, headers and becomes a problem', () async {
      final response = responder.respond(
        const UnauthorizedException(
          message: 'Token expired',
          code: 'token_expired',
          details: {'realm': 'api'},
          headers: {'www-authenticate': 'Bearer'},
        ),
        StackTrace.current,
        instance: '/me',
      );

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Unauthorized',
        'status': 401,
        'detail': 'Token expired',
        'instance': '/me',
        'code': 'token_expired',
        'details': {'realm': 'api'},
      });
      expect(log.errors, isEmpty);
    });

    test('a pointer becomes an entry of errors', () async {
      final response = responder.respond(
        const BadRequestException(
          message: 'Invalid query parameter "page".',
          code: 'parameter_invalid',
          pointer: '/query/page',
        ),
        StackTrace.current,
      );

      expect((await jsonOf(response) as Map)['errors'], [
        {
          'detail': 'Invalid query parameter "page".',
          'pointer': '/query/page',
          'code': 'parameter_invalid',
        },
      ]);
    });

    test('details that are problem errors become errors', () async {
      final response = responder.respond(
        const UnprocessableContentException(
          details: [
            ProblemError(detail: 'required', pointer: '/body/title'),
            ProblemError(detail: 'too long', pointer: '/body/note'),
          ],
        ),
        StackTrace.current,
      );

      final body = await jsonOf(response) as Map<String, Object?>;
      expect(response.status, 422);
      expect(body['errors'], hasLength(2));
      expect(body, isNot(contains('details')));
    });

    test('details without a JSON form are sent as text', () async {
      final response = responder.respond(
        BadRequestException(details: Unprintable()),
        StackTrace.current,
      );

      expect((await jsonOf(response) as Map)['details'], 'unprintable');
    });

    test('cyclic details are dropped, the rest of the body is kept', () async {
      final cyclic = <Object?, Object?>{};
      cyclic['self'] = cyclic;

      final response = responder.respond(
        BadRequestException(message: 'Bad input', details: cyclic),
        StackTrace.current,
      );

      expect(response.status, 400);
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'detail': 'Bad input',
      });
    });

    test('an unknown error is a logged 500 without internals', () async {
      final error = StateError('db password is hunter2');

      final response = responder.respond(error, StackTrace.current);

      expect(response.status, 500);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Internal Server Error',
        'status': 500,
        'detail': 'Internal server error',
      });
      expect(log.errors, [same(error)]);
    });

    test('debug mode includes the error and the stack', () async {
      final debug = ProblemResponder(debug: true, log: RecordingErrorLog());

      final body =
          await jsonOf(debug.respond(StateError('boom'), StackTrace.current))
              as Map<String, Object?>;

      expect(body['detail'], 'Bad state: boom');
      expect(body['stack'], contains('problem_responder_test.dart'));
    });
  });
}
```

**`packages/grund_http/test/http/http_request_test.dart`**

```dart
import 'dart:convert';

import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

RequestBody streamed(List<String> chunks) =>
    RequestBody(Stream.fromIterable(chunks.map(utf8.encode)));

void main() {
  group('HttpRequest', () {
    test('upper-cases the method and freezes the headers', () {
      final headers = HeaderMap.of({'X-Id': '1'});
      final request = HttpRequest(
        method: 'get',
        uri: Uri.parse('/users?page=2'),
        headers: headers,
      );
      headers.set('x-id', '2');

      expect(request.method, 'GET');
      expect(request.uri.path, '/users');
      expect(request.uri.queryParameters, {'page': '2'});
      expect(request.headers['x-id'], '1');
      expect(() => request.headers.add('a', 'b'), throwsUnsupportedError);
    });

    test('defaults to an empty body and no connection info', () async {
      final request = HttpRequest(method: 'GET', uri: Uri.parse('/'));

      expect(await request.body.bytes(), isEmpty);
      expect(request.connectionInfo, isNull);
    });
  });

  group('RequestBody', () {
    test('reads a chunked stream once and caches it', () async {
      final body = streamed(['{"a":', '1}']);

      expect(await body.text(), '{"a":1}');
      expect(await body.json(), {'a': 1});
      expect(await body.json(), {'a': 1});
      expect(await body.bytes(), utf8.encode('{"a":1}'));
    });

    test('malformed JSON is a 400, not a crash', () async {
      await expectLater(
        RequestBody.bytes(utf8.encode('{"a":')).json(),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            startsWith('Request body is not valid JSON'),
          ),
        ),
      );
    });

    test('an empty body is a 400 when JSON is expected', () async {
      await expectLater(
        RequestBody.empty().json(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('body errors carry the code and the pointer of the body', () async {
      await expectLater(
        RequestBody.bytes(utf8.encode('{"a":')).json(),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'body_invalid')
              .having((e) => e.pointer, 'pointer', '/body'),
        ),
      );
      await expectLater(
        RequestBody.bytes(const [0xff, 0xfe]).text(),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'body_invalid',
          ),
        ),
      );
    });

    test('malformed UTF-8 is a 400', () async {
      await expectLater(
        RequestBody.bytes(const [0xff, 0xfe]).text(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('the raw stream can be taken once, then readers fail', () async {
      final body = streamed(['abc']);
      final chunks = await body.stream.toList();

      expect(utf8.decode(chunks.expand((c) => c).toList()), 'abc');
      expect(() => body.stream, throwsStateError);
      expect(() => body.bytes(), throwsStateError);
    });

    test('after a cached read, stream replays the cached bytes', () async {
      final body = streamed(['abc']);
      await body.bytes();

      expect(await body.stream.toList(), [utf8.encode('abc')]);
    });
  });
}
```

**Крок 2: запустити — очікується збій компіляції** (типів ще немає).

- [ ] Виконати:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart test 2>&1 | tail -15
```

Очікувано: `Error: ... isn't defined` / `Failed to load`.

**Крок 3: реалізація.** Створити або замінити цілком:

**`packages/grund_http/lib/src/http/http_exception.dart`**

```dart
/// [HttpException] and the built-in subclasses the framework throws itself.
///
/// The subclasses are one family with their base and share this file, like
/// the error families in the core; the base stays open (not sealed) so that
/// applications can add their own statuses.
library;

import 'status_code.dart';

/// An error that `ProblemResponder` turns into an `application/problem+json`
/// response (RFC 9457) with the same status.
///
/// Throw it from hooks and handlers. Extend it for statuses that have no
/// built-in subclass:
///
/// ```dart
/// class PaymentRequiredException extends HttpException {
///   const PaymentRequiredException() : super(402);
/// }
/// ```
class HttpException implements Exception {
  /// Creates an exception for [status]; [message] defaults to the reason
  /// phrase of [status].
  const HttpException(
    this.status, {
    String? message,
    this.code,
    this.pointer,
    this.details,
    this.headers = const {},
  }) : _message = message;

  /// HTTP status code of the response.
  final int status;

  final String? _message;

  /// Human-readable message sent to the client as `detail`.
  String get message => _message ?? StatusCode.reasonPhrase(status);

  /// Stable machine-readable identifier of the failure (`parameter_invalid`),
  /// sent as `code`; clients switch on it, never on [message].
  final String? code;

  /// JSON pointer to the offending input (`/query/page`, `/body/title`),
  /// sent as an entry of `errors`.
  final String? pointer;

  /// Extra data sent as `details`: a JSON value (`Map`, `List`, `String`,
  /// `num`, `bool`), any other object as its `toString()`. A list of
  /// `ProblemError`s is sent as `errors` instead.
  final Object? details;

  /// Headers added to the error response (for example `allow` or
  /// `www-authenticate`).
  final Map<String, String> headers;

  @override
  String toString() => '$runtimeType($status): $message';
}

/// 400: the request is malformed (bad JSON, a parameter of the wrong type).
class BadRequestException extends HttpException {
  /// Creates the exception.
  const BadRequestException({
    super.message,
    super.code,
    super.pointer,
    super.details,
  }) : super(StatusCode.badRequest);
}

/// 401: the request lacks valid credentials.
class UnauthorizedException extends HttpException {
  /// Creates the exception.
  const UnauthorizedException({
    super.message,
    super.code,
    super.details,
    super.headers,
  }) : super(StatusCode.unauthorized);
}

/// 403: the credentials are valid but not sufficient.
class ForbiddenException extends HttpException {
  /// Creates the exception.
  const ForbiddenException({super.message, super.code, super.details})
    : super(StatusCode.forbidden);
}

/// 404: no route matches the path, or the requested entity does not exist.
class NotFoundException extends HttpException {
  /// Creates the exception.
  const NotFoundException({super.message, super.code, super.details})
    : super(StatusCode.notFound);
}

/// 405: a route matches the path but not the method; [allowed] is sent in
/// the `allow` header.
class MethodNotAllowedException extends HttpException {
  /// Creates the exception for the [allowed] methods.
  MethodNotAllowedException(this.allowed, {super.message, super.code})
    : super(
        StatusCode.methodNotAllowed,
        headers: {'allow': allowed.join(', ')},
      );

  /// Methods the matched path accepts, sorted.
  final List<String> allowed;
}

/// 413: the request body is larger than the configured limit.
class PayloadTooLargeException extends HttpException {
  /// Creates the exception.
  const PayloadTooLargeException({super.message, super.code, super.details})
    : super(StatusCode.payloadTooLarge);
}

/// 422: the request is well-formed but its content is not acceptable (a
/// business rule, a failed validation of the body).
class UnprocessableContentException extends HttpException {
  /// Creates the exception.
  const UnprocessableContentException({
    super.message,
    super.code,
    super.pointer,
    super.details,
  }) : super(StatusCode.unprocessableContent);
}

/// 503: the application is shutting down or temporarily unable to serve.
class ServiceUnavailableException extends HttpException {
  /// Creates the exception.
  const ServiceUnavailableException({super.message, super.code, super.details})
    : super(StatusCode.serviceUnavailable);
}
```

**`packages/grund_http/lib/src/http/status_code.dart`**

```dart
/// HTTP status codes that grund itself produces or documents, and their
/// reason phrases. A flat catalog.
abstract final class StatusCode {
  /// 200 OK.
  static const ok = 200;

  /// 201 Created.
  static const created = 201;

  /// 204 No Content.
  static const noContent = 204;

  /// 302 Found.
  static const found = 302;

  /// 400 Bad Request.
  static const badRequest = 400;

  /// 401 Unauthorized.
  static const unauthorized = 401;

  /// 403 Forbidden.
  static const forbidden = 403;

  /// 404 Not Found.
  static const notFound = 404;

  /// 405 Method Not Allowed.
  static const methodNotAllowed = 405;

  /// 409 Conflict.
  static const conflict = 409;

  /// 413.
  static const payloadTooLarge = 413;

  /// 422 Unprocessable Content.
  static const unprocessableContent = 422;

  /// 500 Internal Server Error.
  static const internalServerError = 500;

  /// 503 Service Unavailable.
  static const serviceUnavailable = 503;

  /// The reason phrase of [code], or `'Unknown Status'`.
  static String reasonPhrase(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    409 => 'Conflict',
    410 => 'Gone',
    413 => 'Content Too Large',
    415 => 'Unsupported Media Type',
    422 => 'Unprocessable Content',
    429 => 'Too Many Requests',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    _ => 'Unknown Status',
  };
}
```

**`packages/grund_http/lib/src/http/request_body.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'http_exception.dart';
import 'problem_code.dart';

/// The body of an `HttpRequest`: a byte stream that is read at most once.
///
/// [bytes], [text] and [json] read the whole stream on first use and cache
/// the result, so a guard and a handler can both call `json()`. [stream]
/// hands out the raw stream for large uploads; after that the cached
/// readers fail with a [StateError], and vice versa only the cached bytes
/// are streamed.
final class RequestBody {
  /// Wraps a body stream supplied by an adapter.
  RequestBody(Stream<List<int>> source) : _source = source;

  /// A body whose content is already in memory (tests, middleware).
  RequestBody.bytes(List<int> bytes)
    : _source = null,
      _bytes = Future.value(Uint8List.fromList(bytes));

  /// A body with no content.
  RequestBody.empty() : this.bytes(const []);

  Stream<List<int>>? _source;
  Future<Uint8List>? _bytes;
  Future<Object?>? _json;
  bool _streamTaken = false;

  /// The whole body; read once and cached.
  Future<Uint8List> bytes() {
    if (_streamTaken) {
      throw StateError('The request body was already taken by `stream`.');
    }
    return _bytes ??= _collect();
  }

  /// The body decoded as UTF-8; malformed UTF-8 throws
  /// [BadRequestException].
  Future<String> text() async {
    final data = await bytes();
    try {
      return utf8.decode(data);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid UTF-8: ${error.message}',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
  }

  /// The body decoded as JSON and cached. An empty or malformed body throws
  /// [BadRequestException].
  Future<Object?> json() => _json ??= _decodeJson();

  /// The raw body stream; can be taken once, and not after [bytes] started
  /// reading (then the cached bytes are streamed instead).
  Stream<List<int>> get stream {
    final cached = _bytes;
    if (cached != null) return Stream.fromFuture(cached);
    final source = _source;
    if (source == null || _streamTaken) {
      throw StateError('The request body stream can be taken only once.');
    }
    _streamTaken = true;
    return source;
  }

  Future<Object?> _decodeJson() async {
    final source = await text();
    if (source.trim().isEmpty) {
      throw const BadRequestException(
        message: 'Request body is empty; expected JSON.',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid JSON: ${error.message}',
        code: ProblemCode.bodyInvalid,
        pointer: ProblemCode.bodyPointer,
      );
    }
  }

  Future<Uint8List> _collect() async {
    final source = _source;
    _source = null;
    if (source == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
```

**`packages/grund_http/lib/src/http/problem_code.dart`**

```dart
/// The stable `code` values and pointers the framework puts into problems.
abstract final class ProblemCode {
  /// The request body is not UTF-8, not JSON, not an object or not what the
  /// body reader expected.
  static const bodyInvalid = 'body_invalid';

  /// The request body is larger than `HttpConfig.maxBodyBytes`.
  static const bodyTooLarge = 'body_too_large';

  /// A required path, query, header or cookie value is absent.
  static const parameterMissing = 'parameter_missing';

  /// A parameter value cannot be read as the requested type or violates a
  /// pattern or an enumeration.
  static const parameterInvalid = 'parameter_invalid';

  /// A number or a length is outside the allowed range.
  static const parameterOutOfRange = 'parameter_out_of_range';

  /// No route matches the path.
  static const routeNotFound = 'route_not_found';

  /// A route matches the path, but not the method.
  static const methodNotAllowed = 'method_not_allowed';

  /// The server is shutting down.
  static const serverUnavailable = 'server_unavailable';

  /// The JSON pointer of the request body.
  static const bodyPointer = '/body';
}
```

**`packages/grund_http/lib/src/http/problem_error.dart`**

```dart
/// One failure inside a [Problem]: a rejected field, parameter or header.
final class ProblemError {
  /// Creates the entry.
  const ProblemError({required this.detail, this.pointer, this.code});

  /// What is wrong, for a person.
  final String detail;

  /// JSON pointer to the offending input (`/body/title`, `/query/page`).
  final String? pointer;

  /// Stable machine-readable identifier of this failure.
  final String? code;

  /// The entry as a JSON object; absent members are left out.
  Map<String, Object?> toJson() => {
    'detail': detail,
    if (pointer != null) 'pointer': pointer,
    if (code != null) 'code': code,
  };
}
```

**`packages/grund_http/lib/src/http/problem.dart`**

```dart
import 'problem_error.dart';

/// A problem details object (RFC 9457), the body of every error response.
final class Problem {
  /// Creates the problem; [type] is `about:blank` when the status says it
  /// all.
  const Problem({
    this.type = 'about:blank',
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.code,
    this.errors = const [],
    this.extensions = const {},
  });

  /// URI that identifies the kind of problem.
  final String type;

  /// Short summary of the kind of problem (the reason phrase of [status]).
  final String title;

  /// The HTTP status of the response.
  final int status;

  /// What went wrong this time, for a person.
  final String? detail;

  /// URI that identifies this occurrence (the request path).
  final String? instance;

  /// Stable machine-readable identifier, an extension member.
  final String? code;

  /// The individual failures, an extension member.
  final List<ProblemError> errors;

  /// Further extension members; one never replaces a standard member.
  final Map<String, Object?> extensions;

  /// The problem as a JSON object: the standard members first, then the
  /// extensions.
  Map<String, Object?> toJson() => {
    'type': type,
    'title': title,
    'status': status,
    if (detail != null) 'detail': detail,
    if (instance != null) 'instance': instance,
    if (code != null) 'code': code,
    if (errors.isNotEmpty) 'errors': [for (final e in errors) e.toJson()],
    for (final MapEntry(:key, :value) in extensions.entries)
      if (!_standard.contains(key)) key: value,
  };

  static const _standard = {
    'type',
    'title',
    'status',
    'detail',
    'instance',
    'code',
    'errors',
  };
}
```

**`packages/grund_http/lib/src/http/error_log.dart`**

```dart
/// Receives the errors that become 500 responses, with their stack traces.
///
/// It must not throw. `HttpModule` binds [PrintErrorLog]; bind another
/// implementation under `Key<ErrorLog>()` (an override in tests, a logger in
/// production) to take the reports elsewhere.
abstract interface class ErrorLog {
  /// Records [error] that was turned into a 500 response.
  void report(Object error, StackTrace stackTrace);
}
```

**`packages/grund_http/lib/src/http/print_error_log.dart`**

```dart
import 'dart:io';

import 'error_log.dart';

/// The default [ErrorLog]: writes the error and its stack trace to stderr.
final class PrintErrorLog implements ErrorLog {
  /// Creates the log.
  const PrintErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) {
    stderr.writeln('grund: unhandled error: $error\n$stackTrace');
  }
}
```

**`packages/grund_http/lib/src/http/problem_responder.dart`**

```dart
import 'dart:convert';

import 'error_log.dart';
import 'header_map.dart';
import 'http_exception.dart';
import 'http_response.dart';
import 'problem.dart';
import 'problem_error.dart';
import 'response_body.dart';
import 'status_code.dart';

/// Turns any error into an `application/problem+json` response and never
/// throws.
///
/// - [HttpException]: its status and headers; `detail` is its message, `code`
///   and `pointer` (as an entry of `errors`) are kept, `details` becomes the
///   extension `details` (a list of [ProblemError]s becomes `errors`).
/// - anything else: reported to [log], then 500 with `detail` `Internal
///   server error`; with [debug] the detail is the error's `toString()` and
///   the extension `stack` holds the stack trace.
final class ProblemResponder {
  /// Creates the responder.
  const ProblemResponder({required this.debug, required this.log});

  /// Whether 500 responses reveal the error and its stack trace.
  final bool debug;

  /// Where unexpected errors are reported.
  final ErrorLog log;

  /// The response for [error]; [instance] identifies the failed request.
  HttpResponse respond(
    Object error,
    StackTrace stackTrace, {
    String? instance,
  }) {
    if (error is! HttpException) {
      log.report(error, stackTrace);
      return _response(
        500,
        HeaderMap(),
        _internal(error, stackTrace, instance),
      );
    }
    final headers = HeaderMap.of(error.headers);
    final full = _fromException(error, instance, withDetails: true);
    // A details value the encoder rejects (a cycle) must not turn a 400 into
    // a failure of the responder: it is dropped and the rest is sent.
    return _response(
      error.status,
      headers,
      full,
      fallback: _fromException(error, instance, withDetails: false),
    );
  }

  Problem _fromException(
    HttpException error,
    String? instance, {
    required bool withDetails,
  }) {
    final (listed, extra) = switch (error.details) {
      final List<ProblemError> list => (list, null),
      final other => (const <ProblemError>[], other),
    };
    return Problem(
      title: StatusCode.reasonPhrase(error.status),
      status: error.status,
      detail: error.message,
      instance: instance,
      code: error.code,
      errors: [
        if (error.pointer != null)
          ProblemError(
            detail: error.message,
            pointer: error.pointer,
            code: error.code,
          ),
        ...listed,
      ],
      extensions: {if (withDetails && extra != null) 'details': extra},
    );
  }

  Problem _internal(Object error, StackTrace stackTrace, String? instance) =>
      Problem(
        title: StatusCode.reasonPhrase(StatusCode.internalServerError),
        status: StatusCode.internalServerError,
        detail: debug ? '$error' : 'Internal server error',
        instance: instance,
        extensions: {if (debug) 'stack': '$stackTrace'},
      );

  static HttpResponse _response(
    int status,
    HeaderMap headers,
    Problem problem, {
    Problem? fallback,
  }) {
    headers.set('content-type', 'application/problem+json');
    return HttpResponse(
      status,
      headers: headers,
      body: BytesBody(utf8.encode(_encode(problem, fallback))),
    );
  }

  static String _encode(Problem problem, Problem? fallback) {
    // Anything that is not a JSON value is sent as its toString(), so
    // building an error response cannot fail on odd details.
    String encode(Problem value) =>
        jsonEncode(value.toJson(), toEncodable: (Object? v) => '$v');
    // ProblemResponder boundary: a cyclic details value makes the encoder
    // throw this SDK Error; the problem is then sent without details.
    try {
      return encode(problem);
    } on JsonUnsupportedObjectError {
      return encode(fallback ?? problem);
    }
  }
}
```

**`packages/grund_http/lib/grund_http.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/http/connection_info.dart';
export 'src/http/error_log.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/print_error_log.dart';
export 'src/http/problem.dart';
export 'src/http/problem_code.dart';
export 'src/http/problem_error.dart';
export 'src/http/problem_responder.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
```

- [ ] **Крок 4: запустити — зелено.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart analyze && dart test 2>&1 | tail -3
```

Очікувано: `No issues found!` і `All tests passed!` (усього тестів у пакеті: **82**).

- [ ] **Крок 5: самоперевірка.** `wc -l` кожного зміненого файла (lib ≤ 300, тест ≤ 500), найдовший метод ≤ 40, `dart format packages example` змінює 0 файлів.

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
wc -l packages/grund_http/lib/src/*/*.dart | sort -n | tail -3
dart format packages/grund_http
```

- [ ] **Крок 6: коміт.**

```bash
cd ~/projects/grund
git add packages/grund_http
git commit -m "feat(http): report errors as RFC 9457 problem+json"
```

### Задача 8: `Params` і `HttpCtx`

**Мета.** `Params` (типізовані читачі з іменованими обмеженнями) і `HttpCtx` (параметри, тіло з лімітом, `c.set`/`c<T>()` з ядра).

Усі помилки читачів — `BadRequestException` з `code` (`parameter_missing|invalid|out_of_range|body_invalid`) і `pointer` `/path/id`, `/query/limit`, `/body`.

**Files** (усі шляхи відносно `packages/grund_http/`):

- Modify/Create `lib/src/ctx/param_location.dart`
- Modify/Create `lib/src/ctx/cookie_header.dart`
- Modify/Create `lib/src/ctx/param_constraints.dart`
- Modify/Create `lib/src/ctx/params.dart`
- Modify/Create `lib/src/ctx/body_reader.dart`
- Modify/Create `lib/src/ctx/http_ctx.dart`
- Modify `lib/grund_http.dart`
- Test `test/helpers/ctx_factory.dart`
- Test `test/ctx/params_test.dart`
- Test `test/ctx/http_ctx_test.dart`

Після задачі існують у `packages/grund_http/lib/src/`: `adapter/adapter_lifecycle.dart`, `adapter/error_logger.dart`, `adapter/http_adapter.dart`, `adapter/in_flight_requests.dart`, `ctx/body_reader.dart`, `ctx/cookie_header.dart`, `ctx/http_ctx.dart`, `ctx/param_constraints.dart`, `ctx/param_location.dart`, `ctx/params.dart`, `http/connection_info.dart`, `http/error_log.dart`, `http/header_map.dart`, `http/http_exception.dart`, `http/http_request.dart`, `http/http_response.dart`, `http/print_error_log.dart`, `http/problem.dart`, `http/problem_code.dart`, `http/problem_error.dart`, `http/problem_responder.dart`, `http/request_body.dart`, `http/response_body.dart`, `http/response_head.dart`, `http/status_code.dart`, `routing/pattern_segment.dart`, `routing/route_match.dart`, `routing/route_pattern.dart`, `routing/router.dart`, `routing/routing_error.dart`, `serialize/response_serializer.dart`, `serialize/serialization_error.dart`, `serialize/serializer_registry.dart`, `testing/test_response.dart`.

**Interfaces.**

- Consumes: `HttpRequest`, `RequestBody`, `BadRequestException`/`PayloadTooLargeException`/`ProblemCode` (7); `CallContext`, `CallScope`, `CancelSignal` (ядро).
- Produces: `Params`, `ParamLocation`, `HttpCtx({request, scope, response, pathParameters, cancel, maxBodyBytes})` з `path/query/headers/cookies`, `body`, `bodyList`, `bytes`.

Рішення, що фіксує задача:

- Усі читачі — один шлях помилки (`ParamConstraints`): сире значення в повідомленні обрізається до 64 символів.
- `integer` приймає лише `^[+-]?\d+$`; `boolean` — лише `true`/`false`; `decimal` — скінченні; `uri` — непорожній.
- Тіло: ліміт перевіряється за `Content-Length` і під час читання потоку; `FormatException`/`TypeError` із `fromJson` — 400 `body_invalid`.

**Крок 1: падаючі тести.** Створити такі тести та допоміжні файли (цілком):

**`packages/grund_http/test/helpers/ctx_factory.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';

/// A module without bindings: the smallest graph that has a call scope.
final class EmptyModule extends Module {
  const EmptyModule();
}

/// Builds [HttpCtx]s over real call scopes of an empty application.
final class CtxFactory {
  CtxFactory._(this._app);

  final TestApp _app;

  /// Starts the empty application.
  static Future<CtxFactory> start() async =>
      CtxFactory._(await TestApp.start(root: const EmptyModule()));

  /// A context for [request].
  HttpCtx call(
    HttpRequest request, {
    Map<String, String> pathParameters = const {},
    int? maxBodyBytes,
  }) => HttpCtx(
    request: request,
    scope: _app.injector.openCall(),
    response: ResponseHead(),
    pathParameters: pathParameters,
    maxBodyBytes: maxBodyBytes,
  );

  /// Closes the application.
  Future<void> close() => _app.close();
}
```

**`packages/grund_http/test/ctx/params_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

enum Color { red, green }

Params queryOf(Map<String, List<String>> values) =>
    Params(ParamLocation.query, (name) => values[name] ?? const []);

Matcher badRequest(String code, String pointer) => isA<BadRequestException>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.pointer, 'pointer', pointer);

void main() {
  group('Params reading', () {
    test('converts every built-in type', () {
      final params = queryOf({
        'name': ['ann'],
        'page': ['3'],
        'price': ['2.5'],
        'done': ['true'],
        'at': ['2026-10-15T10:00:00Z'],
        'next': ['https://example.com/a?b=1'],
        'color': ['green'],
      });

      expect(params.string('name'), 'ann');
      expect(params.integer('page'), 3);
      expect(params.decimal('price'), 2.5);
      expect(params.boolean('done'), isTrue);
      expect(params.dateTime('at'), DateTime.utc(2026, 10, 15, 10));
      expect(params.uri('next').host, 'example.com');
      expect(params.enumOf('color', Color.values), Color.green);
    });

    test('the OrNull readers return null for an absent parameter', () {
      final params = queryOf({});

      expect(params.stringOrNull('a'), isNull);
      expect(params.integerOrNull('a'), isNull);
      expect(params.decimalOrNull('a'), isNull);
      expect(params.booleanOrNull('a'), isNull);
      expect(params.dateTimeOrNull('a'), isNull);
      expect(params.uriOrNull('a'), isNull);
      expect(params.enumOfOrNull('a', Color.values), isNull);
    });

    test('a repeated parameter reads as the first value, all has all', () {
      final params = queryOf({
        'tag': ['a', 'b'],
      });

      expect(params.string('tag'), 'a');
      expect(params.all('tag'), ['a', 'b']);
      expect(params.all('none'), isEmpty);
    });

    test('an empty value is a value', () {
      final params = queryOf({
        'q': [''],
      });

      expect(params.string('q'), '');
      expect(() => params.integer('q'), throwsA(isA<BadRequestException>()));
    });
  });

  group('Params errors (RF-3)', () {
    test('an absent required parameter is parameter_missing', () {
      expect(
        () => queryOf({}).integer('page'),
        throwsA(badRequest('parameter_missing', '/query/page')),
      );
    });

    test('the pointer names the location', () {
      final header = Params(ParamLocation.header, (_) => const []);
      final path = Params(ParamLocation.path, (_) => const []);

      expect(
        () => header.string('x-key'),
        throwsA(badRequest('parameter_missing', '/header/x-key')),
      );
      expect(
        () => path.integer('id'),
        throwsA(badRequest('parameter_missing', '/path/id')),
      );
    });

    test('values of the wrong type are parameter_invalid', () {
      for (final read in <(String, Object? Function(Params))>[
        ('abc', (p) => p.integer('v')),
        ('1.5', (p) => p.integer('v')),
        ('0x10', (p) => p.integer('v')),
        ('99999999999999999999', (p) => p.integer('v')),
        ('1e', (p) => p.decimal('v')),
        ('NaN', (p) => p.decimal('v')),
        ('yes', (p) => p.boolean('v')),
        ('tomorrow', (p) => p.dateTime('v')),
        ('', (p) => p.uri('v')),
        ('blue', (p) => p.enumOf('v', Color.values)),
      ]) {
        final params = queryOf({
          'v': [read.$1],
        });
        expect(
          () => read.$2(params),
          throwsA(badRequest('parameter_invalid', '/query/v')),
          reason: 'value "${read.$1}"',
        );
      }
    });

    test('an invalid OrNull value is still rejected', () {
      final params = queryOf({
        'page': ['x'],
      });

      expect(
        () => params.integerOrNull('page'),
        throwsA(badRequest('parameter_invalid', '/query/page')),
      );
    });

    test('a long value is shortened in the message', () {
      final params = queryOf({
        'v': ['x' * 500],
      });

      expect(
        () => params.integer('v'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message.length,
            'message length',
            lessThan(200),
          ),
        ),
      );
    });
  });

  group('Params constraints', () {
    test('integer and decimal bounds are inclusive', () {
      final params = queryOf({
        'a': ['1'],
        'b': ['100'],
        'c': ['0'],
        'd': ['101'],
        'x': ['0.5'],
      });

      expect(params.integer('a', min: 1, max: 100), 1);
      expect(params.integer('b', min: 1, max: 100), 100);
      expect(
        () => params.integer('c', min: 1),
        throwsA(badRequest('parameter_out_of_range', '/query/c')),
      );
      expect(
        () => params.integer('d', max: 100),
        throwsA(badRequest('parameter_out_of_range', '/query/d')),
      );
      expect(
        () => params.decimal('x', min: 1),
        throwsA(badRequest('parameter_out_of_range', '/query/x')),
      );
    });

    test('string length is checked in characters', () {
      final params = queryOf({
        's': ['abc'],
      });

      expect(params.string('s', minLength: 3, maxLength: 3), 'abc');
      expect(
        () => params.string('s', minLength: 4),
        throwsA(badRequest('parameter_out_of_range', '/query/s')),
      );
      expect(
        () => params.string('s', maxLength: 2),
        throwsA(badRequest('parameter_out_of_range', '/query/s')),
      );
    });

    test('a pattern must match the whole value', () {
      final params = queryOf({
        'ok': ['ab12'],
        'partial': ['ab12!'],
      });

      expect(params.string('ok', pattern: r'[a-z]+\d+'), 'ab12');
      expect(
        () => params.string('partial', pattern: r'[a-z]+\d+'),
        throwsA(badRequest('parameter_invalid', '/query/partial')),
      );
    });

    test('oneOf accepts only the listed values', () {
      final params = queryOf({
        'sort': ['name'],
        'bad': ['id'],
      });

      expect(params.string('sort', oneOf: ['name', 'date']), 'name');
      expect(
        () => params.string('bad', oneOf: ['name', 'date']),
        throwsA(badRequest('parameter_invalid', '/query/bad')),
      );
    });
  });
}
```

**`packages/grund_http/test/ctx/http_ctx_test.dart`**

```dart
import 'dart:convert';

import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/ctx_factory.dart';
import '../helpers/http_fixtures.dart';

final class NewUser {
  NewUser(this.name);

  factory NewUser.fromJson(Map<String, Object?> json) =>
      NewUser(json['name']! as String);

  final String name;
}

NewUser strictUser(Map<String, Object?> json) {
  if (json['name'] == '') throw const FormatException('name is empty');
  return NewUser.fromJson(json);
}

TypeMatcher<BadRequestException> problem(String code, String pointer) =>
    isA<BadRequestException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.pointer, 'pointer', pointer);

void main() {
  late CtxFactory contexts;

  setUpAll(() async => contexts = await CtxFactory.start());
  tearDownAll(() => contexts.close());

  group('HttpCtx parameters', () {
    test('reads path, query, header and cookie values', () {
      final c = contexts(
        requestFor(
          'GET',
          '/users/7?page=2&tag=a&tag=b',
          headers: {'x-api-key': 'k', 'cookie': 'sid=abc; theme="dark"'},
        ),
        pathParameters: {'id': '7'},
      );

      expect(c.path.integer('id'), 7);
      expect(c.query.integer('page'), 2);
      expect(c.query.all('tag'), ['a', 'b']);
      expect(c.headers.string('X-Api-Key'), 'k');
      expect(c.cookies.string('sid'), 'abc');
      expect(c.cookies.string('theme'), 'dark');
    });

    test('a query value is percent-decoded', () {
      final c = contexts(requestFor('GET', '/s?q=a%20b%2Fc'));

      expect(c.query.string('q'), 'a b/c');
    });

    test('an unknown path parameter is missing', () {
      final c = contexts(requestFor('GET', '/'));

      expect(
        () => c.path.integer('id'),
        throwsA(problem('parameter_missing', '/path/id')),
      );
    });

    test('the response head starts empty and the handler may change it', () {
      final c = contexts(requestFor('GET', '/'));

      expect(c.response.status, isNull);
      c.response.status = 201;
      expect(c.response.status, 201);
    });
  });

  group('HttpCtx body (RF-3)', () {
    test('decodes a JSON object', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":"ann"}'));

      expect((await c.body(NewUser.fromJson)).name, 'ann');
    });

    test('the body can be read more than once', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":"ann"}'));

      await c.body(NewUser.fromJson);
      expect((await c.body(NewUser.fromJson)).name, 'ann');
      expect(utf8.decode(await c.bytes()), '{"name":"ann"}');
    });

    test('malformed JSON is a 400 body_invalid', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('an empty body is a 400 body_invalid', () async {
      final c = contexts(requestFor('POST', '/'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a JSON value that is not an object is a 400', () async {
      for (final body in ['[1]', '"x"', '3', 'null']) {
        final c = contexts(requestFor('POST', '/', body: body));

        await expectLater(
          c.body(NewUser.fromJson),
          throwsA(problem('body_invalid', '/body')),
          reason: body,
        );
      }
    });

    test('a missing required field is a 400, not a 500', () async {
      final c = contexts(requestFor('POST', '/', body: '{}'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a field of the wrong type is a 400', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":5}'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a FormatException from fromJson is a 400 with its message', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":""}'));

      await expectLater(
        c.body(strictUser),
        throwsA(
          problem(
            'body_invalid',
            '/body',
          ).having((e) => e.message, 'message', contains('name is empty')),
        ),
      );
    });

    test('any other failure of fromJson is not hidden', () async {
      final c = contexts(requestFor('POST', '/', body: '{}'));

      await expectLater(
        c.body<NewUser>((_) => throw StateError('bug')),
        throwsStateError,
      );
    });

    test('bodyList builds every item and points at a bad one', () async {
      final ok = contexts(
        requestFor('POST', '/', body: '[{"name":"a"},{"name":"b"}]'),
      );
      final bad = contexts(
        requestFor('POST', '/', body: '[{"name":"a"},{"nope":1}]'),
      );
      final notArray = contexts(requestFor('POST', '/', body: '{}'));

      expect((await ok.bodyList(NewUser.fromJson)).map((u) => u.name), [
        'a',
        'b',
      ]);
      await expectLater(
        bad.bodyList(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body/1')),
      );
      await expectLater(
        notArray.bodyList(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a declared size over the limit is a 413 without reading', () async {
      var read = false;
      final request = HttpRequest(
        method: 'POST',
        uri: Uri.parse('/'),
        headers: HeaderMap.of({'content-length': '2000'}),
        body: RequestBody(
          Stream.fromIterable([utf8.encode('x')]).map((chunk) {
            read = true;
            return chunk;
          }),
        ),
      );
      final c = contexts(request, maxBodyBytes: 1000);

      await expectLater(
        c.bytes(),
        throwsA(
          isA<PayloadTooLargeException>()
              .having((e) => e.status, 'status', 413)
              .having((e) => e.code, 'code', 'body_too_large'),
        ),
      );
      expect(read, isFalse);
    });

    test('a streamed body over the limit is a 413 while reading', () async {
      final request = HttpRequest(
        method: 'POST',
        uri: Uri.parse('/'),
        body: RequestBody(
          Stream.fromIterable([List.filled(600, 120), List.filled(600, 120)]),
        ),
      );
      final c = contexts(request, maxBodyBytes: 1000);

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(isA<PayloadTooLargeException>()),
      );
    });

    test('a body exactly at the limit is accepted', () async {
      final c = contexts(
        requestFor('POST', '/', body: '{"name":"ann"}'),
        maxBodyBytes: '{"name":"ann"}'.length,
      );

      expect((await c.body(NewUser.fromJson)).name, 'ann');
    });
  });
}
```

**Крок 2: запустити — очікується збій компіляції** (типів ще немає).

- [ ] Виконати:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart test 2>&1 | tail -15
```

Очікувано: `Error: ... isn't defined` / `Failed to load`.

**Крок 3: реалізація.** Створити або замінити цілком:

**`packages/grund_http/lib/src/ctx/param_location.dart`**

```dart
/// Where in the request a parameter is read from.
enum ParamLocation {
  /// A `:name` segment of the route path.
  path('path parameter', 'path'),

  /// A query string parameter.
  query('query parameter', 'query'),

  /// A request header.
  header('header', 'header'),

  /// A cookie of the `Cookie` header.
  cookie('cookie', 'cookie');

  const ParamLocation(this.label, this.pointerSegment);

  /// How messages call it: `query parameter "page"`.
  final String label;

  /// The first segment of the JSON pointer: `/query/page`.
  final String pointerSegment;
}
```

**`packages/grund_http/lib/src/ctx/cookie_header.dart`**

```dart
/// Reads the `Cookie` request header.
abstract final class CookieHeader {
  /// The cookies of the header [values] by name; a name repeated keeps all
  /// its values, a double-quoted value loses the quotes. A pair without `=`
  /// is ignored.
  static Map<String, List<String>> parse(List<String> values) {
    final cookies = <String, List<String>>{};
    for (final header in values) {
      for (final pair in header.split(';')) {
        final separator = pair.indexOf('=');
        if (separator < 0) continue;
        final name = pair.substring(0, separator).trim();
        if (name.isEmpty) continue;
        cookies
            .putIfAbsent(name, () => [])
            .add(_unquote(pair.substring(separator + 1).trim()));
      }
    }
    return cookies;
  }

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;
}
```

**`packages/grund_http/lib/src/ctx/param_constraints.dart`**

```dart
import '../http/http_exception.dart';
import '../http/problem_code.dart';
import 'param_location.dart';

/// The checks a parameter reader applies to a value it has parsed, and the
/// errors it reports: always a [BadRequestException] with a stable `code` and
/// the pointer `/<location>/<name>`.
abstract final class ParamConstraints {
  static const _shownLength = 64;

  /// The error for a parameter that is absent.
  static BadRequestException missing(ParamLocation location, String name) =>
      BadRequestException(
        message: 'Missing ${location.label} "$name".',
        code: ProblemCode.parameterMissing,
        pointer: _pointer(location, name),
      );

  /// The error for a value that is not a [expected].
  static BadRequestException invalid(
    ParamLocation location,
    String name,
    String raw,
    String expected,
  ) => BadRequestException(
    message:
        'Invalid ${location.label} "$name": expected $expected, '
        'got "${_shown(raw)}".',
    code: ProblemCode.parameterInvalid,
    pointer: _pointer(location, name),
  );

  /// The error for a value outside the allowed range.
  static BadRequestException outOfRange(
    ParamLocation location,
    String name,
    String requirement,
  ) => BadRequestException(
    message: 'The ${location.label} "$name" must be $requirement.',
    code: ProblemCode.parameterOutOfRange,
    pointer: _pointer(location, name),
  );

  /// Checks [value] against the inclusive bounds [min] and [max].
  static void checkRange(
    ParamLocation location,
    String name,
    num value, {
    num? min,
    num? max,
  }) {
    if (min != null && value < min) {
      throw outOfRange(location, name, 'at least $min');
    }
    if (max != null && value > max) {
      throw outOfRange(location, name, 'at most $max');
    }
  }

  /// Checks the length of [value] against [minLength] and [maxLength].
  static void checkLength(
    ParamLocation location,
    String name,
    String value, {
    int? minLength,
    int? maxLength,
  }) {
    if (minLength != null && value.length < minLength) {
      throw outOfRange(location, name, 'at least $minLength characters long');
    }
    if (maxLength != null && value.length > maxLength) {
      throw outOfRange(location, name, 'at most $maxLength characters long');
    }
  }

  /// Checks that [value] matches [pattern] as a whole.
  static void checkPattern(
    ParamLocation location,
    String name,
    String value,
    String pattern,
  ) {
    final match = RegExp(pattern).matchAsPrefix(value);
    if (match != null && match.end == value.length) return;
    throw invalid(location, name, value, 'a value matching /$pattern/');
  }

  /// Checks that [value] is one of [allowed].
  static void checkOneOf(
    ParamLocation location,
    String name,
    String value,
    List<String> allowed,
  ) {
    if (allowed.contains(value)) return;
    throw invalid(location, name, value, 'one of ${allowed.join(', ')}');
  }

  static String _pointer(ParamLocation location, String name) =>
      '/${location.pointerSegment}/$name';

  static String _shown(String raw) =>
      raw.length <= _shownLength ? raw : '${raw.substring(0, _shownLength)}...';
}
```

**`packages/grund_http/lib/src/ctx/params.dart`**

```dart
import 'param_constraints.dart';
import 'param_location.dart';

/// Typed readers for the parameters of one [ParamLocation] of a request.
///
/// All validation happens in the readers: an absent required parameter, a
/// value of the wrong type, or one outside the given constraints throws a
/// `BadRequestException` (400) with a stable `code` (`parameter_missing`,
/// `parameter_invalid`, `parameter_out_of_range`) and the pointer
/// `/<location>/<name>`. The `...OrNull` readers return `null` for an absent
/// parameter and still reject an invalid one. A repeated parameter reads as
/// its first value; [all] returns every value.
final class Params {
  /// Creates readers over [lookup], which returns every value of a name
  /// (empty when absent).
  Params(this.location, this._lookup);

  /// Where the values come from.
  final ParamLocation location;

  final List<String> Function(String name) _lookup;

  /// Every value of [name], in order; empty when absent.
  List<String> all(String name) => _lookup(name);

  /// The text of [name], optionally constrained by length, a full-match
  /// [pattern] or a list of allowed values.
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    String? pattern,
    List<String>? oneOf,
  }) => _required(
    name,
    stringOrNull(
      name,
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
      oneOf: oneOf,
    ),
  );

  /// Like [string], `null` when absent.
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    String? pattern,
    List<String>? oneOf,
  }) {
    final raw = _first(name);
    if (raw == null) return null;
    ParamConstraints.checkLength(
      location,
      name,
      raw,
      minLength: minLength,
      maxLength: maxLength,
    );
    if (pattern != null) {
      ParamConstraints.checkPattern(location, name, raw, pattern);
    }
    if (oneOf != null) ParamConstraints.checkOneOf(location, name, raw, oneOf);
    return raw;
  }

  /// The decimal integer in [name], within the inclusive [min] and [max].
  int integer(String name, {int? min, int? max}) =>
      _required(name, integerOrNull(name, min: min, max: max));

  /// Like [integer], `null` when absent.
  int? integerOrNull(String name, {int? min, int? max}) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = _integerPattern.hasMatch(raw) ? int.tryParse(raw) : null;
    if (value == null) _fail(name, raw, 'an integer');
    ParamConstraints.checkRange(location, name, value, min: min, max: max);
    return value;
  }

  /// The finite number in [name], within the inclusive [min] and [max].
  double decimal(String name, {double? min, double? max}) =>
      _required(name, decimalOrNull(name, min: min, max: max));

  /// Like [decimal], `null` when absent.
  double? decimalOrNull(String name, {double? min, double? max}) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) _fail(name, raw, 'a number');
    ParamConstraints.checkRange(location, name, value, min: min, max: max);
    return value;
  }

  /// The literal `true` or `false` in [name].
  bool boolean(String name) => _required(name, booleanOrNull(name));

  /// Like [boolean], `null` when absent.
  bool? booleanOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    return switch (raw) {
      'true' => true,
      'false' => false,
      _ => _fail(name, raw, 'true or false'),
    };
  }

  /// The ISO 8601 date and time in [name].
  DateTime dateTime(String name) => _required(name, dateTimeOrNull(name));

  /// Like [dateTime], `null` when absent.
  DateTime? dateTimeOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    return DateTime.tryParse(raw) ?? _fail(name, raw, 'an ISO 8601 date-time');
  }

  /// The URI in [name].
  Uri uri(String name) => _required(name, uriOrNull(name));

  /// Like [uri], `null` when absent.
  Uri? uriOrNull(String name) {
    final raw = _first(name);
    if (raw == null) return null;
    final value = raw.isEmpty ? null : Uri.tryParse(raw);
    return value ?? _fail(name, raw, 'a URI');
  }

  /// The element of [values] whose `name` equals the text in [name].
  E enumOf<E extends Enum>(String name, List<E> values) =>
      _required(name, enumOfOrNull(name, values));

  /// Like [enumOf], `null` when absent.
  E? enumOfOrNull<E extends Enum>(String name, List<E> values) {
    final raw = _first(name);
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return _fail(name, raw, 'one of ${values.map((v) => v.name).join(', ')}');
  }

  static final _integerPattern = RegExp(r'^[+-]?\d+$');

  String? _first(String name) {
    final values = _lookup(name);
    return values.isEmpty ? null : values.first;
  }

  T _required<T extends Object>(String name, T? value) =>
      value ?? (throw ParamConstraints.missing(location, name));

  Never _fail(String name, String raw, String expected) =>
      throw ParamConstraints.invalid(location, name, raw, expected);
}
```

**`packages/grund_http/lib/src/ctx/body_reader.dart`**

```dart
import 'dart:typed_data';

import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/problem_code.dart';
import '../http/request_body.dart';

/// Reads the body of one request once, within a size limit, and decodes it.
final class BodyReader {
  /// Creates the reader for [request]; [maxBytes] is the limit, `null` for
  /// none.
  BodyReader(this._request, this._maxBytes);

  final HttpRequest _request;
  final int? _maxBytes;
  Future<Uint8List>? _bytes;
  Future<Object?>? _json;

  /// The raw body; throws [PayloadTooLargeException] (413) as soon as the
  /// declared or the received size exceeds the limit.
  Future<Uint8List> bytes() => _bytes ??= _read();

  /// The body decoded as one JSON object and built with [fromJson].
  Future<T> object<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) async {
    final json = await _decoded();
    if (json is! Map<String, Object?>) {
      throw _invalid('Request body must be a JSON object.');
    }
    return _build(json, fromJson, ProblemCode.bodyPointer);
  }

  /// The body decoded as a JSON array of objects, each built with
  /// [fromJson].
  Future<List<T>> list<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) async {
    final json = await _decoded();
    if (json is! List<Object?>) {
      throw _invalid('Request body must be a JSON array.');
    }
    return [
      for (final (index, item) in json.indexed)
        if (item is Map<String, Object?>)
          _build(item, fromJson, '${ProblemCode.bodyPointer}/$index')
        else
          throw _invalid(
            'Item $index of the request body must be a JSON object.',
            pointer: '${ProblemCode.bodyPointer}/$index',
          ),
    ];
  }

  Future<Object?> _decoded() =>
      _json ??= bytes().then((data) => RequestBody.bytes(data).json());

  T _build<T extends Object>(
    Map<String, Object?> json,
    T Function(Map<String, Object?> json) fromJson,
    String pointer,
  ) {
    // fromJson is user code and signals a missing or mistyped field with a
    // FormatException or with the TypeError of a failed cast (an Error the
    // language throws for user data); both are the client's fault and become
    // a 400. Any other failure is a bug and propagates.
    try {
      return fromJson(json);
    } on FormatException catch (error) {
      throw _invalid(
        'Invalid request body: ${error.message}',
        pointer: pointer,
      );
    } on TypeError {
      throw _invalid(
        'Invalid request body: a field is missing or has the wrong type.',
        pointer: pointer,
      );
    }
  }

  Future<Uint8List> _read() async {
    final limit = _maxBytes;
    if (limit == null) return _request.body.bytes();
    final declared = int.tryParse(_request.headers['content-length'] ?? '');
    if (declared != null && declared > limit) throw _tooLarge(limit);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _request.body.stream) {
      builder.add(chunk);
      if (builder.length > limit) throw _tooLarge(limit);
    }
    return builder.takeBytes();
  }

  static PayloadTooLargeException _tooLarge(int limit) =>
      PayloadTooLargeException(
        message: 'Request body is larger than $limit bytes.',
        code: ProblemCode.bodyTooLarge,
      );

  static BadRequestException _invalid(String message, {String? pointer}) =>
      BadRequestException(
        message: message,
        code: ProblemCode.bodyInvalid,
        pointer: pointer ?? ProblemCode.bodyPointer,
      );
}
```

**`packages/grund_http/lib/src/ctx/http_ctx.dart`**

```dart
import 'dart:typed_data';

import 'package:grund/grund.dart';

import '../http/http_request.dart';
import '../http/response_head.dart';
import 'body_reader.dart';
import 'cookie_header.dart';
import 'param_location.dart';
import 'params.dart';

/// The context of one HTTP request: the request, the response being built,
/// typed readers for its parameters and body, and (through [CallContext]) the
/// call scope that resolves `Scoped` bindings and values hooks [set].
///
/// A new context is created for every request and closed when the response
/// is complete; nothing on it is shared between requests.
final class HttpCtx extends CallContext {
  /// Creates the context for [request], routed with [pathParameters].
  ///
  /// [maxBodyBytes] limits the body readers (`null`: no limit).
  HttpCtx({
    required this.request,
    required CallScope scope,
    required this.response,
    required Map<String, String> pathParameters,
    CancelSignal? cancel,
    int? maxBodyBytes,
  }) : path = Params(
         ParamLocation.path,
         (name) => [if (pathParameters[name] case final value?) value],
       ),
       query = Params(
         ParamLocation.query,
         (name) => request.uri.queryParametersAll[name] ?? const [],
       ),
       headers = Params(ParamLocation.header, request.headers.all),
       cookies = _cookies(request),
       _body = BodyReader(request, maxBodyBytes),
       super(scope, cancel: cancel);

  /// The request being served.
  final HttpRequest request;

  /// The status and headers the response will get; the handler may change
  /// them (`c.response.status = 201`).
  final ResponseHead response;

  /// Readers for the `:name` segments of the route path.
  final Params path;

  /// Readers for the query string.
  final Params query;

  /// Readers for the request headers.
  final Params headers;

  /// Readers for the cookies of the request.
  final Params cookies;

  final BodyReader _body;

  /// The body as one JSON object built with [fromJson].
  ///
  /// A body that is not UTF-8, not JSON, not an object, or that [fromJson]
  /// rejects (a `FormatException`, or a missing or mistyped field) is a 400
  /// with the code `body_invalid` and the pointer `/body`; a body over the
  /// limit is a 413 with the code `body_too_large`.
  Future<T> body<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) => _body.object(fromJson);

  /// The body as a JSON array of objects, each built with [fromJson]; errors
  /// as in [body], with the pointer `/body/<index>` for a bad item.
  Future<List<T>> bodyList<T extends Object>(
    T Function(Map<String, Object?> json) fromJson,
  ) => _body.list(fromJson);

  /// The raw body; a body over the limit is a 413.
  Future<Uint8List> bytes() => _body.bytes();

  static Params _cookies(HttpRequest request) {
    final cookies = CookieHeader.parse(request.headers.all('cookie'));
    return Params(ParamLocation.cookie, (name) => cookies[name] ?? const []);
  }
}
```

**`packages/grund_http/lib/grund_http.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/ctx/http_ctx.dart';
export 'src/ctx/param_location.dart';
export 'src/ctx/params.dart';
export 'src/http/connection_info.dart';
export 'src/http/error_log.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/print_error_log.dart';
export 'src/http/problem.dart';
export 'src/http/problem_code.dart';
export 'src/http/problem_error.dart';
export 'src/http/problem_responder.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
```

- [ ] **Крок 4: запустити — зелено.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart analyze && dart test 2>&1 | tail -3
```

Очікувано: `No issues found!` і `All tests passed!` (усього тестів у пакеті: **112**).

- [ ] **Крок 5: самоперевірка.** `wc -l` кожного зміненого файла (lib ≤ 300, тест ≤ 500), найдовший метод ≤ 40, `dart format packages example` змінює 0 файлів.

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
wc -l packages/grund_http/lib/src/*/*.dart | sort -n | tail -3
dart format packages/grund_http
```

- [ ] **Крок 6: коміт.**

```bash
cd ~/projects/grund
git add packages/grund_http
git commit -m "feat(http): typed parameter readers and HttpCtx"
```

### Задача 9: `HttpHook`, `HookRef`, `HookChain`, `Middleware`

**Мета.** `HttpHook`, `HookRef` (`.type()`/`.instance()`), `HookChain` (before зовнішній→внутрішній, handler, after у зворотному порядку; `onError` у зворотному порядку, перший не-null відповідає) і `Middleware`.

RF-1 покрито тут (юніт) і в задачі 10 (через диспетчер).

**Files** (усі шляхи відносно `packages/grund_http/`):

- Modify/Create `lib/src/hook/http_hook.dart`
- Modify/Create `lib/src/hook/hook_ref.dart`
- Modify/Create `lib/src/hook/hook_chain.dart`
- Modify/Create `lib/src/hook/middleware.dart`
- Modify/Create `lib/src/hook/middleware_chain.dart`
- Modify `lib/grund_http.dart`
- Test `test/helpers/log_hook.dart`
- Test `test/hook/hook_chain_test.dart`
- Test `test/hook/hook_ref_test.dart`
- Test `test/hook/middleware_chain_test.dart`

Після задачі існують у `packages/grund_http/lib/src/`: `adapter/adapter_lifecycle.dart`, `adapter/error_logger.dart`, `adapter/http_adapter.dart`, `adapter/in_flight_requests.dart`, `ctx/body_reader.dart`, `ctx/cookie_header.dart`, `ctx/http_ctx.dart`, `ctx/param_constraints.dart`, `ctx/param_location.dart`, `ctx/params.dart`, `hook/hook_chain.dart`, `hook/hook_ref.dart`, `hook/http_hook.dart`, `hook/middleware.dart`, `hook/middleware_chain.dart`, `http/connection_info.dart`, `http/error_log.dart`, `http/header_map.dart`, `http/http_exception.dart`, `http/http_request.dart`, `http/http_response.dart`, `http/print_error_log.dart`, `http/problem.dart`, `http/problem_code.dart`, `http/problem_error.dart`, `http/problem_responder.dart`, `http/request_body.dart`, `http/response_body.dart`, `http/response_head.dart`, `http/status_code.dart`, `routing/pattern_segment.dart`, `routing/route_match.dart`, `routing/route_pattern.dart`, `routing/router.dart`, `routing/routing_error.dart`, `serialize/response_serializer.dart`, `serialize/serialization_error.dart`, `serialize/serializer_registry.dart`, `testing/test_response.dart`.

**Interfaces.**

- Consumes: `HttpCtx` (8), `HttpResponse`, `HttpException` (7); `Injector` (ядро).
- Produces: `HttpHook`, `HookRef<T>.type()/.instance()`, `HookChain`, `Middleware`, `Next`.

Рішення, що фіксує задача:

- `HookChain` не знає про скоупи: приймає вже розв'язані хуки; `HookChain.resolve(refs, injector)` розв'язує `HookRef`.
- `after` викликається лише після успішного handler; виняток у `before` пропускає handler і всі `after`.
- `Next` без аргументів: middleware не може підмінити запит (відхилення, див. нижче).

**Крок 1: падаючі тести.** Створити такі тести та допоміжні файли (цілком):

**`packages/grund_http/test/helpers/log_hook.dart`**

```dart
import 'dart:async';

import 'package:grund_http/grund_http.dart';

/// A hook that writes what it sees to [log] and fails where it is told to.
final class LogHook extends HttpHook {
  LogHook(
    this.name,
    this.log, {
    this.failBefore,
    this.failAfter,
    this.answers,
    this.failOnError,
  });

  final String name;
  final List<String> log;

  /// Thrown by `before` when set.
  final Object? failBefore;

  /// Thrown by `after` when set.
  final Object? failAfter;

  /// Returned by `onError` when set.
  final HttpResponse? answers;

  /// Thrown by `onError` when set.
  final Object? failOnError;

  @override
  FutureOr<void> before(HttpCtx c) {
    log.add('before $name');
    if (failBefore case final error?) throw error;
  }

  @override
  FutureOr<void> after(HttpCtx c, Object? result) {
    log.add('after $name $result');
    if (failAfter case final error?) throw error;
  }

  @override
  FutureOr<HttpResponse?> onError(HttpCtx c, Object error, StackTrace stack) {
    log.add('onError $name ${error.runtimeType}');
    if (failOnError case final failure?) throw failure;
    return answers;
  }
}
```

**`packages/grund_http/test/hook/hook_chain_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/ctx_factory.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/log_hook.dart';

void main() {
  late CtxFactory contexts;
  late HttpCtx c;
  final log = <String>[];

  setUpAll(() async => contexts = await CtxFactory.start());
  tearDownAll(() => contexts.close());
  setUp(() {
    log.clear();
    c = contexts(requestFor('GET', '/'));
  });

  Future<Object?> handler(HttpCtx _) async {
    log.add('handler');
    return 'result';
  }

  HookChain chain(List<LogHook> hooks) => HookChain(hooks);

  group('HookChain on success', () {
    test('before runs outer to inner, after inner to outer', () async {
      final result = await chain([
        LogHook('global', log),
        LogHook('api', log),
        LogHook('route', log),
      ]).run(c, handler);

      expect(result, 'result');
      expect(log, [
        'before global',
        'before api',
        'before route',
        'handler',
        'after route result',
        'after api result',
        'after global result',
      ]);
    });

    test('an empty chain only runs the handler', () async {
      expect(await const HookChain([]).run(c, handler), 'result');
      expect(log, ['handler']);
    });

    test('a hook awaits its own async before', () async {
      final slow = _SlowHook(log);

      await HookChain([slow, LogHook('after', log)]).run(c, handler);

      expect(log.indexOf('slow done'), lessThan(log.indexOf('before after')));
    });
  });

  group('HookChain failures (RF-1)', () {
    test('a throwing before stops the chain, no after runs at all', () async {
      final failure = StateError('no');

      await expectLater(
        chain([
          LogHook('one', log),
          LogHook('two', log, failBefore: failure),
          LogHook('three', log),
        ]).run(c, handler),
        throwsA(same(failure)),
      );

      expect(log.where((e) => e.startsWith('after')), isEmpty);
      expect(log, isNot(contains('handler')));
      expect(log, isNot(contains('before three')));
    });

    test('onError is offered in reverse order to every hook', () async {
      await expectLater(
        chain([
          LogHook('one', log),
          LogHook('two', log, failBefore: StateError('no')),
          LogHook('three', log),
        ]).run(c, handler),
        throwsStateError,
      );

      expect(log.where((e) => e.startsWith('onError')), [
        'onError three StateError',
        'onError two StateError',
        'onError one StateError',
      ]);
    });

    test(
      'the first non-null onError answers, the rest are not asked',
      () async {
        final response = HttpResponse.text('handled', status: 418);

        final result = await chain([
          LogHook('outer', log, answers: HttpResponse.text('late')),
          LogHook('inner', log, answers: response),
        ]).run(c, (_) => throw const ForbiddenException());

        expect(result, same(response));
        expect(log, [
          'before outer',
          'before inner',
          'onError inner ForbiddenException',
        ]);
      },
    );

    test('a failing handler skips after and reaches onError', () async {
      await expectLater(
        chain([LogHook('one', log)]).run(c, (_) => throw StateError('x')),
        throwsStateError,
      );

      expect(log, ['before one', 'onError one StateError']);
    });

    test(
      'a failing after is offered to onError, with no later after',
      () async {
        final response = HttpResponse.text('recovered');

        final result = await chain([
          LogHook('outer', log, answers: response),
          LogHook('inner', log, failAfter: StateError('late')),
        ]).run(c, handler);

        expect(result, same(response));
        expect(log, contains('onError inner StateError'));
        expect(log, isNot(contains('after outer result')));
      },
    );

    test('an error thrown by onError is what the next hook sees', () async {
      final response = HttpResponse.text('final');

      final result = await chain([
        LogHook('outer', log, answers: response),
        LogHook('inner', log, failOnError: const NotFoundException()),
      ]).run(c, (_) => throw StateError('first'));

      expect(result, same(response));
      expect(log, [
        'before outer',
        'before inner',
        'onError inner StateError',
        'onError outer NotFoundException',
      ]);
    });

    test(
      'without an answer the last error is rethrown with its trace',
      () async {
        final trace = StackTrace.fromString('original trace');

        Object? caught;
        StackTrace? caughtTrace;
        try {
          await chain([
            LogHook('one', log),
          ]).run(c, (_) => Error.throwWithStackTrace(StateError('x'), trace));
        } on StateError catch (error, stackTrace) {
          caught = error;
          caughtTrace = stackTrace;
        }

        expect(caught, isA<StateError>());
        expect(caughtTrace.toString(), 'original trace');
      },
    );
  });
}

final class _SlowHook extends HttpHook {
  _SlowHook(this.log);

  final List<String> log;

  @override
  Future<void> before(HttpCtx c) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    log.add('slow done');
  }
}
```

**`packages/grund_http/test/hook/hook_ref_test.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

final class KeyHook extends HttpHook {
  const KeyHook([this.key = 'default']);

  final String key;
}

final class HooksModule extends Module {
  const HooksModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<KeyHook>((i) => const KeyHook('from graph'), dependsOn: const []),
  ];
}

final class BareModule extends Module {
  const BareModule();
}

void main() {
  group('HookRef', () {
    test('type() resolves the hook from the injector', () async {
      final app = await TestApp.start(root: const HooksModule());
      addTearDown(app.close);

      final hook = const HookRef<KeyHook>.type().resolve(app.injector);

      expect(hook.key, 'from graph');
    });

    test('instance() is the value itself, no injector needed', () async {
      final app = await TestApp.start(root: const BareModule());
      addTearDown(app.close);
      const given = KeyHook('given');

      expect(
        const HookRef<KeyHook>.instance(given).resolve(app.injector),
        same(given),
      );
    });

    test(
      'type() of a hook nobody provides is a MissingProviderError',
      () async {
        final app = await TestApp.start(root: const BareModule());
        addTearDown(app.close);

        expect(
          () => const HookRef<KeyHook>.type().resolve(app.injector),
          throwsA(isA<MissingProviderError>()),
        );
      },
    );

    test('resolve of a list keeps the order', () async {
      final app = await TestApp.start(root: const HooksModule());
      addTearDown(app.close);

      final chain = HookChain.resolve(const [
        HookRef<KeyHook>.instance(KeyHook('a')),
        HookRef<KeyHook>.type(),
      ], app.injector);

      expect(chain.hooks.map((h) => (h as KeyHook).key), ['a', 'from graph']);
    });
  });
}
```

**`packages/grund_http/test/hook/middleware_chain_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/hook/middleware_chain.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Tag implements Middleware {
  Tag(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    log.add('in $name');
    final response = await next();
    log.add('out $name');
    return response.mergeHeaders(HeaderMap.of({'x-$name': 'yes'}));
  }
}

final class Stop implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async =>
      HttpResponse.text('stopped', status: 429);
}

void main() {
  final log = <String>[];

  setUp(log.clear);

  Future<HttpResponse> terminal() async {
    log.add('terminal');
    return HttpResponse.text('ok');
  }

  group('MiddlewareChain', () {
    test(
      'runs the first middleware outermost and wraps the response',
      () async {
        final response = await MiddlewareChain.run(
          [Tag('a', log), Tag('b', log)],
          requestFor('GET', '/'),
          terminal,
        );

        expect(log, ['in a', 'in b', 'terminal', 'out b', 'out a']);
        expect(response.headers['x-a'], 'yes');
        expect(response.headers['x-b'], 'yes');
      },
    );

    test('a middleware that does not call next short-circuits', () async {
      final response = await MiddlewareChain.run(
        [Stop(), Tag('a', log)],
        requestFor('GET', '/'),
        terminal,
      );

      expect(response.status, 429);
      expect(log, isEmpty);
    });

    test('no middleware calls the terminal directly', () async {
      final response = await MiddlewareChain.run(
        const [],
        requestFor('GET', '/'),
        terminal,
      );

      expect(response.status, 200);
      expect(log, ['terminal']);
    });
  });
}
```

**Крок 2: запустити — очікується збій компіляції** (типів ще немає).

- [ ] Виконати:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart test 2>&1 | tail -15
```

Очікувано: `Error: ... isn't defined` / `Failed to load`.

**Крок 3: реалізація.** Створити або замінити цілком:

**`packages/grund_http/lib/src/hook/http_hook.dart`**

```dart
import 'dart:async';

import '../ctx/http_ctx.dart';
import '../http/http_response.dart';

/// Code that runs around a route handler: authentication, authorization,
/// validation, auditing, error translation.
///
/// One hook replaces the guards, interceptors, pipes and exception filters of
/// other frameworks. All three methods are optional.
///
/// - [before] runs before the handler. Throw an `HttpException` to refuse the
///   request; hand a value to the handler with `c.set<T>(value)`.
/// - [after] runs after the handler returned, with its [result].
/// - [onError] runs when anything in the chain failed and may answer instead.
///
/// A hook is referenced by a `HookRef`: by type (resolved from the module
/// graph, so it may depend on services) or as a constant instance (when it is
/// parameterized, `RolesHook(Role.editor)`; it reads services with `c<T>()`).
abstract class HttpHook {
  /// Creates the hook; subclasses with only final fields can be `const`.
  const HttpHook();

  /// Runs before the handler; a thrown error ends the chain.
  FutureOr<void> before(HttpCtx c) {}

  /// Runs after the handler succeeded, with the value it returned.
  FutureOr<void> after(HttpCtx c, Object? result) {}

  /// Offered the [error] of the chain; a non-null response replaces it.
  ///
  /// Every hook of the chain is asked, innermost first, also one whose
  /// [before] did not run because an earlier hook refused the request: do
  /// not rely on state that [before] sets up.
  FutureOr<HttpResponse?> onError(HttpCtx c, Object error, StackTrace stack) =>
      null;
}
```

**`packages/grund_http/lib/src/hook/hook_ref.dart`**

```dart
import 'package:grund/grund.dart';

import 'http_hook.dart';

/// A reference to a hook, as listed in `HttpModule(use:)`, `HttpApi.use` and
/// `Route.use`.
///
/// ```dart
/// const HookRef<ApiKeyHook>.type()                      // from the graph
/// const HookRef<RolesHook>.instance(RolesHook(Role.editor)) // a constant
/// ```
///
/// The hook type is a type argument because the graph is resolved by type
/// and a `Type` value cannot be turned into an instance without mirrors.
final class HookRef<T extends HttpHook> {
  /// Refers to the hook of type [T] that the module graph provides.
  const HookRef.type() : _instance = null;

  /// Refers to the constant [hook].
  const HookRef.instance(T hook) : _instance = hook;

  final T? _instance;

  /// The hook type, for messages.
  Type get hookType => T;

  /// The hook: the given instance, or [T] resolved from [injector] (a call
  /// scope, so `Scoped` and `Transient` hooks work).
  T resolve(Injector injector) => _instance ?? injector<T>();
}
```

**`packages/grund_http/lib/src/hook/hook_chain.dart`**

```dart
import 'dart:async';

import 'package:grund/grund.dart';

import '../ctx/http_ctx.dart';
import '../http/http_response.dart';
import 'hook_ref.dart';
import 'http_hook.dart';

/// The hooks that wrap one request, outermost first: the global ones, then
/// those of the API, then those of the route.
///
/// [before] hooks run outer to inner, [after] and [onError] inner to outer.
/// A failure in any [before] ends the chain: no later [before], no handler
/// and no [after] runs; the error goes to the [onError] of the hooks.
final class HookChain {
  /// Creates the chain over resolved [hooks], outermost first.
  const HookChain(this.hooks);

  /// Resolves [refs] (outermost first) through [injector].
  ///
  /// Throws `MissingProviderError` for a hook type nobody provides.
  factory HookChain.resolve(
    Iterable<HookRef<HttpHook>> refs,
    Injector injector,
  ) => HookChain([for (final ref in refs) ref.resolve(injector)]);

  /// The hooks, outermost first.
  final List<HttpHook> hooks;

  /// Runs the [before] hooks, [handler] and the [after] hooks, and returns
  /// the handler's result.
  ///
  /// When anything throws, the [onError] hooks are asked in reverse order;
  /// the first non-null response is returned instead of the result. An error
  /// that an `onError` throws is what the next hook is offered. When nobody
  /// answers, the last error is rethrown with its stack trace.
  Future<Object?> run(
    HttpCtx c,
    FutureOr<Object?> Function(HttpCtx c) handler,
  ) async {
    // Hook chain boundary: hooks and the handler are user code; every
    // failure is offered to onError and, unanswered, rethrown unchanged.
    try {
      for (final hook in hooks) {
        await hook.before(c);
      }
      final result = await handler(c);
      for (final hook in hooks.reversed) {
        await hook.after(c, result);
      }
      return result;
    } on Object catch (error, stackTrace) {
      return _recover(c, error, stackTrace);
    }
  }

  Future<HttpResponse> _recover(
    HttpCtx c,
    Object error,
    StackTrace stackTrace,
  ) async {
    var failure = (error, stackTrace);
    for (final hook in hooks.reversed) {
      // Hook chain boundary: a throwing onError replaces the error the
      // remaining hooks are offered.
      try {
        final response = await hook.onError(c, failure.$1, failure.$2);
        if (response != null) return response;
      } on Object catch (thrown, thrownTrace) {
        failure = (thrown, thrownTrace);
      }
    }
    Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}
```

**`packages/grund_http/lib/src/hook/middleware.dart`**

```dart
import '../http/http_request.dart';
import '../http/http_response.dart';

/// Continues with the next middleware, or the routing when there is none.
typedef Next = Future<HttpResponse> Function();

/// Code around the whole request, before routing: CORS, compression, request
/// ids, rate limits.
///
/// A middleware either answers itself or returns what `next()` produced,
/// possibly changed. It sees every request, also those that match no route.
/// Unlike an `HttpHook` it knows nothing about the route or the call scope.
abstract interface class Middleware {
  /// Handles [request]; call [next] to continue.
  Future<HttpResponse> handle(HttpRequest request, Next next);
}
```

**`packages/grund_http/lib/src/hook/middleware_chain.dart`**

```dart
import '../http/http_request.dart';
import '../http/http_response.dart';
import 'middleware.dart';

/// Runs a list of [Middleware] around a terminal handler.
abstract final class MiddlewareChain {
  /// Calls the first of [middleware] with a `next` that calls the second and
  /// so on; the last `next` calls [terminal].
  static Future<HttpResponse> run(
    List<Middleware> middleware,
    HttpRequest request,
    Future<HttpResponse> Function() terminal,
  ) => _step(middleware, 0, request, terminal);

  static Future<HttpResponse> _step(
    List<Middleware> middleware,
    int index,
    HttpRequest request,
    Future<HttpResponse> Function() terminal,
  ) {
    if (index == middleware.length) return terminal();
    return middleware[index].handle(
      request,
      () => _step(middleware, index + 1, request, terminal),
    );
  }
}
```

**`packages/grund_http/lib/grund_http.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/ctx/http_ctx.dart';
export 'src/ctx/param_location.dart';
export 'src/ctx/params.dart';
export 'src/http/connection_info.dart';
export 'src/http/error_log.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/print_error_log.dart';
export 'src/http/problem.dart';
export 'src/http/problem_code.dart';
export 'src/http/problem_error.dart';
export 'src/http/problem_responder.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/hook/hook_chain.dart';
export 'src/hook/hook_ref.dart';
export 'src/hook/http_hook.dart';
export 'src/hook/middleware.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
```

- [ ] **Крок 4: запустити — зелено.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart analyze && dart test 2>&1 | tail -3
```

Очікувано: `No issues found!` і `All tests passed!` (усього тестів у пакеті: **129**).

- [ ] **Крок 5: самоперевірка.** `wc -l` кожного зміненого файла (lib ≤ 300, тест ≤ 500), найдовший метод ≤ 40, `dart format packages example` змінює 0 файлів.

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
wc -l packages/grund_http/lib/src/*/*.dart | sort -n | tail -3
dart format packages/grund_http
```

- [ ] **Крок 6: коміт.**

```bash
cd ~/projects/grund
git add packages/grund_http
git commit -m "feat(http): HttpHook, HookRef, HookChain and Middleware"
```

### Задача 10: `HttpApi`, `Route`, таблиця роутів, `RequestDispatcher`, `ResponseCodec`

**Мета.** `Route`, `HttpApi`, таблиця роутів із конфліктами між API (`DuplicateRouteError`), `RouteExecutor` (call-скоуп на запит, хуки, статус, серіалізація), `RequestDispatcher` (404/405/400 як problem), `ResponseCodec` у серіалізаторі.

`Router` з v1.0 лишається без змін; конфлікти між різними `HttpApi` ловить спільний `Router`.

**Files** (усі шляхи відносно `packages/grund_http/`):

- Modify/Create `lib/src/api/route.dart`
- Modify/Create `lib/src/api/http_api.dart`
- Modify/Create `lib/src/serialize/response_codec.dart`
- Modify/Create `lib/src/serialize/response_serializer.dart`
- Modify/Create `lib/src/serialize/serialization_error.dart`
- Modify/Create `lib/src/serialize/serializer_registry.dart`
- Modify/Create `lib/src/server/route_entry.dart`
- Modify/Create `lib/src/server/route_table.dart`
- Modify/Create `lib/src/server/route_table_builder.dart`
- Modify/Create `lib/src/server/route_executor.dart`
- Modify/Create `lib/src/server/request_dispatcher.dart`
- Modify `lib/grund_http.dart`
- Test `test/helpers/probe_api.dart`
- Test `test/helpers/call_fixtures.dart`
- Test `test/helpers/dispatch_harness.dart`
- Test `test/server/route_table_builder_test.dart`
- Test `test/server/route_executor_test.dart`
- Test `test/server/request_dispatcher_test.dart`
- Test `test/serialize/response_serializer_test.dart`

Після задачі існують у `packages/grund_http/lib/src/`: `adapter/adapter_lifecycle.dart`, `adapter/error_logger.dart`, `adapter/http_adapter.dart`, `adapter/in_flight_requests.dart`, `api/http_api.dart`, `api/route.dart`, `ctx/body_reader.dart`, `ctx/cookie_header.dart`, `ctx/http_ctx.dart`, `ctx/param_constraints.dart`, `ctx/param_location.dart`, `ctx/params.dart`, `hook/hook_chain.dart`, `hook/hook_ref.dart`, `hook/http_hook.dart`, `hook/middleware.dart`, `hook/middleware_chain.dart`, `http/connection_info.dart`, `http/error_log.dart`, `http/header_map.dart`, `http/http_exception.dart`, `http/http_request.dart`, `http/http_response.dart`, `http/print_error_log.dart`, `http/problem.dart`, `http/problem_code.dart`, `http/problem_error.dart`, `http/problem_responder.dart`, `http/request_body.dart`, `http/response_body.dart`, `http/response_head.dart`, `http/status_code.dart`, `routing/pattern_segment.dart`, `routing/route_match.dart`, `routing/route_pattern.dart`, `routing/router.dart`, `routing/routing_error.dart`, `serialize/response_codec.dart`, `serialize/response_serializer.dart`, `serialize/serialization_error.dart`, `serialize/serializer_registry.dart`, `server/request_dispatcher.dart`, `server/route_entry.dart`, `server/route_executor.dart`, `server/route_table.dart`, `server/route_table_builder.dart`, `testing/test_response.dart`.

**Interfaces.**

- Consumes: `HookChain`/`HookRef` (9), `HttpCtx` (8), `ProblemResponder` (7), `Router` (1), `Injector.openCall` (ядро).
- Produces: `Route.get/post/put/patch/delete`, `HttpApi`, `ResponseCodec<T>`, `RouteTableBuilder.build(apis, globalHooks)`, `RequestDispatcher.dispatch(request, table, cancel)`.

Рішення, що фіксує задача:

- `HttpApi.routes` читається при кожній збірці таблиці, тож hot reload бачить змінені handler-и.
- 404 — `route_not_found`, 405 — `method_not_allowed` + `Allow`; битий percent-encoding — 400 `parameter_invalid`; `HEAD` без тіла.
- Хуки роуту розв'язуються в call-скоупі модуля API; після побудови таблиці всі розв'язуються пробно (fail-fast).
- Статус: `route.status` має пріоритет над `head.status`; call-скоуп закривається у `finally`; заголовки `head` додаються й до помилкових відповідей.

**Крок 1: падаючі тести.** Створити такі тести та допоміжні файли (цілком):

**`packages/grund_http/test/helpers/probe_api.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// An [HttpApi] whose routes a test writes inline.
final class ProbeApi extends HttpApi {
  ProbeApi(
    super.injector,
    this._routes, {
    this.apiPath = '',
    this.apiUse = const [],
  });

  /// A singleton binding of a probe API; [name] keeps several apart.
  static Binding<Object> binding(
    String name,
    List<Route> routes, {
    String path = '',
    List<HookRef<HttpHook>> use = const [],
    List<Key<Object>> dependsOn = const [],
  }) => Singleton<ProbeApi>(
    (i) => ProbeApi(i, routes, apiPath: path, apiUse: use),
    name: name,
    dependsOn: dependsOn,
  );

  final List<Route> _routes;
  final String apiPath;
  final List<HookRef<HttpHook>> apiUse;

  @override
  String get path => apiPath;

  @override
  List<HookRef<HttpHook>> get use => apiUse;

  @override
  List<Route> get routes => _routes;
}

/// A module that binds exactly [bindings].
final class ProbeModule extends Module {
  ProbeModule(this.bindings);

  @override
  final List<Binding<Object>> bindings;
}
```

**`packages/grund_http/test/helpers/call_fixtures.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Counts the lifecycle of [Tx] instances.
final class TxLog {
  /// Instances created.
  int created = 0;

  /// Instances disposed.
  int disposed = 0;
}

/// A call-scoped resource that is disposed after the request.
final class Tx implements Disposable {
  Tx(this._log, {this.failOnDispose = false}) {
    _log.created++;
  }

  final TxLog _log;
  final bool failOnDispose;

  @override
  void dispose() {
    _log.disposed++;
    if (failOnDispose) throw StateError('cannot close the transaction');
  }
}

/// What a hook hands to the handler with `c.set`.
final class CurrentUser {
  CurrentUser(this.name);

  final String name;
}

/// Sets [CurrentUser] from the `x-user` header.
final class UserHook extends HttpHook {
  const UserHook();

  @override
  void before(HttpCtx c) =>
      c.set<CurrentUser>(CurrentUser(c.headers.string('x-user')));
}

/// The bindings the call tests share.
List<Binding<Object>> callBindings({bool failOnDispose = false}) => [
  Singleton<TxLog>((i) => TxLog(), dependsOn: const []),
  Scoped<Tx>(
    (i) => Tx(i<TxLog>(), failOnDispose: failOnDispose),
    dependsOn: const [Key<TxLog>()],
  ),
  Singleton<UserHook>((i) => const UserHook(), dependsOn: const []),
];
```

**`packages/grund_http/test/helpers/dispatch_harness.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/serialize/response_serializer.dart';
import 'package:grund_http/src/server/request_dispatcher.dart';
import 'package:grund_http/src/server/route_executor.dart';
import 'package:grund_http/src/server/route_table.dart';
import 'package:grund_http/src/server/route_table_builder.dart';

import 'http_fixtures.dart';
import 'probe_api.dart';
import 'recording_error_log.dart';

/// A started graph with a route table and a dispatcher, without a server.
final class DispatchHarness {
  DispatchHarness._(this._app, this.table, this.dispatcher, this.log);

  /// Starts a module with [bindings] and serves the `HttpApi`s among them.
  static Future<DispatchHarness> start(
    List<Binding<Object>> bindings, {
    List<HookRef<HttpHook>> global = const [],
    int? maxBodyBytes,
    bool debug = false,
  }) async {
    final log = RecordingErrorLog();
    final app = await TestApp.start(root: ProbeModule(bindings));
    final RouteTable table;
    try {
      table = await RouteTableBuilder.build(
        app.app.container.all<HttpApi>(),
        global,
      );
    } on Object {
      // Test helper: do not leave the application open when the table fails.
      await app.close();
      rethrow;
    }
    final problems = ProblemResponder(debug: debug, log: log);
    final executor = RouteExecutor(
      serializer: ResponseSerializer(SerializerRegistry()),
      problems: problems,
      maxBodyBytes: maxBodyBytes,
    );
    return DispatchHarness._(
      app,
      table,
      RequestDispatcher(executor: executor, problems: problems),
      log,
    );
  }

  final TestApp _app;

  /// The routes of the graph.
  final RouteTable table;

  /// The dispatcher under test.
  final RequestDispatcher dispatcher;

  /// What the responder reported.
  final RecordingErrorLog log;

  /// Resolves a singleton of the graph.
  T call<T extends Object>() => _app.call<T>();

  /// Dispatches a request and returns the response.
  Future<HttpResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    String? body,
  }) => dispatcher.dispatch(
    requestFor(method, target, headers: headers, body: body),
    table,
    CancelSignal(),
  );

  /// Closes the application.
  Future<void> close() => _app.close();
}
```

**`packages/grund_http/test/server/route_table_builder_test.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/server/route_table_builder.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/probe_api.dart';

/// Starts a graph of [bindings] and builds its route table.
Future<List<String>> routesOf(
  List<Binding<Object>> bindings, {
  List<HookRef<HttpHook>> global = const [],
}) async {
  final app = await TestApp.start(root: ProbeModule(bindings));
  try {
    final table = await RouteTableBuilder.build(
      app.app.container.all<HttpApi>(),
      global,
    );
    return table.routes;
  } finally {
    await app.close();
  }
}

Route get(String path) => Route.get(path, (c) => null);

void main() {
  group('RouteTableBuilder', () {
    test('describes every route as METHOD /full/path, sorted', () async {
      final routes = await routesOf([
        ProbeApi.binding('users', [
          get('/:id'),
          Route.post('/', (c) => null),
        ], path: '/users'),
        ProbeApi.binding('root', [get('/health')]),
      ]);

      expect(routes, ['GET /health', 'GET /users/:id', 'POST /users']);
    });

    test('an API without routes contributes nothing', () async {
      expect(await routesOf([ProbeApi.binding('empty', [])]), isEmpty);
    });

    test('a duplicate in one API names both routes', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [
            Route.get('/x', (c) => 1, name: 'first'),
            Route.get('/x', (c) => 2, name: 'second'),
          ]),
        ]),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.method, 'method', 'GET')
              .having((e) => e.path, 'path', '/x')
              .having((e) => e.existing, 'existing', 'ProbeApi.first')
              .having((e) => e.duplicate, 'duplicate', 'ProbeApi.second'),
        ),
      );
    });

    test('a conflict between two APIs is found too (RF-4)', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [get('/:id')], path: '/users'),
          ProbeApi.binding('b', [get('/:userId')], path: '/users'),
        ]),
        throwsA(isA<DuplicateRouteError>()),
      );
    });

    test('the same path with another method is not a conflict', () async {
      final routes = await routesOf([
        ProbeApi.binding('a', [get('/x')]),
        ProbeApi.binding('b', [Route.put('/x', (c) => null)]),
      ]);

      expect(routes, ['GET /x', 'PUT /x']);
    });

    test('an invalid pattern is reported with its text', () async {
      await expectLater(
        routesOf([
          ProbeApi.binding('a', [get('/a/*/b')]),
        ]),
        throwsA(isA<InvalidRoutePatternError>()),
      );
    });
  });

  group('RouteTableBuilder hooks (RF-4)', () {
    test('a global hook type nobody provides is a MissingProviderError', () {
      expect(
        routesOf(
          [
            ProbeApi.binding('a', [get('/')]),
          ],
          global: const [HookRef<UserHook>.type()],
        ),
        throwsA(isA<MissingProviderError>()),
      );
    });

    test('an API and a route hook are checked too', () {
      expect(
        routesOf([
          ProbeApi.binding(
            'a',
            [get('/')],
            use: const [HookRef<UserHook>.type()],
          ),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
      expect(
        routesOf([
          ProbeApi.binding('a', [
            Route.get('/', (c) => null, use: const [HookRef<UserHook>.type()]),
          ]),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
    });

    test('provided hook types and instances pass', () async {
      final routes = await routesOf([
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [get('/')],
          use: const [
            HookRef<UserHook>.type(),
            HookRef<UserHook>.instance(UserHook()),
          ],
        ),
      ]);

      expect(routes, ['GET /']);
    });
  });
}
```

**`packages/grund_http/test/server/route_executor_test.dart`**

```dart
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/dispatch_harness.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/log_hook.dart';
import '../helpers/probe_api.dart';

void main() {
  final log = <String>[];

  setUp(log.clear);

  group('hook order', () {
    test(
      'global, API and route hooks wrap the handler in that order',
      () async {
        final harness = await DispatchHarness.start(
          [
            ProbeApi.binding(
              'a',
              [
                Route.get('/', (c) {
                  log.add('handler');
                  return 'ok';
                }, use: [HookRef.instance(LogHook('route', log))]),
              ],
              use: [HookRef.instance(LogHook('api', log))],
            ),
          ],
          global: [HookRef.instance(LogHook('global', log))],
        );
        addTearDown(harness.close);

        await harness.send('GET', '/');

        expect(log, [
          'before global',
          'before api',
          'before route',
          'handler',
          'after route ok',
          'after api ok',
          'after global ok',
        ]);
      },
    );
  });

  group('a failing hook (RF-1)', () {
    Future<DispatchHarness> chainOf(LogHook second, {LogHook? first}) =>
        DispatchHarness.start([
          ProbeApi.binding(
            'a',
            [
              Route.get('/', (c) {
                log.add('handler');
                return 'ok';
              }),
            ],
            use: [
              HookRef.instance(first ?? LogHook('one', log)),
              HookRef.instance(second),
              HookRef.instance(LogHook('three', log)),
            ],
          ),
        ]);

    test(
      'an unexpected error is a 500 without internals and no after',
      () async {
        final harness = await chainOf(
          LogHook('two', log, failBefore: StateError('secret detail')),
        );
        addTearDown(harness.close);

        final response = await harness.send('GET', '/');

        expect(response.status, 500);
        expect(await textOf(response), isNot(contains('secret detail')));
        expect(
          (await jsonOf(response) as Map)['detail'],
          'Internal server error',
        );
        expect(log.where((e) => e.startsWith('after')), isEmpty);
        expect(log, isNot(contains('handler')));
        expect(harness.log.errors.single, isA<StateError>());
      },
    );

    test('an HttpException keeps its own status and is not logged', () async {
      final harness = await chainOf(
        LogHook('two', log, failBefore: const ForbiddenException()),
      );
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 403);
      expect(harness.log.errors, isEmpty);
    });

    test('onError runs in reverse order; the first answer is sent', () async {
      final harness = await chainOf(
        LogHook('two', log, failBefore: StateError('x')),
        first: LogHook(
          'one',
          log,
          answers: HttpResponse.text('translated', status: 418),
        ),
      );
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 418);
      expect(await textOf(response), 'translated');
      expect(log.where((e) => e.startsWith('onError')), [
        'onError three StateError',
        'onError two StateError',
        'onError one StateError',
      ]);
      expect(harness.log.errors, isEmpty);
    });

    test('a hook can translate an error by throwing another', () async {
      final harness = await DispatchHarness.start([
        ProbeApi.binding(
          'a',
          [Route.get('/', (c) => throw ArgumentError('no user 7'))],
          use: [HookRef.instance(_TranslateHook())],
        ),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 404);
      expect((await jsonOf(response) as Map)['detail'], 'No such user');
    });

    test('headers set before the failure stay on the problem', () async {
      final harness = await DispatchHarness.start([
        ProbeApi.binding('a', [
          Route.get('/', (c) {
            c.response.headers.set('x-trace', '42');
            throw const NotFoundException();
          }),
        ]),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 404);
      expect(response.headers['x-trace'], '42');
    });

    test('a hook type that is not provided fails before serving', () async {
      await expectLater(
        DispatchHarness.start([
          ProbeApi.binding(
            'a',
            [Route.get('/', (c) => 1)],
            use: const [HookRef<UserHook>.type()],
          ),
        ]),
        throwsA(isA<MissingProviderError>()),
      );
    });
  });

  group('call scope', () {
    test('a hook hands a value to the handler with c.set', () async {
      final harness = await DispatchHarness.start([
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [Route.get('/', (c) => c<CurrentUser>().name)],
          use: const [HookRef<UserHook>.type()],
        ),
      ]);
      addTearDown(harness.close);

      final response = await harness.send(
        'GET',
        '/',
        headers: {'x-user': 'ann'},
      );

      expect(await textOf(response), 'ann');
    });

    test(
      'concurrent requests do not see each other c.set values (RF-2)',
      () async {
        final gate = Completer<void>();
        final harness = await DispatchHarness.start([
          ...callBindings(),
          ProbeApi.binding(
            'a',
            [
              Route.get('/', (c) async {
                await gate.future;
                return c<CurrentUser>().name;
              }),
            ],
            use: const [HookRef<UserHook>.type()],
          ),
        ]);
        addTearDown(harness.close);

        final ann = harness.send('GET', '/', headers: {'x-user': 'ann'});
        final bob = harness.send('GET', '/', headers: {'x-user': 'bob'});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        gate.complete();

        expect(await textOf(await bob), 'bob');
        expect(await textOf(await ann), 'ann');
      },
    );

    test(
      'a Scoped instance lives for one request and is disposed (RF-2)',
      () async {
        final harness = await DispatchHarness.start([
          ...callBindings(),
          ProbeApi.binding('a', [
            Route.get('/', (c) {
              expect(identical(c<Tx>(), c<Tx>()), isTrue);
              return 'ok';
            }),
          ]),
        ]);
        addTearDown(harness.close);

        await harness.send('GET', '/');
        await harness.send('GET', '/');

        expect(harness<TxLog>().created, 2);
        expect(harness<TxLog>().disposed, 2);
      },
    );

    test('it is disposed also when the handler throws (RF-2)', () async {
      final harness = await DispatchHarness.start([
        ...callBindings(),
        ProbeApi.binding('a', [
          Route.get('/', (c) {
            c<Tx>();
            throw StateError('after the transaction began');
          }),
        ]),
      ]);
      addTearDown(harness.close);

      final response = await harness.send('GET', '/');

      expect(response.status, 500);
      expect(harness<TxLog>().created, 1);
      expect(harness<TxLog>().disposed, 1);
    });

    test(
      'a failing dispose is reported, the response is kept (RF-2)',
      () async {
        final harness = await DispatchHarness.start([
          ...callBindings(failOnDispose: true),
          ProbeApi.binding('a', [
            Route.get('/', (c) {
              c<Tx>();
              return 'ok';
            }),
          ]),
        ]);
        addTearDown(harness.close);

        final response = await harness.send('GET', '/');

        expect(response.status, 200);
        expect(harness.log.errors.single, isA<ShutdownError>());
      },
    );

    test(
      'a Scoped hook type is created per request, and once to check',
      () async {
        final harness = await DispatchHarness.start([
          Singleton<TxLog>((i) => TxLog(), dependsOn: const []),
          Scoped<CountingHook>(
            (i) => CountingHook(i<TxLog>()),
            dependsOn: const [Key<TxLog>()],
          ),
          ProbeApi.binding(
            'a',
            [Route.get('/', (c) => 'ok')],
            use: const [HookRef<CountingHook>.type()],
          ),
        ]);
        addTearDown(harness.close);
        final afterCheck = harness<TxLog>().created;

        await harness.send('GET', '/');
        await harness.send('GET', '/');

        expect(afterCheck, 1);
        expect(harness<TxLog>().created, 3);
        expect(harness<TxLog>().disposed, 3);
      },
    );
  });
}

/// A hook that counts its own creation.
final class CountingHook extends HttpHook implements Disposable {
  CountingHook(this._log) {
    _log.created++;
  }

  final TxLog _log;

  @override
  void dispose() => _log.disposed++;
}

final class _TranslateHook extends HttpHook {
  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is ArgumentError) {
      throw const NotFoundException(message: 'No such user');
    }
    return null;
  }
}
```

**`packages/grund_http/test/server/request_dispatcher_test.dart`**

```dart
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/dispatch_harness.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_api.dart';

class Item {
  Map<String, Object?> toJson() => {'id': 1};
}

void main() {
  late DispatchHarness harness;

  setUp(() async {
    harness = await DispatchHarness.start([
      ProbeApi.binding('items', [
        Route.get('/', (c) => [Item()]),
        Route.get('/:id', (c) => {'id': c.path.string('id')}),
        Route.post('/', (c) => Item(), status: 201),
        Route.get('/files/*', (c) => c.path.string('*')),
        Route.get('/none', (c) => null),
        Route.get('/broken', (c) => throw StateError('db password is hunter2')),
        Route.get('/missing', (c) => throw const NotFoundException()),
      ], path: '/items'),
    ]);
  });
  tearDown(() => harness.close());

  group('RequestDispatcher routing', () {
    test('answers a matched route with its result as JSON', () async {
      final response = await harness.send('GET', '/items/7');

      expect(response.status, 200);
      expect(await jsonOf(response), {'id': '7'});
    });

    test('an unknown path is a 404 problem+json (RF-3)', () async {
      final response = await harness.send('GET', '/nothing/here');

      expect(response.status, 404);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Not Found',
        'status': 404,
        'detail': 'Cannot GET /nothing/here',
        'instance': '/nothing/here',
        'code': 'route_not_found',
      });
    });

    test('another method on a known path is a 405 with Allow (RF-3)', () async {
      final response = await harness.send('DELETE', '/items');

      expect(response.status, 405);
      expect(response.headers['allow'], 'GET, HEAD, POST');
      expect((await jsonOf(response) as Map)['code'], 'method_not_allowed');
    });

    test('HEAD is answered by the GET route', () async {
      final response = await harness.send('HEAD', '/items/7');

      expect(response.status, 200);
    });

    test('extra and trailing slashes do not change the match (RF-3)', () async {
      for (final target in ['/items/', '/items//', '/items///']) {
        final response = await harness.send('GET', target);
        expect(response.status, 200, reason: target);
      }
      expect(await jsonOf(await harness.send('GET', '/items//7/')), {
        'id': '7',
      });
    });

    test('percent-encoding is decoded per segment (RF-3)', () async {
      final spaced = await harness.send('GET', '/items/a%20b');
      final slash = await harness.send('GET', '/items/a%2Fb');

      expect(await jsonOf(spaced), {'id': 'a b'});
      expect(await jsonOf(slash), {'id': 'a/b'});
    });

    test('invalid percent-encoding is a 400, not a 500 (RF-3)', () async {
      final response = await harness.send('GET', '/items/%E0%A4%A');

      expect(response.status, 400);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(harness.log.errors, isEmpty);
    });

    test('a wildcard captures the rest of the path', () async {
      final response = await harness.send('GET', '/items/files/a/b/c.txt');

      expect(await textOf(response), 'a/b/c.txt');
    });
  });

  group('RequestDispatcher responses', () {
    test('null is 204 and the route status wins over the default', () async {
      final none = await harness.send('GET', '/items/none');
      final created = await harness.send('POST', '/items');

      expect(none.status, 204);
      expect(created.status, 201);
      expect(await jsonOf(created), {'id': 1});
    });

    test('an HttpException of the handler keeps its status', () async {
      final response = await harness.send('GET', '/items/missing');

      expect(response.status, 404);
      expect(harness.log.errors, isEmpty);
    });

    test('an unexpected error is a logged 500 without internals', () async {
      final response = await harness.send('GET', '/items/broken');

      expect(response.status, 500);
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Internal Server Error',
        'status': 500,
        'detail': 'Internal server error',
        'instance': '/items/broken',
      });
      expect(harness.log.errors, hasLength(1));
      expect(harness.log.errors.single, isA<StateError>());
    });

    test('a bad query value is a 400 with a pointer (RF-3)', () async {
      final api = await DispatchHarness.start([
        ProbeApi.binding('p', [
          Route.get('/', (c) => c.query.integer('page', min: 1)),
        ]),
      ]);
      addTearDown(api.close);

      final response = await api.send('GET', '/?page=abc');

      expect(response.status, 400);
      expect(((await jsonOf(response) as Map)['errors'] as List).single, {
        'detail':
            'Invalid query parameter "page": expected an integer, '
            'got "abc".',
        'pointer': '/query/page',
        'code': 'parameter_invalid',
      });
    });
  });
}
```

**`packages/grund_http/test/serialize/response_serializer_test.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/serialize/response_serializer.dart';
import 'package:test/test.dart';

final class User {
  User(this.name);
  final String name;
  Map<String, Object?> toJson() => {'name': name};
}

final class Money {
  Money(this.cents);
  final int cents;
}

final class Opaque {}

final class Broken {
  Object? toJson() => throw StateError('no json');
}

final class Wrapper {
  Object? toJson() => {'inner': Opaque()};
}

Future<String> text(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

HttpResponse serialize(
  Object? result, {
  ResponseHead? head,
  SerializerRegistry? registry,
}) => ResponseSerializer(
  registry ?? SerializerRegistry(),
).serialize(result, head ?? ResponseHead());

Object? _opaqueJson(Opaque _) => 'opaque';

void main() {
  group('ResponseSerializer', () {
    test('null is 204 without a body', () async {
      final response = serialize(null);

      expect(response.status, 204);
      expect(response.headers['content-type'], isNull);
      expect(await response.body.readAll(), isEmpty);
    });

    test('String is text/plain', () async {
      final response = serialize('hi');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await text(response), 'hi');
    });

    test('Uint8List and byte streams are octet-stream', () async {
      final bytes = serialize(Uint8List.fromList([1, 2]));
      final streamed = serialize(Stream.value(const [3, 4]));

      expect(bytes.headers['content-type'], 'application/octet-stream');
      expect(await bytes.body.readAll(), [1, 2]);
      expect(streamed.body, isA<StreamBody>());
      expect(await streamed.body.readAll(), [3, 4]);
    });

    test('maps, lists, scalars and toJson objects are JSON', () async {
      final response = serialize({
        'users': [User('ann')],
        'n': 1,
        'ok': true,
      });

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(
        await text(response),
        '{"users":[{"name":"ann"}],"n":1,"ok":true}',
      );
      expect(await text(serialize(42)), '42');
    });

    // A list of ints is data the client asked for as JSON, not raw bytes.
    test('List<int> is a JSON array, not a byte body', () async {
      final response = serialize(<int>[1, 2, 3]);

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await text(response), '[1,2,3]');
    });

    test('HttpResponse passes through and keeps its own headers', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('x-trace', '7')
        ..headers.set('content-type', 'text/html');
      final original = HttpResponse.text('x', status: 202);

      final response = serialize(original, head: head);

      expect(response.status, 202);
      expect(response.headers['x-trace'], '7');
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
    });

    test('head status and headers override the defaults', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('content-type', 'text/html; charset=utf-8')
        ..headers.set('location', '/users/1');

      final response = serialize('<b>made</b>', head: head);

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.headers['location'], '/users/1');
    });

    test('registered serializers handle types without toJson', () async {
      final registry = SerializerRegistry()
        ..register<Money>((m) => {'cents': m.cents});

      final response = serialize({
        'price': Money(150),
        'history': [Money(1)],
      }, registry: registry);

      expect(
        await text(response),
        '{"price":{"cents":150},"history":[{"cents":1}]}',
      );
    });

    test('a ResponseCodec registers itself under its type', () async {
      final registry = SerializerRegistry();
      ResponseCodec<Money>((m) => m.cents).registerIn(registry);
      // The module keeps codecs as ResponseCodec<Object>; the type survives.
      for (final codec in const <ResponseCodec<Object>>[
        ResponseCodec<Opaque>(_opaqueJson),
      ]) {
        codec.registerIn(registry);
      }

      final response = serialize([Money(5), Opaque()], registry: registry);

      expect(await text(response), '[5,"opaque"]');
    });

    test('a throwing toJson is a SerializationError with its cause', () {
      expect(
        () => serialize(Broken()),
        throwsA(
          isA<SerializationError>()
              .having((e) => e.valueType, 'type', Broken)
              .having((e) => e.cause, 'cause', isA<StateError>())
              .having(
                (e) => e.message,
                'message',
                allOf(contains('no json'), isNot(contains('Give it a'))),
              ),
        ),
      );
    });

    test('a value nested in a toJson result is not converted', () {
      final registry = SerializerRegistry()
        ..register<Opaque>((_) => 'converted');

      expect(
        () => serialize(Wrapper(), registry: registry),
        throwsA(
          isA<SerializationError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("Instance of 'Opaque'"),
              contains('do not apply to values inside'),
            ),
          ),
        ),
      );
    });

    test('an unencodable value is a SerializationError', () {
      expect(
        () => serialize({'x': Opaque()}),
        throwsA(
          isA<SerializationError>()
              .having((e) => e.valueType, 'type', Opaque)
              .having(
                (e) => e.message,
                'message',
                contains('ResponseCodec<Opaque>'),
              ),
        ),
      );
    });
  });
}
```

**Крок 2: запустити — очікується збій компіляції** (типів ще немає).

- [ ] Виконати:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart test 2>&1 | tail -15
```

Очікувано: `Error: ... isn't defined` / `Failed to load`.

**Крок 3: реалізація.** Створити або замінити цілком:

**`packages/grund_http/lib/src/api/route.dart`**

```dart
import 'dart:async';

import '../ctx/http_ctx.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';

/// Handles one request: reads what it needs from [c] and returns the result.
///
/// The result is turned into the response: `null` is 204, an `HttpResponse`
/// is sent as it is, a `Stream<List<int>>` is streamed, `String` and
/// `Uint8List` are sent as text and bytes, anything else as JSON (through
/// `toJson()` or a registered `ResponseCodec`).
typedef RouteHandler = FutureOr<Object?> Function(HttpCtx c);

/// One route of an `HttpApi`: a method, a path below the API's path, the
/// [handler] and the hooks that wrap it.
///
/// ```dart
/// Route.get('/:id', (c) => users.find(c.path.integer('id')))
/// Route.post('/', (c) async => users.create(await c.body(NewUser.fromJson)),
///     status: 201, use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))])
/// ```
final class Route {
  Route._(
    this.method,
    this.path,
    this.handler, {
    this.status,
    this.use = const [],
    String? name,
  }) : name = name ?? '$method $path';

  /// A `GET` route; it also answers `HEAD`.
  Route.get(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('GET', path, handler, status: status, use: use, name: name);

  /// A `POST` route.
  Route.post(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('POST', path, handler, status: status, use: use, name: name);

  /// A `PUT` route.
  Route.put(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('PUT', path, handler, status: status, use: use, name: name);

  /// A `PATCH` route.
  Route.patch(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('PATCH', path, handler, status: status, use: use, name: name);

  /// A `DELETE` route.
  Route.delete(
    String path,
    RouteHandler handler, {
    int? status,
    List<HookRef<HttpHook>> use = const [],
    String? name,
  }) : this._('DELETE', path, handler, status: status, use: use, name: name);

  /// The upper-case HTTP method.
  final String method;

  /// The path below `HttpApi.path`: `/`, `/:id`, `/files/*`.
  final String path;

  /// Produces the result.
  final RouteHandler handler;

  /// The response status; it wins over `c.response.status` and the default.
  final int? status;

  /// Hooks that wrap only this route, after those of the API.
  final List<HookRef<HttpHook>> use;

  /// Names the route in errors; `'GET /:id'` unless given.
  final String name;
}
```

**`packages/grund_http/lib/src/api/http_api.dart`**

```dart
import 'package:grund/grund.dart';

import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import 'route.dart';

/// A group of routes under one path prefix.
///
/// Bind an `HttpApi` subclass as a singleton in a module; every `HttpApi` of
/// the application is served by the `HttpServer`. The explicit form and the
/// code the generator emits for an annotated API class are the same thing:
///
/// ```dart
/// final class UsersApi extends HttpApi {
///   UsersApi(super.injector, this._users);
///   final UsersService _users;
///
///   @override String get path => '/users';
///   @override List<Route> get routes => [
///     Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
///   ];
/// }
/// ```
abstract base class HttpApi {
  /// Creates the API over the [injector] of the module that declares it.
  HttpApi(this.injector);

  /// The injector of the declaring module: hooks are resolved from it and a
  /// call scope is opened on it for every request, so handlers and hooks see
  /// what that module sees.
  final Injector injector;

  /// The prefix of every route; empty for none.
  String get path => '';

  /// Hooks that wrap every route of the API, after the global ones.
  List<HookRef<HttpHook>> get use => const [];

  /// The routes.
  ///
  /// Return a new list on every call: the server reads it again after a hot
  /// reload and so sees the edited handlers.
  List<Route> get routes;
}
```

**`packages/grund_http/lib/src/serialize/response_codec.dart`**

```dart
import 'serializer_registry.dart';

/// Turns values of a type without `toJson()` into JSON for the response.
///
/// ```dart
/// HttpModule(codecs: [
///   ResponseCodec<Money>((m) => {'amount': m.cents, 'currency': m.code}),
/// ])
/// ```
///
/// Write the type argument: the codec applies to values of exactly that
/// type (and its subtypes).
final class ResponseCodec<T extends Object> {
  /// Creates the codec from [toJson].
  const ResponseCodec(this.toJson);

  /// Converts a value to a JSON value (`Map`, `List`, `String`, `num`,
  /// `bool` or `null`).
  final Object? Function(T value) toJson;

  /// Adds this codec to [registry] under its type [T].
  void registerIn(SerializerRegistry registry) => registry.register<T>(toJson);
}
```

**`packages/grund_http/lib/src/serialize/response_serializer.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import '../http/header_map.dart';
import '../http/http_response.dart';
import '../http/response_body.dart';
import '../http/response_head.dart';
import '../http/status_code.dart';
import 'serialization_error.dart';
import 'serializer_registry.dart';

/// Turns a handler (or filter) result into an [HttpResponse].
///
/// | Result | Response |
/// | --- | --- |
/// | [HttpResponse] | as is, plus head headers it does not set |
/// | `null` | 204, empty |
/// | [String] | `text/plain; charset=utf-8` |
/// | [Uint8List] | `application/octet-stream` |
/// | `Stream<List<int>>` | streamed `application/octet-stream` |
/// | anything else | JSON (`Map`, `List` (also `List<int>`), `num`, `bool`, objects with `toJson()`, registered types) |
///
/// The [ResponseHead] status replaces the default status (200, or 204 for
/// `null`), and its headers replace the defaults. A value JSON cannot encode
/// throws [SerializationError].
final class ResponseSerializer {
  /// Creates a serializer using [registry] for types without `toJson()`.
  const ResponseSerializer(this.registry);

  /// Converters for types without `toJson()`.
  final SerializerRegistry registry;

  /// Serializes [result] with the status and headers in [head].
  HttpResponse serialize(Object? result, ResponseHead head) => switch (result) {
    HttpResponse() => result.mergeHeaders(head.headers),
    null => _build(head, StatusCode.noContent, null, BytesBody(const [])),
    String() => _build(
      head,
      StatusCode.ok,
      'text/plain; charset=utf-8',
      BytesBody(utf8.encode(result)),
    ),
    Uint8List() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      BytesBody(result),
    ),
    Stream<List<int>>() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      StreamBody(result),
    ),
    _ => _build(
      head,
      StatusCode.ok,
      'application/json; charset=utf-8',
      BytesBody(utf8.encode(_encode(result))),
    ),
  };

  HttpResponse _build(
    ResponseHead head,
    int defaultStatus,
    String? contentType,
    ResponseBody body,
  ) {
    final headers = HeaderMap();
    if (contentType != null) headers.set('content-type', contentType);
    headers.setAll(head.headers);
    return HttpResponse(
      head.status ?? defaultStatus,
      headers: headers,
      body: body,
    );
  }

  String _encode(Object value) {
    // ResponseSerializer boundary: jsonEncode calls toJson() itself and
    // signals an unencodable user value with this SDK Error; it is converted
    // to the documented SerializationError with the original stack trace.
    try {
      return jsonEncode(registry.prepare(value));
    } on JsonUnsupportedObjectError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SerializationError(
          valueType: error.unsupportedObject.runtimeType,
          cause: error.cause,
        ),
        stackTrace,
      );
    }
  }
}
```

**`packages/grund_http/lib/src/serialize/serialization_error.dart`**

```dart
import 'package:grund/grund.dart' show GrundError;

/// A handler result cannot be encoded as JSON.
final class SerializationError extends GrundError {
  /// Creates the error.
  const SerializationError({required this.valueType, this.cause});

  /// Runtime type of the value that could not be encoded.
  final Type valueType;

  /// What the JSON encoder reported, if anything.
  final Object? cause;

  @override
  String get message {
    final failure = cause;
    // The encoder reports a value without toJson() as a NoSuchMethodError
    // cause; any other cause is a toJson() that threw.
    if (failure != null && failure is! NoSuchMethodError) {
      return 'Cannot serialize $valueType to JSON: its toJson() or the JSON '
          'encoder failed with $failure. Codecs do not apply to '
          'values inside the result of a toJson().';
    }
    return 'Cannot serialize $valueType to JSON. Give it a toJson() method, '
        'return an HttpResponse, or add a '
        'ResponseCodec<$valueType>(...) to HttpModule(codecs: ...). Codecs '
        'do not apply to values inside the result of a toJson().';
  }
}
```

**`packages/grund_http/lib/src/serialize/serializer_registry.dart`**

```dart
/// Converters to JSON values for types that have no `toJson()`, such as
/// third-party classes.
///
/// ```dart
/// registry.register<Money>((m) => {'amount': m.cents, 'cur': m.code});
/// ```
///
/// Applications do not call it: they list `ResponseCodec`s in
/// `HttpModule(codecs: ...)`.
///
/// A converter applies to a handler result and to values nested in its
/// `Map`s and `List`s; it is not applied to values nested inside the result
/// of another object's `toJson()`, so such a `toJson()` must return plain
/// JSON values. The first registered converter whose type matches
/// wins.
final class SerializerRegistry {
  /// Creates an empty registry.
  SerializerRegistry();

  final List<_Converter<Object>> _converters = [];

  /// Registers [toJson] for values of type [T].
  void register<T extends Object>(Object? Function(T value) toJson) {
    _converters.add(_Converter<T>(toJson));
  }

  /// Returns [value] with every registered type replaced by its JSON form,
  /// walking `Map` values and `List` elements; unchanged when nothing is
  /// registered.
  Object? prepare(Object? value) {
    if (_converters.isEmpty) return value;
    final converted = _convert(value);
    return switch (converted) {
      Map<Object?, Object?>() => {
        for (final MapEntry(:key, :value) in converted.entries)
          key: prepare(value),
      },
      List<Object?>() => [for (final item in converted) prepare(item)],
      _ => converted,
    };
  }

  Object? _convert(Object? value) {
    if (value == null) return null;
    for (final converter in _converters) {
      if (converter.accepts(value)) return converter.apply(value);
    }
    return value;
  }
}

final class _Converter<T extends Object> {
  _Converter(this._toJson);

  final Object? Function(T value) _toJson;

  bool accepts(Object value) => value is T;

  Object? apply(Object value) => _toJson(value as T);
}
```

**`packages/grund_http/lib/src/server/route_entry.dart`**

```dart
import '../api/http_api.dart';
import '../api/route.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';

/// A route as the server holds it: the route, the API it belongs to and the
/// hooks around it, outermost first.
final class RouteEntry {
  /// Creates the entry.
  const RouteEntry({
    required this.api,
    required this.route,
    required this.hooks,
    required this.source,
  });

  /// The API the route belongs to.
  final HttpApi api;

  /// The route.
  final Route route;

  /// Global, API and route hooks, in that order.
  final List<HookRef<HttpHook>> hooks;

  /// Names the route in errors: `UsersApi.GET /:id`.
  final String source;
}
```

**`packages/grund_http/lib/src/server/route_table.dart`**

```dart
import '../routing/route_match.dart';
import '../routing/router.dart';
import 'route_entry.dart';

/// Every route of the application, ready to match requests. Immutable: a hot
/// reload builds a new table and swaps it in.
final class RouteTable {
  /// Wraps the filled [router]; [routes] describes it.
  const RouteTable(this._router, this.routes);

  final Router<RouteEntry> _router;

  /// The routes as `'GET /users/:id'`, sorted.
  final List<String> routes;

  /// Finds the route for [method] and the decoded path [segments].
  RouteMatch<RouteEntry> match(String method, List<String> segments) =>
      _router.match(method, segments);
}
```

**`packages/grund_http/lib/src/server/route_table_builder.dart`**

```dart
import '../api/http_api.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import '../routing/route_pattern.dart';
import '../routing/router.dart';
import 'route_entry.dart';
import 'route_table.dart';

/// Builds the [RouteTable] from the `HttpApi`s of the application.
abstract final class RouteTableBuilder {
  /// Registers every route of [apis] and checks that every hook can be
  /// resolved, so that a mistake surfaces before the server listens.
  ///
  /// Throws `InvalidRoutePatternError` for a bad path, `DuplicateRouteError`
  /// when two routes (also of different APIs) share a method and a path, and
  /// the resolution error (`MissingProviderError`, `ProviderCreationError`)
  /// of a hook that cannot be created. Hook types are resolved in a call
  /// scope of the API's module, as they are for a request, and that scope is
  /// closed again.
  static Future<RouteTable> build(
    List<HttpApi> apis,
    List<HookRef<HttpHook>> globalHooks,
  ) async {
    final router = Router<RouteEntry>();
    final routes = <String>[];
    final entries = <HttpApi, List<RouteEntry>>{};
    for (final api in apis) {
      for (final route in api.routes) {
        final pattern = RoutePattern.join(api.path, route.path);
        final entry = RouteEntry(
          api: api,
          route: route,
          hooks: [...globalHooks, ...api.use, ...route.use],
          source: '${api.runtimeType}.${route.name}',
        );
        router.add(route.method, pattern, entry, source: entry.source);
        routes.add('${route.method} $pattern');
        (entries[api] ??= []).add(entry);
      }
    }
    for (final MapEntry(key: api, value: apiEntries) in entries.entries) {
      await _checkHooks(api, apiEntries);
    }
    return RouteTable(router, List.unmodifiable(routes..sort()));
  }

  static Future<void> _checkHooks(HttpApi api, List<RouteEntry> entries) async {
    final scope = api.injector.openCall();
    try {
      for (final entry in entries) {
        for (final ref in entry.hooks) {
          ref.resolve(scope);
        }
      }
    } finally {
      await scope.close();
    }
  }
}
```

**`packages/grund_http/lib/src/server/route_executor.dart`**

```dart
import 'package:grund/grund.dart';

import '../ctx/http_ctx.dart';
import '../hook/hook_chain.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_responder.dart';
import '../http/response_head.dart';
import '../serialize/response_serializer.dart';
import 'route_entry.dart';

/// Runs one matched route for one request: opens the call scope, runs the
/// hooks and the handler, serializes the result, closes the scope. Always
/// answers.
final class RouteExecutor {
  /// Creates the executor.
  const RouteExecutor({
    required this.serializer,
    required this.problems,
    this.maxBodyBytes,
  });

  /// Turns the handler result into a response.
  final ResponseSerializer serializer;

  /// Turns failures into problem responses and reports unexpected ones.
  final ProblemResponder problems;

  /// The request body limit; `null` for none.
  final int? maxBodyBytes;

  /// Serves [request] with [entry]; [cancel] fires when the server stops
  /// waiting for the request.
  Future<HttpResponse> execute(
    HttpRequest request,
    RouteEntry entry,
    Map<String, String> pathParameters,
    CancelSignal cancel,
  ) async {
    final head = ResponseHead();
    final c = HttpCtx(
      request: request,
      scope: entry.api.injector.openCall(),
      response: head,
      pathParameters: pathParameters,
      cancel: cancel,
      maxBodyBytes: maxBodyBytes,
    );
    // Request boundary: hooks, the handler and the serializer are user code;
    // whatever they throw (also when no hook answers) becomes a problem
    // response that keeps the headers set so far, such as www-authenticate.
    try {
      final chain = HookChain.resolve(entry.hooks, c.scope);
      final result = await chain.run(c, entry.route.handler);
      if (entry.route.status case final status?) head.status = status;
      return serializer.serialize(result, head);
    } on Object catch (error, stackTrace) {
      return problems
          .respond(error, stackTrace, instance: request.uri.path)
          .mergeHeaders(head.headers);
    } finally {
      await _close(c);
    }
  }

  Future<void> _close(HttpCtx c) async {
    try {
      await c.close();
    } on ShutdownError catch (error, stackTrace) {
      // Disposing the call's Scoped instances failed; the response is
      // already decided, so the failure is reported, not turned into one.
      problems.log.report(error, stackTrace);
    }
  }
}
```

**`packages/grund_http/lib/src/server/request_dispatcher.dart`**

```dart
import 'package:grund/grund.dart';

import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_code.dart';
import '../http/problem_responder.dart';
import '../routing/route_match.dart';
import 'route_executor.dart';
import 'route_table.dart';

/// Routes one request and serves it; always answers.
final class RequestDispatcher {
  /// Creates the dispatcher.
  const RequestDispatcher({required this.executor, required this.problems});

  /// Serves a matched route.
  final RouteExecutor executor;

  /// Answers the requests that match no route.
  final ProblemResponder problems;

  /// Answers [request] with [table]: 404 for an unknown path, 405 with
  /// `allow` for a known path with another method, otherwise the route's
  /// response. Path segments are percent-decoded and empty segments are
  /// ignored, so `/users/` and `/users//1` match `/users` and `/users/1`.
  Future<HttpResponse> dispatch(
    HttpRequest request,
    RouteTable table,
    CancelSignal cancel,
  ) async {
    final segments = _segments(request);
    if (segments == null) {
      return _problem(
        request,
        const BadRequestException(
          message: 'Malformed percent-encoding in path',
          code: ProblemCode.parameterInvalid,
        ),
      );
    }
    return switch (table.match(request.method, segments)) {
      RouteFound(:final value, :final parameters) => executor.execute(
        request,
        value,
        parameters,
        cancel,
      ),
      RouteMethodNotAllowed(:final allowed) => _problem(
        request,
        MethodNotAllowedException(allowed, code: ProblemCode.methodNotAllowed),
      ),
      RouteNotFound() => _problem(
        request,
        NotFoundException(
          message: 'Cannot ${request.method} ${request.uri.path}',
          code: ProblemCode.routeNotFound,
        ),
      ),
    };
  }

  HttpResponse _problem(HttpRequest request, HttpException error) =>
      problems.respond(error, StackTrace.current, instance: request.uri.path);

  /// The decoded non-empty path segments, or null when the path holds an
  /// invalid percent-encoded UTF-8 sequence (`Uri.pathSegments` throws).
  static List<String>? _segments(HttpRequest request) {
    try {
      return [
        for (final segment in request.uri.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
    } on FormatException {
      return null;
    }
  }
}
```

**`packages/grund_http/lib/grund_http.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/ctx/http_ctx.dart';
export 'src/ctx/param_location.dart';
export 'src/ctx/params.dart';
export 'src/http/connection_info.dart';
export 'src/http/error_log.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/print_error_log.dart';
export 'src/http/problem.dart';
export 'src/http/problem_code.dart';
export 'src/http/problem_error.dart';
export 'src/http/problem_responder.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/api/http_api.dart';
export 'src/api/route.dart';
export 'src/hook/hook_chain.dart';
export 'src/hook/hook_ref.dart';
export 'src/hook/http_hook.dart';
export 'src/hook/middleware.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/response_codec.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
```

- [ ] **Крок 4: запустити — зелено.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart analyze && dart test 2>&1 | tail -3
```

Очікувано: `No issues found!` і `All tests passed!` (усього тестів у пакеті: **164**).

- [ ] **Крок 5: самоперевірка.** `wc -l` кожного зміненого файла (lib ≤ 300, тест ≤ 500), найдовший метод ≤ 40, `dart format packages example` змінює 0 файлів.

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
wc -l packages/grund_http/lib/src/*/*.dart | sort -n | tail -3
dart format packages/grund_http
```

- [ ] **Крок 6: коміт.**

```bash
cd ~/projects/grund
git add packages/grund_http
git commit -m "feat(http): HttpApi, Route, route table and request dispatcher"
```

### Задача 11: `HttpServer`, `HttpModule`, `HttpConfig`, `TestClient`, e2e

**Мета.** `HttpServer` (Runner `http`), `HttpModule`, `HttpConfig`, `TestClient`, e2e на «users app» у явній формі, збої старту (RF-4) і зупинка під навантаженням (RF-5).

Адаптер у тестах — `FakeAdapter` у глобальному модулі `AdapterModule` (справжні `IoAdapterModule`/`ShelfAdapterModule` — задача 12).

**Files** (усі шляхи відносно `packages/grund_http/`):

- Modify/Create `lib/src/server/http_config.dart`
- Modify/Create `lib/src/server/active_calls.dart`
- Modify/Create `lib/src/server/http_server.dart`
- Modify/Create `lib/src/server/http_module.dart`
- Modify/Create `lib/src/testing/test_client.dart`
- Modify/Create `lib/src/adapter/http_adapter.dart`
- Modify `lib/grund_http.dart`, `lib/testing.dart`
- Test `test/helpers/adapter_module.dart`
- Test `test/helpers/users_app.dart`
- Test `test/helpers/probe_root.dart`
- Test `test/e2e/users_app_test.dart`
- Test `test/server/http_server_test.dart`
- Test `test/server/module_options_test.dart`
- Test `test/server/reassemble_test.dart`
- Test `test/server/parallel_requests_test.dart`

Після задачі існують у `packages/grund_http/lib/src/`: `adapter/adapter_lifecycle.dart`, `adapter/error_logger.dart`, `adapter/http_adapter.dart`, `adapter/in_flight_requests.dart`, `api/http_api.dart`, `api/route.dart`, `ctx/body_reader.dart`, `ctx/cookie_header.dart`, `ctx/http_ctx.dart`, `ctx/param_constraints.dart`, `ctx/param_location.dart`, `ctx/params.dart`, `hook/hook_chain.dart`, `hook/hook_ref.dart`, `hook/http_hook.dart`, `hook/middleware.dart`, `hook/middleware_chain.dart`, `http/connection_info.dart`, `http/error_log.dart`, `http/header_map.dart`, `http/http_exception.dart`, `http/http_request.dart`, `http/http_response.dart`, `http/print_error_log.dart`, `http/problem.dart`, `http/problem_code.dart`, `http/problem_error.dart`, `http/problem_responder.dart`, `http/request_body.dart`, `http/response_body.dart`, `http/response_head.dart`, `http/status_code.dart`, `routing/pattern_segment.dart`, `routing/route_match.dart`, `routing/route_pattern.dart`, `routing/router.dart`, `routing/routing_error.dart`, `serialize/response_codec.dart`, `serialize/response_serializer.dart`, `serialize/serialization_error.dart`, `serialize/serializer_registry.dart`, `server/active_calls.dart`, `server/http_config.dart`, `server/http_module.dart`, `server/http_server.dart`, `server/request_dispatcher.dart`, `server/route_entry.dart`, `server/route_executor.dart`, `server/route_table.dart`, `server/route_table_builder.dart`, `testing/test_client.dart`, `testing/test_response.dart`.

**Interfaces.**

- Consumes: усе вище; `Runner`, `App`, `TestApp`, `ReassembleReport`, `Module`, `Singleton`, `Key` (ядро); `HttpAdapter` (1).
- Produces: `HttpConfig`, `HttpModule`, `HttpServer` (`handle`, `routes`, `prepare/start/stop/reassemble`), `TestClient`, `TestClient.of(TestApp)`.

Рішення, що фіксує задача:

- Middleware виконуються до маршрутизації (бачать і 404); збій middleware — 500 problem.
- `HttpServer.stop` ідемпотентний; запит із `handle` рахується in flight, запит від адаптера — лише у `CancelSignal`-набір (адаптер рахує свої сам); після `stop` — 503 `server_unavailable`.
- `HttpModule.onShutdown` викликає `stop()`, щоб застосунок, запущений з `only: const {}` (TestApp, `shelfHandler`), теж давав 503 після `close`.
- Конфлікти роутів і відсутній хук ловляться в `prepare`, тобто до `listen`.

**Крок 1: падаючі тести.** Створити такі тести та допоміжні файли (цілком):

**`packages/grund_http/test/helpers/adapter_module.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Provides [adapter] as the `HttpAdapter` of the graph, the way the real
/// adapter modules do: global, exported.
final class AdapterModule extends Module {
  AdapterModule(this.adapter);

  /// The adapter that is bound.
  final HttpAdapter adapter;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((i) => adapter, dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
```

**`packages/grund_http/test/helpers/users_app.dart`**

```dart
// A small users application written in the explicit form, shared by the
// server and end-to-end tests.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_module.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  UserMissing(this.id);

  final int id;
}

/// A user.
final class User {
  User(this.id, this.name);

  final int id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// Body of `POST /users`.
final class CreateUserDto {
  CreateUserDto(this.name);

  factory CreateUserDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUserDto(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  final String name;
}

/// In-memory users.
final class UsersService {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  List<User> list({required int limit}) => _users.values.take(limit).toList();

  User find(int id) => _users[id] ?? (throw UserMissing(id));

  User create(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }
}

/// The role of the caller, set by [AuthHook].
final class CurrentRole {
  CurrentRole(this.name);

  final String name;
}

/// Accepts `authorization: Bearer <role>` and sets [CurrentRole].
final class AuthHook extends HttpHook {
  const AuthHook();

  @override
  void before(HttpCtx c) {
    final header = c.headers.stringOrNull('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    c.set<CurrentRole>(CurrentRole(header.substring('Bearer '.length)));
  }
}

/// Allows a route only for the given roles; the roles are the hook's
/// parameters, so it is used as a constant instance.
final class RolesHook extends HttpHook {
  const RolesHook(this.names);

  final List<String> names;

  @override
  void before(HttpCtx c) {
    if (!names.contains(c<CurrentRole>().name)) {
      throw const ForbiddenException(code: 'role_not_allowed');
    }
  }
}

/// Translates [UserMissing] into a 404.
final class UserMissingHook extends HttpHook {
  const UserMissingHook();

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is UserMissing) {
      throw NotFoundException(
        message: 'No user ${error.id}',
        code: 'user_not_found',
      );
    }
    return null;
  }
}

/// `/users`: reads are public, writes need an admin.
final class UsersApi extends HttpApi {
  UsersApi(super.injector, this._users);

  final UsersService _users;

  @override
  String get path => '/users';

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<UserMissingHook>.type()];

  @override
  List<Route> get routes => [
    Route.get(
      '/',
      (c) => _users.list(limit: c.query.integerOrNull('limit') ?? 10),
    ),
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async {
        final user = _users.create((await c.body(CreateUserDto.fromJson)).name);
        c.response.headers.set('location', '/users/${user.id}');
        return user;
      },
      status: 201,
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
  ];
}

/// Everything above as a module.
final class UsersModule extends Module {
  const UsersModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>((i) => UsersService(), dependsOn: const []),
    Singleton<AuthHook>((i) => const AuthHook(), dependsOn: const []),
    Singleton<UserMissingHook>(
      (i) => const UserMissingHook(),
      dependsOn: const [],
    ),
    Singleton<UsersApi>(
      (i) => UsersApi(i, i<UsersService>()),
      dependsOn: const [Key<UsersService>()],
    ),
  ];
}

/// The application root: the users module served through [adapter].
final class UsersAppModule extends Module {
  UsersAppModule(this.adapter, {this.http = const HttpModule()});

  /// The adapter the server uses.
  final HttpAdapter adapter;

  /// The HTTP module, to vary its settings.
  final HttpModule http;

  @override
  List<Module> get imports => [
    http,
    AdapterModule(adapter),
    const UsersModule(),
  ];
}
```

**`packages/grund_http/test/helpers/probe_root.dart`**

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_module.dart';
import 'probe_api.dart';

/// A root module that serves `bindings` through [adapter].
final class ProbeRoot extends Module {
  ProbeRoot(
    HttpAdapter adapter,
    List<Binding<Object>> bindings, {
    HttpModule http = const HttpModule(config: HttpConfig(port: 0)),
  }) : _imports = [http, AdapterModule(adapter), ProbeModule(bindings)];

  final List<Module> _imports;

  @override
  List<Module> get imports => _imports;
}

/// The only `HttpServer` of a started [app].
HttpServer serverOf(App app) => app.container.all<HttpServer>().single;
```

**`packages/grund_http/test/e2e/users_app_test.dart`**

```dart
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/users_app.dart';

/// The users application, written in the explicit form, driven through
/// `TestClient`.
void main() {
  late TestApp app;
  late TestClient client;

  Future<void> startApp({HttpModule http = const HttpModule()}) async {
    app = await TestApp.start(root: UsersAppModule(FakeAdapter(), http: http));
    client = TestClient.of(app);
  }

  setUp(startApp);
  tearDown(() => app.close());

  Map<String, String> bearer(String role) => {'authorization': 'Bearer $role'};

  test('lists users with a query limit', () async {
    final all = await client.get('/users');
    final one = await client.get('/users?limit=1');

    expect(all.status, 200);
    expect(all.json, [
      {'id': 1, 'name': 'ann'},
      {'id': 2, 'name': 'bob'},
    ]);
    expect(one.json, [
      {'id': 1, 'name': 'ann'},
    ]);
  });

  test('finds one user by an integer path parameter', () async {
    final response = await client.get('/users/2');

    expect(response.json, {'id': 2, 'name': 'bob'});
    expect(response.headers['content-type'], 'application/json; charset=utf-8');
  });

  test('a hook turns a domain error into a 404 problem', () async {
    final response = await client.get('/users/99');

    expect(response.status, 404);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.json, {
      'type': 'about:blank',
      'title': 'Not Found',
      'status': 404,
      'detail': 'No user 99',
      'instance': '/users/99',
      'code': 'user_not_found',
    });
  });

  test('POST creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: bearer('admin'),
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cy'});
    expect((await client.get('/users/3')).status, 200);
  });

  test('POST without a token is 401 with www-authenticate', () async {
    final response = await client.post('/users', json: {'name': 'cy'});

    expect(response.status, 401);
    expect(response.headers['www-authenticate'], 'Bearer');
    expect((response.json as Map)['title'], 'Unauthorized');
  });

  test(
    'POST by a non-admin is 403 and the hook order is auth, roles',
    () async {
      final response = await client.post(
        '/users',
        json: {'name': 'cy'},
        headers: bearer('viewer'),
      );

      expect(response.status, 403);
      expect((response.json as Map)['code'], 'role_not_allowed');
    },
  );

  group('bad input is a 4xx problem, never a 500 (RF-3)', () {
    test('malformed JSON', () async {
      final response = await client.request(
        'POST',
        '/users',
        body: '{"name":',
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'body_invalid');
    });

    test('a JSON value that is not an object', () async {
      final response = await client.post(
        '/users',
        json: [1, 2],
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'body_invalid');
    });

    test('a missing required field', () async {
      final response = await client.post(
        '/users',
        json: <String, Object?>{},
        headers: bearer('admin'),
      );

      expect(response.status, 400);
      expect(
        ((response.json as Map)['errors'] as List).single,
        containsPair('pointer', '/body'),
      );
    });

    test('a number that is not a number', () async {
      final response = await client.get('/users?limit=ten');

      expect(response.status, 400);
      expect(((response.json as Map)['errors'] as List).single, {
        'detail':
            'Invalid query parameter "limit": expected an integer, '
            'got "ten".',
        'pointer': '/query/limit',
        'code': 'parameter_invalid',
      });
    });

    test('a path parameter of the wrong type', () async {
      final response = await client.get('/users/abc');

      expect(response.status, 400);
      expect((response.json as Map)['code'], 'parameter_invalid');
    });

    test('a body over the configured limit is a 413', () async {
      await app.close();
      await startApp(
        http: const HttpModule(config: HttpConfig(maxBodyBytes: 16)),
      );

      final response = await client.post(
        '/users',
        json: {'name': 'a name that is far too long'},
        headers: bearer('admin'),
      );

      expect(response.status, 413);
      expect((response.json as Map)['code'], 'body_too_large');
    });

    test('a wrong method is 405 with allow, an unknown path is 404', () async {
      final wrongMethod = await client.delete('/users/1');
      final unknown = await client.get('/nothing');

      expect(wrongMethod.status, 405);
      expect(wrongMethod.headers['allow'], 'GET, HEAD');
      expect(unknown.status, 404);
      expect(unknown.headers['content-type'], 'application/problem+json');
    });

    test('extra slashes and percent-encoding in the path', () async {
      expect((await client.get('/users//1/')).status, 200);
      expect((await client.get('/users/%31')).status, 200);
    });
  });

  test('after close every request is 503', () async {
    await app.close();

    final response = await client.get('/users/1');

    expect(response.status, 503);
    expect((response.json as Map)['code'], 'server_unavailable');
  });
}
```

**`packages/grund_http/test/server/http_server_test.dart`**

```dart
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

final class _NoAdapterRoot extends Module {
  @override
  List<Module> get imports => const [HttpModule()];
}

final class _MissingHook extends HttpHook {
  const _MissingHook();
}

Binding<Object> _api(String name, String path) =>
    ProbeApi.binding(name, [Route.get(path, (c) => 'ok')]);

void main() {
  late FakeAdapter adapter;

  setUp(() => adapter = FakeAdapter());

  App appWith(
    List<Binding<Object>> bindings, {
    HttpModule http = const HttpModule(
      config: HttpConfig(address: '127.0.0.1', port: 0),
    ),
  }) => App(root: ProbeRoot(adapter, bindings, http: http));

  group('start', () {
    test('hands the handler, address and port to the adapter', () async {
      final app = appWith([
        _api('a', '/x'),
      ], http: const HttpModule(config: HttpConfig(address: 'h', port: 7)));
      await app.start();
      addTearDown(app.close);

      expect(adapter.address, 'h');
      expect(adapter.port, 7);
      expect((await adapter.send(requestFor('GET', '/x'))).status, 200);
    });

    test('only an empty set does not listen but builds the routes', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start(only: const {});
      addTearDown(app.close);

      expect(adapter.handler, isNull);
      expect(serverOf(app).routes, ['GET /x']);
    });
  });

  group('startup failures (RF-4)', () {
    test('a duplicate route across APIs fails before listen', () async {
      final app = appWith([_api('a', '/x'), _api('b', '/x')]);

      await expectLater(app.start(), throwsA(isA<GrundError>()));

      expect(adapter.handler, isNull);
      expect(app.isClosed, isTrue);
    });

    test('a missing adapter is a MissingProviderError naming it', () async {
      final app = App(root: _NoAdapterRoot());

      await expectLater(
        app.start(),
        throwsA(
          isA<MissingProviderError>().having(
            (e) => e.toString(),
            'message',
            contains('HttpAdapter'),
          ),
        ),
      );
    });

    test('an unknown runner in only is an UnknownRunnerError', () async {
      final app = appWith([_api('a', '/x')]);

      await expectLater(
        app.start(only: const {'htpp'}),
        throwsA(
          isA<UnknownRunnerError>().having(
            (e) => e.available,
            'available',
            contains('http'),
          ),
        ),
      );
    });

    test('a listen failure is a RunnerError and closes the app', () async {
      adapter.listenFailure = StateError('port in use');
      final app = appWith([_api('a', '/x')]);

      await expectLater(
        app.start(),
        throwsA(
          isA<RunnerError>()
              .having((e) => e.runner, 'runner', 'http')
              .having((e) => e.phase, 'phase', 'start'),
        ),
      );

      expect(app.isClosed, isTrue);
    });

    test('a hook that cannot be resolved fails before listen', () async {
      final app = appWith([
        ProbeApi.binding(
          'a',
          [Route.get('/x', (c) => 'ok')],
          use: [HookRef<_MissingHook>.type()],
        ),
      ]);

      await expectLater(app.start(), throwsA(isA<GrundError>()));

      expect(adapter.handler, isNull);
    });
  });

  group('close (RF-5)', () {
    test('is idempotent and closes the adapter once', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start();

      await app.close();
      await app.close();

      expect(adapter.closeCalls, hasLength(1));
    });

    test('does not close an adapter that never listened', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start(only: const {});

      await app.close();

      expect(adapter.closeCalls, isEmpty);
    });

    test('waits for requests in flight, new ones get 503', () async {
      final gate = Completer<void>();
      final app = appWith([
        ProbeApi.binding('a', [
          Route.get('/slow', (c) async {
            await gate.future;
            return 'done';
          }),
        ]),
      ]);
      await app.start(only: const {});
      final server = serverOf(app);
      final slow = server.handle(requestFor('GET', '/slow'));
      await pumpEventQueue();

      final closing = app.close();
      await pumpEventQueue();
      final late = await server.handle(requestFor('GET', '/slow'));
      var closed = false;
      unawaited(closing.then((_) => closed = true));
      await pumpEventQueue();

      expect(late.status, 503);
      expect((await jsonOf(late) as Map)['code'], 'server_unavailable');
      expect(closed, isFalse);
      gate.complete();
      expect((await slow).status, 200);
      await closing;
    });

    test('a request from the adapter does not block close and is '
        'cancelled', () async {
      final seen = Completer<CancelSignal>();
      final hang = Completer<void>();
      final app = appWith([
        ProbeApi.binding('a', [
          Route.get('/hang', (c) async {
            seen.complete(c.cancel);
            await hang.future;
            return 'late';
          }),
        ]),
      ]);
      await app.start();
      final pending = adapter.send(requestFor('GET', '/hang'));
      final cancel = await seen.future;

      await app.close().timeout(const Duration(seconds: 5));
      await cancel.whenCancelled;
      hang.complete();

      expect(cancel.isCancelled, isTrue);
      expect((await pending).status, 200);
    });

    test('a request from the adapter after close gets 503', () async {
      final app = appWith([_api('a', '/x')]);
      await app.start();
      await app.close();

      final response = await adapter.send(requestFor('GET', '/x'));

      expect(response.status, 503);
    });

    test(
      'an adapter close failure is a ShutdownError, the rest closes',
      () async {
        adapter.closeFailure = StateError('stuck');
        final app = appWith([_api('a', '/x')]);
        await app.start();

        await expectLater(app.close(), throwsA(isA<ShutdownError>()));

        expect(app.isClosed, isTrue);
      },
    );
  });
}
```

**`packages/grund_http/test/server/module_options_test.dart`**

```dart
import 'package:grund/grund.dart' show Singleton;
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';
import '../helpers/recording_error_log.dart';

final class _Money {
  const _Money(this.cents);

  final int cents;
}

final class _Header implements Middleware {
  _Header(this.name, this.events);

  final String name;
  final List<String> events;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    events.add('in $name');
    final response = await next();
    events.add('out $name');
    return response.mergeHeaders(HeaderMap.of({'x-$name': 'yes'}));
  }
}

final class _Failing implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) =>
      throw StateError('middleware broke');
}

final class _Shortcut implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async =>
      HttpResponse.text('blocked', status: 418);
}

void main() {
  late TestApp app;

  Future<TestClient> clientFor(
    HttpModule http,
    List<Route> routes, {
    bool withCall = false,
  }) async {
    app = await TestApp.start(
      root: ProbeRoot(FakeAdapter(), [
        ProbeApi.binding('a', routes),
        if (withCall) ...callBindings(),
      ], http: http),
      overrides: [
        Singleton<ErrorLog>((i) => RecordingErrorLog(), dependsOn: const []),
      ],
    );
    return TestClient.of(app);
  }

  tearDown(() => app.close());

  group('middleware', () {
    test('run outermost first around the whole request', () async {
      final events = <String>[];
      final client = await clientFor(
        HttpModule(middleware: [_Header('a', events), _Header('b', events)]),
        [Route.get('/x', (c) => 'ok')],
      );

      final response = await client.get('/x');

      expect(events, ['in a', 'in b', 'out b', 'out a']);
      expect(response.headers['x-a'], 'yes');
      expect(response.headers['x-b'], 'yes');
    });

    test('see requests that match no route', () async {
      final events = <String>[];
      final client = await clientFor(
        HttpModule(middleware: [_Header('a', events)]),
        [Route.get('/x', (c) => 'ok')],
      );

      final response = await client.get('/missing');

      expect(response.status, 404);
      expect(response.headers['x-a'], 'yes');
    });

    test('may answer without calling next', () async {
      final client = await clientFor(HttpModule(middleware: [_Shortcut()]), [
        Route.get('/x', (c) => 'ok'),
      ]);

      expect((await client.get('/x')).status, 418);
    });

    test('a failing middleware is a 500 problem', () async {
      final client = await clientFor(HttpModule(middleware: [_Failing()]), [
        Route.get('/x', (c) => 'ok'),
      ]);

      final response = await client.get('/x');

      expect(response.status, 500);
      expect(response.headers['content-type'], 'application/problem+json');
    });
  });

  group('codecs', () {
    test('a ResponseCodec serializes a type without toJson', () async {
      final client = await clientFor(
        HttpModule(
          codecs: [
            ResponseCodec<_Money>((m) => {'cents': m.cents}),
          ],
        ),
        [Route.get('/m', (c) => const _Money(250))],
      );

      expect((await client.get('/m')).json, {'cents': 250});
    });

    test('a type without a codec is a 500 that names ResponseCodec', () async {
      final client = await clientFor(const HttpModule(), [
        Route.get('/m', (c) => const _Money(250)),
      ]);

      final response = await client.get('/m');

      expect(response.status, 500);
      expect(response.text, isNot(contains('_Money')));
    });
  });

  group('global hooks', () {
    test('wrap every route of every API', () async {
      final client = await clientFor(
        HttpModule(use: [HookRef<UserHook>.type()]),
        [Route.get('/who', (c) => c<CurrentUser>().name)],
        withCall: true,
      );

      final response = await client.get('/who', headers: {'x-user': 'ann'});

      expect(response.text, 'ann');
    });
  });

  group('config', () {
    test('debug shows the error detail of a 500', () async {
      final client = await clientFor(
        const HttpModule(config: HttpConfig(debug: true)),
        [Route.get('/boom', (c) => throw StateError('visible'))],
      );

      final body = (await client.get('/boom')).json as Map;

      expect(body['detail'], contains('visible'));
      expect(body['stack'], isNotNull);
    });

    test('maxBodyBytes limits the body with a 413', () async {
      final client = await clientFor(
        const HttpModule(config: HttpConfig(maxBodyBytes: 8)),
        [Route.post('/p', (c) => c.body((j) => j))],
      );

      final response = await client.post('/p', json: {'long': 'x' * 40});

      expect(response.status, 413);
    });
  });
}
```

**`packages/grund_http/test/server/reassemble_test.dart`**

```dart
import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/probe_root.dart';

/// Stands for the source code of a route: a test edits it, and a hot
/// reload makes `routes` read it again.
final class _Code {
  static var paths = <String>['/old'];
  static Future<void>? gate;
}

final class _Counter {
  static var created = 0;
}

final class _EditableApi extends HttpApi {
  _EditableApi(super.injector);

  @override
  List<Route> get routes => [
    for (final path in _Code.paths)
      Route.get(path, (c) async {
        await _Code.gate;
        return path;
      }),
  ];
}

void main() {
  late App app;
  late HttpServer server;

  setUp(() async {
    _Code.paths = ['/old'];
    _Code.gate = null;
    _Counter.created = 0;
    app = App(
      root: ProbeRoot(FakeAdapter(), [
        Singleton<_EditableApi>(
          (i) => _EditableApi(i),
          name: 'editable',
          dependsOn: const [],
        ),
        Singleton<_Counter>((i) {
          _Counter.created++;
          return _Counter();
        }, dependsOn: const []),
      ]),
    );
    await app.start();
    server = serverOf(app);
  });

  tearDown(() => app.close());

  test('reports the routes added and removed', () async {
    _Code.paths = ['/new'];

    final report = await app.reassemble();

    expect(report.added, ['GET /new']);
    expect(report.removed, ['GET /old']);
    expect(server.routes, ['GET /new']);
  });

  test('a request in flight finishes on the table it began with', () async {
    final gate = Completer<void>();
    _Code.gate = gate.future;
    final inFlight = server.handle(requestFor('GET', '/old'));
    await pumpEventQueue();
    _Code.paths = ['/new'];
    _Code.gate = null;

    await app.reassemble();
    gate.complete();

    expect((await inFlight).status, 200);
    expect((await server.handle(requestFor('GET', '/old'))).status, 404);
    expect((await server.handle(requestFor('GET', '/new'))).status, 200);
  });

  test('a failed reassemble keeps serving the previous table', () async {
    _Code.paths = ['/old', '/old'];

    await expectLater(app.reassemble(), throwsA(isA<GrundError>()));

    expect(server.routes, ['GET /old']);
    expect((await server.handle(requestFor('GET', '/old'))).status, 200);
  });

  test('singletons of an unchanged module are kept', () async {
    _Code.paths = ['/other'];

    await app.reassemble();

    expect(_Counter.created, 1);
  });
}
```

**`packages/grund_http/test/server/parallel_requests_test.dart`**

```dart
import 'dart:async';

import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import '../helpers/call_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/probe_api.dart';
import '../helpers/probe_root.dart';

void main() {
  test('parallel requests never see each other\'s c.set (RF-2)', () async {
    final release = Completer<void>();
    final app = await TestApp.start(
      root: ProbeRoot(FakeAdapter(), [
        ...callBindings(),
        ProbeApi.binding(
          'a',
          [
            Route.get('/who', (c) async {
              // Every request waits here, so all of them are in flight
              // together before any answers.
              await release.future;
              return '${c<CurrentUser>().name}/${identityHashCode(c<Tx>())}';
            }),
          ],
          use: [HookRef<UserHook>.type()],
        ),
      ]),
    );
    addTearDown(app.close);
    final client = TestClient.of(app);

    final responses = [
      for (var i = 0; i < 20; i++)
        client.get('/who', headers: {'x-user': 'user$i'}),
    ];
    await pumpEventQueue();
    release.complete();
    final texts = [for (final r in await Future.wait(responses)) r.text];

    for (var i = 0; i < 20; i++) {
      expect(texts[i], startsWith('user$i/'));
    }
    expect(texts.map((t) => t.split('/').last).toSet(), hasLength(20));
    final log = app.app.container.all<TxLog>().single;
    expect(log.created, 20);
    expect(log.disposed, 20);
  });
}
```

(Тести цієї задачі спираються на `FakeAdapter` і `requestFor`/`jsonOf` із задачі 1.)

**Крок 2: запустити — очікується збій компіляції** (типів ще немає).

- [ ] Виконати:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart test 2>&1 | tail -15
```

Очікувано: `Error: ... isn't defined` / `Failed to load`.

**Крок 3: реалізація.** Створити або замінити цілком:

**`packages/grund_http/lib/src/server/http_config.dart`**

```dart
/// How the HTTP server listens and what it accepts.
///
/// Give it to `HttpModule(config: ...)`, or replace the binding at run time
/// with an override (`Singleton<HttpConfig>(...)`) to read the port from the
/// environment.
final class HttpConfig {
  /// Creates the configuration.
  const HttpConfig({
    this.address = 'localhost',
    this.port = 8080,
    this.maxBodyBytes = 1048576,
    this.debug = false,
  });

  /// What the adapter binds to: a host name or an address object, whatever
  /// the adapter understands.
  final Object address;

  /// The port; 0 asks the adapter for an ephemeral port.
  final int port;

  /// The largest request body the body readers accept; more is a 413.
  final int maxBodyBytes;

  /// Whether a 500 response shows the error and its stack trace. Never
  /// enable it in production.
  final bool debug;
}
```

**`packages/grund_http/lib/src/server/active_calls.dart`**

```dart
import '../adapter/in_flight_requests.dart';
import 'package:grund/grund.dart';

/// The requests the server is serving right now: counted, so that stopping
/// can wait for them, and cancellable, so that stopping can tell the ones
/// that stay behind to give up.
final class ActiveCalls {
  final InFlightRequests _inFlight = InFlightRequests();
  final Set<CancelSignal> _signals = {};

  /// Starts a call: the signal fires if the server gives up on it.
  CancelSignal open() {
    final signal = CancelSignal();
    _signals.add(signal);
    return signal;
  }

  /// Ends the call that [signal] belongs to.
  void release(CancelSignal signal) => _signals.remove(signal);

  /// Counts [serve] as in flight until it completes.
  Future<T> track<T>(Future<T> Function() serve) => _inFlight.track(serve);

  /// Completes when no tracked request is in flight.
  Future<void> get idle => _inFlight.idle;

  /// Fires the signal of every call still open.
  void cancelAll() {
    for (final signal in _signals.toList()) {
      signal.cancel();
    }
    _signals.clear();
  }
}
```

**`packages/grund_http/lib/src/server/http_server.dart`**

```dart
import 'package:grund/grund.dart';

import '../adapter/http_adapter.dart';
import '../api/http_api.dart';
import '../hook/middleware_chain.dart';
import '../http/error_log.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/problem_code.dart';
import '../http/problem_responder.dart';
import '../serialize/response_serializer.dart';
import '../serialize/serializer_registry.dart';
import 'active_calls.dart';
import 'http_config.dart';
import 'http_module.dart';
import 'request_dispatcher.dart';
import 'route_executor.dart';
import 'route_table.dart';
import 'route_table_builder.dart';

/// Serves the `HttpApi`s of the application over an `HttpAdapter`.
///
/// `HttpModule` binds it; `App` finds it as a [Runner] named `http`.
/// [prepare] builds the route table and checks it (so a conflicting route
/// or a missing hook fails the start, before anything listens); [start] hands
/// [handle] to the adapter; [stop] stops accepting, waits for the requests in
/// progress and tells the ones that stay behind to give up.
final class HttpServer extends Runner {
  /// Creates the server; `HttpModule` does this with the bindings of the
  /// graph. [module] supplies the global hooks, the middleware and the codecs.
  HttpServer(
    HttpModule module, {
    required HttpAdapter adapter,
    required HttpConfig config,
    required ErrorLog log,
  }) : this._(
         module,
         adapter,
         config,
         ProblemResponder(debug: config.debug, log: log),
       );

  HttpServer._(this._module, this._adapter, this._config, this._problems)
    : _dispatcher = _dispatcherFor(_module, _config, _problems);

  final HttpModule _module;
  final HttpAdapter _adapter;
  final HttpConfig _config;
  final ProblemResponder _problems;
  final RequestDispatcher _dispatcher;
  final ActiveCalls _calls = ActiveCalls();
  RouteTable? _table;
  var _listening = false;
  var _stopping = false;
  Future<void>? _stopped;

  static RequestDispatcher _dispatcherFor(
    HttpModule module,
    HttpConfig config,
    ProblemResponder problems,
  ) {
    final registry = SerializerRegistry();
    for (final codec in module.codecs) {
      codec.registerIn(registry);
    }
    return RequestDispatcher(
      problems: problems,
      executor: RouteExecutor(
        serializer: ResponseSerializer(registry),
        problems: problems,
        maxBodyBytes: config.maxBodyBytes,
      ),
    );
  }

  @override
  String get name => 'http';

  /// The served routes as `'GET /users/:id'`, sorted; empty before the
  /// application is prepared.
  List<String> get routes => _table?.routes ?? const [];

  /// Answers [request] the way the adapter does, counted as in flight until
  /// it completes: the entry for `TestClient` and `shelfHandler`.
  ///
  /// Never throws for a request; every failure is a problem response, and a
  /// server that is shutting down answers 503.
  Future<HttpResponse> handle(HttpRequest request) {
    if (_stopping) return Future.value(_unavailable(request));
    return _calls.track(() => _answer(request));
  }

  @override
  Future<void> prepare(Injector injector) async {
    _table = await _buildTable(injector);
  }

  @override
  Future<void> start(Injector injector) async {
    _listening = true;
    try {
      await _adapter.listen(
        _answer,
        address: _config.address,
        port: _config.port,
      );
    } on Object {
      // The adapter is third-party code; the failure (a port in use) goes on
      // unchanged, but this server must not claim to listen.
      _listening = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() => _stopped ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    // When the adapter fails to close, its state is unknown: the failure is
    // reported without waiting for requests that may never finish.
    try {
      if (_listening) await _adapter.close();
      await _calls.idle;
    } finally {
      _calls.cancelAll();
    }
  }

  @override
  Future<ReassembleReport> reassemble(Injector injector) async {
    final next = await _buildTable(injector);
    final previous = routes;
    _table = next;
    return ReassembleReport.between(previous, next.routes);
  }

  Future<RouteTable> _buildTable(Injector injector) =>
      RouteTableBuilder.build(injector.all<HttpApi>(), _module.use);

  Future<HttpResponse> _answer(HttpRequest request) async {
    final table = _table;
    if (table == null) {
      throw const ApplicationStateError(
        operation: 'handle',
        reason: 'the application is not started',
      );
    }
    if (_stopping) return _unavailable(request);
    final cancel = _calls.open();
    // Request boundary: a middleware is user code; its failure is a problem
    // response, like that of a hook, and the adapter never sees a throw.
    try {
      return await MiddlewareChain.run(
        _module.middleware,
        request,
        () => _dispatcher.dispatch(request, table, cancel),
      );
    } on Object catch (error, stackTrace) {
      return _problems.respond(error, stackTrace, instance: request.uri.path);
    } finally {
      _calls.release(cancel);
    }
  }

  HttpResponse _unavailable(HttpRequest request) => _problems.respond(
    const ServiceUnavailableException(
      message: 'The server is shutting down.',
      code: ProblemCode.serverUnavailable,
    ),
    StackTrace.current,
    instance: request.uri.path,
  );
}
```

**`packages/grund_http/lib/src/server/http_module.dart`**

```dart
import 'package:grund/grund.dart';

import '../adapter/http_adapter.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import '../hook/middleware.dart';
import '../http/error_log.dart';
import '../http/print_error_log.dart';
import '../serialize/response_codec.dart';
import 'http_config.dart';
import 'http_server.dart';

/// The HTTP server of the application.
///
/// Import it from the root module together with a module that provides the
/// `HttpAdapter` (`IoAdapterModule`, `ShelfAdapterModule`):
///
/// ```dart
/// final class AppModule extends Module {
///   const AppModule();
///   @override List<Module> get imports => const [
///     HttpModule(use: [HookRef<RequestIdHook>.type()]),
///     IoAdapterModule(),
///     TasksModule(),
///   ];
/// }
/// ```
///
/// It binds the `HttpServer` (a `Runner` named `http`), the `HttpConfig` and
/// the `ErrorLog`, and exports all three; replace the config or the log with
/// an override of the same key. Without an adapter the application does not
/// start: `HttpAdapter` is missing.
final class HttpModule extends Module {
  /// Creates the module.
  ///
  /// [use] are hooks that wrap every route, outermost first; [middleware]
  /// run around the whole request before routing; [codecs] teach the
  /// response serializer types without `toJson()`.
  const HttpModule({
    this.use = const [],
    this.middleware = const [],
    this.codecs = const [],
    this.config = const HttpConfig(),
  });

  /// Hooks that wrap every route.
  final List<HookRef<HttpHook>> use;

  /// Middleware, outermost first.
  final List<Middleware> middleware;

  /// Codecs for the response serializer.
  final List<ResponseCodec<Object>> codecs;

  /// The default configuration.
  final HttpConfig config;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ErrorLog>((i) => const PrintErrorLog(), dependsOn: const []),
    Singleton<HttpConfig>((i) => config, dependsOn: const []),
    Singleton<HttpServer>(
      (i) => HttpServer(
        this,
        adapter: i<HttpAdapter>(),
        config: i<HttpConfig>(),
        log: i<ErrorLog>(),
      ),
      dependsOn: const [Key<HttpAdapter>(), Key<HttpConfig>(), Key<ErrorLog>()],
    ),
  ];

  // The runner is stopped by App.close only when it was started; an
  // application started with `only: const {}` (tests, shelfHandler) is
  // stopped here, before any value is disposed.
  @override
  Future<void> onShutdown(Injector injector) => injector<HttpServer>().stop();

  @override
  List<Object> get exports => const [
    Key<HttpServer>(),
    Key<HttpConfig>(),
    Key<ErrorLog>(),
  ];
}
```

**`packages/grund_http/lib/src/testing/test_client.dart`**

```dart
import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:grund/testing.dart';

import '../http/header_map.dart';
import '../http/http_request.dart';
import '../http/request_body.dart';
import '../server/http_server.dart';
import 'test_response.dart';

/// Sends requests straight to [HttpServer.handle], without a socket.
///
/// ```dart
/// final app = await TestApp.start(root: AppModule());
/// final client = TestClient.of(app);
/// final response = await client.get('/users/1');
/// expect(response.json, {'id': 1, 'name': 'ann'});
/// ```
final class TestClient {
  /// Creates a client for [server].
  TestClient(this.server);

  /// Creates a client for the `HttpServer` of [app].
  ///
  /// Throws an `ApplicationStateError` when the application imports no
  /// `HttpModule`.
  factory TestClient.of(TestApp app) {
    final servers = app.app.container.all<HttpServer>();
    if (servers.isEmpty) {
      throw const ApplicationStateError(
        operation: 'TestClient.of',
        reason: 'the application has no HttpServer; import HttpModule',
      );
    }
    return TestClient(servers.first);
  }

  /// The server under test.
  final HttpServer server;

  /// Sends `GET` to [target] (a path with an optional query).
  Future<TestResponse> get(
    String target, {
    Map<String, String> headers = const {},
  }) => request('GET', target, headers: headers);

  /// Sends `DELETE` to [target].
  Future<TestResponse> delete(
    String target, {
    Map<String, String> headers = const {},
  }) => request('DELETE', target, headers: headers);

  /// Sends `POST` to [target] with [json] encoded as the body.
  Future<TestResponse> post(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('POST', target, json: json, headers: headers);

  /// Sends `PUT` to [target] with [json] encoded as the body.
  Future<TestResponse> put(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PUT', target, json: json, headers: headers);

  /// Sends `PATCH` to [target] with [json] encoded as the body.
  Future<TestResponse> patch(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PATCH', target, json: json, headers: headers);

  /// Sends [method] to [target]. The body is [json] encoded as JSON (with
  /// `content-type: application/json`) or the raw [body] string; passing
  /// both is an `ArgumentError`. `json: null` cannot be sent: null means no
  /// body. A response to `HEAD` keeps its body here, unlike real adapters,
  /// which drop it.
  Future<TestResponse> request(
    String method,
    String target, {
    Object? json,
    String? body,
    Map<String, String> headers = const {},
  }) {
    if (json != null && body != null) {
      throw ArgumentError('Pass either json or body, not both.');
    }
    final requestHeaders = HeaderMap.of(headers);
    final text = json == null ? body : jsonEncode(json);
    if (json != null && requestHeaders['content-type'] == null) {
      requestHeaders.set('content-type', 'application/json');
    }
    return send(
      HttpRequest(
        method: method,
        uri: Uri.parse(target),
        headers: requestHeaders,
        body: text == null ? null : RequestBody.bytes(utf8.encode(text)),
      ),
    );
  }

  /// Sends a prepared [request] and reads the whole response body.
  Future<TestResponse> send(HttpRequest request) async {
    final response = await server.handle(request);
    return TestResponse(
      status: response.status,
      headers: response.headers,
      bytes: await response.body.readAll(),
    );
  }
}
```

**`packages/grund_http/lib/src/adapter/http_adapter.dart`**

```dart
import '../http/http_request.dart';
import '../http/http_response.dart';

/// Answers one request. `HttpServer` passes adapters an
/// implementation equal to `HttpServer.handle` but not counted by the
/// server's in-flight counter: adapters count their own requests.
typedef RequestHandler = Future<HttpResponse> Function(HttpRequest request);

/// Connects an HTTP server library to an `HttpServer`.
///
/// Implemented outside this package (`grund_io`, `grund_shelf`).
/// Contract:
///
/// - [listen] is called at most once, by `HttpServer.start`, and completes
///   when the server accepts connections. For every native request the
///   adapter builds an [HttpRequest] (upper-cased method; `uri` with path and
///   query; every header value, multi-valued headers included; the body as
///   an unread stream; `connectionInfo` when known), awaits `handler`, and
///   writes the response status, every header value and the body (bytes, or
///   the stream chunk by chunk). It writes no body for `HEAD` requests.
///   `handler` answers every request, errors included; if it ever throws,
///   the adapter answers 500 without a body and keeps serving.
/// - [address] is adapter-specific (a host name or an address object); a
///   [port] of 0 asks for an ephemeral port.
/// - [close] stops accepting connections. With `force: false` it completes
///   after the responses in progress are written; an adapter may bound that
///   wait (e.g. a `closeTimeout`) and then drop the remaining connections
///   as `force: true` does. With `force: true` it drops open connections at
///   once. It is idempotent and completes at once if [listen] was never
///   called. `HttpServer.stop` calls it first and does not itself wait
///   for the requests the adapter delivered: that wait is the adapter's.
abstract interface class HttpAdapter {
  /// Starts serving [handler] on [address] and [port].
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  });

  /// Stops serving; see the class documentation.
  Future<void> close({bool force = false});
}
```

**`packages/grund_http/lib/grund_http.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// HTTP for grund: request/response values, routing and the adapter contract.
library;

export 'src/adapter/error_logger.dart';
export 'src/adapter/http_adapter.dart';
export 'src/ctx/http_ctx.dart';
export 'src/ctx/param_location.dart';
export 'src/ctx/params.dart';
export 'src/http/connection_info.dart';
export 'src/http/error_log.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/print_error_log.dart';
export 'src/http/problem.dart';
export 'src/http/problem_code.dart';
export 'src/http/problem_error.dart';
export 'src/http/problem_responder.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/api/http_api.dart';
export 'src/api/route.dart';
export 'src/hook/hook_chain.dart';
export 'src/hook/hook_ref.dart';
export 'src/hook/http_hook.dart';
export 'src/hook/middleware.dart';
export 'src/routing/routing_error.dart';
export 'src/serialize/response_codec.dart';
export 'src/serialize/serialization_error.dart';
export 'src/serialize/serializer_registry.dart';
export 'src/server/http_config.dart';
export 'src/server/http_module.dart';
export 'src/server/http_server.dart';
```

**`packages/grund_http/lib/testing.dart`** (цілком, лише експорти файлів, що вже існують)

```dart
/// Test support for HTTP applications.
library;

export 'src/testing/test_client.dart';
export 'src/testing/test_response.dart';
```

- [ ] **Крок 4: запустити — зелено.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund/packages/grund_http
dart analyze && dart test 2>&1 | tail -3
```

Очікувано: `No issues found!` і `All tests passed!` (усього тестів у пакеті: **206**).

- [ ] **Крок 5: самоперевірка.** `wc -l` кожного зміненого файла (lib ≤ 300, тест ≤ 500), найдовший метод ≤ 40, `dart format packages example` змінює 0 файлів.

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd ~/projects/grund
wc -l packages/grund_http/lib/src/*/*.dart | sort -n | tail -3
dart format packages/grund_http
```

- [ ] **Крок 6: коміт.**

```bash
cd ~/projects/grund
git add packages/grund_http
git commit -m "feat(http): HttpServer, HttpModule, TestClient and end-to-end tests"
```

## Частина D (1/2): адаптери та conformance

### Задача 12: Адаптери `IoAdapterModule`/`ShelfAdapterModule`, `shelfHandler(App)`, conformance на новому API

**Мета:** `grund_io` і `grund_shelf` залежать від `grund_http` (не від ядра), кожен постачає глобальний модуль, що біндить `HttpAdapter` і експортує `Key<HttpAdapter>`; `shelfHandler` приймає `App`; `grund_conformance` будує застосунок на новому API (`App` + `HttpModule` + модуль адаптера), 404 тепер `application/problem+json`.

**Передумови:** задачі 1-11 виконані (є `grund_http` з `HttpServer`, `HttpModule`, `HttpConfig`, `ErrorLog`, `HttpApi`, `Route`; ядро з `App`, `Module`, `Singleton`, `Key`, `RunnerError`).

**Files:**
- Перевірити (без змін): `packages/grund_http/lib/src/adapter/error_logger.dart` і його `export` у `packages/grund_http/lib/grund_http.dart`
- Modify (лише імпорти + `pubspec.yaml`, крок 2): `packages/grund_io/lib/src/{io_adapter,io_request_mapper,io_response_writer}.dart`, `packages/grund_io/test/{io_adapter_test,io_adapter_tls_test}.dart`, `packages/grund_shelf/lib/src/{guarded_reporter,shelf_adapter,shelf_bridge,shelf_request_mapper,shelf_response_mapper}.dart`, `packages/grund_shelf/test/{shelf_adapter_test,shelf_bridge_test,shelf_response_mapper_test,helpers/shelf_adapter_support}.dart`
- Create: `packages/grund_io/lib/src/io_adapter_module.dart`, `packages/grund_io/test/io_adapter_module_test.dart`, `packages/grund_shelf/lib/src/shelf_adapter_module.dart`, `packages/grund_shelf/test/shelf_adapter_module_test.dart`
- Modify: `packages/grund_io/lib/grund_io.dart`, `packages/grund_shelf/lib/grund_shelf.dart`, `packages/grund_shelf/lib/src/shelf_handler.dart`, `packages/grund_{io,shelf}/example/*.dart`, `packages/grund_{io,shelf}/test/*_adapter_conformance_test.dart`, `packages/grund_shelf/test/shelf_handler_test.dart`
- Create/Modify/Delete у `packages/grund_conformance` (кроки 6-7; `lib/src/conformance_app.dart` видалити)

**Interfaces:**
- Consumes: `HttpAdapter`, `RequestHandler`, `AdapterLifecycle`, `InFlightRequests` (`grund_http/adapter.dart`), `HttpServer.handle`, `HttpModule`, `HttpConfig`, `ErrorLog`, `HttpApi`, `Route`, `App`, `Module`, `Singleton`, `Key`, `RunnerError`.
- Produces: `IoAdapterModule({securityContext, closeTimeout, onError})`, `ShelfAdapterModule({closeTimeout, onError})`, `shelf.Handler shelfHandler(App app, {ErrorLogger? onError})`, `typedef ErrorLogger` (у `grund_http`), `ConformanceRoot(probe, {required Module adapter, int port = 0})`, `AdapterUnderTest.of<A>(Module, {required int Function(A) port})`.

**Рішення (відхилення від угоди частин плану, див. кінець):** тип `ErrorLogger = void Function(Object, StackTrace)` (callback `onError` адаптерів) лишається в `grund_http` з задачі 1 (задача 7 його не чіпає), тож адаптери не змінюють публічних сигнатур. `HttpServer` потребує `Key<HttpAdapter>`, тому `shelfHandler` вимагає модуль адаптера в графі (`ShelfAdapterModule` лише конструюється, `listen` не викликається, бо застосунок стартує з `only: const {}`).

- [ ] **Крок 1: перевірити, що `ErrorLogger` на місці**

Файл `packages/grund_http/lib/src/adapter/error_logger.dart` має існувати (з задачі 1) і експортуватися з `grund_http.dart`; якщо ні — відновити:

```dart
/// Receives a failure that an adapter cannot turn into a response.
typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);
```

У `packages/grund_http/lib/grund_http.dart` додати перед `export 'src/adapter/http_adapter.dart';` рядок `export 'src/adapter/error_logger.dart';`.

- [ ] **Крок 2: перемкнути імпорти й залежності адаптерів на `grund_http`**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages
grep -rl "package:grund/" grund_io grund_shelf --include=*.dart | xargs sed -i \
  -e "s#package:grund/adapter.dart#package:grund_http/adapter.dart#" \
  -e "s#package:grund/grund.dart#package:grund_http/grund_http.dart#"
```

У `packages/grund_io/pubspec.yaml` і `packages/grund_shelf/pubspec.yaml` у `dependencies:` після `grund: ^0.1.0` додати рядок `grund_http: ^0.1.0` (адаптерний модуль імпортує ядро для `Module`/`Singleton`/`Key`). Файли, що змінюються лише так, перелічені у **Files**; решта змін — цілими файлами в кроках 3-8 (після sed вони перезаписуються).

Запустити: `cd packages/grund_io && dart pub get && dart test test/io_adapter_test.dart test/io_adapter_tls_test.dart`; `cd ../grund_shelf && dart test test/shelf_adapter_test.dart test/shelf_bridge_test.dart test/shelf_request_mapper_test.dart test/shelf_response_mapper_test.dart test/guarded_reporter_test.dart`. Очікування: зелені (кількості порівняти з числами до змін).

- [ ] **Крок 3: `IoAdapterModule`**

Тест (п'ять поведінок: біндить адаптер; глобальний — споживач без імпорту його бачить; один адаптер на застосунок; параметри доходять до адаптера; значення за замовчуванням):

Файл `packages/grund_io/test/io_adapter_module_test.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

/// The root: imports the adapter module under test and the consumer.
final class _Root extends Module {
  const _Root(this.adapter);

  final IoAdapterModule adapter;

  @override
  List<Module> get imports => [adapter, const _Consumer()];
}

/// Resolves the adapter although it does not import its module.
final class _Consumer extends Module {
  const _Consumer();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<String>(
      (i) => i<HttpAdapter>().runtimeType.toString(),
      dependsOn: const [Key<HttpAdapter>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<String>()];
}

Future<TestApp> _start([IoAdapterModule adapter = const IoAdapterModule()]) =>
    TestApp.start(root: _Root(adapter));

void main() {
  group('IoAdapterModule', () {
    test('binds an IoAdapter as the HttpAdapter', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<HttpAdapter>(), isA<IoAdapter>());
    });

    test('is global: a module that does not import it resolves it', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<String>(), 'IoAdapter');
    });

    test('creates one adapter per application', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(identical(app<HttpAdapter>(), app<HttpAdapter>()), isTrue);
    });

    test('hands closeTimeout and onError to the adapter', () async {
      void onError(Object error, StackTrace stackTrace) {}
      final app = await _start(
        IoAdapterModule(
          closeTimeout: const Duration(seconds: 3),
          onError: onError,
        ),
      );
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<IoAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              const Duration(seconds: 3),
            )
            .having((a) => a.onError, 'onError', same(onError)),
      );
    });

    test('keeps the defaults of the adapter without arguments', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<IoAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              IoAdapter.defaultCloseTimeout,
            )
            .having((a) => a.onError, 'onError', same(IoAdapter.printError)),
      );
    });
  });
}
```

Запустити `dart test test/io_adapter_module_test.dart`. Очікування: збій компіляції (`IoAdapterModule` не існує). Реалізація:

Файл `packages/grund_io/lib/src/io_adapter_module.dart`:

```dart
import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'io_adapter.dart';

/// Provides an [IoAdapter] to the application: import it next to
/// `HttpModule` and the HTTP server listens through `dart:io`.
///
/// The module is global and exports `Key<HttpAdapter>()`, so every module
/// of the graph can resolve the adapter without importing this one. The
/// parameters are those of the [IoAdapter] constructor.
///
/// ```dart
/// final class AppModule extends Module {
///   @override
///   List<Module> get imports => const [HttpModule(), IoAdapterModule()];
/// }
/// ```
final class IoAdapterModule extends Module {
  /// Creates the module; see [IoAdapter] for the parameters.
  const IoAdapterModule({
    this.securityContext,
    this.closeTimeout = IoAdapter.defaultCloseTimeout,
    this.onError,
  });

  /// TLS configuration; `null` serves plain HTTP.
  final io.SecurityContext? securityContext;

  /// How long a graceful close waits for the requests in flight; `null`
  /// waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures; `null` prints them to stderr.
  final ErrorLogger? onError;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>(
      (_) => IoAdapter(
        securityContext: securityContext,
        closeTimeout: closeTimeout,
        onError: onError,
      ),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
```

Файл `packages/grund_io/lib/grund_io.dart`:

```dart
/// Serves grund applications on a `dart:io` `HttpServer`.
library;

export 'src/io_adapter.dart';
export 'src/io_adapter_module.dart';
```

Запустити тест ще раз: 5 зелених.

- [ ] **Крок 4: `ShelfAdapterModule`**

Файл `packages/grund_shelf/test/shelf_adapter_module_test.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:test/test.dart';

/// The root: imports the adapter module under test and the consumer.
final class _Root extends Module {
  const _Root(this.adapter);

  final ShelfAdapterModule adapter;

  @override
  List<Module> get imports => [adapter, const _Consumer()];
}

/// Resolves the adapter although it does not import its module.
final class _Consumer extends Module {
  const _Consumer();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<String>(
      (i) => i<HttpAdapter>().runtimeType.toString(),
      dependsOn: const [Key<HttpAdapter>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<String>()];
}

Future<TestApp> _start([
  ShelfAdapterModule adapter = const ShelfAdapterModule(),
]) => TestApp.start(root: _Root(adapter));

void main() {
  group('ShelfAdapterModule', () {
    test('binds an ShelfAdapter as the HttpAdapter', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<HttpAdapter>(), isA<ShelfAdapter>());
    });

    test('is global: a module that does not import it resolves it', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<String>(), 'ShelfAdapter');
    });

    test('creates one adapter per application', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(identical(app<HttpAdapter>(), app<HttpAdapter>()), isTrue);
    });

    test('hands closeTimeout and onError to the adapter', () async {
      void onError(Object error, StackTrace stackTrace) {}
      final app = await _start(
        ShelfAdapterModule(
          closeTimeout: const Duration(seconds: 3),
          onError: onError,
        ),
      );
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<ShelfAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              const Duration(seconds: 3),
            )
            .having((a) => a.onError, 'onError', same(onError)),
      );
    });

    test('keeps the defaults of the adapter without arguments', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<ShelfAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              ShelfAdapter.defaultCloseTimeout,
            )
            .having((a) => a.onError, 'onError', same(ShelfAdapter.printError)),
      );
    });
  });
}
```

Очікуваний збій (немає класу), далі реалізація:

Файл `packages/grund_shelf/lib/src/shelf_adapter_module.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'shelf_adapter.dart';

/// Provides a [ShelfAdapter] to the application: import it next to
/// `HttpModule` and the HTTP server listens through `shelf_io`.
///
/// The module is global and exports `Key<HttpAdapter>()`, so every module
/// of the graph can resolve the adapter without importing this one. The
/// parameters are those of the [ShelfAdapter] constructor.
///
/// ```dart
/// final class AppModule extends Module {
///   @override
///   List<Module> get imports => const [HttpModule(), ShelfAdapterModule()];
/// }
/// ```
final class ShelfAdapterModule extends Module {
  /// Creates the module; see [ShelfAdapter] for the parameters.
  const ShelfAdapterModule({
    this.closeTimeout = ShelfAdapter.defaultCloseTimeout,
    this.onError,
  });

  /// How long a graceful close waits for the requests in flight; `null`
  /// waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures; `null` prints them to stderr.
  final ErrorLogger? onError;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>(
      (_) => ShelfAdapter(closeTimeout: closeTimeout, onError: onError),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
```

- [ ] **Крок 5: `shelfHandler(App)`**

Тест (RF-4: нестартований застосунок -> `ApplicationStateError`; після `close()` -> 503; виняток `ErrorLog` -> 500 без тіла; HEAD; користувацький конвеєр shelf):

Файл `packages/grund_shelf/test/shelf_handler_test.dart`:

```dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// The user's own shelf stack: a middleware that tags every response, an
/// own route, and the grund application mounted under `/api/`.
shelf.Handler userPipeline(shelf.Handler api) => const shelf.Pipeline()
    .addMiddleware(
      (inner) =>
          (request) async =>
              (await inner(request)).change(headers: {'x-user-stack': 'yes'}),
    )
    .addHandler(
      shelf.Cascade()
          .add(
            (request) => request.url.path == 'health'
                ? shelf.Response.ok('healthy')
                : shelf.Response.notFound(null),
          )
          .add(
            (request) => request.url.path.startsWith('api/')
                ? api(request.change(path: 'api'))
                : shelf.Response.notFound(null),
          )
          .handler,
    );

void main() {
  group('shelfHandler', () {
    late App app; // Set in setUp before every test.

    // The application only prepares its routes: no port is opened.
    Future<App> startApp({List<Binding<Object>> overrides = const []}) async {
      final app = App(
        root: ConformanceRoot(
          ConformanceProbe(),
          adapter: const ShelfAdapterModule(),
        ),
        overrides: overrides,
      );
      await app.start(only: const {});
      addTearDown(app.close);
      return app;
    }

    setUp(() async => app = await startApp());

    test('answers inside a user pipeline, mounted under a prefix', () async {
      final server = await shelf_io.serve(
        userPipeline(shelfHandler(app)),
        io.InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      Future<(int, String?, String)> get(String path) async {
        final response = await (await client.get(
          '127.0.0.1',
          server.port,
          path,
        )).close();
        return (
          response.statusCode,
          response.headers.value('x-user-stack'),
          await utf8.decoder.bind(response).join(),
        );
      }

      expect(await get('/api/users/1'), (
        200,
        'yes',
        jsonEncode({'id': 1, 'name': 'ann'}),
      ));
      expect(await get('/health'), (200, 'yes', 'healthy'));
    });

    test('answers 503 after the application is closed', () async {
      final handler = shelfHandler(app);
      await app.close();

      final response = await handler(
        shelf.Request('GET', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 503);
    });

    test('refuses an application that is not started', () {
      final idle = App(
        root: ConformanceRoot(
          ConformanceProbe(),
          adapter: const ShelfAdapterModule(),
        ),
      );

      expect(() => shelfHandler(idle), throwsA(isA<ApplicationStateError>()));
    });

    Future<App> failingLogApp() => startApp(
      overrides: [
        Singleton<ErrorLog>(
          (_) => const _ThrowingErrorLog(),
          dependsOn: const [],
        ),
      ],
    );

    // A function: a request body can be read only once.
    shelf.Request failRequest() =>
        shelf.Request('GET', Uri.parse('http://localhost/probe/fail'));

    test('answers 500 without a body when the ErrorLog throws', () async {
      final errors = <Object>[];

      final response = await shelfHandler(
        await failingLogApp(),
        onError: (error, _) => errors.add(error),
      )(failRequest());

      expect(response.statusCode, 500);
      expect(await response.readAsString(), isEmpty);
      expect(errors, [isA<StateError>()]);
    });

    test('answers 500 even when its own onError throws', () async {
      final response = await shelfHandler(
        await failingLogApp(),
        onError: (error, _) => throw StateError('reporter failed'),
      )(failRequest());

      expect(response.statusCode, 500);
    });

    test('drops the body of a HEAD response', () async {
      final response = await shelfHandler(app)(
        shelf.Request('HEAD', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['content-length'],
        '${jsonEncode({'id': 1, 'name': 'ann'}).length}',
      );
      expect(await response.readAsString(), isEmpty);
    });
  });
}

/// An error log that fails, to prove the handler survives it.
final class _ThrowingErrorLog implements ErrorLog {
  const _ThrowingErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) =>
      throw StateError('log failed');
}
```

Запустити (очікуваний збій: стара сигнатура приймає `Application`). Реалізація:

Файл `packages/grund_shelf/lib/src/shelf_handler.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'guarded_reporter.dart';
import 'shelf_adapter.dart';
import 'shelf_bridge.dart';

/// A shelf [shelf.Handler] that answers through the `HttpServer` of [app],
/// for embedding a grund application in an existing shelf pipeline.
///
/// Start [app] with `only: const {}`: the graph is built and the routes are
/// prepared, but the application opens no port of its own; the user's shelf
/// server does. The root module of [app] must import `HttpModule` and
/// an adapter module (`ShelfAdapterModule`), because the server depends on
/// `HttpAdapter`. Asking for the handler of an application
/// that is not started throws `ApplicationStateError`; a request after
/// `app.close()` is answered with 503.
///
/// The pipeline stays the user's: the handler changes nothing around it.
/// The application sees paths relative to the shelf `handlerPath`, so it
/// can be mounted under a prefix. [app] is not closed with the server.
/// [onError] receives a failure of the request handler (only possible when
/// the application's own `ErrorLog` throws), answered with a 500 without a
/// body; it defaults to [ShelfAdapter.printError]. A failure of [onError]
/// itself goes to stderr.
///
/// Routing uses the path shelf hands over (`Request.url`). A plain
/// `shelf_io` server derives it from `Host` and the client-controlled
/// `X-Forwarded-Host`; behind it, strip or overwrite those headers. Use
/// `ShelfAdapterModule` to be independent of them.
///
/// ```dart
/// final app = App(root: AppModule());
/// await app.start(only: const {});
/// final handler = const shelf.Pipeline()
///     .addMiddleware(shelf.logRequests())
///     .addHandler(shelfHandler(app));
/// await shelf_io.serve(handler, 'localhost', 8080);
/// ```
shelf.Handler shelfHandler(App app, {ErrorLogger? onError}) {
  final server = app.container.root<HttpServer>();
  return ShelfBridge(
    (request) async => app.isRunning
        ? server.handle(request)
        : HttpResponse(StatusCode.serviceUnavailable),
    onError: GuardedReporter(onError ?? ShelfAdapter.printError).call,
  ).call;
}
```

Файл `packages/grund_shelf/lib/grund_shelf.dart`:

```dart
/// Serves grund applications through shelf: [ShelfAdapter] runs a
/// server, [ShelfAdapterModule] provides it to an application and
/// [shelfHandler] embeds an application in an existing shelf pipeline.
library;

export 'src/shelf_adapter.dart';
export 'src/shelf_adapter_module.dart';
export 'src/shelf_handler.dart';
```

- [ ] **Крок 6: `grund_conformance` на новому API (lib)**

`pubspec.yaml`: `dependencies:` — `grund: ^0.1.0`, `grund_http: ^0.1.0`, `test: ^1.25.0`; `dev_dependencies:` — `lints`. Видалити `lib/src/conformance_app.dart`. Нові й змінені файли `lib/` (повністю):

Файл `packages/grund_conformance/lib/grund_conformance.dart`:

```dart
/// The shared conformance suite for grund `HttpAdapter`s: one users
/// application served on a loopback ephemeral port, run by every adapter
/// package from its own tests. Test support only: it imports
/// `package:test`.
library;

export 'src/adapter_conformance.dart';
export 'src/adapter_under_test.dart';
export 'src/client_response.dart';
export 'src/conformance_data.dart';
export 'src/conformance_module.dart';
export 'src/conformance_probe.dart';
export 'src/conformance_root.dart';
export 'src/conformance_server.dart';
export 'src/raw_http.dart';
export 'src/raw_response.dart';
```
Файл `packages/grund_conformance/lib/src/adapter_conformance.dart`:

```dart
import 'package:test/test.dart';

import 'adapter_under_test.dart';
import 'groups/body_conformance.dart';
import 'groups/lifecycle_conformance.dart';
import 'groups/request_conformance.dart';

/// Entry point of the shared suite: an adapter package calls [run] from a
/// test file.
///
/// ```dart
/// void main() => AdapterConformance.run(
///   'IoAdapter',
///   (onError, closeTimeout) => AdapterUnderTest.of<IoAdapter>(
///     IoAdapterModule(onError: onError, closeTimeout: closeTimeout),
///     port: (adapter) => adapter.port,
///   ),
/// );
/// ```
abstract final class AdapterConformance {
  /// Registers every conformance group for the adapters [factory] creates,
  /// inside a group called [name].
  static void run(String name, AdapterFactory factory) {
    group('$name conformance', () {
      RequestConformance.register(factory);
      BodyConformance.register(factory);
      LifecycleConformance.register(factory);
    });
  }
}
```
Файл `packages/grund_conformance/lib/src/adapter_under_test.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Creates the adapter under test; [onError] receives the failures the
/// adapter reports itself (a throwing handler, a failing body stream), and
/// [closeTimeout] is the adapter's limit for a graceful close (`null`: no
/// limit).
typedef AdapterFactory =
    AdapterUnderTest Function(ErrorLogger onError, Duration? closeTimeout);

/// The module of an adapter for the conformance suite and how to read the
/// port it bound; the suite always listens on port 0.
final class AdapterUnderTest {
  /// Wraps [module]; [portOf] reads the port from the adapter the module
  /// binds, once `listen` completed.
  const AdapterUnderTest(this.module, {required this.portOf});

  /// Wraps [module], which binds an adapter of type [A]; [port] reads its
  /// port.
  static AdapterUnderTest of<A extends HttpAdapter>(
    Module module, {
    required int Function(A adapter) port,
  }) => AdapterUnderTest(
    module,
    portOf: (adapter) => switch (adapter) {
      final A typed => port(typed),
      _ => throw StateError('The module bound $adapter, not an $A.'),
    },
  );

  /// The global module that binds the `HttpAdapter`.
  final Module module;

  /// The port the adapter listens on.
  final int Function(HttpAdapter adapter) portOf;
}
```
Файл `packages/grund_conformance/lib/src/conformance_users.dart`:

```dart
import 'package:grund_http/grund_http.dart';

/// In-memory users of the conformance application.
final class ConformanceUsers {
  final Map<int, String> _names = {1: 'ann', 2: 'bob'};

  /// The user with [id] as JSON; [NotFoundException] when absent.
  Map<String, Object?> find(int id) => switch (_names[id]) {
    final name? => {'id': id, 'name': name},
    null => throw NotFoundException(message: 'No user $id'),
  };

  /// Adds a user called [name] and returns it as JSON.
  Map<String, Object?> create(String name) {
    final id = _names.length + 1;
    _names[id] = name;
    return find(id);
  }
}
```
Файл `packages/grund_conformance/lib/src/users_api.dart`:

```dart
import 'package:grund_http/grund_http.dart';

import 'conformance_users.dart';

/// `GET /users/:id` and `POST /users` (`{"name"}` answers 201 with a
/// `location` header).
final class UsersApi extends HttpApi {
  /// Creates the API over [_users].
  UsersApi(super.injector, this._users);

  final ConformanceUsers _users;

  @override
  String get path => '/users';

  @override
  List<Route> get routes => [
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post('/', _create, status: StatusCode.created),
  ];

  Future<Map<String, Object?>> _create(HttpCtx c) async {
    final name = await c.body(
      (json) => switch (json) {
        {'name': final String name} => name,
        _ => throw const FormatException('"name" must be a string'),
      },
    );
    final user = _users.create(name);
    c.response.headers.set('location', '/users/${user['id']}');
    return user;
  }
}
```
Файл `packages/grund_conformance/lib/src/probe_handlers.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';

/// Handlers of the probe routes that do not fit in one expression.
abstract final class ProbeHandlers {
  /// The request as JSON: method, path, raw query, every header value, the
  /// body as text and the client address.
  static Future<Map<String, Object?>> echo(HttpCtx c) async {
    final request = c.request;
    return {
      'method': request.method,
      'path': request.uri.path,
      'query': request.uri.query,
      'headers': {
        for (final name in request.headers.names)
          name: request.headers.all(name),
      },
      'body': await request.body.text(),
      'remoteAddress': request.connectionInfo?.remoteAddress,
      'remotePort': request.connectionInfo?.remotePort,
    };
  }

  /// Streams the request body; answers its length and checksum.
  static Future<Map<String, Object?>> upload(
    ConformanceProbe probe,
    HttpCtx c,
  ) async {
    var length = 0;
    var checksum = 0;
    await for (final chunk in c.request.body.stream) {
      if (!probe.firstUploadChunk.isCompleted) {
        probe.firstUploadChunk.complete();
      }
      length += chunk.length;
      checksum = (checksum + ConformanceData.checksum(chunk)) % 65521;
    }
    return {'length': length, 'checksum': checksum};
  }

  /// `first;`, then waits for the probe's release, then `last`.
  static Stream<List<int>> gated(ConformanceProbe probe) async* {
    yield utf8.encode('first;');
    probe.entered.complete();
    await probe.release.future;
    yield utf8.encode('last');
  }

  /// One chunk, then a failure.
  static Stream<List<int>> broken() async* {
    yield utf8.encode('partial');
    // Gives the adapter time to flush the first chunk before the failure.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('broken body stream');
  }

  /// A response with repeated `set-cookie` and `x-multi` headers.
  static HttpResponse cookies() => HttpResponse.text(
    'cookies',
    headers: HeaderMap()
      ..add('set-cookie', 'a=1')
      ..add('set-cookie', 'b=2')
      ..add('x-multi', 'one')
      ..add('x-multi', 'two'),
  );
}
```
Файл `packages/grund_conformance/lib/src/probe_api.dart`:

```dart
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';
import 'probe_handlers.dart';

/// The `/probe` routes: they expose what the adapter delivered and produce
/// the responses that stress it.
///
/// - `GET|POST|PUT|PATCH|DELETE /probe/echo`: method, path, raw query,
///   every header value, the body as text and the client address.
/// - `GET /probe/segments/:value`: the decoded path parameter.
/// - `POST /probe/upload`: streams the body; answers its length and
///   checksum.
/// - `GET /probe/download?size=n` (streamed) and
///   `GET /probe/download-fixed?size=n` (in memory): [ConformanceData].
/// - `GET /probe/gated-stream`, `GET /probe/slow`, `GET /probe/endless`:
///   wait for or report through the [ConformanceProbe].
/// - `GET /probe/broken-stream`: a body stream that fails after a chunk.
/// - `GET /probe/cookies`, `/probe/framing`, `/probe/close-connection`,
///   `/probe/empty`, `/probe/fail`: header and error edge cases.
/// - `GET /probe/bad-header`, `/probe/bad-length`: responses whose head
///   cannot be written.
final class ProbeApi extends HttpApi {
  /// Creates the API over [_probe].
  ProbeApi(super.injector, this._probe);

  final ConformanceProbe _probe;

  @override
  String get path => '/probe';

  @override
  List<Route> get routes => [
    ..._echoRoutes,
    ..._streamRoutes,
    ..._headerRoutes,
    ..._failureRoutes,
  ];

  List<Route> get _echoRoutes => [
    Route.get('/echo', ProbeHandlers.echo),
    Route.post('/echo', ProbeHandlers.echo),
    Route.put('/echo', ProbeHandlers.echo),
    Route.patch('/echo', ProbeHandlers.echo),
    Route.delete('/echo', ProbeHandlers.echo),
    Route.get('/segments/:value', (c) => {'value': c.path.string('value')}),
  ];

  List<Route> get _streamRoutes => [
    Route.post('/upload', (c) => ProbeHandlers.upload(_probe, c)),
    Route.get(
      '/download',
      (c) =>
          HttpResponse.stream(ConformanceData.chunks(c.query.integer('size'))),
    ),
    Route.get(
      '/download-fixed',
      (c) => HttpResponse.bytes(ConformanceData.bytes(c.query.integer('size'))),
    ),
    Route.get(
      '/gated-stream',
      (_) => HttpResponse.stream(ProbeHandlers.gated(_probe)),
    ),
    Route.get('/slow', (_) async {
      _probe.entered.complete();
      await _probe.release.future;
      return 'done';
    }),
    Route.get(
      '/endless',
      (_) => HttpResponse.stream(
        ConformanceData.endless(_probe.endlessCancelled.complete),
      ),
    ),
  ];

  List<Route> get _headerRoutes => [
    Route.get('/cookies', (_) => ProbeHandlers.cookies()),
    Route.get(
      '/framing',
      (_) => HttpResponse.text(
        'framed',
        headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
      ),
    ),
    Route.get(
      '/close-connection',
      (_) => HttpResponse.text(
        'bye',
        headers: HeaderMap.of({'connection': 'close'}),
      ),
    ),
    Route.get('/empty', (_) => null),
  ];

  List<Route> get _failureRoutes => [
    Route.get(
      '/broken-stream',
      (_) => HttpResponse.stream(ProbeHandlers.broken()),
    ),
    Route.get(
      '/bad-header',
      (_) => HttpResponse.text(
        'x',
        headers: HeaderMap.of({'x-bad': 'one\r\ntwo'}),
      ),
    ),
    Route.get(
      '/bad-length',
      (_) => HttpResponse.stream(
        Stream.value(utf8.encode('x')),
        headers: HeaderMap.of({'content-length': 'abc'}),
      ),
    ),
    Route.get('/fail', (_) => throw StateError('handler failure')),
  ];
}
```
Файл `packages/grund_conformance/lib/src/conformance_module.dart`:

```dart
import 'package:grund/grund.dart';

import 'conformance_probe.dart';
import 'conformance_users.dart';
import 'probe_api.dart';
import 'users_api.dart';

/// The application every adapter serves in the conformance suite: a small
/// users API plus `/probe` routes that expose what the adapter delivered.
///
/// The module needs an `HttpModule` and an adapter module next to it; see
/// `ConformanceRoot`. [UsersApi] and [ProbeApi] describe the routes.
final class ConformanceModule extends Module {
  /// Creates the module around the [probe] the test holds.
  const ConformanceModule(this.probe);

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ConformanceProbe>((_) => probe, dependsOn: const []),
    Singleton<ConformanceUsers>((_) => ConformanceUsers(), dependsOn: const []),
    Singleton<UsersApi>(
      (i) => UsersApi(i, i<ConformanceUsers>()),
      dependsOn: const [Key<ConformanceUsers>()],
    ),
    Singleton<ProbeApi>(
      (i) => ProbeApi(i, i<ConformanceProbe>()),
      dependsOn: const [Key<ConformanceProbe>()],
    ),
  ];
}
```
Файл `packages/grund_conformance/lib/src/conformance_root.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'conformance_module.dart';
import 'conformance_probe.dart';

/// The root module of the conformance application: `HttpModule` on a
/// loopback ([port], by default an ephemeral one), the [adapter] under test and the
/// [ConformanceModule].
final class ConformanceRoot extends Module {
  /// Creates the root around [probe]; [adapter] is the module of the
  /// adapter under test (`HttpModule` needs one, even when the application
  /// is only started with `only: const {}`).
  const ConformanceRoot(this.probe, {required this.adapter, this.port = 0});

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  /// The module that binds the `HttpAdapter` under test.
  final Module adapter;

  /// The port `HttpModule` listens on; 0 picks a free one.
  final int port;

  @override
  List<Module> get imports => [
    HttpModule(
      config: HttpConfig(address: '127.0.0.1', port: port),
    ),
    adapter,
    ConformanceModule(probe),
  ];
}
```
Файл `packages/grund_conformance/lib/src/conformance_server.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_under_test.dart';
import 'client_response.dart';
import 'conformance_probe.dart';
import 'conformance_root.dart';

/// The conformance application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the first error the
/// adapter reported.
final class ConformanceServer {
  ConformanceServer._(
    this.app,
    this.adapter,
    this.port,
    this.probe,
    this._errors,
  );

  /// The adapter's `closeTimeout` unless a test sets one: longer than any
  /// wait in the suite, so only the timeout tests reach it.
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// Starts the application with the adapter from [factory] and listens.
  /// [errorLog] replaces the recording `ErrorLog` of the application (to
  /// test one that throws); [closeTimeout] goes to the adapter.
  static Future<ConformanceServer> start(
    AdapterFactory factory, {
    ErrorLog? errorLog,
    Duration? closeTimeout = defaultCloseTimeout,
  }) async {
    final probe = ConformanceProbe();
    final errors = _ReportedErrors();
    final underTest = factory(errors.adapter, closeTimeout);
    final app = App(
      root: ConformanceRoot(probe, adapter: underTest.module),
      overrides: [
        Singleton<ErrorLog>(
          (_) => errorLog ?? errors.application,
          dependsOn: const [],
        ),
      ],
    );
    await app.start();
    final adapter = app.container.root<HttpAdapter>();
    return ConformanceServer._(
      app,
      adapter,
      underTest.portOf(adapter),
      probe,
      errors,
    );
  }

  /// The served application.
  final App app;

  /// The adapter under test, as the application resolved it.
  final HttpAdapter adapter;

  /// The port the adapter bound.
  final int port;

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  final _ReportedErrors _errors;

  /// A client with at most one connection, so keep-alive reuse is visible.
  final HttpClient client = HttpClient()..maxConnectionsPerHost = 1;

  /// Completes with the first error the adapter reports.
  Future<Object> get firstAdapterError => _errors.firstFromAdapter.future;

  /// `http://127.0.0.1:port` + [target].
  Uri uri(String target) => Uri.parse('http://127.0.0.1:$port$target');

  /// Sends [method] to [target] with [headers] and [body]; reads the whole
  /// response.
  Future<ClientResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, uri(target));
    headers.forEach(request.headers.add);
    if (body != null) request.add(body);
    return ClientResponse.read(await request.close());
  }

  /// Closes the client, the adapter (forcefully, so a test that failed
  /// midway does not hang the suite) and the application, and releases
  /// waiting handlers.
  Future<void> close() async {
    if (!probe.release.isCompleted) probe.release.complete();
    client.close(force: true);
    await adapter.close(force: true);
    await app.close();
  }
}

/// Records the first adapter error and silences the application log.
final class _ReportedErrors {
  final Completer<Object> firstFromAdapter = Completer<Object>();

  void adapter(Object error, StackTrace _) {
    if (!firstFromAdapter.isCompleted) firstFromAdapter.complete(error);
  }

  /// Silences the application log: 500s are expected in the suite.
  ErrorLog get application => const _SilentErrorLog();
}

final class _SilentErrorLog implements ErrorLog {
  const _SilentErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) {}
}
```

- [ ] **Крок 7: групи conformance (RF-3, RF-4, RF-5) і тести пакета**

Зміни проти v1: 404 — `application/problem+json` з `status: 404` (RF-3); «force close» викликає `adapter.close(force: true)` (в `App.close` немає `force`); виняток логера — `ErrorLog`, що кидає; невдалий bind — `RunnerError` із `SocketException`, `app.isClosed`, наступний застосунок працює (RF-4); `close` під навантаженням (RF-5) — у `lifecycle_conformance.dart`.

Файл `packages/grund_conformance/lib/src/groups/request_conformance.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Requests reach the application as `HttpRequest`s that match what the
/// client sent: method, target, headers, body and connection details.
abstract final class RequestConformance {
  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('requests', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('serves the users app', () async {
        final found = await server.send('GET', '/users/1');
        final created = await server.send(
          'POST',
          '/users',
          headers: {'content-type': 'application/json'},
          body: utf8.encode(jsonEncode({'name': 'cid'})),
        );
        final missing = await server.send('GET', '/users/9');

        // Separate checks: a record compares a Map inside it by identity.
        expect(found.status, 200);
        expect(found.json, {'id': 1, 'name': 'ann'});
        expect(
          (created.status, created.headers.value('location')),
          (201, '/users/3'),
        );
        expect(missing.status, 404);
        expect(
          missing.headers.contentType?.mimeType,
          'application/problem+json',
        );
        expect(missing.json, containsPair('status', 404));
      });

      test('passes every method upper-cased', () async {
        for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
          final response = await server.send(method, '/probe/echo');

          expect((response.json as Map)['method'], method);
        }
      });

      test('keeps the raw query', () async {
        final response = await server.send('GET', '/probe/echo?b=%20x&a=1&a=2');

        expect((response.json as Map)['query'], 'b=%20x&a=1&a=2');
      });

      test('removes dot segments from the target', () async {
        for (final target in ['/probe/../users/1', '/users/./1']) {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', target),
          );

          expect(response.json, {'id': 1, 'name': 'ann'}, reason: target);
        }
      });

      // Review Focus 3: dart:io parses `//users` as an authority.
      test('reads a target that starts with // as a path', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '//users//1'),
        );

        expect(response.json, {'id': 1, 'name': 'ann'});
      });

      // The client controls X-Forwarded-*: they must not change the route.
      test(
        'routes on the target despite X-Forwarded-Host and -Proto',
        () async {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head(
              'GET',
              '/users/1',
              headers: {
                'X-Forwarded-Host': 'x/admin',
                'X-Forwarded-Proto': 'https',
                'Connection': 'close',
              },
            ),
          );

          expect(response.status, 200);
          expect(response.json, {'id': 1, 'name': 'ann'});
        },
      );

      test('keeps %2F inside one path segment', () async {
        final response = await server.send('GET', '/probe/segments/a%2Fb');

        expect(response.json, {'value': 'a/b'});
      });

      test('answers 400 to invalid percent-encoded UTF-8', () async {
        final response = await server.send('GET', '/probe/segments/%FF');

        expect(response.status, 400);
      });

      test('passes multi-valued headers case-insensitively', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head(
            'GET',
            '/probe/echo',
            headers: {
              'X-Multi': 'a',
              'x-multi': 'b',
              'X-CASE': 'Value',
              'Connection': 'close',
            },
          ),
        );
        final headers = (response.json as Map)['headers'] as Map;

        expect(headers['x-multi'], ['a', 'b']);
        expect(headers['x-case'], ['Value']);
      });

      test('sends every set-cookie and repeated header value', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/cookies'),
        );

        expect(response.headers.all('set-cookie'), ['a=1', 'b=2']);
        expect(response.headers.all('x-multi').join(', '), 'one, two');
      });

      test('reports the client address and port', () async {
        final response = await server.send('GET', '/probe/echo');
        final echo = response.json as Map;

        expect(echo['remoteAddress'], '127.0.0.1');
        expect(echo['remotePort'], response.localPort);
      });

      test('reuses a keep-alive connection', () async {
        final ports = [
          for (var i = 0; i < 3; i++)
            (await server.send('GET', '/probe/echo')).localPort,
        ];

        expect(ports.toSet(), hasLength(1));
      });

      test('answers pipelined requests in order', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/echo?n=1', headers: const {}) +
              RawHttp.head('GET', '/probe/echo?n=2'),
        );
        final text = latin1.decode(response.bytes);

        expect('HTTP/1.1 200'.allMatches(text), hasLength(2));
        expect(text.indexOf('n=1'), lessThan(text.indexOf('n=2')));
      });

      test('de-chunks the request body and drops transfer-encoding', () async {
        final head = RawHttp.head(
          'POST',
          '/probe/echo',
          headers: {'Transfer-Encoding': 'chunked', 'Connection': 'close'},
        );
        final response = await RawHttp.exchange(
          server.port,
          '${head}5\r\nhello\r\n0\r\n\r\n',
        );
        final echo = response.json as Map;

        expect(echo['body'], 'hello');
        expect(echo['headers'] as Map, isNot(contains('transfer-encoding')));
      });

      test('adds no default headers of the server library', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/empty'),
        );

        expect(response.status, 204);
        expect(response.headers.contains('content-type'), isFalse);
        expect(response.headers.contains('x-frame-options'), isFalse);
        expect(response.headers.contains('x-powered-by'), isFalse);
      });
    });
  }
}
```
Файл `packages/grund_conformance/lib/src/groups/lifecycle_conformance.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_probe.dart';
import '../conformance_root.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Closing, failures and misbehaving clients: the adapter finishes or
/// drops in-flight work as asked, releases its port, and keeps serving
/// after anything a single request does.
abstract final class LifecycleConformance {
  /// How long a test waits for a step the adapter must make on its own.
  static const stepTimeout = Duration(seconds: 5);

  /// How long a test watches that something does not happen.
  static const settle = Duration(milliseconds: 200);

  /// The adapter's `closeTimeout` in the tests that let it expire.
  static const shortCloseTimeout = Duration(milliseconds: 250);

  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('lifecycle', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      // Replaces the server with one whose adapter has [closeTimeout].
      Future<void> restart({
        Duration? closeTimeout = ConformanceServer.defaultCloseTimeout,
        ErrorLog? errorLog,
      }) async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          closeTimeout: closeTimeout,
          errorLog: errorLog,
        );
      }

      Future<void> expectPortFree() async {
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        await rebound.close();
      }

      // Holds a slow request, checks close waits for it, then lets it end.
      Future<void> expectCloseWaitsForSlowHandler() async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      }

      test('close waits for a response that is still streaming', () async {
        final request = await server.client.get(
          '127.0.0.1',
          server.port,
          '/probe/gated-stream',
        );
        final response = await request.close().timeout(stepTimeout);
        final body = utf8.decoder.bind(response).join();
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect(await body, 'first;last');
        await closing.timeout(stepTimeout);
      });

      test('close waits for a slow handler', () async {
        await expectCloseWaitsForSlowHandler();
      });

      test('close refuses new connections and releases the port', () async {
        await server.app.close().timeout(stepTimeout);

        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, server.port),
          throwsA(isA<SocketException>()),
        );
        await expectPortFree();
      });

      test('force close drops a request in flight', () async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);

        await server.adapter.close(force: true).timeout(stepTimeout);

        await expectLater(response, throwsA(isA<IOException>()));
      });

      // Review Focus 6: the adapter drops the connection after the timeout
      // and App.close does not wait for the abandoned handler.
      test('close gives up on a stuck handler after closeTimeout', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final stopwatch = Stopwatch()..start();

        await server.app.close().timeout(stepTimeout);

        expect(stopwatch.elapsed, greaterThan(shortCloseTimeout ~/ 2));
        await expectLater(response, throwsA(isA<IOException>()));
        await expectPortFree();
      });

      test('close cuts a streaming response after closeTimeout', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final streamed = RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/gated-stream'),
        );
        await server.probe.entered.future.timeout(stepTimeout);

        await server.app.close().timeout(stepTimeout);

        final response = await streamed;
        expect((response.status, response.isComplete), (200, false));
      });

      test('close lets a handler that finishes in time answer', () async {
        await restart(closeTimeout: shortCloseTimeout);
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final closing = server.app.close();

        server.probe.release.complete();

        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      });

      test('close without a closeTimeout waits for a slow handler', () async {
        await restart(closeTimeout: null);
        await expectCloseWaitsForSlowHandler();
      });

      test('answers 500 without a body when the ErrorLog throws', () async {
        await restart(errorLog: const _ThrowingErrorLog());

        final failed = await server.send('GET', '/probe/fail');
        final next = await server.send('GET', '/users/1');

        expect(failed.status, 500);
        expect(failed.bytes, isEmpty);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      test('aborts the connection when the body stream fails', () async {
        final broken = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/broken-stream'),
        );
        final next = await server.send('GET', '/users/1');

        expect(broken.isComplete, isFalse);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      test('close completes after a body stream failed', () async {
        await restart(closeTimeout: null);
        await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/broken-stream'),
        );
        await server.firstAdapterError.timeout(stepTimeout);

        await server.app.close().timeout(stepTimeout);
      });

      for (final route in const ['bad-header', 'bad-length']) {
        test('a response whose head cannot be written is reported and the '
            'connection closes ($route)', () async {
          // The client sees the connection closed, with or without a head.
          await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', '/probe/$route'),
          );
          await server.firstAdapterError.timeout(stepTimeout);
          await server.app.close().timeout(stepTimeout);
          await expectLater(
            Socket.connect(InternetAddress.loopbackIPv4, server.port),
            throwsA(isA<SocketException>()),
          );
        });
      }

      test(
        'a failed bind fails the start; another application serves',
        () async {
          final blocker = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(blocker.close);
          final app = App(
            root: ConformanceRoot(
              ConformanceProbe(),
              adapter: factory((_, _) {}, null).module,
              port: blocker.port,
            ),
          );

          await expectLater(
            app.start(),
            throwsA(
              isA<RunnerError>().having(
                (error) => error.error,
                'error',
                isA<SocketException>(),
              ),
            ),
          );
          final next = await ConformanceServer.start(factory);
          addTearDown(next.close);

          expect(app.isClosed, isTrue);
          expect((await next.send('GET', '/users/1')).status, 200);
        },
      );

      // Review Focus 4: the stream is cancelled and close is not stuck.
      test('survives a client that leaves mid-response', () async {
        await RawHttp.abortAfterFirstBytes(
          server.port,
          RawHttp.head('GET', '/probe/endless'),
        );

        await server.probe.endlessCancelled.future.timeout(stepTimeout);
        expect((await server.send('GET', '/users/1')).status, 200);
        await server.app.close().timeout(stepTimeout);
      });
    });
  }
}

/// An error log that fails, to prove the adapter survives it.
final class _ThrowingErrorLog implements ErrorLog {
  const _ThrowingErrorLog();

  @override
  void report(Object error, StackTrace stackTrace) =>
      throw StateError('log failed');
}
```
Файл `packages/grund_conformance/test/helpers/no_socket_adapter_module.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Binds an `HttpAdapter` that never opens a socket: for tests that start
/// the application with `only: const {}` and call the server directly.
final class NoSocketAdapterModule extends Module {
  /// Creates the module.
  const NoSocketAdapterModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((_) => _NoSocketAdapter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}

final class _NoSocketAdapter implements HttpAdapter {
  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) => throw StateError('This adapter opens no socket.');

  @override
  Future<void> close({bool force = false}) async {}
}
```
Файл `packages/grund_conformance/test/conformance_app_test.dart`:

```dart
import 'dart:convert';

import 'package:grund/testing.dart';
import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';

import 'helpers/no_socket_adapter_module.dart';

void main() {
  group('ConformanceRoot', () {
    late ConformanceProbe probe; // Set in setUp before every test.
    late TestApp app; // Set in setUp before every test.
    late HttpServer server; // Set in setUp before every test.
    late TestClient client; // Set in setUp before every test.

    setUp(() async {
      probe = ConformanceProbe();
      app = await TestApp.start(
        root: ConformanceRoot(probe, adapter: const NoSocketAdapterModule()),
      );
      server = app<HttpServer>();
      client = TestClient(server);
    });
    tearDown(() => app.close());

    test('serves the users API', () async {
      final created = await client.post('/users', json: {'name': 'cid'});

      expect((await client.get('/users/1')).json, {'id': 1, 'name': 'ann'});
      expect((created.status, created.headers['location']), (201, '/users/3'));
      final missing = await client.get('/users/9');
      expect(missing.status, 404);
      expect(
        missing.headers['content-type'],
        startsWith('application/problem+json'),
      );
    });

    test('echoes the request', () async {
      final response = await client.request(
        'PUT',
        '/probe/echo?b=%20x',
        body: 'hi',
        headers: {'X-Multi': 'a'},
      );

      expect(response.json, {
        'method': 'PUT',
        'path': '/probe/echo',
        'query': 'b=%20x',
        'headers': {
          'x-multi': ['a'],
        },
        'body': 'hi',
        'remoteAddress': null,
        'remotePort': null,
      });
    });

    test('streams an upload and reports its length and checksum', () async {
      final response = await client.send(
        HttpRequest(
          method: 'POST',
          uri: Uri.parse('/probe/upload'),
          body: RequestBody(ConformanceData.chunks(200000)),
        ),
      );

      expect(response.json, {
        'length': 200000,
        'checksum': ConformanceData.checksum(ConformanceData.bytes(200000)),
      });
      expect(probe.firstUploadChunk.isCompleted, isTrue);
    });

    test('downloads the payload streamed and in memory', () async {
      final streamed = await client.get('/probe/download?size=100000');
      final fixed = await client.get('/probe/download-fixed?size=100000');

      expect(streamed.bytes, ConformanceData.bytes(100000));
      expect(fixed.bytes, ConformanceData.bytes(100000));
    });

    test('holds the gated stream until the probe releases it', () async {
      final response = await server.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/gated-stream')),
      );
      final body = response.body.readAll();

      await probe.entered.future;
      probe.release.complete();

      expect(utf8.decode(await body), 'first;last');
    });

    test('reports when the endless stream is cancelled', () async {
      final response = await server.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/endless')),
      );
      final subscription = switch (response.body) {
        StreamBody(:final stream) => stream.listen(null),
        BytesBody() => fail('expected a stream body'),
      };

      await subscription.cancel();

      expect(probe.endlessCancelled.isCompleted, isTrue);
    });

    test('fails the broken stream after one chunk', () async {
      final response = await server.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/broken-stream')),
      );

      await expectLater(response.body.readAll(), throwsStateError);
    });

    test('sends repeated headers and framing edge cases', () async {
      final cookies = await client.get('/probe/cookies');

      expect(cookies.headers.all('set-cookie'), ['a=1', 'b=2']);
      expect(cookies.headers.all('x-multi'), ['one', 'two']);
      expect(
        (await client.get('/probe/framing')).headers['transfer-encoding'],
        'chunked',
      );
      expect((await client.get('/probe/empty')).status, 204);
      expect((await client.get('/probe/fail')).status, 500);
    });
  });
}
```

(`body_conformance.dart`, `raw_*`, `client_response.dart`, `conformance_data.dart`, `conformance_probe.dart` не змінюються.)

- [ ] **Крок 8: conformance-тести адаптерів і приклади**

Файл `packages/grund_io/test/io_adapter_conformance_test.dart`:

```dart
import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_io/grund_io.dart';

void main() => AdapterConformance.run(
  'IoAdapter',
  (onError, closeTimeout) => AdapterUnderTest.of<IoAdapter>(
    IoAdapterModule(onError: onError, closeTimeout: closeTimeout),
    port: (adapter) => adapter.port,
  ),
);
```
Файл `packages/grund_shelf/test/shelf_adapter_conformance_test.dart`:

```dart
import 'package:grund_conformance/grund_conformance.dart';
import 'package:grund_shelf/grund_shelf.dart';

void main() => AdapterConformance.run(
  'ShelfAdapter',
  (onError, closeTimeout) => AdapterUnderTest.of<ShelfAdapter>(
    ShelfAdapterModule(onError: onError, closeTimeout: closeTimeout),
    port: (adapter) => adapter.port,
  ),
);
```
Файл `packages/grund_io/example/grund_io_example.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingApi extends HttpApi {
  /// Creates the API.
  PingApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/ping', (_) => 'pong'),
    Route.get(
      '/count',
      // One chunk per line, sent without buffering.
      (_) => Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n')),
    ),
  ];
}

/// The root module: the HTTP server on [port], the `dart:io` adapter and
/// [PingApi].
final class AppModule extends Module {
  /// Creates the module; port 0 picks a free port.
  const AppModule({this.port = 8080});

  /// The port the server listens on.
  final int port;

  @override
  List<Module> get imports => [
    HttpModule(
      config: HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
    ),
    const IoAdapterModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<PingApi>(PingApi.new, dependsOn: const []),
  ];
}

/// Serves [AppModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server is `App(root: AppModule()).run()`: it stops on SIGINT and
/// SIGTERM.
Future<String> run() async {
  final app = App(root: const AppModule(port: 0));
  await app.start();
  final client = HttpClient();
  try {
    final port = switch (app.container.root<HttpAdapter>()) {
      IoAdapter(:final port) => port,
      final other => throw StateError('Unexpected adapter $other.'),
    };
    final uri = Uri.http('127.0.0.1:$port', '/count');
    final response = await (await client.getUrl(uri)).close();
    return await utf8.decodeStream(response);
  } finally {
    client.close();
    await app.close();
  }
}

/// Prints what [run] received.
Future<void> main() async => stdout.write(await run());
```
Файл `packages/grund_shelf/example/grund_shelf_example.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_shelf/grund_shelf.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingApi extends HttpApi {
  /// Creates the API.
  PingApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/ping', (_) => 'pong'),
    Route.get(
      '/count',
      // One chunk per line, sent without buffering.
      (_) => Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n')),
    ),
  ];
}

/// The root module: the HTTP server on [port], the shelf adapter and
/// [PingApi].
final class AppModule extends Module {
  /// Creates the module; port 0 picks a free port.
  const AppModule({this.port = 8080});

  /// The port the server listens on.
  final int port;

  @override
  List<Module> get imports => [
    HttpModule(
      config: HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
    ),
    const ShelfAdapterModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<PingApi>(PingApi.new, dependsOn: const []),
  ];
}

/// Serves [AppModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server is `App(root: AppModule()).run()`: it stops on SIGINT and
/// SIGTERM.
Future<String> run() async {
  final app = App(root: const AppModule(port: 0));
  await app.start();
  final client = HttpClient();
  try {
    final port = switch (app.container.root<HttpAdapter>()) {
      ShelfAdapter(:final port) => port,
      final other => throw StateError('Unexpected adapter $other.'),
    };
    final uri = Uri.http('127.0.0.1:$port', '/count');
    final response = await (await client.getUrl(uri)).close();
    return await utf8.decodeStream(response);
  } finally {
    client.close();
    await app.close();
  }
}

/// Prints what [run] received.
Future<void> main() async => stdout.write(await run());
```

- [ ] **Крок 9: перевірка і коміти**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
dart pub get
for p in grund_conformance grund_io grund_shelf; do (cd packages/$p && dart analyze && dart test); done
wc -l packages/grund_conformance/lib/src/groups/*.dart packages/grund_shelf/lib/src/*.dart packages/grund_io/lib/src/*.dart
```

Очікування: `No issues found!`; тести зелені (на прототипі проти реального `proto/http`: conformance 14, io 52, shelf 74); кожен файл `lib/` <= 300 рядків (найбільший `lifecycle_conformance.dart`, 273; `register`-методи груп звільнені від ліміту методу за CLAUDE.md). Коміти: `feat(io): IoAdapterModule on grund_http`, `feat(shelf): ShelfAdapterModule and shelfHandler(App)`, `refactor(conformance): conformance app on the new API`.

**Review Focus цієї задачі:** RF-3 (404 `problem+json` у `request_conformance`), RF-4 (збій bind -> `RunnerError(SocketException)`, застосунок закритий, наступний стартує; `shelfHandler` на нестартованому `App` -> `ApplicationStateError`), RF-5 (`close` чекає in-flight, `closeTimeout`, `force`, повторний `close`).

## Частина C: задачі 13–18 (анотації та генератор)

> **Як перевірено.** Задачі 13–18 виконано послідовно в копії `/tmp/.../scratchpad/repo_c` (коміти `78e2739`, `3b823f8`, `868eedd`, `6876f8f`, `a210a35`, `00b6c5d`, `9e73efa`, `dd1d387`; між ними лише scaffold-коміти з прототипами ядра й `grund_http`). Блоки «файл цілком» нижче згенеровано скриптом `parts/build_c.py` з `git show <коміт>:<шлях>`, тобто вони збігаються з перевіреним кодом байт-в-байт. Результат: `grund_annotations` 7 тестів; `grund_generator` `dart analyze` чистий, 142 тести зелені, з них 11 — e2e/еквівалентність у fixture `users_app`; згенерований `users_app.grund.dart` **компілюється й працює** проти `S/proto/core` (пакет `grund`, 166 тестів) і `S/proto/http` (пакет `grund_http`, 206 тестів): відповіді через `TestClient` збігаються з рукописною явною формою.

**Угоди частини C.**

- Блок з підписом `**\`шлях\`**` — повний вміст файла (створити або замінити цілком); шляхи від кореня репозиторію. Файли, що видаляються, дано списком `git rm`.
- У кожній задачі порядок кроків: спочатку створити/замінити файли тестів і fixture-ів (тести падають або не компілюються), потім файли `lib/`, потім запуск (зелено), format/analyze, коміт.
- Fixture-пакети `cases_app` і `users_app` залежать від `grund`, `grund_annotations`, `grund_http` (`grund_http: ^0.1.0` додати в їхні `pubspec.yaml` і в `workspace` кореневого `pubspec.yaml`, якщо частина B ще цього не зробила). Задачі 13–15 у прототипі збиралися проти заглушки `grund_http`; задачі 16–18 — проти справжніх прототипів ядра й HTTP. Dev-залежність `build_runner` (і `build.yaml` для `grund_build`) у `users_app` повертає задача 19; у прототипі її немає, бо `grund_build` вилучено з копії.
- Модулі у `cases_app` свідомо НЕ мають `with $X` (немає згенерованого файла), щоб fixture компілювався; `users_app` має `with $X` і golden.
- Пакети `grund_cli`, `grund_build`, `grund_io`, `grund_shelf`, `example` у цій частині червоні/не збираються за задумом (їх переносить частина D, задача 19+). Ліміти: файл ≤300, тест ≤500, метод ≤40, вкладеність ≤3; перевірено `parts/lint_limits.py`.

---

### Задача 13: `grund_annotations` — нова модель анотацій

**Мета.** Замінити анотації v1 (`Controller`, `Param`, `Inject`, `Value`, `RouteMetadata`, `UseGuards…`) анотаціями узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17).

**Files.**
- Create: `packages/grund_annotations/lib/src/{scope,provides,named,api,validator_annotation}.dart`
- Modify: `module.dart`, `injectable.dart`, `bind.dart`, `route_annotation.dart`, `parameter_annotation.dart`, `lib/grund_annotations.dart`, `test/annotations_test.dart`
- Delete: `argument_annotation, controller, inject, route_metadata, use_components, value` (`.dart`)

**Interfaces.** Produces: `Scope {singleton, call, transient}`; `Module({imports, providers, exports, global = false})`; `Injectable({scope})`; `Provides({scope})`; `Bind<I extends Object, C extends I>()`; `Named(name)`; `Api(path, {use})`; `Get/Post/Put/Patch/Delete(path, {status, use})` (шлях — обов'язковий позиційний, бо Dart не допускає необов'язкових позиційних разом з іменованими); `Path/Query/Header/Cookie({name})`, `Body()`; `Range`, `Length`, `Pattern`, `OneOf`.

- [ ] **Крок 1: тест і файли.**

**Видалити** (`git rm`):

```bash
git rm -q \
  packages/grund_annotations/lib/src/argument_annotation.dart \
  packages/grund_annotations/lib/src/controller.dart \
  packages/grund_annotations/lib/src/inject.dart \
  packages/grund_annotations/lib/src/route_metadata.dart \
  packages/grund_annotations/lib/src/use_components.dart \
  packages/grund_annotations/lib/src/value.dart
```

**`packages/grund_annotations/test/annotations_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_annotations/grund_annotations.dart';
import 'package:test/test.dart';

void main() {
  test('Module defaults to an empty, non-global module', () {
    const module = Module();

    expect(module.imports, isEmpty);
    expect(module.providers, isEmpty);
    expect(module.exports, isEmpty);
    expect(module.global, isFalse);
  });

  test('Injectable and Provides default to the singleton scope', () {
    expect(const Injectable().scope, Scope.singleton);
    expect(const Provides().scope, Scope.singleton);
    expect(const Injectable(scope: Scope.call).scope, Scope.call);
    expect(const Provides(scope: Scope.transient).scope, Scope.transient);
  });

  test('Api keeps its path and hooks; Named keeps its name', () {
    const api = Api('/tasks', use: [#hook]);

    expect(api.path, '/tasks');
    expect(api.use, [#hook]);
    expect(const Named('primary').name, 'primary');
  });

  test('route annotations carry method, path, status and hooks', () {
    const routes = <RouteAnnotation>[
      Get('/:id'),
      Post('/', status: 201, use: [#roles]),
      Put('/a'),
      Patch('/b'),
      Delete('/c'),
    ];

    expect(
      [for (final r in routes) '${r.method} ${r.path} ${r.status} ${r.use}'],
      [
        'GET /:id null []',
        'POST / 201 [Symbol("roles")]',
        'PUT /a null []',
        'PATCH /b null []',
        'DELETE /c null []',
      ],
    );
  });

  test('parameter annotations name the request part', () {
    const parameters = <ParameterAnnotation>[
      Path(),
      Query(name: 'page_size'),
      Header(name: 'x-key'),
      Cookie(),
      Body(),
    ];

    expect(
      [for (final parameter in parameters) parameter.name],
      [null, 'page_size', 'x-key', null, null],
    );
  });

  test('validator annotations hold their bounds', () {
    const range = Range(min: 1, max: 100);
    const length = Length(max: 8);

    expect((range.min, range.max, length.min, length.max), (1, 100, null, 8));
    expect(const Pattern(r'^\d+$').regex, r'^\d+$');
    expect(const OneOf(['a', 'b']).values, ['a', 'b']);
  });

  test('Bind has the interface and the implementation as type arguments', () {
    expect(
      const Bind<Object, String>().runtimeType.toString(),
      'Bind<Object, String>',
    );
  });
}
```

**`packages/grund_annotations/lib/grund_annotations.dart`** (повний вміст після зміни):

```dart
/// Annotations for grund applications.
///
/// `grund_generator` reads them and writes ordinary code on the explicit
/// `package:grund` and `package:grund_http` API into
/// `lib/<package>.grund.dart`. The annotations have no runtime behavior and
/// this package has no dependencies.
///
/// `Module` shares its name with the explicit API; a library that needs both
/// imports `package:grund/grund.dart` with a prefix (`as grund`).
library;

export 'src/api.dart';
export 'src/bind.dart';
export 'src/injectable.dart';
export 'src/module.dart';
export 'src/named.dart';
export 'src/parameter_annotation.dart';
export 'src/provides.dart';
export 'src/route_annotation.dart';
export 'src/scope.dart';
export 'src/validator_annotation.dart';
```

**`packages/grund_annotations/lib/src/api.dart`** (новий):

```dart
/// Declares an HTTP API class; the generator writes the `HttpApi` subclass
/// `<Name>Routes` and a binding for it next to the binding of the class.
///
/// The class is created through its unnamed constructor, like an
/// `Injectable`, and listed in `Module.providers`. Methods annotated with
/// `Get`, `Post`, `Put`, `Patch` or `Delete` become routes.
///
/// ```dart
/// @Api('/tasks', use: [HookRef<ApiKeyHook>.type()])
/// final class TasksApi {
///   TasksApi(this.service);
///   final TasksService service;
///
///   @Get('/:id')
///   Future<Task> find(@Path() int id) => service.find(id);
/// }
/// ```
final class Api {
  /// Creates the annotation with the path prefix of every route and the
  /// [use] hooks of every route.
  const Api(this.path, {this.use = const []});

  /// Path prefix of every route.
  final String path;

  /// `HookRef` constants (`grund_http`), run for every route of the API.
  final List<Object> use;
}
```

**`packages/grund_annotations/lib/src/bind.dart`** (повний вміст після зміни):

```dart
/// A binding of the interface [I] created by the `Injectable` class [C].
///
/// ```dart
/// @Module(providers: [Bind<Clock, SystemClock>()])
/// final class TimeModule extends grund.Module with $TimeModule {
///   const TimeModule();
/// }
/// ```
final class Bind<I extends Object, C extends I> {
  /// Creates the binding.
  const Bind();
}
```

**`packages/grund_annotations/lib/src/injectable.dart`** (повний вміст після зміни):

```dart
import 'scope.dart';

/// Marks a class that dependency injection creates through its unnamed
/// constructor; list it in `Module.providers`.
///
/// Every constructor parameter is resolved by its type, or by its `Named`
/// annotation. Named parameters must be `required`. The class stays an
/// ordinary class: a test can create it by hand.
///
/// ```dart
/// @Injectable()
/// final class UsersService {
///   UsersService(this.repo, @Named('primary') this.db);
///   final UsersRepo repo;
///   final Database db;
/// }
/// ```
final class Injectable {
  /// Creates the annotation with the [scope] of the binding.
  const Injectable({this.scope = Scope.singleton});

  /// How long the instances live.
  final Scope scope;
}
```

**`packages/grund_annotations/lib/src/module.dart`** (повний вміст після зміни):

```dart
/// Declares a module; the generator writes the mixin `$X` that implements
/// `imports`, `bindings` and `exports` of the class `X`.
///
/// The class extends the core `Module` (imported with a prefix, because the
/// names are the same) and mixes in the generated half. It declares a
/// `const` constructor itself.
///
/// ```dart
/// import 'package:grund/grund.dart' as grund;
///
/// @Module(
///   imports: [AuthModule()],
///   providers: [TasksService, TasksApi, Bind<TaskStore, InMemoryTaskStore>()],
///   exports: [TasksService],
/// )
/// final class TasksModule extends grund.Module with $TasksModule {
///   const TasksModule();
/// }
/// ```
///
/// [imports] takes `const` module instances. [providers] takes classes
/// annotated with `Injectable` or `Api`, and `Bind<I, C>()`. [exports] takes
/// types (the binding of that type), `Key<T>('name')` constants (a named
/// binding) and the types of imported modules (re-export).
final class Module {
  /// Creates the annotation.
  const Module({
    this.imports = const [],
    this.providers = const [],
    this.exports = const [],
    this.global = false,
  });

  /// Imported modules, as `const` instances.
  final List<Object> imports;

  /// Classes and `Bind`s the module owns.
  final List<Object> providers;

  /// What importers of the module can see.
  final List<Object> exports;

  /// Whether the exports are visible to every module; the generated mixin
  /// overrides `Module.global`.
  final bool global;
}
```

**`packages/grund_annotations/lib/src/named.dart`** (новий):

```dart
/// Qualifies a binding when several bindings share a type.
///
/// On an `Injectable` class or a `Provides` method it names the binding; on a
/// constructor or method parameter it selects the binding to inject; on a
/// route parameter that comes from the call scope it selects the value set
/// under that name.
///
/// ```dart
/// @Injectable()
/// @Named('primary')
/// final class PrimaryDb implements Database {}
/// ```
final class Named {
  /// Creates the annotation for [name].
  const Named(this.name);

  /// The qualifier; the `name` of the `Key`.
  final String name;
}
```

**`packages/grund_annotations/lib/src/parameter_annotation.dart`** (новий):

```dart
/// Binds a route parameter to a part of the request.
///
/// A parameter without one of these annotations is a `HttpCtx` (passed as
/// is) or a value of the call scope, resolved by its type (and `Named`).
sealed class ParameterAnnotation {
  /// Creates the annotation.
  const ParameterAnnotation([this.name]);

  /// The name in the request; `null` means the name of the parameter.
  final String? name;
}

/// A path parameter (`:name` in the route path).
final class Path extends ParameterAnnotation {
  /// Creates the annotation.
  const Path({String? name}) : super(name);
}

/// A query parameter; a repeated one is a `List<String>`.
final class Query extends ParameterAnnotation {
  /// Creates the annotation.
  const Query({String? name}) : super(name);
}

/// A request header.
final class Header extends ParameterAnnotation {
  /// Creates the annotation.
  const Header({String? name}) : super(name);
}

/// A request cookie.
final class Cookie extends ParameterAnnotation {
  /// Creates the annotation.
  const Cookie({String? name}) : super(name);
}

/// The JSON request body: `T.fromJson(Map<String, Object?>)` (or a `List<T>`
/// of them), a `Map<String, Object?>`, or the raw bytes (`Uint8List`).
final class Body extends ParameterAnnotation {
  /// Creates the annotation.
  const Body();
}
```

**`packages/grund_annotations/lib/src/provides.dart`** (новий):

```dart
import 'scope.dart';

/// Marks a `static` method of a `Module` class as a binding of its return
/// type.
///
/// The parameters are resolved like the constructor parameters of an
/// `Injectable`. A `Future<T>` result makes the binding asynchronous: the
/// singleton is awaited at startup. This is how runtime configuration enters
/// the graph.
///
/// ```dart
/// @Provides()
/// static TasksConfig config(AppConfig app) => TasksConfig(pageSize: app.pageSize);
/// ```
final class Provides {
  /// Creates the annotation with the [scope] of the binding.
  const Provides({this.scope = Scope.singleton});

  /// How long the instances live.
  final Scope scope;
}
```

**`packages/grund_annotations/lib/src/route_annotation.dart`** (повний вміст після зміни):

```dart
/// Makes a method of an `Api` class an HTTP route.
///
/// [path] is relative to the API path and may contain `:name` parameters and
/// a trailing `*`, as in the explicit `Route`.
sealed class RouteAnnotation {
  /// Creates the annotation for [method] and [path].
  const RouteAnnotation(this.method, this.path, this.status, this.use);

  /// The upper-cased HTTP method.
  final String method;

  /// Path relative to the API path.
  final String path;

  /// The response status; `null` leaves the default of the response.
  final int? status;

  /// `HookRef` constants (`grund_http`), run for this route after the hooks
  /// of the API.
  final List<Object> use;
}

/// A `GET` route.
final class Get extends RouteAnnotation {
  /// Creates the annotation.
  const Get(String path, {int? status, List<Object> use = const []})
    : super('GET', path, status, use);
}

/// A `POST` route.
final class Post extends RouteAnnotation {
  /// Creates the annotation.
  const Post(String path, {int? status, List<Object> use = const []})
    : super('POST', path, status, use);
}

/// A `PUT` route.
final class Put extends RouteAnnotation {
  /// Creates the annotation.
  const Put(String path, {int? status, List<Object> use = const []})
    : super('PUT', path, status, use);
}

/// A `PATCH` route.
final class Patch extends RouteAnnotation {
  /// Creates the annotation.
  const Patch(String path, {int? status, List<Object> use = const []})
    : super('PATCH', path, status, use);
}

/// A `DELETE` route.
final class Delete extends RouteAnnotation {
  /// Creates the annotation.
  const Delete(String path, {int? status, List<Object> use = const []})
    : super('DELETE', path, status, use);
}
```

**`packages/grund_annotations/lib/src/scope.dart`** (новий):

```dart
/// How long the instances of a binding live.
///
/// `Scope.call` becomes `Scoped` in the generated bindings: one instance per
/// call (an HTTP request, a job run).
enum Scope {
  /// One instance per application, created at startup.
  singleton,

  /// One instance per call.
  call,

  /// A new instance on every resolution.
  transient,
}
```

**`packages/grund_annotations/lib/src/validator_annotation.dart`** (новий):

```dart
/// A constraint on a path, query, header or cookie parameter; a violation is
/// a 400 response with `code` and `pointer`.
sealed class ValidatorAnnotation {
  /// Creates the annotation.
  const ValidatorAnnotation();
}

/// The bounds of an `int` or `double` parameter, both inclusive.
final class Range extends ValidatorAnnotation {
  /// Creates the annotation; either bound may be left out.
  const Range({this.min, this.max});

  /// The smallest allowed value.
  final num? min;

  /// The largest allowed value.
  final num? max;
}

/// The length bounds of a `String` parameter, both inclusive.
final class Length extends ValidatorAnnotation {
  /// Creates the annotation; either bound may be left out.
  const Length({this.min, this.max});

  /// The shortest allowed length.
  final int? min;

  /// The longest allowed length.
  final int? max;
}

/// The regular expression a `String` parameter must match.
final class Pattern extends ValidatorAnnotation {
  /// Creates the annotation for [regex], a Dart `RegExp` source.
  const Pattern(this.regex);

  /// The regular expression source.
  final String regex;
}

/// The values a `String` parameter may have.
final class OneOf extends ValidatorAnnotation {
  /// Creates the annotation.
  const OneOf(this.values);

  /// The allowed values.
  final List<String> values;
}
```


- [ ] **Крок 2: запуск.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_annotations && dart analyze && dart test
```

Очікувано: `No issues found!`, `+7: All tests passed!`. (До кроку 1 тест не компілюється: `Provides`, `Api`… не існують.)

- [ ] **Крок 3: коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_annotations && dart format . && cd ../.. && git add -A && git commit -m "feat(annotations): module, injectable, provides, api, route and parameter annotations"
```

---

### Задача 14: модель і колектор генератора

**Мета.** Модель `PackageModel` і колектор читають `@Module/@Injectable/@Provides/@Api/@Get…`, `Bind`, `@Named`, `Scope`, `Key<T>('name')` в `exports`, параметри `@Path/@Query/@Header/@Cookie/@Body`, валідатори, хуки (`HookRef`), тип результату. Старі моделі/колектори/конструкти/емітери v1 видаляються; `GrundGenerator.core()` тимчасово порожній (`const []`), поки задачі 15–17 не додадуть конструкти.

**Files.** Create/Modify/Delete — повний перелік нижче (з коміту). Ключове:
- `model/`: `BindingKey(type, [name])`, `Lifetime {singleton, scoped, transient}`, `InjectableModel`, `ProviderModel(key, injectable)`, `ProvidesModel`, `BindingModel`, `ModuleModel` (геттер `bindings`), `ModuleReference` (`Local`/`Opaque`, з `instance` для емісії), `ModuleExport` (`KeyExport`/`ModuleReexport`), `ApiModel`, `RouteModel`, `ParamModel`, `ParamSource` (`ValueSource`/`BodySource`/`ContextSource`/`CallScopeSource`/`InvalidSource`), `HookModel`, `ValidatorModel`, `ReturnKind {value, none, byteStream, stream, unsupported}`, `BodyKind`, `ValueKind`, `GeneratedNames` (`module` → `$X`, `routes` → `XRoutes`).
- `collector/`: `lifetime_reader`, `dependency_reader`, `constructor_reader`, `injectable_reader`, `provides_reader`, `module_reference_reader`, `provider_entry_reader`, `export_entry_reader`, `module_reader`, `hook_reader`, `return_reader`, `value_kind_reader`, `body_kind_reader`, `validator_reader`, `param_reader`, `route_reader`, `api_reader`, `package_collector`; `Annotations.named`, `TypeReader.isFrom`.
- Правила колектора: неанотований параметр: `HttpCtx` → `ContextSource`; не-SDK клас → `CallScopeSource`; інакше `InvalidSource`. Модуль не з цього пакета → `OpaqueModuleReference`. `@Provides` повертає `Future<T>` → `isAsync`. Імпорти зберігаються як `ObjectConstant` (емітуються як non-const екземпляри).
- `Annotations.field` шукає поле й по ланцюгу `(super)`.

**Interfaces.** Consumes: `PackageCollector(packageName, root).collect(libraries)`. Produces: `PackageModel(modules, injectables, apis, strayProvides, strayRoutes, dtos)`.

- [ ] **Крок 1: тести, fixture-и й код.** Порядок: спочатку блоки `test/…` (collector/model/helpers/fixtures), потім `lib/…`.

**Видалити** (`git rm`):

```bash
git rm -q \
  packages/grund_generator/lib/src/collector/controller_reader.dart \
  packages/grund_generator/lib/src/collector/enhancers_reader.dart \
  packages/grund_generator/lib/src/collector/handler_parameter_reader.dart \
  packages/grund_generator/lib/src/collector/token_reader.dart \
  packages/grund_generator/lib/src/constructs/constructor_check.dart \
  packages/grund_generator/lib/src/constructs/controller_check.dart \
  packages/grund_generator/lib/src/constructs/controller_construct.dart \
  packages/grund_generator/lib/src/constructs/dependency_check.dart \
  packages/grund_generator/lib/src/constructs/module_construct.dart \
  packages/grund_generator/lib/src/constructs/module_scope.dart \
  packages/grund_generator/lib/src/constructs/module_structure_check.dart \
  packages/grund_generator/lib/src/constructs/provider_construct.dart \
  packages/grund_generator/lib/src/constructs/scoped_provider.dart \
  packages/grund_generator/lib/src/emit/argument_emitter.dart \
  packages/grund_generator/lib/src/emit/controller_emitter.dart \
  packages/grund_generator/lib/src/emit/enhancers_emitter.dart \
  packages/grund_generator/lib/src/emit/injection_emitter.dart \
  packages/grund_generator/lib/src/emit/module_emitter.dart \
  packages/grund_generator/lib/src/emit/route_emitter.dart \
  packages/grund_generator/lib/src/model/component_reference.dart \
  packages/grund_generator/lib/src/model/controller_model.dart \
  packages/grund_generator/lib/src/model/enhancers_model.dart \
  packages/grund_generator/lib/src/model/parameter_binding.dart \
  packages/grund_generator/lib/src/model/provider_key.dart \
  packages/grund_generator/test/collector/controller_collector_edges_test.dart \
  packages/grund_generator/test/collector/controller_collector_test.dart \
  packages/grund_generator/test/collector/module_collector_edges_test.dart \
  packages/grund_generator/test/constructs/controller_construct_edges_test.dart \
  packages/grund_generator/test/constructs/controller_construct_test.dart \
  packages/grund_generator/test/constructs/controller_duplicates_test.dart \
  packages/grund_generator/test/constructs/dependency_check_graph_test.dart \
  packages/grund_generator/test/constructs/dependency_check_test.dart \
  packages/grund_generator/test/constructs/module_construct_test.dart \
  packages/grund_generator/test/constructs/module_graph_models_test.dart \
  packages/grund_generator/test/constructs/module_scope_test.dart \
  packages/grund_generator/test/constructs/module_structure_check_test.dart \
  packages/grund_generator/test/constructs/provider_construct_test.dart \
  packages/grund_generator/test/e2e/users_app_e2e_test.dart \
  packages/grund_generator/test/example_test.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/controllers/components.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/controllers/edge_handlers.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/controllers/invalid_handlers.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/controllers/users.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/dependencies/graph.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/app.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/explicit.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/invalid_providers.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/references.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/structure_errors.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/modules/with_controller.dart \
  packages/grund_generator/test/fixtures/cases_app/lib/providers/provider_module.dart \
  packages/grund_generator/test/fixtures/users_app/lib/explicit.dart \
  packages/grund_generator/test/fixtures/users_app/lib/src/auth.dart \
  packages/grund_generator/test/fixtures/users_app/lib/src/greeting.dart \
  packages/grund_generator/test/fixtures/users_app/lib/src/modules.dart \
  packages/grund_generator/test/fixtures/users_app/lib/src/users.dart \
  packages/grund_generator/test/fixtures/users_app/lib/users_app.grund.dart \
  packages/grund_generator/test/golden/determinism_test.dart \
  packages/grund_generator/test/golden/golden_test.dart \
  packages/grund_generator/test/helpers/controller_models.dart
```

**Перейменувати:** `git mv packages/grund_generator/lib/src/model/handler_parameter.dart packages/grund_generator/lib/src/model/param_model.dart` (вміст нижче).

**`packages/grund_generator/test/collector/annotations_test.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/collector/annotations.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late ClassElement holder; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final library = (await fixture.libraries(['lib/constants.dart'])).single;
    holder = library.classes.firstWhere((c) => c.name == 'Holder');
  });

  String? typeName(DartObject? value) => value?.type?.element?.name;

  test('find returns the first annotation of that name', () {
    expect(typeName(Annotations.find(holder, 'Api')), 'Api');
    expect(Annotations.find(holder, 'Module'), isNull);
  });

  test('all returns annotations of any given name in source order', () {
    final found = Annotations.all(holder, {'Api', 'Named'});

    expect(found.map(typeName), ['Named', 'Api']);
  });

  test('an annotation from another package is not matched by name', () {
    expect(Annotations.all(holder, {'Tagged', 'Wrapped'}), isEmpty);
  });

  test('named reads the name of @Named', () {
    expect(Annotations.named(holder), 'db');
  });

  test('field reads a field declared on the annotation class', () {
    final api = Annotations.find(holder, 'Api')!;

    expect(Annotations.field(api, 'path')?.toStringValue(), '/holder');
    expect(Annotations.field(api, 'missing'), isNull);
  });

  test('describe names a type and falls back to the value type', () {
    final api = Annotations.find(holder, 'Api')!;
    final use = Annotations.field(api, 'use')?.toListValue();

    expect(Annotations.describe(use!.single), 'a value of type Symbol');
    expect(Annotations.describe(api), 'a value of type Api');
  });
}
```

**`packages/grund_generator/test/collector/api_collector_test.dart`** (новий):

```dart
import 'package:grund_generator/src/model/api_model.dart';
import 'package:grund_generator/src/model/body_kind.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/param_model.dart';
import 'package:grund_generator/src/model/param_source.dart';
import 'package:grund_generator/src/model/return_kind.dart';
import 'package:grund_generator/src/model/route_model.dart';
import 'package:grund_generator/src/model/validator_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']);
  });

  ApiModel api(String name) =>
      package.apis.firstWhere((a) => a.type.name == name);

  RouteModel route(String api_, String name) =>
      api(api_).routes.firstWhere((r) => r.handlerName == name);

  ParamModel param(String api_, String route_, String name) =>
      route(api_, route_).parameters.firstWhere((p) => p.name == name);

  String source(ParamModel param) => switch (param.source) {
    ValueSource(:final location, :final name, :final kind) =>
      '${location.name} $name ${kind.name}',
    BodySource(:final kind) => 'body ${kind.name}',
    ContextSource() => 'context',
    CallScopeSource(:final key) => 'call scope $key',
    InvalidSource(:final problem) => 'invalid: $problem',
  };

  test('an api keeps its path, hooks and routes in source order', () {
    final tasks = api('TasksApi');

    expect(tasks.path, '/tasks');
    expect(tasks.use.single.type.display, 'ApiKeyHook');
    expect(tasks.use.single.isInstance, isFalse);
    expect(
      [for (final r in tasks.routes) '${r.method} ${r.path}'],
      [
        'GET /:id',
        'GET /',
        'POST /',
        'DELETE /:id',
        'PUT /:id/priority/:priority',
        'PUT /:id/raw',
        'POST /import',
        'POST /free',
        'GET /export',
      ],
    );
  });

  test('a route keeps status and hook instances', () {
    final create = route('TasksApi', 'create');

    expect(create.status, 201);
    expect(create.use.single.type.display, 'RolesHook');
    expect(create.use.single.isInstance, isTrue);
  });

  test('return types classify into value, none and byte stream', () {
    expect(route('TasksApi', 'find').returnKind, ReturnKind.value);
    expect(route('TasksApi', 'remove').returnKind, ReturnKind.none);
    expect(route('TasksApi', 'mark').returnKind, ReturnKind.none);
    expect(route('TasksApi', 'export').returnKind, ReturnKind.byteStream);
    expect(route('BadApi', 'events').returnKind, ReturnKind.stream);
    expect(route('BadApi', 'callback').returnKind, ReturnKind.unsupported);
  });

  test('parameters read their source, name and value kind', () {
    expect(source(param('TasksApi', 'find', 'id')), 'path id integer');
    expect(source(param('TasksApi', 'list', 'tag')), 'query tag stringList');
    expect(
      source(param('TasksApi', 'list', 'pageSize')),
      'query page_size integer',
    );
    expect(
      source(param('TasksApi', 'remove', 'trace')),
      'header x-trace string',
    );
    expect(
      source(param('TasksApi', 'raw', 'session')),
      'cookie session string',
    );
    expect(
      source(param('TasksApi', 'mark', 'priority')),
      'path priority enumeration',
    );
    expect(
      source(param('TasksApi', 'export', 'since')),
      'query since dateTime',
    );
  });

  test('bodies are objects, lists, JSON objects or bytes', () {
    BodyKind kind(String route_, String name) =>
        (param('TasksApi', route_, name).source as BodySource).kind;

    expect(kind('create', 'dto'), BodyKind.object);
    expect(kind('import', 'tasks'), BodyKind.list);
    expect(kind('free', 'json'), BodyKind.jsonObject);
    expect(kind('raw', 'data'), BodyKind.bytes);
  });

  test('unannotated parameters are the context or a call scope value', () {
    expect(source(param('TasksApi', 'mark', 'ctx')), 'context');
    expect(
      source(param('TasksApi', 'create', 'user')),
      'call scope CurrentUser',
    );
  });

  test('named parameters and defaults are kept', () {
    final pageSize = param('TasksApi', 'list', 'pageSize');

    expect(pageSize.isNamed, isTrue);
    expect(pageSize.defaultValue, isNotNull);
    expect(param('TasksApi', 'list', 'done').type.display, 'bool?');
    expect(param('TasksApi', 'list', 'done').defaultValue, isNull);
  });

  test('validators are read with their arguments', () {
    final range = param('TasksApi', 'list', 'pageSize').validators.single;
    final [length, pattern] = param('TasksApi', 'list', 'q').validators;

    expect((range as RangeValidator).min, 1);
    expect(range.max, 100);
    expect((length as LengthValidator).max, 8);
    expect((pattern as PatternValidator).regex, r'^\w+$');
  });

  test('problems of a route are kept for the checks', () {
    expect(route('BadApi', 'twice').problem, contains('more than one route'));
    expect(route('BadApi', 'staticHandler').problem, contains('is static'));
    expect(source(param('BadApi', 'noSource', 'page')), contains('no source'));
    expect(source(param('BadApi', 'both', 'x')), contains('more than one of'));
    expect(source(param('BadApi', 'number', 'n')), contains('supports'));
    expect(
      source(param('BadApi', 'body', 'dto')),
      'body ${BodyKind.unsupported.name}',
    );
    expect(route('BadApi', 'hook').invalidEntries, hasLength(1));
    expect(route('BadApi', 'hook').status, 700);
    expect(api('BadApi').invalidEntries, hasLength(1));
  });

  test('routes outside an api are collected apart', () {
    expect([for (final r in package.strayRoutes) r.handlerName], ['stray']);
  });
}
```

**`packages/grund_generator/test/collector/constant_reader_test.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/collector/constant_reader.dart';
import 'package:grund_generator/src/collector/source_locations.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.
  late ClassElement holder; // Set in setUpAll.

  setUpAll(() async {
    fixture = FixturePackage.open('cases_app');
    final library = (await fixture.libraries(['lib/constants.dart'])).single;
    holder = library.classes.firstWhere((c) => c.name == 'Holder');
  });

  DartObject annotation(String name) => [
    for (final a in holder.metadata.annotations)
      if (a.computeConstantValue() case final value?) value,
  ].firstWhere((value) => value.type?.element?.name == name);

  test('an object constant keeps its constructor arguments', () {
    final tagged = ConstantReader.read(annotation('Tagged')) as ObjectConstant;

    expect(tagged.type.display, 'Tagged');
    expect(tagged.constructorName, '');
    expect((tagged.positional.single as StringConstant).value, r"it's $5");
    expect((tagged.named['count'] as NumberConstant).literal, '3');
    expect(
      (tagged.named['flags'] as SetConstant).elements.single,
      isA<StringConstant>(),
    );
    final extra = tagged.named['extra'] as MapConstant;
    expect('${extra.keyType} ${extra.valueType}', 'String int');
    final status = tagged.named['status'] as ReferenceConstant;
    expect('${status.enclosingName}.${status.name}', 'Status.banned');
    expect((tagged.named['type'] as TypeConstant).type.display, 'Holder');
    expect(tagged.unsupported, isNull);
  });

  List<DartObject> wrappedValues() => [
    for (final a in holder.metadata.annotations)
      if (a.computeConstantValue() case final value?)
        if (value.type?.element?.name == 'Wrapped') value,
  ];

  ConstantValue wrapped(int index) =>
      (ConstantReader.read(wrappedValues()[index]) as ObjectConstant)
          .positional
          .single;

  // Review Focus 3: private constants and classes in annotations.
  test('a private constant is rebuilt from its constructor call', () {
    final label = wrapped(1) as ObjectConstant;

    expect(label.type.display, 'Label');
    expect((label.positional.single as StringConstant).value, 'secret');
  });

  test('a private class cannot be written in generated code', () {
    final hidden = ConstantReader.read(wrappedValues().first);

    expect(hidden.unsupported?.reason, '_Hidden is private');
  });

  test('a named constructor keeps its name and type arguments', () {
    final ref = wrapped(2) as ObjectConstant;

    expect(ref.type.display, 'Ref<Holder>');
    expect(ref.constructorName, 'instance');
    expect(ref.positional.single, isA<ObjectConstant>());
  });

  test('a key keeps its name argument', () {
    final key = wrapped(3) as ObjectConstant;

    expect(key.type.display, 'Key<Holder>');
    expect((key.positional.single as StringConstant).value, 'main');
  });

  test('a list of symbols is unsupported', () {
    final api = ConstantReader.read(annotation('Api')) as ObjectConstant;
    final use = api.named['use'] as ListConstant;

    expect(use.elements.single, isA<UnsupportedConstant>());
  });

  test('locations are relative to the package root', () {
    final location = SourceLocations(fixture.root).of(holder);
    final source = fixture.read('lib/constants.dart').split('\n');

    expect(location.path, 'lib/constants.dart');
    expect(source[location.line - 1].indexOf('Holder'), location.column - 1);
  });

  group('edge constants', () {
    late LibraryElement edges; // Set in setUpAll.

    setUpAll(() async {
      edges = (await fixture.libraries(['lib/edge_constants.dart'])).single;
    });

    ConstantValue probe(String className) {
      final element = edges.classes.firstWhere((c) => c.name == className);
      final annotation = element.metadata.annotations.single
          .computeConstantValue();
      final object = ConstantReader.read(annotation) as ObjectConstant;
      return object.positional.single;
    }

    test('null', () => expect(probe('NullCase'), isA<NullConstant>()));

    test('a bool', () {
      expect((probe('BoolCase') as BoolConstant).value, isTrue);
    });

    test('a double keeps its literal', () {
      expect((probe('DoubleCase') as NumberConstant).literal, '1.5');
    });

    test('a non-finite double is unsupported', () {
      expect(
        (probe('InfiniteCase') as UnsupportedConstant).reason,
        'Infinity is not a finite number',
      );
    });

    test('a private constructor is unsupported', () {
      expect(
        (probe('LockedCase') as UnsupportedConstant).reason,
        contains('constructor'),
      );
      expect(probe('LockedCase').unsupported?.reason, contains('private'));
    });

    test('a function is not a constructor call', () {
      expect(
        (probe('FunctionCase') as UnsupportedConstant).reason,
        contains('is not a constructor call'),
      );
    });

    test('a static constant of a public class is a reference', () {
      final reference = probe('StaticCase') as ReferenceConstant;

      expect('${reference.enclosingName}.${reference.name}', 'Limits.max');
      expect(reference.libraryUri, 'package:cases_app/edge_constants.dart');
    });

    test('a static constant of a private class is its value', () {
      expect((probe('PrivateOwnerCase') as NumberConstant).literal, '7');
    });
  });
}
```

**`packages/grund_generator/test/collector/injectable_collector_test.dart`** (новий):

```dart
import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/providers/constructors.dart', 'lib/modules/basic.dart']);
  });

  InjectableModel injectable(String name) =>
      package.injectables.firstWhere((i) => i.type.name == name);

  List<String> dependencies(String name) => [
    for (final dependency in injectable(name).constructor.dependencies)
      switch (dependency) {
        DependencyModel(:final key?) => '${dependency.name}: $key',
        DependencyModel(:final problem) => '${dependency.name}: $problem',
      },
  ];

  test('injectables keep their scope and name', () {
    expect(injectable('Tx').lifetime, Lifetime.scoped);
    expect(injectable('Fine').lifetime, Lifetime.transient);
    expect(injectable('SystemClock').lifetime, Lifetime.singleton);
    expect("${injectable('PrimaryDb').key}", "PrimaryDb('primary')");
  });

  test('dependencies by type, by name and by required name', () {
    expect(dependencies('Repo'), [
      'clock: Clock',
      "db: PrimaryDb('primary')",
      'config: AppConfig',
    ]);
    expect(injectable('Repo').constructor.dependencies.last.isNamed, isTrue);
    expect(dependencies('Fine'), [
      'clock: Clock',
      "db: PrimaryDb('primary')",
      'repo: Repo',
    ]);
  });

  test('classes dependency injection cannot create', () {
    expect(injectable('Shape').constructor.problem, 'Shape is abstract.');
    expect(
      injectable('Box').constructor.problem,
      'Box is generic; provide a subclass with fixed type arguments.',
    );
    expect(
      injectable('OnlyNamed').constructor.problem,
      'OnlyNamed has no unnamed constructor; grund creates it with '
      'OnlyNamed(...).',
    );
    expect(injectable('_Hidden').constructor.problem, '_Hidden is private.');
  });

  test('an abstract class with a factory can be created', () {
    expect(injectable('Service').constructor.problem, isNull);
  });

  test('parameters dependency injection cannot fill', () {
    expect(dependencies('Optional'), [
      'clock: Parameter clock of Optional is optional; grund injects '
          'required positional and required named parameters only.',
    ]);
    expect(dependencies('Odd'), [
      'clock: Parameter clock of Odd has type Clock?; grund injects '
          'non-nullable class types, qualified with @Named.',
      'callback: Parameter callback of Odd has type void Function(); grund '
          'injects non-nullable class types, qualified with @Named.',
    ]);
    expect(dependencies('Loose'), [
      'anything: Parameter anything of Loose has type Object; grund injects '
          'non-nullable class types, qualified with @Named.',
    ]);
  });

  test('a @Provides method of a class that is no module is stray', () {
    expect(
      [for (final s in package.strayProvides) '${s.owner}.${s.methodName}'],
      ['NotAModule.plain'],
    );
  });
}
```

**`packages/grund_generator/test/collector/module_collector_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    package = await fixture.collect([
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
      'lib/modules/with_api.dart',
    ]);
  });

  ModuleModel module(String name) =>
      package.modules.firstWhere((m) => m.type.name == name);

  test('modules come in library URI order', () {
    expect(package.languageVersion.toString(), '3.8.0');
    expect(
      [for (final m in package.modules) m.type.name],
      ['DbModule', 'AppModule', 'BrokenModule', 'TasksModule'],
    );
  });

  test('a module keeps its flags, location and documentation', () {
    final db = module('DbModule');

    expect(db.isGlobal, isTrue);
    expect(db.extendsModule, isTrue);
    expect(db.documentation, '/// Database access.');
    expect(db.location.path, 'lib/modules/basic.dart');
    expect(module('AppModule').isGlobal, isFalse);
    expect(db.invalidEntries, isEmpty);
  });

  test('class and Bind providers are keyed by what they provide', () {
    final providers = module('DbModule').providers;

    expect(
      [for (final p in providers) "${p.key} <- ${p.injectable.type}"],
      [
        'Repo <- Repo',
        'Clock <- SystemClock',
        "PrimaryDb('primary') <- PrimaryDb",
        'Tx <- Tx',
      ],
    );
    expect(providers.last.injectable.lifetime, Lifetime.scoped);
  });

  test('@Provides methods keep key, scope and async-ness', () {
    final provides = module('DbModule').provides;

    expect(provides.first.key.toString(), 'AppConfig');
    expect(provides.first.lifetime, Lifetime.singleton);
    final session = provides[1];
    expect("${session.key}", "Session('main')");
    expect(session.lifetime, Lifetime.scoped);
    expect(session.isAsync, isTrue);
    expect("${session.dependencies.single.key}", 'Clock');
  });

  test('a @Provides method that cannot be called has a problem', () {
    final [_, _, notStatic, nothing] = module('DbModule').provides;

    expect(notStatic.problem, contains('is not static'));
    expect(nothing.problem, contains('returns void'));
    expect(notStatic.key, isNull);
  });

  test('imports are local or opaque, re-exports and keys are exports', () {
    final app = module('AppModule');
    final db = module('DbModule');

    expect(app.imports.first, isA<LocalModuleReference>());
    expect(app.imports.last, isA<OpaqueModuleReference>());
    expect(app.imports.last.display, 'ExplicitModule');
    expect((app.exports.single as ModuleReexport).type.display, 'DbModule');
    expect(
      [for (final e in db.exports) '${(e as KeyExport).key}'],
      ['Repo', "PrimaryDb('primary')", 'Clock', "Session('main')"],
    );
  });

  test('entries the generator cannot read become problems', () {
    final broken = module('BrokenModule');

    expect(broken.extendsModule, isFalse);
    expect(broken.invalidEntries, [
      'imports: String is not a const instance of a Module.',
      'imports: a value of type String is not a const instance of a Module.',
      'providers: a value of type int is not a class or Bind<I, C>().',
      'providers: a value of type Label is not a class or Bind<I, C>().',
      'exports: a value of type int is not a class, a Key<T>() or an '
          'imported module.',
    ]);
    expect(broken.imports, isEmpty);
    expect(broken.providers, isEmpty);
  });
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/apis/invalid.dart`** (новий):

```dart
// An API whose routes the generator rejects, one problem per method.
import 'package:grund_annotations/grund_annotations.dart';

import 'tasks.dart';

/// A class without `@Injectable` or `@Api`.
final class NoJson {}

/// Every route has a problem.
@Api('/bad', use: [42])
final class BadApi {
  /// Two annotations.
  @Get('/a')
  @Post('/a')
  void twice() {}

  /// Static.
  @Get('/b')
  static void staticHandler() {}

  /// A stream of non-bytes.
  @Get('/c')
  Stream<Task> events() => const Stream.empty();

  /// A parameter without a source.
  @Get('/d')
  void noSource(int page) {}

  /// A body without `fromJson`.
  @Post('/e')
  void body(@Body() NoJson dto) {}

  /// A path parameter the path does not have.
  @Get('/f/:id')
  void unknownPath(@Path() int other) {}

  /// Two sources.
  @Get('/g')
  void both(@Path() @Query() int x) {}

  /// A validator of the wrong type.
  @Get('/h')
  void range(@Query() @Range(min: 1) String name) {}

  /// A type no reader supports.
  @Get('/i')
  void number(@Query() num n) {}

  /// A function type result.
  @Get('/j')
  void Function() callback() => () {};

  /// Same method and path as the next one.
  @Get('/dup/:a')
  void one() {}

  /// Same method and path as the previous one.
  @Get('/dup/:b')
  void two() {}

  /// A hook that is not a HookRef.
  @Get('/k', use: ['hook'], status: 700)
  void hook() {}

  /// Named the same as a path parameter of another route.
  @Get('/l')
  Future<void> optional(@Query() int? a, [@Query() int b = 1]) async {}
}

/// Routes outside of an API.
final class NotAnApi {
  /// Never served.
  @Get('/stray')
  void stray() {}
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/apis/tasks.dart`** (новий):

```dart
// A valid API with every kind of route parameter and result.
import 'dart:typed_data';

import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

/// How urgent a task is.
enum Priority {
  /// Can wait.
  low,

  /// Cannot wait.
  high,
}

/// A task.
final class Task {
  /// Creates the task.
  const Task(this.id);

  /// The identifier.
  final int id;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id};
}

/// The body of `create`.
final class CreateTask {
  /// Creates the body.
  const CreateTask(this.title);

  /// Reads the body.
  factory CreateTask.fromJson(Map<String, Object?> json) =>
      CreateTask(json['title']! as String);

  /// The title.
  final String title;
}

/// The caller, set into the call scope by a hook.
final class CurrentUser {}

/// Checks the API key.
@Injectable()
final class ApiKeyHook extends HttpHook {
  /// Creates the hook.
  const ApiKeyHook();
}

/// Checks the role.
final class RolesHook extends HttpHook {
  /// Creates the hook.
  const RolesHook(this.priority);

  /// The minimum priority.
  final Priority priority;
}

/// The tasks of the workspace.
@Api('/tasks', use: [HookRef<ApiKeyHook>.type()])
final class TasksApi {
  /// Creates the API.
  TasksApi(this.store);

  /// Where tasks live.
  final Map<int, Task> store;

  /// Returns one task.
  @Get('/:id')
  Future<Task> find(@Path() int id) async => Task(id);

  /// Lists tasks.
  @Get('/')
  Future<List<Task>> list(
    @Query() bool? done,
    @Query() List<String> tag, {
    @Query(name: 'page_size') @Range(min: 1, max: 100) int pageSize = 20,
    @Query() @Length(min: 1, max: 8) @Pattern(r'^\w+$') String? q,
  }) async => [];

  /// Creates a task.
  @Post(
    '/',
    status: 201,
    use: [HookRef<RolesHook>.instance(RolesHook(Priority.high))],
  )
  Future<Task> create(@Body() CreateTask dto, CurrentUser user) async =>
      Task(1);

  /// Removes a task.
  @Delete('/:id')
  Future<void> remove(
    @Path() int id,
    @Header(name: 'x-trace') String? trace,
  ) async {}

  /// Marks a task.
  @Put('/:id/priority/:priority')
  void mark(@Path() int id, @Path() Priority priority, HttpCtx ctx) {}

  /// Replaces the attachment.
  @Put('/:id/raw')
  Task raw(@Path() int id, @Body() Uint8List data, @Cookie() String session) =>
      Task(id);

  /// Imports tasks.
  @Post('/import')
  Task import(@Body() List<CreateTask> tasks) => const Task(0);

  /// Takes an arbitrary JSON object.
  @Post('/free')
  Task free(@Body() Map<String, Object?> json) => const Task(0);

  /// Streams bytes.
  @Get('/export')
  Stream<List<int>> export(@Query() DateTime since, @Query() Uri? next) =>
      const Stream.empty();
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/constants.dart`** (повний вміст після зміни):

```dart
// Constants for ConstantReader tests: each annotation on [Holder] is read
// by name.
import 'package:grund/grund.dart' show Key;
import 'package:grund_annotations/grund_annotations.dart';

/// A value object with a public constant.
final class Label {
  /// Creates the label.
  const Label(this.name);

  /// The label text.
  final String name;
}

/// A public constant.
const dbLabel = Label('db.url');

const _secret = Label('secret');

/// Something that is built from a named constructor and has a type argument.
final class Ref<T extends Object> {
  /// A reference by type.
  const Ref.type() : value = null;

  /// A reference to a given value.
  const Ref.instance(this.value);

  /// The value, if any.
  final T? value;
}

/// Marks something for the tests.
abstract class Marker {
  /// Creates the marker.
  const Marker();
}

/// Statuses.
enum Status { active, banned }

/// Metadata with every kind of field.
final class Tagged extends Marker {
  /// Creates the metadata.
  const Tagged(
    this.label, {
    this.count = 0,
    this.ratio = 0.5,
    this.flags = const {},
    this.extra = const {},
    this.status,
    this.type,
    this.nothing,
  });

  /// A string.
  final String label;

  /// An int.
  final int count;

  /// A double.
  final double ratio;

  /// A set.
  final Set<String> flags;

  /// A map.
  final Map<String, int> extra;

  /// An enum value.
  final Status? status;

  /// A type.
  final Type? type;

  /// Always null.
  final Object? nothing;
}

/// Metadata holding a private object.
final class Wrapped extends Marker {
  /// Creates the metadata.
  const Wrapped(this.value);

  /// The wrapped value.
  final Object value;
}

final class _Hidden {
  const _Hidden();
}

/// Carries the annotations the tests read.
@Tagged(
  'it\'s \$5',
  count: 3,
  flags: {'a'},
  extra: {'x': 1},
  status: Status.banned,
  type: Holder,
)
@Wrapped(_Hidden())
@Named('db')
@Wrapped(_secret)
@Wrapped(Ref<Holder>.instance(Holder()))
@Wrapped(Key<Holder>('main'))
@Api('/holder', use: [#guard])
class Holder {
  /// Creates the holder.
  const Holder();
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/edge_constants.dart`** (повний вміст після зміни):

```dart
// Edge-case constants for ConstantReader tests: each class below carries one
// [Probe] whose single argument is read by class name.
import 'constants.dart' show Marker;

/// Metadata that wraps any constant.
final class Probe extends Marker {
  /// Creates the metadata.
  const Probe(this.value);

  /// The wrapped constant.
  final Object? value;
}

/// A class with a private constructor.
final class Locked {
  const Locked._();
}

const _locked = Locked._();

/// A class with a public static constant.
final class Limits {
  /// The maximum.
  static const max = 5;
}

final class _Private {
  static const value = 7;
}

/// A function to tear off.
void tearOff() {}

/// Null.
@Probe(null)
class NullCase {}

/// A bool.
@Probe(true)
class BoolCase {}

/// A double.
@Probe(1.5)
class DoubleCase {}

/// A non-finite double.
@Probe(1 / 0)
class InfiniteCase {}

/// A private constructor.
@Probe(_locked)
class LockedCase {}

/// A function, which is not a constructor call.
@Probe(tearOff)
class FunctionCase {}

/// A static constant of a public class.
@Probe(Limits.max)
class StaticCase {}

/// A static constant of a private class.
@Probe(_Private.value)
class PrivateOwnerCase {}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/modules/basic.dart`** (повний вміст після зміни):

```dart
// Valid modules: class, Bind and Provides bindings, scopes and names.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

/// A clock.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The system clock.
@Injectable()
final class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// A named binding.
@Injectable()
@Named('primary')
final class PrimaryDb {}

/// Lives as long as a call.
@Injectable(scope: Scope.call)
final class Tx {}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Named('primary') this.db, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The settings.
  final AppConfig config;
}

/// A session opened asynchronously.
final class Session {
  /// Creates the session.
  const Session();
}

/// Database access.
@Module(
  providers: [Repo, Bind<Clock, SystemClock>(), PrimaryDb, Tx],
  exports: [Repo, PrimaryDb, grund.Key<Clock>(), grund.Key<Session>('main')],
  global: true,
)
final class DbModule extends grund.Module {
  /// Creates the module.
  const DbModule();

  /// The settings.
  @Provides()
  static AppConfig config() => const AppConfig('demo');

  /// A session per call.
  @Provides(scope: Scope.call)
  @Named('main')
  static Future<Session> session(Clock clock) async => const Session();

  /// Not static.
  @Provides()
  Repo notStatic() => throw UnimplementedError();

  /// Returns nothing.
  @Provides()
  static void nothing() {}
}

/// Re-exports the database module.
@Module(
  imports: [
    DbModule(),
    ExplicitModule(name: 'x'),
  ],
  exports: [DbModule],
)
final class AppModule extends grund.Module {
  /// Creates the module.
  const AppModule();
}

/// A module written with the explicit API.
final class ExplicitModule extends grund.Module {
  /// Creates the module.
  const ExplicitModule({this.name});

  /// Tells instances apart.
  final String? name;

  @override
  Object? get qualifier => name;
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/modules/invalid_entries.dart`** (повний вміст після зміни):

```dart
// Module entries the generator cannot read.
import 'package:grund_annotations/grund_annotations.dart';

import 'basic.dart';

/// Every list holds something wrong.
@Module(imports: [String, 'db'], providers: [42, Label()], exports: [3])
class BrokenModule {}

/// Not a Module.
final class Label {
  /// Creates it.
  const Label();
}

/// Uses the same names so the file is reachable from the tests.
const brokenUses = DbModule();
```

**`packages/grund_generator/test/fixtures/cases_app/lib/modules/with_api.dart`** (новий):

```dart
// A module that provides an API and its service.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

import '../apis/tasks.dart';

/// Hooks and the API.
@Module(providers: [TasksApi, ApiKeyHook])
final class TasksModule extends grund.Module {
  /// Creates the module.
  const TasksModule();

  /// Where tasks live.
  @Provides()
  static Map<int, Task> store() => {};
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/providers/constructors.dart`** (повний вміст після зміни):

```dart
// Classes whose constructors dependency injection cannot or can call.
import 'package:grund_annotations/grund_annotations.dart';

import '../modules/basic.dart';

/// Not annotated.
final class Plain {}

/// Abstract.
@Injectable()
abstract class Shape {}

/// Generic.
@Injectable()
final class Box<T> {}

/// Only a named constructor.
@Injectable()
final class OnlyNamed {
  /// Creates it.
  OnlyNamed.create();
}

/// An optional parameter.
@Injectable()
final class Optional {
  /// Creates it.
  Optional([this.clock]);

  /// The clock.
  final Clock? clock;
}

/// A nullable required parameter and a function parameter.
@Injectable()
final class Odd {
  /// Creates it.
  Odd(this.clock, this.callback);

  /// The clock.
  final Clock? clock;

  /// A callback.
  final void Function() callback;
}

/// Private classes cannot be created from the generated library.
@Injectable()
// ignore: unused_element, read by the collector only.
final class _Hidden {}

/// An abstract class with a factory can be created.
@Injectable()
abstract class Service {
  /// Creates the default service.
  factory Service() => _DefaultService();
}

final class _DefaultService implements Service {}

/// An `Object` parameter says nothing about what to inject.
@Injectable()
final class Loose {
  /// Creates it.
  Loose(this.anything);

  /// Anything.
  final Object anything;
}

/// Injects through every accepted form.
@Injectable(scope: Scope.transient)
final class Fine {
  /// Creates it.
  Fine(this.clock, @Named('primary') this.db, {required this.repo});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The repository.
  final Repo repo;
}

/// A class with `@Provides` that is not a module.
final class NotAModule {
  /// Provided from the wrong place.
  @Provides()
  static Plain plain() => Plain();
}
```

**`packages/grund_generator/test/fixtures/users_app/lib/users_app.dart`** (повний вміст після зміни):

```dart
// Rewritten for the annotated model in task 18.
library;
```

**`packages/grund_generator/test/helpers/graph_models.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/provider_model.dart';
import 'package:grund_generator/src/model/provides_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';

/// Builders of small hand-made module graphs for the check tests.
abstract final class GraphModels {
  /// A class type named [name].
  static TypeModel type(String name) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
  );

  /// The key of the class [name], qualified by [qualifier].
  static BindingKey key(String name, [String? qualifier]) =>
      BindingKey(type(name), qualifier);

  /// A dependency on [need] (`Name` or `Name('qualifier')` is not parsed;
  /// pass the key).
  static DependencyModel need(BindingKey need) => DependencyModel.injected(
    name: need.type.name.toLowerCase(),
    isNamed: false,
    location: SourceLocation('lib/app.dart', 2, need.type.name.length),
    key: need,
  );

  /// A class provider of [name] that needs the classes [needs].
  static ProviderModel provider(
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
  }) => ProviderModel(
    key(name),
    InjectableModel(
      type: type(name),
      lifetime: lifetime,
      isAnnotated: true,
      location: SourceLocation('lib/app.dart', 1, name.length),
      constructor: ConstructorModel([for (final n in needs) need(key(n))]),
    ),
  );

  /// A `@Provides` method of [owner] that provides [name].
  static ProvidesModel provides(
    String owner,
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
    String? problem,
  }) => ProvidesModel(
    owner: type(owner),
    methodName: name.toLowerCase(),
    location: SourceLocation('lib/app.dart', 6, name.length),
    key: problem == null ? key(name) : null,
    lifetime: lifetime,
    dependencies: [for (final n in needs) need(key(n))],
    problem: problem,
  );

  /// A module named [name].
  static ModuleModel module(
    String name, {
    List<ModuleReference> imports = const [],
    List<ProviderModel> providers = const [],
    List<ProvidesModel> provides = const [],
    List<ModuleExport> exports = const [],
    bool isGlobal = false,
  }) => ModuleModel(
    type: type(name),
    location: SourceLocation('lib/app.dart', 3, name.length),
    imports: imports,
    providers: providers,
    provides: provides,
    exports: exports,
    isGlobal: isGlobal,
  );

  /// A reference to the module [name] from this package.
  static LocalModuleReference reference(String name) =>
      LocalModuleReference(type(name), _instance(name));

  /// A reference to the module [name] from elsewhere.
  static OpaqueModuleReference opaque(String name) =>
      OpaqueModuleReference(type(name), _instance(name));

  /// An export of the class [name].
  static KeyExport export(String name, [String? qualifier]) =>
      KeyExport(key(name, qualifier));

  /// A package of [modules].
  static PackageModel package(List<ModuleModel> modules) => PackageModel(
    packageName: 'app',
    languageVersion: Version(3, 8, 0),
    modules: modules,
  );

  static ObjectConstant _instance(String name) =>
      ObjectConstant(type: type(name), constructorName: '');
}
```

**`packages/grund_generator/test/model/model_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/generated_names.dart';
import 'package:grund_generator/src/model/return_kind.dart';
import 'package:grund_generator/src/model/route_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:test/test.dart';

const _users = 'package:app/users.dart';

TypeModel _type(
  String name, {
  bool nullable = false,
  List<TypeModel> args = const [],
}) => TypeModel(
  name: name,
  kind: TypeKind.interface,
  libraryUri: _users,
  typeArguments: args,
  isNullable: nullable,
);

void main() {
  test('a diagnostic prints as path:line:col: error: message [code]', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.missingProvider,
      const SourceLocation('lib/users.dart', 3, 7),
      'No provider for Repo in module "users".',
    );

    expect(
      '$diagnostic',
      'lib/users.dart:3:7: error: No provider for Repo in module "users". '
          '[missing_provider]',
    );
  });

  test('diagnostics sort by path, line, column, then code', () {
    Diagnostic at(String path, int line, int column, DiagnosticCode code) =>
        Diagnostic(code, SourceLocation(path, line, column), 'm');
    final sorted = [
      at('lib/b.dart', 1, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 9, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 2, 5, DiagnosticCode.notInjectable),
      at('lib/a.dart', 2, 5, DiagnosticCode.missingProvider),
      at('lib/a.dart', 2, 1, DiagnosticCode.duplicateRoute),
    ]..sort();

    expect(
      [for (final d in sorted) '${d.location} ${d.code.id}'],
      [
        'lib/a.dart:2:1 duplicate_route',
        'lib/a.dart:2:5 missing_provider',
        'lib/a.dart:2:5 not_injectable',
        'lib/a.dart:9:1 duplicate_route',
        'lib/b.dart:1:1 duplicate_route',
      ],
    );
  });

  test('type models compare by library, name, arguments and nullability', () {
    final list = _type('List', args: [_type('User')]);

    expect(list, _type('List', args: [_type('User')]));
    expect(list.display, 'List<User>');
    expect(_type('User', nullable: true).display, 'User?');
    expect(_type('User', nullable: true).nonNullable, _type('User'));
    expect(_type('User'), isNot(_type('User', nullable: true)));
    expect(_type('User').isDeclaredAs('User', _users), isTrue);
  });

  test('binding keys: a type with an optional name', () {
    final repo = BindingKey(_type('Repo'));
    final named = BindingKey(_type('Repo'), 'main');

    expect(repo, BindingKey(_type('Repo')));
    expect(repo, isNot(named));
    expect(named.display, "Repo('main')");
    expect(repo.display, 'Repo');
  });

  test('binding keys sort by display, then library', () {
    final keys = [
      BindingKey(_type('Repo'), 'b'),
      BindingKey(_type('Repo')),
      BindingKey(_type('Clock')),
    ]..sort();

    expect([for (final k in keys) k.display], ['Clock', 'Repo', "Repo('b')"]);
  });

  test('route path parameters in declaration order', () {
    final route = RouteModel(
      method: 'GET',
      path: '/:org/users/:id/*',
      handlerName: 'find',
      returnType: TypeModel.voidType,
      returnKind: ReturnKind.none,
      location: const SourceLocation('lib/a.dart', 1, 1),
    );

    expect(route.pathParameters, ['org', 'id', '*']);
  });

  test('generated names derive from class names', () {
    expect(GeneratedNames.module('UsersModule'), r'$UsersModule');
    expect(GeneratedNames.routes('TasksApi'), 'TasksApiRoutes');
    expect(GeneratedNames.library('shop'), 'package:shop/shop.grund.dart');
  });
}
```

**`packages/grund_generator/test/model/package_model_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/grund_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  test('a package without modules, injectables or apis is empty', () {
    expect(GraphModels.package([]).isEmpty, isTrue);
  });

  test('a module makes the package non-empty', () {
    expect(GraphModels.package([GraphModels.module('App')]).isEmpty, isFalse);
  });

  test('an api makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      apis: [
        ApiModel(
          type: GraphModels.type('TasksApi'),
          path: '/tasks',
          location: const SourceLocation('lib/app.dart', 1, 7),
        ),
      ],
    );

    expect(package.isEmpty, isFalse);
  });

  test('an injectable makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      injectables: [GraphModels.provider('Clock').injectable],
    );

    expect(package.isEmpty, isFalse);
  });

  test('a module lists the bindings of its providers and @Provides', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('Repo', needs: ['Clock']),
      ],
      provides: [GraphModels.provides('App', 'Clock')],
    );

    expect([for (final b in module.bindings) '${b.key}'], ['Repo', 'Clock']);
  });
}
```

**`packages/grund_generator/lib/grund_generator.dart`** (повний вміст після зміни):

```dart
/// Turns grund annotations into ordinary code on the explicit grund
/// API, and checks the module graph before the application starts.
///
/// A driver (the CLI, build_runner) resolves the libraries of a package,
/// builds its model with [PackageCollector] and runs a [GrundGenerator]:
///
/// ```dart
/// final package = PackageCollector('shop', root).collect(libraries);
/// final result = const GrundGenerator.core().generate(package);
/// if (!result.isSuccess) result.diagnostics.forEach(print);
/// ```
///
/// The model and [Construct] are public so later packages (OpenAPI,
/// GraphQL) can add constructs of their own.
library;

export 'src/collector/package_collector.dart';
export 'src/construct/construct.dart';
export 'src/construct/content_type.dart';
export 'src/construct/grund_generator.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/diagnostic/syntax_problem.dart';
export 'src/emit/library_writer.dart';
export 'src/model/api_model.dart';
export 'src/model/binding_key.dart';
export 'src/model/binding_model.dart';
export 'src/model/body_kind.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/hook_model.dart';
export 'src/model/injectable_model.dart';
export 'src/model/lifetime.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/param_location.dart';
export 'src/model/param_model.dart';
export 'src/model/param_source.dart';
export 'src/model/provider_model.dart';
export 'src/model/provides_model.dart';
export 'src/model/return_kind.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
export 'src/model/validator_model.dart';
export 'src/model/value_kind.dart';
```

**`packages/grund_generator/lib/src/collector/annotations.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Reads `package:grund_annotations` annotations from elements.
///
/// Annotations are matched by class name and library, not by type, so the
/// generator does not depend on the annotations package.
abstract final class Annotations {
  /// URI prefix of the annotations package.
  static const packageUri = 'package:grund_annotations/';

  /// The value of the first annotation on [element] whose class is [name]
  /// from the annotations package.
  static DartObject? find(Element element, String name) =>
      all(element, {name}).firstOrNull;

  /// The values of every annotation on [element] whose class is one of
  /// [names] from the annotations package, in source order.
  static List<DartObject> all(Element element, Set<String> names) => [
    for (final value in _values(element))
      if (isAnnotation(value.type, names)) value,
  ];

  /// Whether [type] is one of the classes [names] of the annotations
  /// package.
  static bool isAnnotation(DartType? type, Set<String> names) =>
      type is InterfaceType &&
      names.contains(type.element.name) &&
      '${type.element.library.uri}'.startsWith(packageUri);

  /// The `@Named` qualifier of [element], or `null`.
  static String? named(Element element) {
    final annotation = find(element, 'Named');
    return annotation == null
        ? null
        : field(annotation, 'name')?.toStringValue();
  }

  /// Field [name] of [object], looked up in its superclasses too.
  static DartObject? field(DartObject object, String name) {
    for (DartObject? current = object; current != null;) {
      final value = current.getField(name);
      if (value != null) return value;
      current = current.getField('(super)');
    }
    return null;
  }

  /// [entry] of an annotation list as a diagnostic shows it: a type or
  /// function by name, anything else as `a value of type T`.
  static String describe(DartObject entry) =>
      entry.toTypeValue()?.getDisplayString() ??
      entry.toFunctionValue()?.displayName ??
      'a value of type ${entry.type?.getDisplayString() ?? 'unknown'}';

  static Iterable<DartObject> _values(Element element) sync* {
    for (final annotation in element.metadata.annotations) {
      if (annotation.computeConstantValue() case final value?) yield value;
    }
  }
}
```

**`packages/grund_generator/lib/src/collector/api_reader.dart`** (новий):

```dart
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
```

**`packages/grund_generator/lib/src/collector/body_kind_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/body_kind.dart';

/// Decides how a `@Body()` parameter of a given type is read.
abstract final class BodyKindReader {
  /// The body kind of [type]: a class with `fromJson(Map<String, ...>)`, a
  /// list of them, a JSON object map, or raw bytes.
  static BodyKind read(DartType type) {
    if (type is! InterfaceType ||
        type.nullabilitySuffix != NullabilitySuffix.none) {
      return BodyKind.unsupported;
    }
    if (_isBytes(type)) return BodyKind.bytes;
    if (_isJsonObject(type)) return BodyKind.jsonObject;
    if (type.isDartCoreList) {
      final item = type.typeArguments.single;
      return item is InterfaceType &&
              item.nullabilitySuffix == NullabilitySuffix.none &&
              hasFromJson(item.element)
          ? BodyKind.list
          : BodyKind.unsupported;
    }
    return hasFromJson(type.element) ? BodyKind.object : BodyKind.unsupported;
  }

  /// Whether [element] has a `fromJson` constructor or static method whose
  /// only required parameter takes a `Map<String, ...>`.
  static bool hasFromJson(InterfaceElement element) {
    final ExecutableElement? fromJson =
        element.getNamedConstructor('fromJson') ??
        element.getMethod('fromJson');
    if (fromJson == null ||
        (fromJson is MethodElement && !fromJson.isStatic) ||
        element.typeParameters.isNotEmpty) {
      return false;
    }
    final required = [
      for (final parameter in fromJson.formalParameters)
        if (parameter.isRequired) parameter,
    ];
    return required.length == 1 &&
        required.single.isPositional &&
        _isJsonObject(required.single.type);
  }

  static bool _isBytes(InterfaceType type) =>
      (type.element.name == 'Uint8List' &&
          '${type.element.library.uri}' == 'dart:typed_data') ||
      (type.isDartCoreList && type.typeArguments.single.isDartCoreInt);

  static bool _isJsonObject(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreMap &&
      type.typeArguments.first.isDartCoreString &&
      switch (type.typeArguments.last) {
        DynamicType() => true,
        final InterfaceType value =>
          value.isDartCoreObject &&
              value.nullabilitySuffix == NullabilitySuffix.question,
        _ => false,
      };
}
```

**`packages/grund_generator/lib/src/collector/constructor_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';

import '../model/constructor_model.dart';
import 'dependency_reader.dart';
import 'source_locations.dart';

/// Reads how dependency injection creates a class: its unnamed constructor
/// and what each parameter resolves to.
final class ConstructorReader {
  /// Creates the reader.
  ConstructorReader(SourceLocations locations)
    : _dependencies = DependencyReader(locations);

  final DependencyReader _dependencies;

  /// The constructor model of [element].
  ConstructorModel read(InterfaceElement element) {
    final name = element.displayName;
    final constructor = element.unnamedConstructor;
    if (element is! ClassElement) {
      return ConstructorModel.invalid('$name is not a class.');
    }
    if (element.isPrivate) return ConstructorModel.invalid('$name is private.');
    if (element.typeParameters.isNotEmpty) {
      return ConstructorModel.invalid(
        '$name is generic; provide a subclass with fixed type arguments.',
      );
    }
    if (constructor == null) {
      return ConstructorModel.invalid(
        '$name has no unnamed constructor; grund creates it with '
        '$name(...).',
      );
    }
    if (element.isAbstract && !constructor.isFactory) {
      return ConstructorModel.invalid('$name is abstract.');
    }
    return ConstructorModel([
      for (final parameter in constructor.formalParameters)
        _dependencies.read(parameter, name),
    ]);
  }
}
```

**`packages/grund_generator/lib/src/collector/dependency_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import 'annotations.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads what one parameter of a constructor or `@Provides` method resolves
/// to: its type and its `@Named` qualifier.
final class DependencyReader {
  /// Creates the reader.
  DependencyReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  /// The dependency [parameter] of [owner] (for example `UsersService` or
  /// `UsersModule.config`) declares.
  DependencyModel read(FormalParameterElement parameter, String owner) {
    final where = 'Parameter ${parameter.displayName} of $owner';
    if (parameter.isOptional) {
      return _invalid(
        parameter,
        '$where is optional; grund injects required positional and '
        'required named parameters only.',
      );
    }
    if (!_isInjectable(parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}; grund '
        'injects non-nullable class types, qualified with @Named.',
      );
    }
    return DependencyModel.injected(
      name: parameter.displayName,
      isNamed: parameter.isNamed,
      location: locations.of(parameter),
      key: BindingKey(
        TypeReader.read(parameter.type),
        Annotations.named(parameter),
      ),
    );
  }

  DependencyModel _invalid(FormalParameterElement parameter, String problem) =>
      DependencyModel.invalid(
        name: parameter.displayName,
        isNamed: parameter.isNamed,
        location: locations.of(parameter),
        problem: problem,
      );

  static bool _isInjectable(DartType type) =>
      type is InterfaceType &&
      type.nullabilitySuffix == NullabilitySuffix.none &&
      !type.isDartCoreObject;
}
```

**`packages/grund_generator/lib/src/collector/dto_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/dto_field.dart';
import '../model/dto_model.dart';
import 'body_kind_reader.dart';
import 'type_reader.dart';

/// Collects the data classes that travel as request bodies and handler
/// results, for the documentation constructs of later versions.
abstract final class DtoReader {
  static const _containers = {'Future', 'FutureOr', 'List', 'Iterable', 'Set'};

  /// The data classes reachable from [roots] (body and return types), each
  /// once, following `Future`, `FutureOr`, `List`, `Iterable`, `Set` and
  /// field types; sorted by library URI and name.
  static List<DtoModel> read(Iterable<DartType> roots) {
    final seen = <InterfaceElement>{};
    final pending = [
      for (final root in roots)
        if (_dataClass(root) case final element?) element,
    ];
    final dtos = <DtoModel>[];
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (!seen.add(element)) continue;
      dtos.add(_dto(element));
      for (final field in _fields(element)) {
        if (_dataClass(field.type) case final nested?) pending.add(nested);
      }
    }
    return dtos..sort(
      (a, b) => '${a.type.libraryUri}#${a.type.name}'.compareTo(
        '${b.type.libraryUri}#${b.type.name}',
      ),
    );
  }

  static InterfaceElement? _dataClass(DartType type) {
    if (type is! InterfaceType) return null;
    final element = type.element;
    if (_containers.contains(element.name) && element.library.isInSdk) {
      return type.typeArguments.isEmpty
          ? null
          : _dataClass(type.typeArguments.single);
    }
    final uri = '${element.library.uri}';
    final isData =
        element is ClassElement &&
        element.typeParameters.isEmpty &&
        !element.library.isInSdk &&
        !uri.startsWith('package:grund/') &&
        !uri.startsWith('package:grund_http/');
    return isData ? element : null;
  }

  static DtoModel _dto(InterfaceElement element) => DtoModel(
    type: TypeReader.read(element.thisType),
    fields: [
      for (final field in _fields(element))
        DtoField(
          name: field.displayName,
          jsonName: _jsonName(field) ?? field.displayName,
          type: TypeReader.read(field.type),
          defaultValue: _defaultValue(element, field.displayName),
          documentation: field.documentationComment,
        ),
    ],
    hasFromJson: BodyKindReader.hasFromJson(element),
    documentation: element.documentationComment,
  );

  static List<FieldElement> _fields(InterfaceElement element) => [
    for (final field in element.fields)
      if (!field.isStatic && field.isPublic && field.nonSynthetic == field)
        field,
  ];

  static String? _jsonName(FieldElement field) {
    for (final annotation in field.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value?.type?.element?.name == 'JsonKey') {
        return value?.getField('name')?.toStringValue();
      }
    }
    return null;
  }

  static String? _defaultValue(InterfaceElement element, String name) => element
      .unnamedConstructor
      ?.formalParameters
      .where((parameter) => parameter.displayName == name)
      .firstOrNull
      ?.defaultValueCode;
}
```

**`packages/grund_generator/lib/src/collector/export_entry_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/module_export.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'module_reference_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(exports: [...])`: a type, a
/// `Key<T>('name')`, or the type of an imported module.
abstract final class ExportEntryReader {
  /// The export [entry] declares.
  static EntryRead<ModuleExport> read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType type) {
      return ReadEntry(
        ModuleReferenceReader.isModuleClass(type)
            ? ModuleReexport(TypeReader.read(type))
            : KeyExport(
                BindingKey(
                  TypeReader.read(type),
                  Annotations.named(type.element),
                ),
              ),
      );
    }
    final type = entry.type;
    if (type is InterfaceType && TypeReader.isGrund(type, 'Key')) {
      final name = Annotations.field(entry, 'name')?.toStringValue();
      return ReadEntry(
        KeyExport(BindingKey(TypeReader.read(type.typeArguments.single), name)),
      );
    }
    return InvalidEntry(
      'exports: ${Annotations.describe(entry)} is not a class, a Key<T>() '
      'or an imported module.',
    );
  }
}
```

**`packages/grund_generator/lib/src/collector/hook_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/hook_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'entry_read.dart';
import 'type_reader.dart';

/// Reads the `use:` list of `@Api` and of the route annotations.
abstract final class HookReader {
  /// The hooks of the `use` field of [annotation], in order.
  static List<EntryRead<HookModel>> read(DartObject annotation) => [
    for (final entry
        in Annotations.field(annotation, 'use')?.toListValue() ??
            const <DartObject>[])
      _hook(entry),
  ];

  static EntryRead<HookModel> _hook(DartObject entry) {
    final type = entry.type;
    if (type is! InterfaceType ||
        !TypeReader.isFrom(type, 'HookRef', 'package:grund_http/')) {
      return InvalidEntry(
        'use: ${Annotations.describe(entry)} is not a HookRef.',
      );
    }
    return ReadEntry(
      HookModel(
        type: TypeReader.read(type.typeArguments.single),
        isInstance: entry.constructorInvocation?.constructor.name == 'instance',
        expression: ConstantReader.read(entry),
      ),
    );
  }
}
```

**`packages/grund_generator/lib/src/collector/injectable_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';

import '../model/injectable_model.dart';
import 'annotations.dart';
import 'constructor_reader.dart';
import 'lifetime_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a class that dependency injection creates: a provider class, a
/// `Bind` implementation or an `@Api` class.
final class InjectableReader {
  /// Creates the reader.
  InjectableReader(this.locations)
    : _constructors = ConstructorReader(locations);

  /// Locations of classes and parameters.
  final SourceLocations locations;

  final ConstructorReader _constructors;

  /// The model of [element].
  InjectableModel read(InterfaceElement element) {
    final injectable = Annotations.find(element, 'Injectable');
    final isApi = Annotations.find(element, 'Api') != null;
    return InjectableModel(
      type: TypeReader.read(element.thisType),
      name: Annotations.named(element),
      lifetime: LifetimeReader.read(injectable),
      isAnnotated: injectable != null || isApi,
      isApi: isApi,
      constructor: _constructors.read(element),
      location: locations.of(element),
      documentation: element.documentationComment,
    );
  }
}
```

**`packages/grund_generator/lib/src/collector/lifetime_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';

import '../model/lifetime.dart';
import 'annotations.dart';

/// Reads the `scope` of `@Injectable` and `@Provides`.
abstract final class LifetimeReader {
  /// The lifetime of [annotation]; a missing annotation or `Scope.singleton`
  /// is [Lifetime.singleton].
  static Lifetime read(DartObject? annotation) {
    final scope = annotation == null
        ? null
        : Annotations.field(annotation, 'scope');
    return switch (scope?.variable?.name) {
      'call' => Lifetime.scoped,
      'transient' => Lifetime.transient,
      _ => Lifetime.singleton,
    };
  }
}
```

**`packages/grund_generator/lib/src/collector/module_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/module_model.dart';
import '../model/module_reference.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'export_entry_reader.dart';
import 'injectable_reader.dart';
import 'module_reference_reader.dart';
import 'provider_entry_reader.dart';
import 'provides_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a `@Module` class into a [ModuleModel]. Entries it cannot read go
/// to [ModuleModel.invalidEntries]; the module construct reports them.
final class ModuleReader {
  /// Creates the reader for package [packageName].
  ModuleReader(this.packageName, this.locations)
    : _references = ModuleReferenceReader(packageName),
      _providers = ProviderEntryReader(InjectableReader(locations)),
      _provides = ProvidesReader(locations);

  /// The package being generated.
  final String packageName;

  /// Locations of declarations.
  final SourceLocations locations;

  final ModuleReferenceReader _references;

  final ProviderEntryReader _providers;

  final ProvidesReader _provides;

  /// The module declared by [element], whose `@Module` is [annotation].
  ModuleModel read(ClassElement element, DartObject annotation) {
    final imports = [for (final e in _list(annotation, 'imports')) _import(e)];
    final providers = [
      for (final e in _list(annotation, 'providers')) _providers.read(e),
    ];
    final exports = [
      for (final e in _list(annotation, 'exports')) ExportEntryReader.read(e),
    ];
    return ModuleModel(
      type: TypeReader.read(element.thisType),
      location: locations.of(element),
      imports: EntryRead.values(imports),
      providers: EntryRead.values(providers),
      provides: _provides.read(element),
      exports: EntryRead.values(exports),
      isGlobal: Annotations.field(annotation, 'global')?.toBoolValue() ?? false,
      extendsModule: TypeReader.hasSupertype(
        element,
        'Module',
        'package:grund/',
      ),
      invalidEntries: EntryRead.problems([
        ...imports,
        ...providers,
        ...exports,
      ]),
      documentation: element.documentationComment,
    );
  }

  EntryRead<ModuleReference> _import(DartObject entry) =>
      switch (_references.read(entry)) {
        final reference? => ReadEntry(reference),
        null => InvalidEntry(
          'imports: ${Annotations.describe(entry)} is not a const instance '
          'of a Module.',
        ),
      };

  static List<DartObject> _list(DartObject annotation, String name) =>
      Annotations.field(annotation, name)?.toListValue() ?? const [];
}
```

**`packages/grund_generator/lib/src/collector/module_reference_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/module_reference.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'type_reader.dart';

/// Reads an entry of `@Module(imports: ...)`: a `const` instance of a class
/// that extends the core `Module`.
final class ModuleReferenceReader {
  /// Creates the reader for package [packageName].
  ModuleReferenceReader(this.packageName);

  /// The package being generated.
  final String packageName;

  /// The reference [entry] denotes, or `null` when it is not a module
  /// instance.
  ModuleReference? read(DartObject entry) {
    final type = entry.type;
    if (type is! InterfaceType || !isModuleClass(type)) return null;
    final model = TypeReader.read(type);
    final instance = ConstantReader.read(entry);
    return _isLocal(type)
        ? LocalModuleReference(model, instance)
        : OpaqueModuleReference(model, instance);
  }

  /// Whether [type] extends the core `Module`.
  static bool isModuleClass(InterfaceType type) =>
      TypeReader.hasSupertype(type.element, 'Module', 'package:grund/');

  bool _isLocal(InterfaceType type) =>
      Annotations.find(type.element, 'Module') != null &&
      '${type.element.library.uri}'.startsWith('package:$packageName/');
}
```

**`packages/grund_generator/lib/src/collector/package_collector.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/api_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/route_model.dart';
import 'annotations.dart';
import 'api_reader.dart';
import 'dto_reader.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'provides_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generated `*.grund.dart` is skipped.
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(this.packageName, String packageRoot)
    : _locations = SourceLocations(packageRoot);

  /// The package being generated.
  final String packageName;

  final SourceLocations _locations;

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!'${library.uri}'.endsWith('.grund.dart')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final modules = ModuleReader(packageName, _locations);
    final injectables = InjectableReader(_locations);
    final apis = ApiReader(_locations);
    final provides = ProvidesReader(_locations);
    final routes = RouteReader(_locations);
    final moduleModels = <ModuleModel>[];
    final injectableModels = <InjectableModel>[];
    final apiModels = <ApiModel>[];
    final strayProvides = <ProvidesModel>[];
    final strayRoutes = <RouteModel>[];
    final dtoRoots = <DartType>[];
    for (final element in [for (final l in sorted) ...l.classes]) {
      final module = Annotations.find(element, 'Module');
      final api = Annotations.find(element, 'Api');
      if (module != null) {
        moduleModels.add(modules.read(element, module));
      } else {
        strayProvides.addAll(provides.read(element));
      }
      if (api != null) {
        apiModels.add(apis.read(element, api));
        dtoRoots.addAll(_dtoRoots(element));
      } else {
        strayRoutes.addAll(routes.read(element));
      }
      if (Annotations.all(element, const {'Injectable', 'Api'}).isNotEmpty) {
        injectableModels.add(injectables.read(element));
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: moduleModels,
      injectables: injectableModels,
      apis: apiModels,
      strayProvides: strayProvides,
      strayRoutes: strayRoutes,
      dtos: DtoReader.read(dtoRoots),
    );
  }

  static List<DartType> _dtoRoots(ClassElement api) => [
    for (final method in api.methods)
      if (Annotations.all(method, RouteReader.annotations).isNotEmpty) ...[
        method.returnType,
        for (final parameter in method.formalParameters)
          if (Annotations.find(parameter, 'Body') != null) parameter.type,
      ],
  ];

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}
```

**`packages/grund_generator/lib/src/collector/param_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/constant_value.dart';
import '../model/param_location.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/value_kind.dart';
import 'annotations.dart';
import 'body_kind_reader.dart';
import 'constant_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';
import 'validator_reader.dart';
import 'value_kind_reader.dart';

/// Reads where a parameter of a route handler gets its value from.
final class ParamReader {
  /// Creates the reader.
  ParamReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  static const _sources = {'Path', 'Query', 'Header', 'Cookie', 'Body'};

  static const _locations = {
    'Path': ParamLocation.path,
    'Query': ParamLocation.query,
    'Header': ParamLocation.header,
    'Cookie': ParamLocation.cookie,
  };

  /// The model of [parameter].
  ParamModel read(FormalParameterElement parameter) => ParamModel(
    name: parameter.displayName,
    type: TypeReader.read(parameter.type),
    source: _source(parameter),
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
    validators: ValidatorReader.read(parameter),
    defaultValue: _default(parameter),
  );

  ParamSource _source(FormalParameterElement parameter) {
    final type = parameter.type;
    final annotations = Annotations.all(parameter, _sources);
    final shown = '${parameter.displayName} (${type.getDisplayString()})';
    if (annotations.length > 1) {
      return InvalidSource(
        'Parameter $shown has more than one of @Path, @Query, @Header, '
        '@Cookie and @Body.',
      );
    }
    if (annotations.isEmpty) return _unannotated(parameter, shown);
    final annotation = annotations.single;
    final name = annotation.type?.element?.name;
    final location = _locations[name];
    if (location == null) return BodySource(BodyKindReader.read(type));
    return _value(annotation, location, parameter, shown);
  }

  static ParamSource _value(
    DartObject annotation,
    ParamLocation location,
    FormalParameterElement parameter,
    String shown,
  ) {
    final kind = ValueKindReader.read(parameter.type);
    final isList = kind == ValueKind.stringList;
    if (kind == ValueKind.unsupported ||
        (isList && location == ParamLocation.path)) {
      return InvalidSource(
        'Parameter $shown: @${annotation.type?.element?.name} supports '
        'String, int, double, bool, DateTime, Uri and enums, and '
        'List<String> except for @Path.',
      );
    }
    final name =
        Annotations.field(annotation, 'name')?.toStringValue() ??
        parameter.displayName;
    return ValueSource(location, name, kind);
  }

  static ParamSource _unannotated(
    FormalParameterElement parameter,
    String shown,
  ) {
    final type = parameter.type;
    if (TypeReader.isFrom(type, 'HttpCtx', 'package:grund_http/')) {
      return const ContextSource();
    }
    if (type is InterfaceType &&
        type.element is ClassElement &&
        !type.element.library.isInSdk) {
      return CallScopeSource(
        BindingKey(
          TypeReader.read(type).nonNullable,
          Annotations.named(parameter),
        ),
      );
    }
    return InvalidSource(
      'Parameter $shown has no source: annotate it with @Path, @Query, '
      '@Header, @Cookie or @Body, or give it the class type of a value of '
      'the call scope.',
    );
  }

  static ConstantValue? _default(FormalParameterElement parameter) =>
      parameter.hasDefaultValue
      ? ConstantReader.read(parameter.computeConstantValue())
      : null;
}
```

**`packages/grund_generator/lib/src/collector/provider_entry_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/provider_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(providers: [...])`: a class or `Bind<I, C>()`.
final class ProviderEntryReader {
  /// Creates the reader.
  ProviderEntryReader(this.injectables);

  /// Reads provider classes.
  final InjectableReader injectables;

  /// The provider [entry] declares.
  EntryRead<ProviderModel> read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType provided) {
      final injectable = injectables.read(provided.element);
      return ReadEntry(ProviderModel(injectable.key, injectable));
    }
    final type = entry.type;
    if (type is InterfaceType &&
        Annotations.isAnnotation(type, const {'Bind'})) {
      return _bind(type);
    }
    return InvalidEntry(
      'providers: ${Annotations.describe(entry)} is not a class or '
      'Bind<I, C>().',
    );
  }

  EntryRead<ProviderModel> _bind(InterfaceType bind) {
    final [interface, implementation] = bind.typeArguments;
    if (interface is! InterfaceType || implementation is! InterfaceType) {
      return InvalidEntry(
        'providers: ${bind.getDisplayString()} must bind a class to a class.',
      );
    }
    final injectable = injectables.read(implementation.element);
    return ReadEntry(
      ProviderModel(
        BindingKey(TypeReader.read(interface), injectable.name),
        injectable,
      ),
    );
  }
}
```

**`packages/grund_generator/lib/src/collector/provides_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/provides_model.dart';
import 'annotations.dart';
import 'dependency_reader.dart';
import 'lifetime_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the `@Provides` methods of a class.
final class ProvidesReader {
  /// Creates the reader.
  ProvidesReader(this.locations) : _dependencies = DependencyReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final DependencyReader _dependencies;

  /// The `@Provides` methods of [owner], in declaration order.
  List<ProvidesModel> read(ClassElement owner) => [
    for (final method in owner.methods)
      if (Annotations.find(method, 'Provides') case final annotation?)
        _read(owner, method, annotation),
  ];

  ProvidesModel _read(
    ClassElement owner,
    MethodElement method,
    DartObject annotation,
  ) {
    final name = '${owner.displayName}.${method.displayName}';
    final provided = _provided(method.returnType);
    final problem = _problem(method, name, provided);
    return ProvidesModel(
      owner: TypeReader.read(owner.thisType),
      methodName: method.displayName,
      location: locations.of(method),
      key: problem != null || provided == null
          ? null
          : BindingKey(TypeReader.read(provided), Annotations.named(method)),
      lifetime: LifetimeReader.read(annotation),
      isAsync: _isAsync(method.returnType),
      dependencies: [
        for (final parameter in method.formalParameters)
          _dependencies.read(parameter, name),
      ],
      documentation: method.documentationComment,
      problem: problem,
    );
  }

  /// The `T` of `T`, `Future<T>` and `FutureOr<T>`; `null` when the type is
  /// not a non-nullable class type.
  static InterfaceType? _provided(DartType returned) {
    final type = _isAsync(returned) && returned is InterfaceType
        ? returned.typeArguments.single
        : returned;
    return type is InterfaceType &&
            type.nullabilitySuffix == NullabilitySuffix.none &&
            !type.isDartCoreObject
        ? type
        : null;
  }

  static bool _isAsync(DartType type) =>
      type.isDartAsyncFuture || type.isDartAsyncFutureOr;

  static String? _problem(
    MethodElement method,
    String name,
    InterfaceType? provided,
  ) {
    if (!method.isStatic) return '@Provides method $name is not static.';
    if (method.isPrivate) return '@Provides method $name is private.';
    if (method.typeParameters.isNotEmpty) {
      return '@Provides method $name is generic.';
    }
    if (provided == null) {
      return '@Provides method $name returns '
          '${method.returnType.getDisplayString()}; it must return a '
          'non-nullable class type, or a Future of one.';
    }
    return null;
  }
}
```

**`packages/grund_generator/lib/src/collector/return_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/element/type.dart';

import '../model/return_kind.dart';

/// Classifies the return type of a route handler.
abstract final class ReturnReader {
  /// The kind of [returned], looking through one `Future` or `FutureOr`.
  static ReturnKind read(DartType returned) {
    final type = _unwrapped(returned);
    if (type is VoidType || type.isDartCoreNull) return ReturnKind.none;
    if (type is InterfaceType && type.isDartAsyncStream) {
      return _isByteList(type.typeArguments.single)
          ? ReturnKind.byteStream
          : ReturnKind.stream;
    }
    return type is InterfaceType || type is DynamicType
        ? ReturnKind.value
        : ReturnKind.unsupported;
  }

  static DartType _unwrapped(DartType type) =>
      type is InterfaceType &&
          (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
          type.typeArguments.length == 1
      ? type.typeArguments.single
      : type;

  static bool _isByteList(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreList &&
      type.typeArguments.single.isDartCoreInt;
}
```

**`packages/grund_generator/lib/src/collector/route_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/route_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'hook_reader.dart';
import 'param_reader.dart';
import 'return_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the route methods of a class.
final class RouteReader {
  /// Creates the reader.
  RouteReader(this.locations) : _parameters = ParamReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final ParamReader _parameters;

  /// The names of the route annotations.
  static const annotations = {'Get', 'Post', 'Put', 'Patch', 'Delete'};

  /// The routes of [owner]: one per method with a route annotation, in
  /// declaration order.
  List<RouteModel> read(ClassElement owner) => [
    for (final method in owner.methods)
      if (Annotations.all(method, annotations) case [
        final first,
        ...final rest,
      ])
        _route(method, first, isSingle: rest.isEmpty),
  ];

  RouteModel _route(
    MethodElement method,
    DartObject route, {
    required bool isSingle,
  }) {
    final hooks = HookReader.read(route);
    return RouteModel(
      method: _string(method, route, 'method'),
      path: _string(method, route, 'path'),
      handlerName: method.displayName,
      returnType: TypeReader.read(method.returnType),
      returnKind: ReturnReader.read(method.returnType),
      location: locations.of(method),
      status: Annotations.field(route, 'status')?.toIntValue(),
      parameters: [
        for (final parameter in method.formalParameters)
          _parameters.read(parameter),
      ],
      use: EntryRead.values(hooks),
      invalidEntries: EntryRead.problems(hooks),
      documentation: method.documentationComment,
      problem: _problem(method, isSingle: isSingle),
    );
  }

  /// The string field [field] of the route annotation [route] on [method].
  static String _string(MethodElement method, DartObject route, String field) {
    final value = Annotations.field(route, field)?.toStringValue();
    if (value == null) {
      throw StateError(
        'The route annotation on ${method.displayName} has no constant '
        'string "$field".',
      );
    }
    return value;
  }

  static String? _problem(MethodElement method, {required bool isSingle}) {
    final name =
        '${method.enclosingElement?.displayName}.${method.displayName}';
    if (!isSingle) return 'Handler $name has more than one route annotation.';
    if (method.isStatic) return 'Handler $name is static.';
    if (method.isPrivate) return 'Handler $name is private.';
    if (method.typeParameters.isNotEmpty) return 'Handler $name is generic.';
    return null;
  }
}
```

**`packages/grund_generator/lib/src/collector/type_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/type_kind.dart';
import '../model/type_model.dart';

/// Converts analyzer types to [TypeModel]s.
abstract final class TypeReader {
  /// The model of [type].
  static TypeModel read(DartType type) => switch (type) {
    VoidType() => TypeModel.voidType,
    DynamicType() => const TypeModel(
      name: 'dynamic',
      kind: TypeKind.dynamicType,
    ),
    InterfaceType(:final element, :final typeArguments) => TypeModel(
      name: element.name ?? element.displayName,
      kind: element is EnumElement ? TypeKind.enumeration : TypeKind.interface,
      libraryUri: '${element.library.uri}',
      typeArguments: [for (final argument in typeArguments) read(argument)],
      isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
    ),
    _ => TypeModel(name: type.getDisplayString(), kind: TypeKind.unsupported),
  };

  /// Whether [type] is the class [name] of a `package:grund` library.
  static bool isGrund(DartType? type, String name) =>
      type is InterfaceType &&
      type.element.name == name &&
      _isIn(type.element.library, 'package:grund/');

  /// Whether [type] is the class [name] of a library under [uriPrefix].
  static bool isFrom(DartType? type, String name, String uriPrefix) =>
      type is InterfaceType &&
      type.element.name == name &&
      _isIn(type.element.library, uriPrefix);

  /// Whether [element] or one of its supertypes is the class [name] of a
  /// library under [uriPrefix].
  static bool hasSupertype(
    InterfaceElement element,
    String name,
    String uriPrefix,
  ) => [element.thisType, ...element.allSupertypes].any(
    (type) =>
        type.element.name == name && _isIn(type.element.library, uriPrefix),
  );

  static bool _isIn(LibraryElement library, String uriPrefix) =>
      '${library.uri}'.startsWith(uriPrefix);
}
```

**`packages/grund_generator/lib/src/collector/validator_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/validator_model.dart';
import 'annotations.dart';

/// Reads `@Range`, `@Length`, `@Pattern` and `@OneOf` of a parameter.
abstract final class ValidatorReader {
  static const _names = {'Range', 'Length', 'Pattern', 'OneOf'};

  /// The validators of [parameter], in source order.
  static List<ValidatorModel> read(Element parameter) => [
    for (final annotation in Annotations.all(parameter, _names))
      _validator(annotation),
  ];

  static ValidatorModel _validator(DartObject annotation) =>
      switch (annotation.type?.element?.name) {
        'Range' => RangeValidator(
          min: _number(annotation, 'min'),
          max: _number(annotation, 'max'),
        ),
        'Length' => LengthValidator(
          min: Annotations.field(annotation, 'min')?.toIntValue(),
          max: Annotations.field(annotation, 'max')?.toIntValue(),
        ),
        'Pattern' => PatternValidator(
          Annotations.field(annotation, 'regex')?.toStringValue() ?? '',
        ),
        _ => OneOfValidator([
          for (final value
              in Annotations.field(annotation, 'values')?.toListValue() ??
                  const <DartObject>[])
            if (value.toStringValue() case final text?) text,
        ]),
      };

  static num? _number(DartObject annotation, String field) {
    final value = Annotations.field(annotation, field);
    return value?.toIntValue() ?? value?.toDoubleValue();
  }
}
```

**`packages/grund_generator/lib/src/collector/value_kind_reader.dart`** (новий):

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/value_kind.dart';

/// Decides which `Params` reader fills a parameter of a given type.
abstract final class ValueKindReader {
  /// The kind of [type], whether nullable or not.
  static ValueKind read(DartType type) {
    if (type is! InterfaceType) return ValueKind.unsupported;
    if (type.element is EnumElement) return ValueKind.enumeration;
    if (type.isDartCoreString) return ValueKind.string;
    if (type.isDartCoreInt) return ValueKind.integer;
    if (type.isDartCoreDouble) return ValueKind.decimal;
    if (type.isDartCoreBool) return ValueKind.boolean;
    if (_isCore(type, 'DateTime')) return ValueKind.dateTime;
    if (_isCore(type, 'Uri')) return ValueKind.uri;
    return type.isDartCoreList && type.typeArguments.single.isDartCoreString
        ? ValueKind.stringList
        : ValueKind.unsupported;
  }

  static bool _isCore(InterfaceType type, String name) =>
      type.element.name == name && type.element.library.isDartCore;
}
```

**`packages/grund_generator/lib/src/construct/grund_generator.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/library_writer.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generated_unit.dart';
import 'generation_result.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// Every construct validates first; any diagnostic stops generation, so a
/// package with an error never gets a half-generated library.
final class GrundGenerator {
  /// Creates the generator; [constructs] run in order.
  const GrundGenerator(this.constructs);

  /// The v1 constructs. None yet: the module, provider and API constructs
  /// arrive with the checks and the emitters.
  const GrundGenerator.core() : constructs = const [];

  /// The constructs.
  final List<Construct> constructs;

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final diagnostics = {
      for (final construct in constructs) ...construct.validate(package),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final units = [
      for (final construct in constructs) ...construct.generate(package),
    ];
    final dartUnits = units.whereType<DartUnit>().toList();
    final duplicates = _duplicateNames(dartUnits);
    if (duplicates.isNotEmpty) return GenerationResult.failed(duplicates);
    return GenerationResult.generated(
      library: LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: <Spec>[for (final unit in dartUnits) unit.spec],
      ),
      files: units.whereType<FileUnit>().toList(),
    );
  }

  static List<Diagnostic> _duplicateNames(List<DartUnit> units) {
    final first = <String, DartUnit>{};
    return [
      for (final unit in units)
        if (first.putIfAbsent(unit.name, () => unit) case final other
            when other != unit)
          Diagnostic(
            DiagnosticCode.duplicateGeneratedName,
            unit.origin,
            'Generated name ${unit.name} is used twice: for the declaration '
            'at ${other.origin} and for this one. Rename one of them.',
          ),
    ]..sort();
  }
}
```

**`packages/grund_generator/lib/src/model/api_model.dart`** (новий):

```dart
import '../diagnostic/source_location.dart';
import 'hook_model.dart';
import 'route_model.dart';
import 'type_model.dart';

/// A class annotated with `@Api`.
///
/// Together with [RouteModel] and `ParamModel` this is everything an
/// OpenAPI description needs (types, `///` comments, validation
/// annotations); stage 2 builds its `ApiDescription` from it, stage 1 only
/// emits the routes.
final class ApiModel {
  /// Creates the model.
  const ApiModel({
    required this.type,
    required this.path,
    required this.location,
    this.use = const [],
    this.routes = const [],
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The API class.
  final TypeModel type;

  /// The path prefix of every route.
  final String path;

  /// Where the class is declared.
  final SourceLocation location;

  /// Hooks of every route, in order.
  final List<HookModel> use;

  /// The routes, in declaration order.
  final List<RouteModel> routes;

  /// One sentence per `use` entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
```

**`packages/grund_generator/lib/src/model/binding_key.dart`** (новий):

```dart
import 'type_model.dart';

/// What a binding is looked up by: a type and an optional name, like the
/// core `Key<T>([name])`.
final class BindingKey implements Comparable<BindingKey> {
  /// Creates the key of [type], qualified by [name] when several bindings
  /// share the type.
  const BindingKey(this.type, [this.name]);

  /// The type of the bound value.
  final TypeModel type;

  /// The qualifier (`@Named`), or `null`.
  final String? name;

  /// The key as grund prints it: `UsersService` or `Database('primary')`.
  String get display => name == null ? '$type' : "$type('$name')";

  /// Orders keys by type name, then qualifier, then declaring library, so
  /// a sorted list never depends on the order of collection.
  @override
  int compareTo(BindingKey other) {
    final byDisplay = display.compareTo(other.display);
    if (byDisplay != 0) return byDisplay;
    return '${type.libraryUri}'.compareTo('${other.type.libraryUri}');
  }

  @override
  bool operator ==(Object other) =>
      other is BindingKey && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);

  @override
  String toString() => display;
}
```

**`packages/grund_generator/lib/src/model/binding_model.dart`** (новий):

```dart
import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'dependency_model.dart';
import 'lifetime.dart';

/// A binding a module owns, as the graph checks see it: its key, lifetime
/// and what it resolves, whether it comes from a class or a `@Provides`
/// method.
final class BindingModel {
  /// Creates the binding.
  const BindingModel({
    required this.key,
    required this.lifetime,
    required this.dependencies,
    required this.location,
  });

  /// What the binding is looked up by.
  final BindingKey key;

  /// How long the instances live.
  final Lifetime lifetime;

  /// What the factory resolves, in parameter order.
  final List<DependencyModel> dependencies;

  /// Where the binding is declared.
  final SourceLocation location;
}
```

**`packages/grund_generator/lib/src/model/body_kind.dart`** (повний вміст після зміни):

```dart
/// How a `@Body()` parameter is read.
enum BodyKind {
  /// `await c.body(T.fromJson)`.
  object,

  /// `await c.bodyList(T.fromJson)` for a `List<T>`.
  list,

  /// The decoded JSON object as a `Map<String, Object?>`.
  jsonObject,

  /// The raw bytes as a `Uint8List`.
  bytes,

  /// No way to read the type: no `fromJson`, or nullable.
  unsupported,
}
```

**`packages/grund_generator/lib/src/model/dependency_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'binding_key.dart';

/// A parameter of a constructor or `@Provides` method that dependency
/// injection fills.
///
/// Exactly one of [key] and [problem] is set.
final class DependencyModel {
  /// A parameter resolved by [key].
  const DependencyModel.injected({
    required this.name,
    required this.isNamed,
    required this.location,
    required BindingKey this.key,
  }) : problem = null;

  /// A parameter that cannot be injected, because of [problem].
  const DependencyModel.invalid({
    required this.name,
    required this.isNamed,
    required this.location,
    required String this.problem,
  }) : key = null;

  /// The parameter name.
  final String name;

  /// Whether the parameter is named (passed as `name: value`).
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;

  /// The binding to resolve; `null` when [problem] is set.
  final BindingKey? key;

  /// Why the parameter cannot be injected, as a sentence.
  final String? problem;
}
```

**`packages/grund_generator/lib/src/model/generated_names.dart`** (повний вміст після зміни):

```dart
/// Names of the declarations the generator emits, derived from class names.
///
/// `UsersModule` → the mixin `$UsersModule`, `TasksApi` → the `HttpApi`
/// subclass `TasksApiRoutes`. Another package's module is not imported by
/// this library: its mixin is applied in its own source.
abstract final class GeneratedNames {
  /// The mixin of `@Module` class [className].
  static String module(String className) => '\$$className';

  /// The `HttpApi` subclass of `@Api` class [className].
  static String routes(String className) => '${className}Routes';

  /// The generated library of package [packageName].
  static String library(String packageName) =>
      'package:$packageName/$packageName.grund.dart';
}
```

**`packages/grund_generator/lib/src/model/hook_model.dart`** (новий):

```dart
import 'constant_value.dart';
import 'type_model.dart';

/// One entry of `use:` on `@Api` or a route annotation: a `HookRef`.
final class HookModel {
  /// Creates the model.
  const HookModel({
    required this.type,
    required this.isInstance,
    required this.expression,
  });

  /// The hook class: the `T` of `HookRef<T>`.
  final TypeModel type;

  /// Whether the hook is a given instance (`HookRef<T>.instance(...)`);
  /// otherwise (`HookRef<T>.type()`) it is a binding of the module.
  final bool isInstance;

  /// The `HookRef` as written in the annotation.
  final ConstantValue expression;
}
```

**`packages/grund_generator/lib/src/model/injectable_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'constructor_model.dart';
import 'lifetime.dart';
import 'type_model.dart';

/// A class that a module provides through its constructor: a class in
/// `@Module(providers: ...)` or the implementation of a `Bind`.
final class InjectableModel {
  /// Creates the model.
  const InjectableModel({
    required this.type,
    required this.lifetime,
    required this.isAnnotated,
    required this.constructor,
    required this.location,
    this.name,
    this.isApi = false,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// The `@Named` qualifier of the class, or `null`.
  final String? name;

  /// The lifetime of the binding.
  final Lifetime lifetime;

  /// Whether the class is annotated with `@Injectable()` or `@Api(...)`.
  final bool isAnnotated;

  /// Whether the class is annotated with `@Api(...)`.
  final bool isApi;

  /// How to create an instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// The `///` comment of the class, if any.
  final String? documentation;

  /// The key under which the class is bound when it is bound as itself.
  BindingKey get key => BindingKey(type, name);
}
```

**`packages/grund_generator/lib/src/model/lifetime.dart`** (новий):

```dart
/// How long the instances of a binding live; the generated binding class
/// (`Singleton`, `Scoped`, `Transient`) follows from it.
enum Lifetime {
  /// One instance per application: `Singleton`.
  singleton,

  /// One instance per call: `Scoped` (`Scope.call` in annotations).
  scoped,

  /// A new instance on every resolution: `Transient`.
  transient,
}
```

**`packages/grund_generator/lib/src/model/module_export.dart`** (повний вміст після зміни):

```dart
import 'binding_key.dart';
import 'type_model.dart';

/// One entry of `@Module(exports: ...)`.
sealed class ModuleExport {
  /// Creates the export.
  const ModuleExport();
}

/// An exported binding: a type or a `Key<T>('name')`.
final class KeyExport extends ModuleExport {
  /// Creates the export.
  const KeyExport(this.key);

  /// The exported key.
  final BindingKey key;
}

/// A re-exported imported module, written as its type.
final class ModuleReexport extends ModuleExport {
  /// Creates the export.
  const ModuleReexport(this.type);

  /// The class of the re-exported module.
  final TypeModel type;
}
```

**`packages/grund_generator/lib/src/model/module_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'binding_model.dart';
import 'module_export.dart';
import 'module_reference.dart';
import 'provider_model.dart';
import 'provides_model.dart';
import 'type_model.dart';

/// A class annotated with `@Module`.
final class ModuleModel {
  /// Creates the model.
  const ModuleModel({
    required this.type,
    required this.location,
    this.imports = const [],
    this.providers = const [],
    this.provides = const [],
    this.exports = const [],
    this.isGlobal = false,
    this.extendsModule = true,
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The module class.
  final TypeModel type;

  /// Where the class is declared.
  final SourceLocation location;

  /// Imported modules, in order.
  final List<ModuleReference> imports;

  /// Classes and `Bind`s, in order.
  final List<ProviderModel> providers;

  /// The `@Provides` methods, in declaration order.
  final List<ProvidesModel> provides;

  /// Exports, in order.
  final List<ModuleExport> exports;

  /// Whether the module is global.
  final bool isGlobal;

  /// Whether the class extends the core `Module`.
  final bool extendsModule;

  /// One sentence per annotation entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;

  /// The bindings the module owns, in the order the mixin writes them:
  /// providers first, then `@Provides` methods. A `@Provides` method with a
  /// problem has no key and is left out; the provider construct reports it.
  List<BindingModel> get bindings => [
    for (final provider in providers)
      BindingModel(
        key: provider.key,
        lifetime: provider.injectable.lifetime,
        dependencies: provider.injectable.constructor.dependencies,
        location: provider.injectable.location,
      ),
    for (final provided in provides)
      if (provided.key case final key?)
        BindingModel(
          key: key,
          lifetime: provided.lifetime,
          dependencies: provided.dependencies,
          location: provided.location,
        ),
  ];
}
```

**`packages/grund_generator/lib/src/model/module_reference.dart`** (повний вміст після зміни):

```dart
import 'constant_value.dart';
import 'type_model.dart';

/// A module listed in `@Module(imports: ...)`: a `const` instance.
sealed class ModuleReference {
  /// Creates the reference.
  const ModuleReference(this.type, this.instance);

  /// The module class.
  final TypeModel type;

  /// The instance as written in the annotation; the generated mixin writes
  /// the same constructor call.
  final ConstantValue instance;

  /// The reference as written in the annotation, for messages.
  String get display => type.display;
}

/// An instance of a class annotated with `@Module` in the generated package:
/// the generator knows its imports, bindings and exports.
final class LocalModuleReference extends ModuleReference {
  /// Creates the reference.
  const LocalModuleReference(super.type, super.instance);
}

/// An instance of any other `Module`: another package's module, or one
/// written with the explicit API. The generator cannot see its bindings, so
/// the graph check is partial for it; the core checks the rest at startup.
final class OpaqueModuleReference extends ModuleReference {
  /// Creates the reference.
  const OpaqueModuleReference(super.type, super.instance);
}
```

**`packages/grund_generator/lib/src/model/package_model.dart`** (повний вміст після зміни):

```dart
import 'package:pub_semver/pub_semver.dart';

import 'api_model.dart';
import 'dto_model.dart';
import 'injectable_model.dart';
import 'module_model.dart';
import 'provides_model.dart';
import 'route_model.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.injectables = const [],
    this.apis = const [],
    this.strayProvides = const [],
    this.strayRoutes = const [],
    this.dtos = const [],
  });

  /// The package name; the output is `lib/<packageName>.grund.dart`.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, in library-URI order, then source
  /// order within a library.
  final List<ModuleModel> modules;

  /// Classes annotated with `@Injectable` or `@Api`, each once, in
  /// library-URI order, then source order within a library.
  final List<InjectableModel> injectables;

  /// Classes annotated with `@Api`, in the same order.
  final List<ApiModel> apis;

  /// `@Provides` methods of classes that are not annotated with `@Module`.
  final List<ProvidesModel> strayProvides;

  /// Route methods of classes that are not annotated with `@Api`.
  final List<RouteModel> strayRoutes;

  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;

  /// Whether the package has no modules, injectables or APIs: there is
  /// nothing to generate, and a driver removes a library it generated
  /// before.
  bool get isEmpty => modules.isEmpty && injectables.isEmpty && apis.isEmpty;
}
```

**`packages/grund_generator/lib/src/model/param_location.dart`** (новий):

```dart
/// The request part a path, query, header or cookie parameter comes from.
enum ParamLocation {
  /// `@Path`: `c.path`.
  path('path'),

  /// `@Query`: `c.query`.
  query('query'),

  /// `@Header`: `c.headers`.
  header('headers'),

  /// `@Cookie`: `c.cookies`.
  cookie('cookies');

  const ParamLocation(this.reader);

  /// The `HttpCtx` getter that holds the `Params` of this part.
  final String reader;
}
```

**`packages/grund_generator/lib/src/model/param_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'constant_value.dart';
import 'param_source.dart';
import 'type_model.dart';
import 'validator_model.dart';

/// A parameter of a route handler method.
final class ParamModel {
  /// Creates the model.
  const ParamModel({
    required this.name,
    required this.type,
    required this.source,
    required this.isNamed,
    required this.location,
    this.validators = const [],
    this.defaultValue,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final TypeModel type;

  /// Where the value comes from.
  final ParamSource source;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;

  /// The validation annotations, in source order.
  final List<ValidatorModel> validators;

  /// The default value of an optional parameter; `null` when it has none.
  final ConstantValue? defaultValue;
}
```

**`packages/grund_generator/lib/src/model/param_source.dart`** (новий):

```dart
import 'binding_key.dart';
import 'body_kind.dart';
import 'param_location.dart';
import 'value_kind.dart';

/// Where the value of a route parameter comes from.
sealed class ParamSource {
  /// Creates the source.
  const ParamSource();
}

/// A named value of the request.
final class ValueSource extends ParamSource {
  /// Creates the source.
  const ValueSource(this.location, this.name, this.kind);

  /// The request part.
  final ParamLocation location;

  /// The name in the request.
  final String name;

  /// The type of the value.
  final ValueKind kind;
}

/// `@Body()`.
final class BodySource extends ParamSource {
  /// Creates the source.
  const BodySource(this.kind);

  /// How the body is read.
  final BodyKind kind;
}

/// A parameter of type `HttpCtx`: the context itself.
final class ContextSource extends ParamSource {
  /// Creates the source.
  const ContextSource();
}

/// A parameter without annotation: a value of the call scope, resolved by
/// its type (`c<T>()`).
final class CallScopeSource extends ParamSource {
  /// Creates the source.
  const CallScopeSource(this.key);

  /// The value looked up.
  final BindingKey key;
}

/// A parameter that cannot be filled, because of [problem].
final class InvalidSource extends ParamSource {
  /// Creates the source.
  const InvalidSource(this.problem);

  /// Why the parameter has no source, as a sentence fragment.
  final String problem;
}
```

**`packages/grund_generator/lib/src/model/provider_model.dart`** (повний вміст після зміни):

```dart
import 'binding_key.dart';
import 'injectable_model.dart';

/// One entry of `@Module(providers: ...)`: a class bound as itself, or
/// `Bind<I, C>()` (the interface `I` bound to the class `C`).
final class ProviderModel {
  /// Creates the provider; [key] is the interface for a `Bind`.
  const ProviderModel(this.key, this.injectable);

  /// What the provider is looked up by.
  final BindingKey key;

  /// The class that is created.
  final InjectableModel injectable;
}
```

**`packages/grund_generator/lib/src/model/provides_model.dart`** (новий):

```dart
import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'dependency_model.dart';
import 'lifetime.dart';
import 'type_model.dart';

/// A `static` method of a module class annotated with `@Provides`.
final class ProvidesModel {
  /// Creates the model.
  const ProvidesModel({
    required this.owner,
    required this.methodName,
    required this.location,
    this.key,
    this.lifetime = Lifetime.singleton,
    this.isAsync = false,
    this.dependencies = const [],
    this.documentation,
    this.problem,
  });

  /// The class that declares the method.
  final TypeModel owner;

  /// The method name.
  final String methodName;

  /// Where the method is declared.
  final SourceLocation location;

  /// The binding the method provides: its return type (without `Future`)
  /// and `@Named`; `null` when [problem] is set.
  final BindingKey? key;

  /// The lifetime of the binding.
  final Lifetime lifetime;

  /// Whether the method returns a `Future` or `FutureOr`.
  final bool isAsync;

  /// The parameters, in declaration order.
  final List<DependencyModel> dependencies;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot provide a binding, as a sentence; `null` when it
  /// can.
  final String? problem;
}
```

**`packages/grund_generator/lib/src/model/return_kind.dart`** (новий):

```dart
/// What a route handler returns, which decides how the generated handler
/// ends.
enum ReturnKind {
  /// A value (or a `Future` of one): serialized by the response codec.
  value,

  /// `void`, `Null` or a `Future` of them: the handler returns `null`, a 204.
  none,

  /// `Stream<List<int>>`: streamed bytes.
  byteStream,

  /// Any other `Stream<T>`: reserved for the SSE package.
  stream,

  /// A function, record or type parameter: cannot be a response.
  unsupported,
}
```

**`packages/grund_generator/lib/src/model/route_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'hook_model.dart';
import 'param_model.dart';
import 'return_kind.dart';
import 'type_model.dart';

/// A method of an `@Api` class annotated with `@Get`, `@Post`, `@Put`,
/// `@Patch` or `@Delete`.
final class RouteModel {
  /// Creates the model.
  const RouteModel({
    required this.method,
    required this.path,
    required this.handlerName,
    required this.returnType,
    required this.returnKind,
    required this.location,
    this.status,
    this.parameters = const [],
    this.use = const [],
    this.invalidEntries = const [],
    this.documentation,
    this.problem,
  });

  /// The upper-cased HTTP method.
  final String method;

  /// The path relative to the API path.
  final String path;

  /// The method name.
  final String handlerName;

  /// The declared return type.
  final TypeModel returnType;

  /// What the handler returns.
  final ReturnKind returnKind;

  /// Where the method is declared.
  final SourceLocation location;

  /// The response status of the annotation, or `null`.
  final int? status;

  /// The parameters, in declaration order.
  final List<ParamModel> parameters;

  /// Route-level hooks, in order.
  final List<HookModel> use;

  /// One sentence per `use` entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot be a handler, as a sentence; `null` when it can.
  final String? problem;

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  List<String> get pathParameters => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];
}
```

**`packages/grund_generator/lib/src/model/validator_model.dart`** (новий):

```dart
/// A constraint annotation (`@Range`, `@Length`, `@Pattern`, `@OneOf`) on a
/// route parameter.
sealed class ValidatorModel {
  /// Creates the validator.
  const ValidatorModel();

  /// The annotation as a user writes it, for messages.
  String get display;
}

/// `@Range(min:, max:)`.
final class RangeValidator extends ValidatorModel {
  /// Creates the validator.
  const RangeValidator({this.min, this.max});

  /// The smallest allowed value.
  final num? min;

  /// The largest allowed value.
  final num? max;

  @override
  String get display => '@Range';
}

/// `@Length(min:, max:)`.
final class LengthValidator extends ValidatorModel {
  /// Creates the validator.
  const LengthValidator({this.min, this.max});

  /// The shortest allowed length.
  final int? min;

  /// The longest allowed length.
  final int? max;

  @override
  String get display => '@Length';
}

/// `@Pattern(regex)`.
final class PatternValidator extends ValidatorModel {
  /// Creates the validator.
  const PatternValidator(this.regex);

  /// The regular expression source.
  final String regex;

  @override
  String get display => '@Pattern';
}

/// `@OneOf(values)`.
final class OneOfValidator extends ValidatorModel {
  /// Creates the validator.
  const OneOfValidator(this.values);

  /// The allowed values.
  final List<String> values;

  @override
  String get display => '@OneOf';
}
```

**`packages/grund_generator/lib/src/model/value_kind.dart`** (новий):

```dart
/// The type of a path, query, header or cookie parameter, which decides the
/// reader of `Params` that fills it.
enum ValueKind {
  /// `String`: `string`.
  string('string'),

  /// `int`: `integer`.
  integer('integer'),

  /// `double`: `decimal`.
  decimal('decimal'),

  /// `bool`: `boolean`.
  boolean('boolean'),

  /// `DateTime`: `dateTime`.
  dateTime('dateTime'),

  /// `Uri`: `uri`.
  uri('uri'),

  /// An enum: `enumOf`.
  enumeration('enumOf'),

  /// `List<String>` (repeated parameters): `all`.
  stringList('all'),

  /// Any other type: the parameter cannot come from a request part.
  unsupported('');

  const ValueKind(this.reader);

  /// The `Params` method that reads the value; the nullable variant adds
  /// `OrNull`.
  final String reader;
}
```


- [ ] **Крок 2: запуск.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test
```

Очікувано: `No issues found!`, `All tests passed!` (92 тести; старий fixture `users_app` вилучено, `users_app/lib/users_app.dart` — заглушка `library;`, поки не буде переписаний у задачі 18).

- [ ] **Крок 3: коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
dart format packages && git add -A && git commit -m "feat(generator): model and collector for modules, injectables, provides and apis"
```

---

### Задача 15: перевірки та діагностики

**Мета.** Конструкти `ModuleConstruct` і `ApiConstruct` (поки лише `validate`; `generate` повертає `const []`) із стабільними кодами та `path:line:col`. `GrundGenerator.core()` = `[ModuleConstruct(), ApiConstruct()]`. Таблиця кодів — у розділі «Перелік діагностик».

**Files.** Create `lib/src/constructs/*` (`module_scope`, `scoped_binding`, `import_cycle_finder`, `module_structure_check`, `binding_check`, `dependency_check`, `dependency_cycle_finder`, `captive_finder`, `route_paths`, `validator_check`, `param_check`, `route_check`, `api_check`, `route_conflict_check`, `module_construct`, `api_construct`); Modify `diagnostic_code.dart`, `grund_generator.dart`, `param_source.dart` (`InvalidSource` отримує `reason`, щоб відрізнити `parameter_without_source`), `param_reader.dart`, `route_model.dart` (геттер `pathParameters` видалено: його замінює `RoutePaths.parameters`); Test `test/construct/checks_test.dart`, `test/helpers/graph_models.dart`.

**Семантика видимості** — як у `VisibilityIndex` ядра: власні біндинги > експорти імпортів > експорти глобальних модулів. Перевірка `missing_provider` повна, якщо жоден модуль пакета не імпортує/реекспортує модуль з іншого пакета; інакше повідомляються лише ключі, які біндить якийсь локальний модуль (решту ловить `ModuleGraph.build` ядра до запуску фабрик). Двозначність (два імпорти експортують один ключ) генератор не перевіряє — це `AmbiguousProviderError` ядра.

- [ ] **Крок 1: тест, helper і код.** (Тест `checks_test.dart` падає: `GrundGenerator.core()` порожній.)

**`packages/grund_generator/test/construct/checks_test.dart`** (новий):

```dart
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/graph_models.dart';

void main() {
  late PackageModel cases; // Set in setUpAll.

  setUpAll(() async {
    cases = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']);
  });

  List<String> codes(PackageModel package) => [
    for (final d in const GrundGenerator.core().generate(package).diagnostics)
      d.code.id,
  ];

  test('a cycle between two bindings is circular_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', needs: ['A']),
      ],
    );

    expect(
      codes(GraphModels.package([module])),
      contains('circular_dependency'),
    );
  });

  test('a singleton on a call-scoped binding is captive_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', lifetime: Lifetime.scoped),
      ],
    );

    expect(codes(GraphModels.package([module])), ['captive_dependency']);
  });

  test('a dependency nobody binds is missing_provider', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([module])), ['missing_provider']);
  });

  test('a binding exported by another module needs an import', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final app = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );
    final imported = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([lib, app])), ['missing_provider']);
    expect(codes(GraphModels.package([lib, imported])), isEmpty);
  });

  test('two bindings of one key are duplicate_binding', () {
    final module = GraphModels.module(
      'App',
      providers: [GraphModels.provider('A'), GraphModels.provider('A')],
    );

    expect(codes(GraphModels.package([module])), ['duplicate_binding']);
  });

  test('the invalid api routes report their stable codes', () {
    expect(
      codes(cases).toSet(),
      containsAll([
        'invalid_route_handler',
        'parameter_without_source',
        'missing_from_json',
        'unknown_path_parameter',
        'invalid_handler_parameter',
        'invalid_validator',
        'unsupported_return_type',
        'stream_return_reserved',
        'duplicate_route',
        'invalid_hook',
        'invalid_status',
        'route_outside_api',
      ]),
    );
  });
}
```

**`packages/grund_generator/test/model/model_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/generated_names.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:test/test.dart';

const _users = 'package:app/users.dart';

TypeModel _type(
  String name, {
  bool nullable = false,
  List<TypeModel> args = const [],
}) => TypeModel(
  name: name,
  kind: TypeKind.interface,
  libraryUri: _users,
  typeArguments: args,
  isNullable: nullable,
);

void main() {
  test('a diagnostic prints as path:line:col: error: message [code]', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.missingProvider,
      const SourceLocation('lib/users.dart', 3, 7),
      'No provider for Repo in module "users".',
    );

    expect(
      '$diagnostic',
      'lib/users.dart:3:7: error: No provider for Repo in module "users". '
          '[missing_provider]',
    );
  });

  test('diagnostics sort by path, line, column, then code', () {
    Diagnostic at(String path, int line, int column, DiagnosticCode code) =>
        Diagnostic(code, SourceLocation(path, line, column), 'm');
    final sorted = [
      at('lib/b.dart', 1, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 9, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 2, 5, DiagnosticCode.notInjectable),
      at('lib/a.dart', 2, 5, DiagnosticCode.missingProvider),
      at('lib/a.dart', 2, 1, DiagnosticCode.duplicateRoute),
    ]..sort();

    expect(
      [for (final d in sorted) '${d.location} ${d.code.id}'],
      [
        'lib/a.dart:2:1 duplicate_route',
        'lib/a.dart:2:5 missing_provider',
        'lib/a.dart:2:5 not_injectable',
        'lib/a.dart:9:1 duplicate_route',
        'lib/b.dart:1:1 duplicate_route',
      ],
    );
  });

  test('type models compare by library, name, arguments and nullability', () {
    final list = _type('List', args: [_type('User')]);

    expect(list, _type('List', args: [_type('User')]));
    expect(list.display, 'List<User>');
    expect(_type('User', nullable: true).display, 'User?');
    expect(_type('User', nullable: true).nonNullable, _type('User'));
    expect(_type('User'), isNot(_type('User', nullable: true)));
    expect(_type('User').isDeclaredAs('User', _users), isTrue);
  });

  test('binding keys: a type with an optional name', () {
    final repo = BindingKey(_type('Repo'));
    final named = BindingKey(_type('Repo'), 'main');

    expect(repo, BindingKey(_type('Repo')));
    expect(repo, isNot(named));
    expect(named.display, "Repo('main')");
    expect(repo.display, 'Repo');
  });

  test('binding keys sort by display, then library', () {
    final keys = [
      BindingKey(_type('Repo'), 'b'),
      BindingKey(_type('Repo')),
      BindingKey(_type('Clock')),
    ]..sort();

    expect([for (final k in keys) k.display], ['Clock', 'Repo', "Repo('b')"]);
  });

  test('generated names derive from class names', () {
    expect(GeneratedNames.module('UsersModule'), r'$UsersModule');
    expect(GeneratedNames.routes('TasksApi'), 'TasksApiRoutes');
    expect(GeneratedNames.library('shop'), 'package:shop/shop.grund.dart');
  });
}
```

**`packages/grund_generator/lib/src/collector/param_reader.dart`** (повний вміст після зміни):

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/constant_value.dart';
import '../model/param_location.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/value_kind.dart';
import 'annotations.dart';
import 'body_kind_reader.dart';
import 'constant_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';
import 'validator_reader.dart';
import 'value_kind_reader.dart';

/// Reads where a parameter of a route handler gets its value from.
final class ParamReader {
  /// Creates the reader.
  ParamReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  static const _sources = {'Path', 'Query', 'Header', 'Cookie', 'Body'};

  static const _locations = {
    'Path': ParamLocation.path,
    'Query': ParamLocation.query,
    'Header': ParamLocation.header,
    'Cookie': ParamLocation.cookie,
  };

  /// The model of [parameter].
  ParamModel read(FormalParameterElement parameter) => ParamModel(
    name: parameter.displayName,
    type: TypeReader.read(parameter.type),
    source: _source(parameter),
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
    validators: ValidatorReader.read(parameter),
    defaultValue: _default(parameter),
  );

  ParamSource _source(FormalParameterElement parameter) {
    final type = parameter.type;
    final annotations = Annotations.all(parameter, _sources);
    final shown = '${parameter.displayName} (${type.getDisplayString()})';
    if (annotations.length > 1) {
      return InvalidSource(
        InvalidSourceReason.ambiguous,
        'Parameter $shown has more than one of @Path, @Query, @Header, '
        '@Cookie and @Body.',
      );
    }
    if (annotations.isEmpty) return _unannotated(parameter, shown);
    final annotation = annotations.single;
    final name = annotation.type?.element?.name;
    final location = _locations[name];
    if (location == null) return BodySource(BodyKindReader.read(type));
    return _value(annotation, location, parameter, shown);
  }

  static ParamSource _value(
    DartObject annotation,
    ParamLocation location,
    FormalParameterElement parameter,
    String shown,
  ) {
    final kind = ValueKindReader.read(parameter.type);
    final isList = kind == ValueKind.stringList;
    if (kind == ValueKind.unsupported ||
        (isList && location == ParamLocation.path)) {
      return InvalidSource(
        InvalidSourceReason.unsupportedType,
        'Parameter $shown: @${annotation.type?.element?.name} supports '
        'String, int, double, bool, DateTime, Uri and enums, and '
        'List<String> except for @Path.',
      );
    }
    final name =
        Annotations.field(annotation, 'name')?.toStringValue() ??
        parameter.displayName;
    return ValueSource(location, name, kind);
  }

  static ParamSource _unannotated(
    FormalParameterElement parameter,
    String shown,
  ) {
    final type = parameter.type;
    if (TypeReader.isFrom(type, 'HttpCtx', 'package:grund_http/')) {
      return const ContextSource();
    }
    if (type is InterfaceType &&
        type.element is ClassElement &&
        !type.element.library.isInSdk) {
      return CallScopeSource(
        BindingKey(
          TypeReader.read(type).nonNullable,
          Annotations.named(parameter),
        ),
      );
    }
    return InvalidSource(
      InvalidSourceReason.missing,
      'Parameter $shown has no source: annotate it with @Path, @Query, '
      '@Header, @Cookie or @Body, or give it the class type of a value of '
      'the call scope.',
    );
  }

  static ConstantValue? _default(FormalParameterElement parameter) =>
      parameter.hasDefaultValue
      ? ConstantReader.read(parameter.computeConstantValue())
      : null;
}
```

**`packages/grund_generator/lib/src/construct/grund_generator.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../constructs/api_construct.dart';
import '../constructs/module_construct.dart';
import '../emit/library_writer.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generated_unit.dart';
import 'generation_result.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// Every construct validates first; any diagnostic stops generation, so a
/// package with an error never gets a half-generated library.
final class GrundGenerator {
  /// Creates the generator; [constructs] run in order.
  const GrundGenerator(this.constructs);

  /// The v1 constructs: modules with their bindings, and APIs.
  const GrundGenerator.core()
    : constructs = const [ModuleConstruct(), ApiConstruct()];

  /// The constructs.
  final List<Construct> constructs;

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final diagnostics = {
      for (final construct in constructs) ...construct.validate(package),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final units = [
      for (final construct in constructs) ...construct.generate(package),
    ];
    final dartUnits = units.whereType<DartUnit>().toList();
    final duplicates = _duplicateNames(dartUnits);
    if (duplicates.isNotEmpty) return GenerationResult.failed(duplicates);
    return GenerationResult.generated(
      library: LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: <Spec>[for (final unit in dartUnits) unit.spec],
      ),
      files: units.whereType<FileUnit>().toList(),
    );
  }

  static List<Diagnostic> _duplicateNames(List<DartUnit> units) {
    final first = <String, DartUnit>{};
    return [
      for (final unit in units)
        if (first.putIfAbsent(unit.name, () => unit) case final other
            when other != unit)
          Diagnostic(
            DiagnosticCode.duplicateGeneratedName,
            unit.origin,
            'Generated name ${unit.name} is used twice: for the declaration '
            'at ${other.origin} and for this one. Rename one of them.',
          ),
    ]..sort();
  }
}
```

**`packages/grund_generator/lib/src/constructs/api_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/api_model.dart';
import '../model/injectable_model.dart';
import '../model/lifetime.dart';
import '../model/package_model.dart';
import 'route_check.dart';
import 'route_paths.dart';

/// Checks the `@Api` classes of a package: how they are provided, their
/// hooks and each of their routes.
abstract final class ApiCheck {
  /// The problems of the apis of [package].
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    for (final api in package.apis) {
      yield* _provided(api, package);
      yield* _hooks(api);
      for (final route in api.routes) {
        yield* RouteCheck.check(route, RoutePaths.join(api.path, route.path));
      }
    }
    for (final route in package.strayRoutes) {
      yield Diagnostic(
        DiagnosticCode.routeOutsideApi,
        route.location,
        'Route ${route.handlerName} is in a class that is not annotated with '
        '@Api; it is never served.',
      );
    }
  }

  static Iterable<Diagnostic> _provided(
    ApiModel api,
    PackageModel package,
  ) sync* {
    final injectable = _injectable(api, package);
    if (injectable != null && injectable.lifetime != Lifetime.singleton) {
      yield Diagnostic(
        DiagnosticCode.invalidApi,
        api.location,
        '${api.type} is an @Api but its @Injectable has scope '
        '${injectable.lifetime.name}; an API is created once, so it must be '
        'a singleton.',
      );
    }
    final owners = [
      for (final module in package.modules)
        if (module.providers.any((p) => p.injectable.type == api.type))
          module.type.display,
    ];
    if (owners.length > 1) {
      yield Diagnostic(
        DiagnosticCode.duplicateApi,
        api.location,
        '${api.type} is provided by modules [${owners.join(', ')}]; its '
        'routes would be registered twice. Provide it in one module.',
      );
    }
  }

  static InjectableModel? _injectable(ApiModel api, PackageModel package) =>
      package.injectables.where((i) => i.type == api.type).firstOrNull;

  static Iterable<Diagnostic> _hooks(ApiModel api) sync* {
    for (final problem in api.invalidEntries) {
      yield Diagnostic(
        DiagnosticCode.invalidHook,
        api.location,
        'Api ${api.type}: $problem',
      );
    }
    yield* RouteCheck.hookConstants(api.use, api.location, '${api.type}');
  }
}
```

**`packages/grund_generator/lib/src/constructs/api_construct.dart`** (новий):

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'api_check.dart';
import 'route_conflict_check.dart';

/// Validates the `@Api` classes of a package and their routes.
final class ApiConstruct implements Construct {
  /// Creates the construct.
  const ApiConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => [
    ...ApiCheck.check(package),
    ...RouteConflictCheck.check(package),
  ];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [];
}
```

**`packages/grund_generator/lib/src/constructs/binding_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/type_model.dart';

/// Checks that every provider class and `@Provides` method can be called by
/// generated code and that its names are usable.
abstract final class BindingCheck {
  /// The problems of the providers of [package].
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    final checked = <TypeModel>{};
    for (final module in package.modules) {
      yield* _providers(module, checked);
      for (final provides in module.provides) {
        yield* _provides(provides);
      }
    }
    for (final injectable in package.injectables) {
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
    for (final provides in package.strayProvides) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        '@Provides method ${provides.owner}.${provides.methodName} is in a '
        'class that is not annotated with @Module; it is never called.',
      );
    }
  }

  static Iterable<Diagnostic> _providers(
    ModuleModel module,
    Set<TypeModel> checked,
  ) sync* {
    for (final provider in module.providers) {
      final injectable = provider.injectable;
      if (!injectable.isAnnotated) {
        yield Diagnostic(
          DiagnosticCode.notInjectable,
          injectable.location,
          '${injectable.type} is a provider of module ${module.type} but is '
          'not annotated with @Injectable().',
        );
      }
      yield* _name(provider.key, injectable.location);
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
  }

  static Iterable<Diagnostic> _injectable(InjectableModel injectable) sync* {
    if (injectable.constructor.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidConstructor,
        injectable.location,
        problem,
      );
    }
    yield* _dependencies(injectable.constructor.dependencies);
  }

  static Iterable<Diagnostic> _provides(ProvidesModel provides) sync* {
    if (provides.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        problem,
      );
    }
    if (provides.key case final key?) yield* _name(key, provides.location);
    yield* _dependencies(provides.dependencies);
  }

  static Iterable<Diagnostic> _dependencies(
    List<DependencyModel> dependencies,
  ) sync* {
    for (final dependency in dependencies) {
      if (dependency.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidDependency,
          dependency.location,
          problem,
        );
      }
      if (dependency.key case final key?) {
        yield* _name(key, dependency.location);
      }
    }
  }

  static Iterable<Diagnostic> _name(
    BindingKey key,
    SourceLocation location,
  ) sync* {
    if (key.name != '') return;
    yield Diagnostic(
      DiagnosticCode.invalidName,
      location,
      'The name of ${key.type} is empty; give @Named a non-empty name.',
    );
  }
}
```

**`packages/grund_generator/lib/src/constructs/captive_finder.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_key.dart';
import '../model/lifetime.dart';
import '../model/module_model.dart';
import 'module_scope.dart';
import 'scoped_binding.dart';

/// Finds singletons that keep a call-scoped binding alive.
final class CaptiveFinder {
  /// Creates the finder over the bindings of [modules], resolved by [scope].
  CaptiveFinder(this._scope, this._modules);

  final ModuleScope _scope;

  final List<ModuleModel> _modules;

  /// One diagnostic per singleton that reaches a call-scoped binding
  /// directly or through transient ones.
  List<Diagnostic> find() => [
    for (final module in _modules)
      for (final binding in module.bindings)
        if (binding.lifetime == Lifetime.singleton)
          ..._captive((owner: module, binding: binding)),
  ];

  Iterable<Diagnostic> _captive(ScopedBinding singleton) sync* {
    final path = _pathToScoped(singleton, {singleton}, [singleton.binding.key]);
    if (path == null) return;
    yield Diagnostic(
      DiagnosticCode.captiveDependency,
      singleton.binding.location,
      'Singleton ${path.first} depends on the call-scoped ${path.last} '
      '(${path.join(' -> ')}); a singleton outlives every call. Make '
      '${path.first} call-scoped or transient, or ${path.last} a singleton.',
    );
  }

  List<BindingKey>? _pathToScoped(
    ScopedBinding from,
    Set<ScopedBinding> seen,
    List<BindingKey> path,
  ) {
    final visible = _scope.visibleIn(from.owner);
    for (final dependency in from.binding.dependencies) {
      final next = visible[dependency.key];
      if (next == null || !seen.add(next)) continue;
      final trail = [...path, next.binding.key];
      switch (next.binding.lifetime) {
        case Lifetime.scoped:
          return trail;
        case Lifetime.transient:
          if (_pathToScoped(next, seen, trail) case final found?) return found;
        case Lifetime.singleton:
          break;
      }
    }
    return null;
  }
}
```

**`packages/grund_generator/lib/src/constructs/dependency_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/api_model.dart';
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/package_model.dart';
import '../model/type_model.dart';
import 'captive_finder.dart';
import 'dependency_cycle_finder.dart';
import 'module_scope.dart';

/// Checks that every dependency of a binding is visible in its module and
/// that the bindings form no cycle and no captive dependency.
final class DependencyCheck {
  DependencyCheck._(this._package, this._scope)
    : _isPartial = _hasOpaqueReference(_package.modules);

  final PackageModel _package;

  final ModuleScope _scope;

  // A module from another package may export what looks missing, so then
  // only keys that a module of this package binds are reported.
  final bool _isPartial;

  /// The dependency problems of the modules of [package].
  ///
  /// The import graph must be acyclic.
  static List<Diagnostic> check(PackageModel package) {
    final modules = package.modules;
    final check = DependencyCheck._(package, ModuleScope(modules));
    return [
      for (final module in modules) ...check._missing(module),
      ...DependencyCycleFinder(check._scope, modules).find(),
      ...CaptiveFinder(check._scope, modules).find(),
    ];
  }

  static bool _hasOpaqueReference(List<ModuleModel> modules) {
    final local = {for (final module in modules) module.type};
    return modules.any(
      (module) =>
          module.imports.any((i) => i is OpaqueModuleReference) ||
          module.exports.any(
            (e) => e is ModuleReexport && !local.contains(e.type),
          ),
    );
  }

  Iterable<Diagnostic> _missing(ModuleModel module) sync* {
    final visible = _scope.visibleIn(module);
    for (final binding in module.bindings) {
      for (final dependency in binding.dependencies) {
        final key = dependency.key;
        if (key == null || visible.containsKey(key)) continue;
        if (_isUnknowable(key)) continue;
        yield _diagnostic(module, key, binding.key, dependency.location);
      }
    }
    yield* _hooks(module, visible.containsKey);
  }

  Iterable<Diagnostic> _hooks(
    ModuleModel module,
    bool Function(BindingKey) isVisible,
  ) sync* {
    for (final provider in module.providers) {
      final api = _apiOf(provider.injectable.type);
      if (api == null) continue;
      for (final hook in [
        ...api.use,
        for (final route in api.routes) ...route.use,
      ]) {
        final key = BindingKey(hook.type);
        if (hook.isInstance || isVisible(key) || _isUnknowable(key)) continue;
        yield _diagnostic(module, key, provider.key, api.location);
      }
    }
  }

  ApiModel? _apiOf(TypeModel type) =>
      _package.apis.where((api) => api.type == type).firstOrNull;

  bool _isUnknowable(BindingKey key) =>
      _isPartial && _scope.declaring(key).isEmpty;

  Diagnostic _diagnostic(
    ModuleModel module,
    BindingKey key,
    BindingKey owner,
    SourceLocation location,
  ) {
    final declaring = _scope.declaring(key);
    final hint = declaring.isEmpty
        ? ''
        : ' It is bound in module(s) [${declaring.join(', ')}]; export it '
              'there and import that module into ${module.type}.';
    return Diagnostic(
      DiagnosticCode.missingProvider,
      location,
      'No provider for $key in module ${module.type} (needed by $owner).'
      '$hint',
    );
  }
}
```

**`packages/grund_generator/lib/src/constructs/dependency_cycle_finder.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/module_model.dart';
import 'module_scope.dart';
import 'scoped_binding.dart';

/// Finds cycles in the dependencies between the bindings of a package.
final class DependencyCycleFinder {
  /// Creates the finder over the bindings of [modules], resolved by [scope].
  DependencyCycleFinder(this._scope, this._modules);

  final ModuleScope _scope;

  final List<ModuleModel> _modules;

  final Set<ScopedBinding> _done = {};

  final List<ScopedBinding> _path = [];

  /// One diagnostic per cycle found.
  List<Diagnostic> find() {
    final found = <Diagnostic>[];
    for (final module in _modules) {
      for (final binding in module.bindings) {
        _visit((owner: module, binding: binding), found);
      }
    }
    return found;
  }

  void _visit(ScopedBinding node, List<Diagnostic> found) {
    final index = _path.indexOf(node);
    if (index >= 0) {
      found.add(_report(_path.sublist(index)));
      return;
    }
    if (_done.contains(node)) return;
    _path.add(node);
    final visible = _scope.visibleIn(node.owner);
    for (final dependency in node.binding.dependencies) {
      if (visible[dependency.key] case final next?) _visit(next, found);
    }
    _path.removeLast();
    _done.add(node);
  }

  Diagnostic _report(List<ScopedBinding> cycle) {
    final names = [...cycle, cycle.first].map((node) => node.binding.key);
    return Diagnostic(
      DiagnosticCode.circularDependency,
      cycle.first.binding.location,
      'Circular dependency: ${names.join(' -> ')}.',
    );
  }
}
```

**`packages/grund_generator/lib/src/constructs/import_cycle_finder.dart`** (новий):

```dart
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/type_model.dart';

/// Finds cycles in the import graph of the modules of one package.
final class ImportCycleFinder {
  /// Creates the finder over [modules].
  ImportCycleFinder(List<ModuleModel> modules)
    : _modules = modules,
      _byType = {for (final module in modules) module.type: module};

  final List<ModuleModel> _modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Set<ModuleModel> _done = {};

  final List<ModuleModel> _path = [];

  /// Every cycle found, each starting at its first module in package order.
  List<List<ModuleModel>> find() {
    final found = <List<ModuleModel>>[];
    for (final module in _modules) {
      _visit(module, found);
    }
    return found;
  }

  void _visit(ModuleModel module, List<List<ModuleModel>> found) {
    final index = _path.indexOf(module);
    if (index >= 0) {
      found.add(_path.sublist(index));
      return;
    }
    if (_done.contains(module)) return;
    _path.add(module);
    for (final reference in module.imports) {
      if (reference is! LocalModuleReference) continue;
      if (_byType[reference.type] case final next?) _visit(next, found);
    }
    _path.removeLast();
    _done.add(module);
  }
}
```

**`packages/grund_generator/lib/src/constructs/module_construct.dart`** (новий):

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'binding_check.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';

/// Validates the modules of a package and their bindings.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) {
    final own = [
      ...ModuleStructureCheck.check(package.modules),
      ...BindingCheck.check(package),
    ];
    return own.isEmpty ? DependencyCheck.check(package) : own;
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [];
}
```

**`packages/grund_generator/lib/src/constructs/module_scope.dart`** (новий):

```dart
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/type_model.dart';
import 'scoped_binding.dart';

/// Which bindings a module of the package can see, the way the core's
/// module graph decides it: its own bindings, then what its imports export,
/// then what global modules export; a nearer tier shadows a farther one.
///
/// Modules from other packages are not known here and see/export nothing.
final class ModuleScope {
  /// Creates the scope over the [_modules] of one package.
  ModuleScope(this._modules)
    : _byType = {for (final module in _modules) module.type: module};

  final List<ModuleModel> _modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Map<ModuleModel, Map<BindingKey, ScopedBinding>> _visible = {};

  /// The bindings visible in [module], by key.
  ///
  /// The import graph must be acyclic: re-exports are followed.
  Map<BindingKey, ScopedBinding> visibleIn(ModuleModel module) =>
      _visible.putIfAbsent(module, () => _computeVisible(module));

  /// The display names of the modules that bind [key].
  List<String> declaring(BindingKey key) => [
    for (final module in _modules)
      if (module.bindings.any((binding) => binding.key == key))
        module.type.display,
  ];

  Map<BindingKey, ScopedBinding> _computeVisible(ModuleModel module) => {
    for (final global in _modules.reversed)
      if (global.isGlobal && global != module) ..._exported(global),
    for (final reference in module.imports.reversed) ..._exportedBy(reference),
    for (final binding in module.bindings.reversed)
      binding.key: (owner: module, binding: binding),
  };

  Map<BindingKey, ScopedBinding> _exportedBy(ModuleReference reference) =>
      switch (reference) {
        LocalModuleReference(:final type) => _exportedByType(type),
        OpaqueModuleReference() => const {},
      };

  Map<BindingKey, ScopedBinding> _exportedByType(TypeModel type) =>
      switch (_byType[type]) {
        final module? => _exported(module),
        null => const {},
      };

  Map<BindingKey, ScopedBinding> _exported(ModuleModel module) => {
    for (final export in module.exports.reversed)
      ...switch (export) {
        KeyExport(:final key) => _own(module, key),
        ModuleReexport(:final type) => _exportedByType(type),
      },
  };

  Map<BindingKey, ScopedBinding> _own(ModuleModel module, BindingKey key) => {
    for (final binding in module.bindings.reversed)
      if (binding.key == key) key: (owner: module, binding: binding),
  };
}
```

**`packages/grund_generator/lib/src/constructs/module_structure_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import 'import_cycle_finder.dart';

/// Checks what a module declares without looking at other modules'
/// bindings: its class, entries, duplicates, exports and constants.
abstract final class ModuleStructureCheck {
  /// The structural problems of [modules].
  static Iterable<Diagnostic> check(List<ModuleModel> modules) sync* {
    yield* _importCycles(modules);
    for (final module in modules) {
      yield* _moduleClass(module);
      yield* _entries(module);
      yield* _duplicateBindings(module);
      yield* _exports(module);
      yield* _constants(module);
    }
  }

  static Iterable<Diagnostic> _importCycles(List<ModuleModel> modules) sync* {
    final reported = <ModuleModel>{};
    for (final cycle in ImportCycleFinder(modules).find()) {
      if (cycle.any(reported.contains)) continue;
      reported.addAll(cycle);
      yield Diagnostic(
        DiagnosticCode.circularModuleImport,
        cycle.first.location,
        'Module imports form a cycle: '
        '${[...cycle, cycle.first].map((m) => m.type).join(' -> ')}. Move '
        'the shared providers into a third module imported by both.',
      );
    }
  }

  static Iterable<Diagnostic> _moduleClass(ModuleModel module) sync* {
    if (module.extendsModule) return;
    yield Diagnostic(
      DiagnosticCode.invalidModuleClass,
      module.location,
      '${module.type} is annotated with @Module but does not extend Module '
      'of package:grund/grund.dart. Write "final class ${module.type} '
      'extends Module with \$${module.type}".',
    );
  }

  static Iterable<Diagnostic> _entries(ModuleModel module) => [
    for (final problem in module.invalidEntries)
      Diagnostic(
        DiagnosticCode.invalidModuleEntry,
        module.location,
        'Module ${module.type}: $problem',
      ),
  ];

  static Iterable<Diagnostic> _duplicateBindings(ModuleModel module) sync* {
    final seen = <BindingKey>{};
    for (final binding in module.bindings) {
      if (seen.add(binding.key)) continue;
      yield Diagnostic(
        DiagnosticCode.duplicateBinding,
        binding.location,
        'Module ${module.type} binds ${binding.key} more than once.',
      );
    }
  }

  static Iterable<Diagnostic> _exports(ModuleModel module) sync* {
    final keys = {for (final binding in module.bindings) binding.key};
    final imported = {for (final reference in module.imports) reference.type};
    for (final export in module.exports) {
      final (isValid, what) = switch (export) {
        KeyExport(:final key) => (keys.contains(key), '$key'),
        ModuleReexport(:final type) => (
          imported.contains(type),
          'module $type',
        ),
      };
      if (isValid) continue;
      yield Diagnostic(
        DiagnosticCode.invalidExport,
        module.location,
        'Module ${module.type} exports $what, which is neither one of its '
        'bindings nor one of its imports.',
      );
    }
  }

  static Iterable<Diagnostic> _constants(ModuleModel module) sync* {
    for (final reference in module.imports) {
      if (reference.instance.unsupported case final unsupported?) {
        yield Diagnostic(
          DiagnosticCode.unsupportedConstant,
          module.location,
          'Module ${module.type}: the import ${reference.display} cannot be '
          'written in generated code: ${unsupported.reason}. Use public '
          'constants and const constructors of public classes.',
        );
      }
    }
  }
}
```

**`packages/grund_generator/lib/src/constructs/param_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/body_kind.dart';
import '../model/param_location.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/route_model.dart';
import 'route_paths.dart';
import 'validator_check.dart';

/// Checks the parameters of one route handler.
abstract final class ParamCheck {
  /// The problems of the parameters of [route] whose full path is [path].
  static Iterable<Diagnostic> check(RouteModel route, String path) sync* {
    final known = RoutePaths.parameters(path);
    var bodies = 0;
    for (final param in route.parameters) {
      if (param.source is BodySource && ++bodies > 1) {
        yield _diagnostic(
          DiagnosticCode.invalidHandlerParameter,
          param,
          'Parameter ${param.name} is a second @Body; a request has one body.',
        );
      }
      yield* _source(param, known, path);
      yield* ValidatorCheck.check(param);
    }
  }

  static Iterable<Diagnostic> _source(
    ParamModel param,
    List<String> known,
    String path,
  ) sync* {
    switch (param.source) {
      case InvalidSource(:final reason, :final problem):
        yield _diagnostic(
          reason == InvalidSourceReason.missing
              ? DiagnosticCode.parameterWithoutSource
              : DiagnosticCode.invalidHandlerParameter,
          param,
          problem,
        );
      case BodySource(kind: BodyKind.unsupported):
        yield _diagnostic(
          DiagnosticCode.missingFromJson,
          param,
          'The @Body parameter ${param.name} has type ${param.type}, which '
          'cannot be read: use a class with a fromJson(Map<String, Object?>) '
          'factory, a List of one, Map<String, Object?> or Uint8List.',
        );
      case ValueSource(location: ParamLocation.path, :final name):
        yield* _pathParameter(param, name, known, path);
      case _:
        break;
    }
  }

  static Iterable<Diagnostic> _pathParameter(
    ParamModel param,
    String name,
    List<String> known,
    String path,
  ) sync* {
    if (!known.contains(name)) {
      yield _diagnostic(
        DiagnosticCode.unknownPathParameter,
        param,
        'The path $path has no parameter :$name for ${param.name}; its '
        'parameters are [${known.join(', ')}].',
      );
    }
    if (param.type.isNullable) {
      yield _diagnostic(
        DiagnosticCode.invalidHandlerParameter,
        param,
        'The path parameter ${param.name} cannot be nullable: a path always '
        'has its parameters.',
      );
    }
  }

  static Diagnostic _diagnostic(
    DiagnosticCode code,
    ParamModel param,
    String message,
  ) => Diagnostic(code, param.location, message);
}
```

**`packages/grund_generator/lib/src/constructs/route_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/hook_model.dart';
import '../model/return_kind.dart';
import '../model/route_model.dart';
import 'param_check.dart';

/// Checks one route handler: its annotation, status, result, hooks and
/// parameters.
abstract final class RouteCheck {
  /// The problems of [route] whose full path is [path].
  static Iterable<Diagnostic> check(RouteModel route, String path) sync* {
    final where = '${route.handlerName} ($path)';
    if (route.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidRouteHandler,
        route.location,
        problem,
      );
      return;
    }
    yield* _status(route, where);
    yield* _result(route, where);
    yield* _hooks(route);
    yield* ParamCheck.check(route, path);
  }

  static Iterable<Diagnostic> _status(RouteModel route, String where) sync* {
    final status = route.status;
    if (status == null || (status >= 100 && status <= 599)) return;
    yield Diagnostic(
      DiagnosticCode.invalidStatus,
      route.location,
      'Route $where has status $status, which is not an HTTP status code '
      '(100 to 599).',
    );
  }

  static Iterable<Diagnostic> _result(RouteModel route, String where) sync* {
    switch (route.returnKind) {
      case ReturnKind.unsupported:
        yield Diagnostic(
          DiagnosticCode.unsupportedReturnType,
          route.location,
          'Route $where returns ${route.returnType}, which cannot be sent: '
          'return a value, void, or a Stream<List<int>>.',
        );
      case ReturnKind.stream:
        yield Diagnostic(
          DiagnosticCode.streamReturnReserved,
          route.location,
          'Route $where returns ${route.returnType}; streams of events are '
          'reserved for grund_sse. Return a Stream<List<int>> for bytes.',
        );
      case ReturnKind.value || ReturnKind.none || ReturnKind.byteStream:
        break;
    }
  }

  static Iterable<Diagnostic> _hooks(RouteModel route) sync* {
    for (final problem in route.invalidEntries) {
      yield Diagnostic(
        DiagnosticCode.invalidHook,
        route.location,
        'Route ${route.handlerName}: $problem',
      );
    }
    yield* hookConstants(route.use, route.location, route.handlerName);
  }

  /// The hooks of [hooks] that cannot be written in generated code, found in
  /// [owner] at [location].
  static Iterable<Diagnostic> hookConstants(
    List<HookModel> hooks,
    SourceLocation location,
    String owner,
  ) sync* {
    for (final hook in hooks) {
      if (hook.expression.unsupported case final unsupported?) {
        yield Diagnostic(
          DiagnosticCode.unsupportedConstant,
          location,
          '$owner: the hook ${hook.type} cannot be written in generated '
          'code: ${unsupported.reason}. Use public constants and const '
          'constructors of public classes.',
        );
      }
    }
  }
}
```

**`packages/grund_generator/lib/src/constructs/route_conflict_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/package_model.dart';
import 'route_paths.dart';

/// Finds routes of a package that answer the same requests.
abstract final class RouteConflictCheck {
  /// One diagnostic for every route after the first of the same method and
  /// path shape, in package order.
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    final first = <String, SourceLocation>{};
    for (final api in package.apis) {
      for (final route in api.routes) {
        if (route.problem != null) continue;
        final path = RoutePaths.join(api.path, route.path);
        final id = '${route.method} ${RoutePaths.shape(path)}';
        final other = first.putIfAbsent(id, () => route.location);
        if (other == route.location) continue;
        yield Diagnostic(
          DiagnosticCode.duplicateRoute,
          route.location,
          '${route.method} $path is already handled at $other. Change the '
          'method or the path of one of them.',
        );
      }
    }
  }
}
```

**`packages/grund_generator/lib/src/constructs/route_paths.dart`** (новий):

```dart
/// Joins and compares the paths of routes.
abstract final class RoutePaths {
  /// The path of a route as the server sees it: [apiPath] followed by
  /// [routePath], with a leading slash, no empty segments and no trailing
  /// slash (except the root).
  static String join(String apiPath, String routePath) {
    final segments = [
      for (final segment in '$apiPath/$routePath'.split('/'))
        if (segment.isNotEmpty) segment,
    ];
    return '/${segments.join('/')}';
  }

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  static List<String> parameters(String path) => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];

  /// [path] with every parameter name erased: two paths with the same shape
  /// match the same requests.
  static String shape(String path) => [
    for (final segment in path.split('/'))
      segment.startsWith(':') ? ':' : segment,
  ].join('/');
}
```

**`packages/grund_generator/lib/src/constructs/scoped_binding.dart`** (новий):

```dart
import '../model/binding_model.dart';
import '../model/module_model.dart';

/// A binding together with the module that declares it.
typedef ScopedBinding = ({ModuleModel owner, BindingModel binding});
```

**`packages/grund_generator/lib/src/constructs/validator_check.dart`** (новий):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/validator_model.dart';
import '../model/value_kind.dart';

/// Checks `@Range`, `@Length`, `@Pattern` and `@OneOf` against the
/// parameter they are on.
abstract final class ValidatorCheck {
  /// The problems of the validators of [param].
  static Iterable<Diagnostic> check(ParamModel param) sync* {
    for (final validator in param.validators) {
      final problem = _problem(param, validator);
      if (problem == null) continue;
      yield Diagnostic(
        DiagnosticCode.invalidValidator,
        param.location,
        '${validator.display} on parameter ${param.name}: $problem',
      );
    }
  }

  static String? _problem(ParamModel param, ValidatorModel validator) {
    final kind = switch (param.source) {
      ValueSource(:final kind) => kind,
      _ => null,
    };
    return switch (validator) {
      RangeValidator(:final min, :final max) =>
        _onlyOn(kind, const {
              ValueKind.integer,
              ValueKind.decimal,
            }, 'int or double') ??
            _order(min, max),
      LengthValidator(:final min, :final max) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ?? _order(min, max),
      PatternValidator(:final regex) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ?? _pattern(regex),
      OneOfValidator(:final values) =>
        _onlyOn(kind, const {ValueKind.string}, 'String') ??
            (values.isEmpty ? 'the list of values is empty.' : null),
    };
  }

  static String? _onlyOn(
    ValueKind? kind,
    Set<ValueKind> allowed,
    String what,
  ) => kind != null && allowed.contains(kind)
      ? null
      : 'it can only be used on a $what value parameter.';

  static String? _order(num? min, num? max) =>
      min != null && max != null && min > max
      ? 'min ($min) is greater than max ($max).'
      : null;

  static String? _pattern(String regex) {
    try {
      RegExp(regex);
      return null;
    } on FormatException catch (error) {
      return 'the pattern is not a valid regular expression: ${error.message}';
    }
  }
}
```

**`packages/grund_generator/lib/src/diagnostic/diagnostic_code.dart`** (повний вміст після зміни):

```dart
/// Every problem the generator reports, with a stable [id] that tools and
/// tests may rely on.
///
/// A flat catalog without logic. Renaming a Dart identifier here is fine;
/// changing an [id] is a breaking change.
enum DiagnosticCode {
  /// Modules import each other in a cycle.
  circularModuleImport('circular_module_import'),

  /// A module binds the same key twice.
  duplicateBinding('duplicate_binding'),

  /// A module exports a key it does not bind or a module it does not
  /// import.
  invalidExport('invalid_export'),

  /// An entry of `@Module` the generator cannot use.
  invalidModuleEntry('invalid_module_entry'),

  /// A `@Module` class does not extend `Module` of `package:grund`.
  invalidModuleClass('invalid_module_class'),

  /// A `@Named` name is empty.
  invalidName('invalid_name'),

  /// A dependency is not visible in the module that needs it.
  missingProvider('missing_provider'),

  /// Bindings depend on each other in a cycle.
  circularDependency('circular_dependency'),

  /// A singleton depends, directly or through transients, on a call-scoped
  /// binding.
  captiveDependency('captive_dependency'),

  /// A provider class is not annotated with `@Injectable()`.
  notInjectable('not_injectable'),

  /// A provider or API class cannot be created through its unnamed
  /// constructor.
  invalidConstructor('invalid_constructor'),

  /// A constructor or `@Provides` parameter cannot be injected.
  invalidDependency('invalid_dependency'),

  /// A `@Provides` method cannot be called by generated code, or is not in
  /// a module.
  invalidProvides('invalid_provides'),

  /// A constant (module instance, key, hook) cannot be written as Dart
  /// code.
  unsupportedConstant('unsupported_constant'),

  /// An `@Api` class cannot be created once per module.
  invalidApi('invalid_api'),

  /// An `@Api` class is provided by more than one module.
  duplicateApi('duplicate_api'),

  /// An entry of `use:` is not a `HookRef`.
  invalidHook('invalid_hook'),

  /// A route annotation is on a method that cannot handle requests.
  invalidRouteHandler('invalid_route_handler'),

  /// A route annotation is outside of an `@Api` class.
  routeOutsideApi('route_outside_api'),

  /// A handler parameter cannot be bound to the request.
  invalidHandlerParameter('invalid_handler_parameter'),

  /// A handler parameter has neither a source annotation nor a call scope
  /// class type.
  parameterWithoutSource('parameter_without_source'),

  /// A `@Body()` type has no `fromJson` and is not read directly.
  missingFromJson('missing_from_json'),

  /// A `@Path` name is not a parameter of the route path.
  unknownPathParameter('unknown_path_parameter'),

  /// A `@Range`, `@Length`, `@Pattern` or `@OneOf` does not fit the
  /// parameter or its own arguments.
  invalidValidator('invalid_validator'),

  /// A route `status` is not an HTTP status code.
  invalidStatus('invalid_status'),

  /// A handler returns a type the response serializer cannot take.
  unsupportedReturnType('unsupported_return_type'),

  /// A handler returns a `Stream<T>` of something but bytes; reserved for
  /// `grund_sse`.
  streamReturnReserved('stream_return_reserved'),

  /// Two routes have the same method and path.
  duplicateRoute('duplicate_route'),

  /// Two generated declarations would have the same name.
  duplicateGeneratedName('duplicate_generated_name');

  const DiagnosticCode(this.id);

  /// The stable identifier printed with the message.
  final String id;
}
```

**`packages/grund_generator/lib/src/model/param_source.dart`** (повний вміст після зміни):

```dart
import 'binding_key.dart';
import 'body_kind.dart';
import 'param_location.dart';
import 'value_kind.dart';

/// Where the value of a route parameter comes from.
sealed class ParamSource {
  /// Creates the source.
  const ParamSource();
}

/// A named value of the request.
final class ValueSource extends ParamSource {
  /// Creates the source.
  const ValueSource(this.location, this.name, this.kind);

  /// The request part.
  final ParamLocation location;

  /// The name in the request.
  final String name;

  /// The type of the value.
  final ValueKind kind;
}

/// `@Body()`.
final class BodySource extends ParamSource {
  /// Creates the source.
  const BodySource(this.kind);

  /// How the body is read.
  final BodyKind kind;
}

/// A parameter of type `HttpCtx`: the context itself.
final class ContextSource extends ParamSource {
  /// Creates the source.
  const ContextSource();
}

/// A parameter without annotation: a value of the call scope, resolved by
/// its type (`c<T>()`).
final class CallScopeSource extends ParamSource {
  /// Creates the source.
  const CallScopeSource(this.key);

  /// The value looked up.
  final BindingKey key;
}

/// Why a parameter cannot be filled.
enum InvalidSourceReason {
  /// No `@Path`, `@Query`, ... and not a call scope class.
  missing,

  /// More than one of `@Path`, `@Query`, `@Header`, `@Cookie` and `@Body`.
  ambiguous,

  /// The parameter type is not one the annotation supports.
  unsupportedType,
}

/// A parameter that cannot be filled, because of [problem].
final class InvalidSource extends ParamSource {
  /// Creates the source.
  const InvalidSource(this.reason, this.problem);

  /// The kind of problem; it selects the diagnostic code.
  final InvalidSourceReason reason;

  /// Why the parameter has no source, as a sentence fragment.
  final String problem;
}
```

**`packages/grund_generator/lib/src/model/route_model.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/source_location.dart';
import 'hook_model.dart';
import 'param_model.dart';
import 'return_kind.dart';
import 'type_model.dart';

/// A method of an `@Api` class annotated with `@Get`, `@Post`, `@Put`,
/// `@Patch` or `@Delete`.
final class RouteModel {
  /// Creates the model.
  const RouteModel({
    required this.method,
    required this.path,
    required this.handlerName,
    required this.returnType,
    required this.returnKind,
    required this.location,
    this.status,
    this.parameters = const [],
    this.use = const [],
    this.invalidEntries = const [],
    this.documentation,
    this.problem,
  });

  /// The upper-cased HTTP method.
  final String method;

  /// The path relative to the API path.
  final String path;

  /// The method name.
  final String handlerName;

  /// The declared return type.
  final TypeModel returnType;

  /// What the handler returns.
  final ReturnKind returnKind;

  /// Where the method is declared.
  final SourceLocation location;

  /// The response status of the annotation, or `null`.
  final int? status;

  /// The parameters, in declaration order.
  final List<ParamModel> parameters;

  /// Route-level hooks, in order.
  final List<HookModel> use;

  /// One sentence per `use` entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot be a handler, as a sentence; `null` when it can.
  final String? problem;
}
```


- [ ] **Крок 2: запуск.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test
```

Очікувано: чисто, `+97: All tests passed!`.

- [ ] **Крок 3: коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
dart format packages && git add -A && git commit -m "feat(generator): module, binding and api checks with stable diagnostics"
```

---

### Задача 16: емісія модулів і bindings

**Мета.** `ModuleConstruct.generate` видає на кожен `@Module` міксин `mixin $X on grund.Module` (узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17)) з `imports`, `bindings`, `exports`, `global`. Згенеровано й перевірено: `dart analyze` чистий, 109 тестів зелені (12 нових).

**Files.** Create `lib/src/emit/{core_references,binding_emitter,module_emitter}.dart`, `test/emit/module_emitter_test.dart`, `test/fixtures/cases_app/lib/emit/modules.dart` (валідні модулі без навмисних помилок: у `modules/basic.dart` лишаються `invalid_provides`); Modify `lib/src/constructs/module_construct.dart`, `lib/src/emit/{constant_emitter,dart_string,import_allocator}.dart`.

**Правила емісії (перевірені).**
1. `imports` → `List<grund.Module> get imports => [AuthModule(), …]`: non-const екземпляри через `ConstantEmitter.instance(import.instance)`, порядок анотації.
2. `bindings` → `List<grund.Binding<Object>>`, порядок: `providers` в порядку анотації (клас і `Bind<I, C>`), далі `@Provides` за порядком оголошення (метод без `key` пропущено: його вже відхилила перевірка), далі (задача 17) `XRoutes` кожного `@Api` з `providers`. Бінд: `Singleton<T>((i) => T(i<A>(), b: i<B>()), name: 'n', dependsOn: const [Key<A>(), Key<B>()])`. `Scope.call` → `Scoped`, `Scope.transient` → `Transient`. `Bind<I, C>` → `Singleton<I>((i) => C())`.
3. Іменована залежність — `i<T>('n')` (форма `Injector.call<T>([String? name])` ядра), іменований параметр конструктора — іменований аргумент.
4. `@Provides static Future<T> f(...)` → ту саму `Singleton<T>((i) => Owner.f(...))`: фабрика повертає `Future<T>`, а `create` ядра приймає `FutureOr<T>`; `Singleton.factory` не потрібен.
5. `dependsOn` — множина ключів, відсортована за `BindingKey.compareTo` (не в порядку параметрів), тож дві генерації дають однаковий текст.
6. `exports` — `const [Key<T>(), Key<T>('n')]`, а якщо є реекспорт модуля — non-const `[Key<T>(), OtherModule()]` (ядро приймає реекспорт лише екземпляром, як елемент `imports`; реекспортований модуль з qualifier треба оголошувати явною формою): спочатку ключі за `compareTo`, потім реекспорт модулів за ім'ям; порожні `imports`/`bindings`/`exports` не емітяться. `global: true` → `bool get global => true`.
7. `ImportAllocator`: `package:grund_http/…` → префікс `http` (як `package:grund/…` → `grund`); решта — `i1`, `i2`, … за порядком першого використання.
8. `ModuleEmitter.emit` у цьому коміті має 41 рядок (ліміт 40) і власні `_getter`/`_list`; задача 17 розбиває метод і виносить їх в `OverrideGetter`.
9. Усі рядки користувача (`name:`) — через `DartString.expression` (екранує `'`, `$`, `\`, керівні символи).

- [ ] **Крок 1: тест і fixture (падають).** Створити `test/fixtures/cases_app/lib/emit/modules.dart` і `test/emit/module_emitter_test.dart` (повний вміст — у блоці кроку 3; запустити лише тест).

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart test test/emit/module_emitter_test.dart
```

Очікувано: тест не проходить (`ModuleConstruct.generate` повертає порожній список, `source` не містить міксинів).

- [ ] **Крок 2: код емісії.** `ModuleEmitter` + `BindingEmitter` + `CoreReferences`, правки `ImportAllocator`/`ConstantEmitter`/`DartString`, `ModuleConstruct.generate`.

- [ ] **Крок 3: файли цілком.** Порядок застосування: fixture і тест, потім `lib/`.

**`packages/grund_generator/test/emit/module_emitter_test.dart`** (новий):

```dart
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late String source; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final package = await fixture.collect(['lib/emit/modules.dart']);
    final result = const GrundGenerator.core().generate(package);
    expect(result.diagnostics, isEmpty);
    source = result.library ?? '';
  });

  test('a module becomes a mixin on the core Module', () {
    expect(source, contains('mixin \$EmitDbModule on grund.Module {'));
    expect(source, contains('mixin \$EmitAppModule on grund.Module {'));
  });

  test('imports are plain instances in annotation order', () {
    expect(source, contains('List<grund.Module> get imports => ['));
    expect(
      source,
      contains(
        "i1.EmitDbModule(),\n    i1.EmitExplicitModule(name: 'x'),\n  ];",
      ),
    );
  });

  test('a class provider calls its constructor with injected arguments', () {
    expect(source, contains('(i) => i1.Repo('));
    expect(source, contains('i<i1.Clock>(),'));
    expect(source, contains("i<i1.PrimaryDb>('primary'),"));
    expect(source, contains('config: i<i1.AppConfig>(),'));
  });

  test('dependsOn is sorted by key, not by parameter order', () {
    expect(
      source,
      contains(
        'dependsOn: const [\n'
        '        grund.Key<i1.AppConfig>(),\n'
        '        grund.Key<i1.Clock>(),\n'
        "        grund.Key<i1.PrimaryDb>('primary'),\n"
        '      ],',
      ),
    );
  });

  test('Bind registers the implementation under the interface', () {
    expect(
      source,
      contains(
        'grund.Singleton<i1.Clock>((i) => i1.SystemClock(), '
        'dependsOn: const [])',
      ),
    );
  });

  test('scopes map to Singleton, Scoped and Transient', () {
    expect(source, contains('grund.Scoped<i1.Tx>('));
    expect(source, contains('grund.Transient<i1.Counter>('));
    expect(source, contains('grund.Singleton<i1.Repo>('));
  });

  test('a @Provides method is called on its module class', () {
    expect(source, contains('(i) => i1.EmitDbModule.config()'));
    expect(
      source,
      contains(
        "i1.EmitDbModule.session(i<i1.Clock>(), i<i1.PrimaryDb>('primary'))",
      ),
    );
  });

  test('a @Named binding passes name and the scope of its provider', () {
    expect(source, contains("name: 'main'"));
    expect(source, contains('grund.Scoped<i1.Session>('));
  });

  test('a name is escaped in every position', () {
    expect(source, contains(r"name: 'a\'b\$c'"));
  });

  test('exports are const keys in order, then re-exported modules', () {
    expect(
      source,
      contains(
        'List<Object> get exports => const [\n'
        '    grund.Key<i1.Clock>(),\n'
        "    grund.Key<i1.PrimaryDb>('primary'),\n"
        '    grund.Key<i1.Repo>(),\n'
        "    grund.Key<i1.Session>('main'),\n"
        '  ];',
      ),
    );
    expect(source, contains('exports => [i1.EmitDbModule()];'));
  });

  test('global is overridden only by a global module', () {
    expect('bool get global => true'.allMatches(source), hasLength(1));
  });

  test('two generations give the same bytes', () async {
    final fixture = FixturePackage.open('cases_app');
    final package = await fixture.collect(['lib/emit/modules.dart']);

    final again = const GrundGenerator.core().generate(package).library;

    expect(again, source);
  });
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/emit/modules.dart`** (новий):

```dart
// Valid modules that exercise every binding form the emitter writes.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

/// A clock.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The system clock.
@Injectable()
final class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// A named binding.
@Injectable()
@Named('primary')
final class PrimaryDb {}

/// A name that needs escaping in generated code.
@Injectable()
@Named(r"a'b$c")
final class OddName {}

/// Lives as long as a call.
@Injectable(scope: Scope.call)
final class Tx {
  /// Creates the transaction.
  Tx(this.clock);

  /// The clock.
  final Clock clock;
}

/// Created on every request for it.
@Injectable(scope: Scope.transient)
final class Counter {}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Named('primary') this.db, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The settings.
  final AppConfig config;
}

/// A session opened asynchronously.
final class Session {
  /// Creates the session.
  const Session();
}

/// Database access.
@Module(
  providers: [
    Repo,
    Bind<Clock, SystemClock>(),
    PrimaryDb,
    Tx,
    Counter,
    OddName,
  ],
  exports: [Repo, PrimaryDb, grund.Key<Session>('main'), grund.Key<Clock>()],
  global: true,
)
final class EmitDbModule extends grund.Module {
  /// Creates the module.
  const EmitDbModule();

  /// The settings.
  @Provides()
  static AppConfig config() => const AppConfig('it\'s demo');

  /// A session per call.
  @Provides(scope: Scope.call)
  @Named('main')
  static Future<Session> session(Clock clock, @Named('primary') PrimaryDb db) =>
      Future.value(const Session());
}

/// Re-exports the database module.
@Module(
  imports: [
    EmitDbModule(),
    EmitExplicitModule(name: 'x'),
  ],
  exports: [EmitDbModule],
)
final class EmitAppModule extends grund.Module {
  /// Creates the module.
  const EmitAppModule();
}

/// A module written with the explicit API.
final class EmitExplicitModule extends grund.Module {
  /// Creates the module.
  const EmitExplicitModule({this.name});

  /// Tells instances apart.
  final String? name;

  @override
  Object? get qualifier => name;
}
```

**`packages/grund_generator/lib/src/constructs/module_construct.dart`** (повний вміст після зміни):

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../emit/module_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'binding_check.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';

/// Validates the modules of a package and their bindings.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) {
    final own = [
      ...ModuleStructureCheck.check(package.modules),
      ...BindingCheck.check(package),
    ];
    return own.isEmpty ? DependencyCheck.check(package) : own;
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final module in package.modules)
      DartUnit(
        name: GeneratedNames.module(module.type.name),
        spec: ModuleEmitter.emit(module, package.apis),
        origin: module.location,
      ),
  ];
}
```

**`packages/grund_generator/lib/src/emit/binding_emitter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/api_model.dart';
import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import '../model/lifetime.dart';
import '../model/provider_model.dart';
import '../model/provides_model.dart';
import 'core_references.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes the `Singleton`, `Scoped` or `Transient` expression of one binding.
///
/// The factory is a lambda over the module's `Injector` (`i`) that calls
/// the constructor, the `@Provides` method or the generated routes class;
/// `dependsOn` lists the keys it resolves, sorted, so the container
/// validates them before any factory runs.
abstract final class BindingEmitter {
  /// The binding of the injectable class behind [provider], keyed by
  /// the provider's key (the interface of a `Bind<I, C>`).
  static Expression provider(ProviderModel provider) {
    final injectable = provider.injectable;
    final dependencies = injectable.constructor.dependencies;
    return _binding(
      key: provider.key,
      lifetime: injectable.lifetime,
      dependencies: dependencies,
      create: TypeEmitter.reference(
        injectable.type,
      ).newInstance(_positional(dependencies), _named(dependencies)),
    );
  }

  /// The binding of a `@Provides` method; [provided] must have a key.
  static Expression provides(ProvidesModel provided, BindingKey key) =>
      _binding(
        key: key,
        lifetime: provided.lifetime,
        dependencies: provided.dependencies,
        create: TypeEmitter.reference(provided.owner)
            .property(provided.methodName)
            .call(
              _positional(provided.dependencies),
              _named(provided.dependencies),
            ),
      );

  /// The binding of the routes class [routesName] of [api], provided by
  /// the module that provides the API under [apiKey].
  static Expression routes(ApiModel api, BindingKey apiKey, String routesName) {
    final routesType = refer(routesName);
    return CoreReferences.grund('Singleton').newInstance(
      [
        _lambda(routesType.newInstance([refer('i'), _inject(apiKey)])),
      ],
      {
        'dependsOn': _dependsOn([apiKey]),
      },
      [routesType],
    );
  }

  static Expression _binding({
    required BindingKey key,
    required Lifetime lifetime,
    required List<DependencyModel> dependencies,
    required Expression create,
  }) {
    final name = key.name;
    return CoreReferences.grund(switch (lifetime) {
      Lifetime.singleton => 'Singleton',
      Lifetime.scoped => 'Scoped',
      Lifetime.transient => 'Transient',
    }).newInstance(
      [_lambda(create)],
      {
        if (name != null) 'name': DartString.expression(name),
        'dependsOn': _dependsOn([
          for (final dependency in dependencies)
            if (dependency.key case final key?) key,
        ]),
      },
      [TypeEmitter.reference(key.type)],
    );
  }

  static Expression _lambda(Expression body) => Method(
    (b) => b
      ..requiredParameters.add(Parameter((p) => p..name = 'i'))
      ..lambda = true
      ..body = body.code,
  ).closure;

  static Expression _dependsOn(List<BindingKey> keys) {
    final sorted = {...keys}.toList()..sort();
    return literalConstList([
      for (final key in sorted)
        CoreReferences.key(TypeEmitter.reference(key.type), key.name),
    ]);
  }

  static Expression _inject(BindingKey key) => refer('i').call(
    [if (key.name case final name?) DartString.expression(name)],
    const {},
    [TypeEmitter.reference(key.type)],
  );

  static List<Expression> _positional(List<DependencyModel> dependencies) => [
    for (final dependency in dependencies)
      if (!dependency.isNamed)
        if (dependency.key case final key?) _inject(key),
  ];

  static Map<String, Expression> _named(List<DependencyModel> dependencies) => {
    for (final dependency in dependencies)
      if (dependency.isNamed)
        if (dependency.key case final key?) dependency.name: _inject(key),
  };
}
```

**`packages/grund_generator/lib/src/emit/constant_emitter.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/constant_value.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes [ConstantValue]s as expressions.
abstract final class ConstantEmitter {
  /// [value] as an expression; a collection or constructor call is `const`
  /// at the top and plain inside, as the lints expect. An
  /// [UnsupportedConstant] must have been reported before generation.
  static Expression expression(ConstantValue value) =>
      _write(value, isConst: true);

  /// [value] as an expression without `const`: a module instance that is
  /// created again for every generated getter.
  static Expression instance(ConstantValue value) => _write(value);

  /// [values] as one `const` list literal.
  static Expression list(List<ConstantValue> values) =>
      literalConstList([for (final value in values) _write(value)]);

  static Expression _write(ConstantValue value, {bool isConst = false}) =>
      switch (value) {
        NullConstant() => literalNull,
        BoolConstant(:final value) => literalBool(value),
        NumberConstant(:final literal) => CodeExpression(Code(literal)),
        StringConstant(:final value) => CodeExpression(
          Code(DartString.literal(value)),
        ),
        TypeConstant(:final type) => TypeEmitter.reference(type),
        ReferenceConstant(
          :final name,
          :final libraryUri,
          :final enclosingName,
        ) =>
          enclosingName == null
              ? refer(name, libraryUri)
              : refer(enclosingName, libraryUri).property(name),
        ListConstant(:final elementType, :final elements) =>
          (isConst ? literalConstList : literalList)([
            for (final element in elements) _write(element),
          ], TypeEmitter.reference(elementType)),
        SetConstant(:final elementType, :final elements) =>
          (isConst ? literalConstSet : literalSet)({
            for (final element in elements) _write(element),
          }, TypeEmitter.reference(elementType)),
        MapConstant(:final keyType, :final valueType, :final entries) =>
          (isConst ? literalConstMap : literalMap)(
            {for (final (key, value) in entries) _write(key): _write(value)},
            TypeEmitter.reference(keyType),
            TypeEmitter.reference(valueType),
          ),
        ObjectConstant() => _object(value, isConst: isConst),
        UnsupportedConstant(:final reason) => throw StateError(
          'An unsupported constant reached generation: $reason.',
        ),
      };

  static Expression _object(ObjectConstant value, {required bool isConst}) {
    final type = TypeEmitter.reference(value.type);
    final positional = [for (final v in value.positional) _write(v)];
    final named = {
      for (final MapEntry(:key, :value) in value.named.entries)
        key: _write(value),
    };
    final name = value.constructorName;
    if (isConst) {
      return name.isEmpty
          ? type.constInstance(positional, named)
          : type.constInstanceNamed(name, positional, named);
    }
    return name.isEmpty
        ? type.newInstance(positional, named)
        : type.newInstanceNamed(name, positional, named);
  }
}
```

**`packages/grund_generator/lib/src/emit/core_references.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import 'dart_string.dart';
import 'import_allocator.dart';

/// References to the declarations of the core and HTTP barrels that
/// generated code uses.
abstract final class CoreReferences {
  /// [symbol] of `package:grund/grund.dart`.
  static Reference grund(String symbol) => refer(symbol, ImportAllocator.grund);

  /// [symbol] of `package:grund_http/grund_http.dart`.
  static Reference http(String symbol) => refer(symbol, ImportAllocator.http);

  /// `Key<T>` with type argument [type] and an optional [name].
  static Expression key(Reference type, [String? name]) =>
      grund('Key').newInstance(
        [if (name != null) DartString.expression(name)],
        const {},
        [type],
      );
}
```

**`packages/grund_generator/lib/src/emit/dart_string.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

/// Writes user strings (ids, paths, names) as Dart string literals.
///
/// `code_builder`'s `literalString` escapes only quotes and newlines; a
/// user string reaches generated code only through [literal], which also
/// escapes `\`, `$`, every control character (C0, DEL and C1), the line and
/// paragraph separators and lone surrogates.
abstract final class DartString {
  /// [value] as a single-quoted Dart literal.
  static String literal(String value) {
    return "'${escape(value)}'";
  }

  /// [value] as an expression for `code_builder`.
  static Expression expression(String value) =>
      CodeExpression(Code(literal(value)));

  /// [value] escaped for the inside of a single-quoted literal, without the
  /// quotes: the form for a URI in a directive.
  static String escape(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      buffer.write(_escape(rune));
    }
    return '$buffer';
  }

  static String _escape(int rune) => switch (rune) {
    0x5C => r'\\',
    0x27 => r"\'",
    0x24 => r'\$',
    0x0A => r'\n',
    0x0D => r'\r',
    0x09 => r'\t',
    < 0x20 ||
    0x7F ||
    >= 0x80 && <= 0x9F ||
    0x2028 ||
    0x2029 ||
    >= 0xD800 && <= 0xDFFF => '\\u{${rune.toRadixString(16)}}',
    _ => String.fromCharCode(rune),
  };
}
```

**`packages/grund_generator/lib/src/emit/import_allocator.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

import 'dart_string.dart';

/// Prefixes every import of the generated library: `grund` for the
/// core barrel, `http` for the `grund_http` barrel, `i1`, `i2`, … for the
/// others in order of first use; `dart:core` stays unprefixed. Declarations
/// of `package:grund/src/` and `package:grund_http/src/` are imported from
/// their barrels.
///
/// `Allocator.simplePrefixing` names prefixes `_i1`, which the
/// `no_leading_underscores_for_library_prefixes` lint rejects.
final class ImportAllocator implements Allocator {
  /// The core barrel every generated library imports.
  static const grund = 'package:grund/grund.dart';

  /// The HTTP barrel the generated `HttpApi` classes import.
  static const http = 'package:grund_http/grund_http.dart';

  final Map<String, String> _prefixes = {};

  @override
  String allocate(Reference reference) {
    final symbol = reference.symbol;
    if (symbol == null) {
      throw StateError(
        'A reference to library ${reference.url} has no symbol.',
      );
    }
    final url = switch (reference.url) {
      final String url when url.startsWith('package:grund/') => grund,
      final String url when url.startsWith('package:grund_http/') => http,
      final url => url,
    };
    if (url == null || url == 'dart:core') return symbol;
    final prefix = _prefixes.putIfAbsent(
      url,
      () => switch (url) {
        grund => 'grund',
        http => 'http',
        _ => 'i${_numbered + 1}',
      },
    );
    return '$prefix.$symbol';
  }

  int get _numbered =>
      _prefixes.keys.where((url) => url != grund && url != http).length;

  @override
  Iterable<Directive> get imports => [
    for (final MapEntry(key: url, value: prefix) in _prefixes.entries)
      Directive.import(DartString.escape(url), as: prefix),
  ];
}
```

**`packages/grund_generator/lib/src/emit/module_emitter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/api_model.dart';
import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import 'binding_emitter.dart';
import 'constant_emitter.dart';
import 'core_references.dart';
import 'type_emitter.dart';

/// Writes the mixin `$X on Module` that gives a `@Module` class X its
/// `imports`, `bindings`, `exports` and `global`.
abstract final class ModuleEmitter {
  /// The mixin of [module]; [apis] are the `@Api` classes of the package, of
  /// which the ones [module] provides get a routes binding.
  static Mixin emit(ModuleModel module, List<ApiModel> apis) {
    final bindings = _bindings(module, apis);
    return Mixin(
      (b) => b
        ..name = GeneratedNames.module(module.type.name)
        ..docs.add('/// The generated declarations of [${module.type.name}].')
        ..on = CoreReferences.grund('Module')
        ..methods.addAll([
          if (module.imports.isNotEmpty)
            _getter(
              'imports',
              _list(CoreReferences.grund('Module')),
              literalList([
                for (final import in module.imports)
                  ConstantEmitter.instance(import.instance),
              ]),
            ),
          if (bindings.isNotEmpty)
            _getter(
              'bindings',
              _list(
                TypeReference(
                  (b) => b
                    ..symbol = 'Binding'
                    ..url = CoreReferences.grund('Binding').url
                    ..types.add(refer('Object')),
                ),
              ),
              literalList(bindings),
            ),
          if (module.exports.isNotEmpty)
            _getter('exports', _list(refer('Object')), _exports(module)),
          if (module.isGlobal) _getter('global', refer('bool'), literalTrue),
        ]),
    );
  }

  static List<Expression> _bindings(ModuleModel module, List<ApiModel> apis) {
    final apisByType = {for (final api in apis) api.type: api};
    return [
      for (final provider in module.providers)
        BindingEmitter.provider(provider),
      for (final provided in module.provides)
        if (provided.key case final key?)
          BindingEmitter.provides(provided, key),
      for (final provider in module.providers)
        if (apisByType[provider.injectable.type] case final api?)
          BindingEmitter.routes(
            api,
            provider.key,
            GeneratedNames.routes(api.type.name),
          ),
    ];
  }

  static Expression _exports(ModuleModel module) {
    final keys = [
      for (final export in module.exports)
        if (export case KeyExport(:final key)) key,
    ]..sort();
    final modules = [
      for (final export in module.exports)
        if (export case ModuleReexport(:final type)) type,
    ]..sort((a, b) => a.display.compareTo(b.display));
    // The core accepts a re-exported module only as an instance (like an
    // entry of `imports`), and the module classes may have no const
    // constructor, so a list with a module is not const.
    final values = [
      for (final key in keys)
        CoreReferences.key(TypeEmitter.reference(key.type), key.name),
      for (final type in modules) TypeEmitter.reference(type).newInstance([]),
    ];
    return modules.isEmpty ? literalConstList(values) : literalList(values);
  }

  static Method _getter(String name, Reference type, Expression value) =>
      Method(
        (b) => b
          ..annotations.add(refer('override'))
          ..returns = type
          ..type = MethodType.getter
          ..name = name
          ..lambda = true
          ..body = value.code,
      );

  static TypeReference _list(Reference element) => TypeReference(
    (b) => b
      ..symbol = 'List'
      ..types.add(element),
  );
}
```


- [ ] **Крок 4: запуск, лінт, коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test
cd ../.. && dart format packages && git add -A && git commit -m "feat(generator): emit module mixins and bindings"
```

Очікувано: чисто, `+109: All tests passed!`. Приклад виходу (`lib/emit/modules.dart`, фрагмент): `grund.Singleton<i1.Repo>((i) => i1.Repo(i<i1.Clock>(), i<i1.PrimaryDb>('primary'), config: i<i1.AppConfig>()), dependsOn: const [grund.Key<i1.AppConfig>(), grund.Key<i1.Clock>(), grund.Key<i1.PrimaryDb>('primary')])`.

---

### Задача 17: емісія `HttpApi`-адаптерів

**Мета.** `ApiConstruct.generate` видає на кожен `@Api`-клас X клас `final class XRoutes extends http.HttpApi` (конструктор `XRoutes(super.injector, this._api)`, поле `final X _api`); `ModuleConstruct` (задача 16) уже додає до `bindings` модуля, що провайдить X, `grund.Singleton<XRoutes>((i) => XRoutes(i, i<X>()), dependsOn: const [grund.Key<X>()])`. Згенероване перевірено компіляцією проти `S/proto/core` + `S/proto/http` (див. задачу 18). Після задачі: `dart analyze` чистий, 124 тести зелені (15 нових).

**Files.** Create `lib/src/emit/{override_getter,param_emitter,route_emitter,api_emitter}.dart`, `test/emit/api_emitter_test.dart`; Modify `lib/src/constructs/api_construct.dart`, `lib/src/emit/module_emitter.dart` (метод `emit` розбито на `emit` + `_getters`, щоб вкластися у 40 рядків: у задачі 16 він мав 41; спільні `getter`/`List<T>` переїхали в `OverrideGetter`).

**Правила (перевірені).** `path` → `String get path => '/tasks'`; `use` → `const [http.HookRef<ApiKeyHook>.type()]` (елементи — `ConstantEmitter.list`, тобто `.instance(...)` теж). `routes` → `http.Route.get|post|put|patch|delete(path, (c) => …, status:, use:)`. Параметр handler-а — за `ParamSource`:

| Джерело | Вираз |
| --- | --- |
| `@Path() int id` | `c.path.integer('id')` |
| `@Query() bool? done` | `c.query.booleanOrNull('done')` |
| `@Query() int x = 20` | `c.query.integerOrNull('x') ?? 20` (значення за замовчуванням — `ConstantEmitter.expression`) |
| `@Query() List<String> tag` | `c.query.all('tag')` |
| `@Header(name: 'x-trace') String? t` | `c.headers.stringOrNull('x-trace')` |
| `@Cookie() String s` | `c.cookies.string('s')` |
| enum | `c.path.enumOf('p', Priority.values)` (`…OrNull` для nullable) |
| `@Range(min:, max:)` | `min:`, `max:` у читачі; `@Length` → `minLength:`/`maxLength:`; `@Pattern` → `pattern: '…'` (через `DartString`); `@OneOf` → `oneOf: const ['a', 'b']` |
| `@Body() T` | `await c.body(T.fromJson)`; `List<T>` → `await c.bodyList(T.fromJson)`; `Map<String, Object?>` → `await c.body((json) => json)`; `Uint8List` → `await c.bytes()` |
| `HttpCtx` без анотації | `c` |
| клас call-скоупа без анотації | `c<T>()` (`c<T>('n')` для `@Named`) |

Іменований параметр Dart передається іменованим. Результат: `value`/`byteStream` — вираз-лямбда (`(c) => _api.m(...)`; `async`, лише коли є `await` тіла); `void`/`Future<void>` — блок `{ [await] _api.m(...); return null; }` (HttpServer відповідає 204); `stream`/`unsupported` до генерації не доходять (діагностики `stream_return_reserved`, `unsupported_return_type`).

- [ ] **Крок 1: тест (падає).** `test/emit/api_emitter_test.dart` — у блоці кроку 3. Запуск `dart test test/emit/api_emitter_test.dart` до кроку 2 падає: `ApiConstruct.generate` порожній.

- [ ] **Крок 2: код.** `ParamEmitter` (вираз параметра), `RouteEmitter` (один `Route.*`), `ApiEmitter` (клас), `OverrideGetter`, `ApiConstruct.generate`.

- [ ] **Крок 3: файли цілком** (з урахуванням правки `module_emitter.dart`; порядок: тест, потім `lib/`).

**`packages/grund_generator/test/emit/api_emitter_test.dart`** (новий):

```dart
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late String source; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final package = await fixture.collect([
      'lib/modules/with_api.dart',
      'lib/apis/tasks.dart',
    ]);
    final result = const GrundGenerator.core().generate(package);
    expect(result.diagnostics, isEmpty);
    source = result.library ?? '';
  });

  test('an API becomes a final HttpApi that holds the API instance', () {
    expect(source, contains('final class TasksApiRoutes extends http.HttpApi'));
    expect(source, contains('TasksApiRoutes(super.injector, this._api);'));
    expect(source, contains('final i1.TasksApi _api;'));
  });

  test('the HTTP barrel is imported as http, once', () {
    expect(
      "import 'package:grund_http/grund_http.dart' as http;".allMatches(source),
      hasLength(1),
    );
  });

  test('path and hooks of the API are overridden', () {
    expect(source, contains("String get path => '/tasks';"));
    expect(
      source,
      contains(
        'List<http.HookRef<http.HttpHook>> get use => const [\n'
        '    http.HookRef<i1.ApiKeyHook>.type(),\n'
        '  ];',
      ),
    );
  });

  test('the module that provides the API provides its routes', () {
    expect(source, contains('grund.Singleton<TasksApiRoutes>('));
    expect(source, contains('(i) => TasksApiRoutes(i, i<i1.TasksApi>())'));
    expect(source, contains('dependsOn: const [grund.Key<i1.TasksApi>()]'));
  });

  test('path, query, header and cookie parameters use their reader', () {
    expect(source, contains("c.path.integer('id')"));
    expect(source, contains("c.query.booleanOrNull('done')"));
    expect(source, contains("c.headers.stringOrNull('x-trace')"));
    expect(source, contains("c.cookies.string('session')"));
    expect(source, contains("c.query.dateTime('since')"));
    expect(source, contains("c.query.uriOrNull('next')"));
  });

  test('a repeated query parameter is read with all', () {
    expect(source, contains("c.query.all('tag')"));
  });

  test('an enum parameter passes the values of the enum', () {
    expect(source, contains("c.path.enumOf('priority', i1.Priority.values)"));
  });

  test('a default turns the reader nullable and falls back to it', () {
    expect(
      source,
      contains(
        "pageSize: c.query.integerOrNull('page_size', min: 1, max: 100) ?? 20",
      ),
    );
  });

  test('validators become reader arguments, escaped', () {
    expect(source, contains("minLength: 1"));
    expect(source, contains("maxLength: 8"));
    expect(source, contains(r"pattern: '^\\w+\$'"));
  });

  test('a body is read with the fromJson of its type', () {
    expect(source, contains('await c.body(i1.CreateTask.fromJson)'));
    expect(source, contains('await c.bodyList(i1.CreateTask.fromJson)'));
    expect(source, contains('await c.body((json) => json)'));
    expect(source, contains('await c.bytes()'));
  });

  test('a lambda is async only when it awaits', () {
    expect(source, contains('(c) async => _api.create('));
    expect(source, contains("(c) => _api.find(c.path.integer('id'))"));
  });

  test('the context and call-scope values are passed through', () {
    expect(source, contains('c<i1.CurrentUser>()'));
    expect(source, contains(',\n        c,\n      );'));
  });

  test('status and hooks of a route are named arguments', () {
    expect(source, contains('status: 201,'));
    expect(
      source,
      contains(
        'http.HookRef<i1.RolesHook>.instance(i1.RolesHook(i1.Priority.high))',
      ),
    );
  });

  test('a void result is answered with null after the call', () {
    expect(source, contains('await _api.remove('));
    expect(source, contains('return null;'));
    expect(source, contains('_api.mark('));
  });

  test('a byte stream is returned as is', () {
    expect(source, contains('(c) => _api.export('));
  });
}
```

**`packages/grund_generator/lib/src/constructs/api_construct.dart`** (повний вміст після зміни):

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../emit/api_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'api_check.dart';
import 'route_conflict_check.dart';

/// Validates the `@Api` classes of a package and their routes.
final class ApiConstruct implements Construct {
  /// Creates the construct.
  const ApiConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => [
    ...ApiCheck.check(package),
    ...RouteConflictCheck.check(package),
  ];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final api in package.apis)
      DartUnit(
        name: GeneratedNames.routes(api.type.name),
        spec: ApiEmitter.emit(api),
        origin: api.location,
      ),
  ];
}
```

**`packages/grund_generator/lib/src/emit/api_emitter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/api_model.dart';
import '../model/generated_names.dart';
import 'constant_emitter.dart';
import 'core_references.dart';
import 'dart_string.dart';
import 'route_emitter.dart';
import 'override_getter.dart';
import 'type_emitter.dart';

/// Writes the class `XRoutes extends HttpApi` that serves the routes of an
/// `@Api` class X by calling its methods.
abstract final class ApiEmitter {
  /// The routes class of [api].
  static Class emit(ApiModel api) => Class(
    (b) => b
      ..name = GeneratedNames.routes(api.type.name)
      ..modifier = ClassModifier.final$
      ..docs.add('/// The routes of [${api.type.name}].')
      ..extend = CoreReferences.http('HttpApi')
      ..fields.add(
        Field(
          (f) => f
            ..name = '_api'
            ..modifier = FieldModifier.final$
            ..type = TypeEmitter.reference(api.type),
        ),
      )
      ..constructors.add(_constructor())
      ..methods.addAll(_getters(api)),
  );

  static Constructor _constructor() => Constructor(
    (c) => c
      ..docs.add('/// Creates the routes over an instance of the API.')
      ..requiredParameters.addAll([
        Parameter(
          (p) => p
            ..name = 'injector'
            ..toSuper = true,
        ),
        Parameter(
          (p) => p
            ..name = '_api'
            ..toThis = true,
        ),
      ]),
  );

  static List<Method> _getters(ApiModel api) => [
    OverrideGetter.emit(
      'path',
      refer('String'),
      DartString.expression(api.path),
    ),
    if (api.use.isNotEmpty)
      OverrideGetter.emit(
        'use',
        OverrideGetter.list(
          TypeReference(
            (b) => b
              ..symbol = 'HookRef'
              ..url = CoreReferences.http('HookRef').url
              ..types.add(CoreReferences.http('HttpHook')),
          ),
        ),
        ConstantEmitter.list([for (final hook in api.use) hook.expression]),
      ),
    OverrideGetter.emit(
      'routes',
      OverrideGetter.list(CoreReferences.http('Route')),
      literalList([for (final route in api.routes) RouteEmitter.emit(route)]),
    ),
  ];
}
```

**`packages/grund_generator/lib/src/emit/module_emitter.dart`** (повний вміст після зміни):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/api_model.dart';
import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import 'binding_emitter.dart';
import 'constant_emitter.dart';
import 'core_references.dart';
import 'override_getter.dart';
import 'type_emitter.dart';

/// Writes the mixin `$X on Module` that gives a `@Module` class X its
/// `imports`, `bindings`, `exports` and `global`.
abstract final class ModuleEmitter {
  /// The mixin of [module]; [apis] are the `@Api` classes of the package, of
  /// which the ones [module] provides get a routes binding.
  static Mixin emit(ModuleModel module, List<ApiModel> apis) => Mixin(
    (b) => b
      ..name = GeneratedNames.module(module.type.name)
      ..docs.add('/// The generated declarations of [${module.type.name}].')
      ..on = CoreReferences.grund('Module')
      ..methods.addAll(_getters(module, _bindings(module, apis))),
  );

  static List<Method> _getters(ModuleModel module, List<Expression> bindings) =>
      [
        if (module.imports.isNotEmpty)
          OverrideGetter.emit(
            'imports',
            OverrideGetter.list(CoreReferences.grund('Module')),
            literalList([
              for (final import in module.imports)
                ConstantEmitter.instance(import.instance),
            ]),
          ),
        if (bindings.isNotEmpty)
          OverrideGetter.emit(
            'bindings',
            OverrideGetter.list(
              TypeReference(
                (b) => b
                  ..symbol = 'Binding'
                  ..url = CoreReferences.grund('Binding').url
                  ..types.add(refer('Object')),
              ),
            ),
            literalList(bindings),
          ),
        if (module.exports.isNotEmpty)
          OverrideGetter.emit(
            'exports',
            OverrideGetter.list(refer('Object')),
            _exports(module),
          ),
        if (module.isGlobal)
          OverrideGetter.emit('global', refer('bool'), literalTrue),
      ];

  static List<Expression> _bindings(ModuleModel module, List<ApiModel> apis) {
    final apisByType = {for (final api in apis) api.type: api};
    return [
      for (final provider in module.providers)
        BindingEmitter.provider(provider),
      for (final provided in module.provides)
        if (provided.key case final key?)
          BindingEmitter.provides(provided, key),
      for (final provider in module.providers)
        if (apisByType[provider.injectable.type] case final api?)
          BindingEmitter.routes(
            api,
            provider.key,
            GeneratedNames.routes(api.type.name),
          ),
    ];
  }

  static Expression _exports(ModuleModel module) {
    final keys = [
      for (final export in module.exports)
        if (export case KeyExport(:final key)) key,
    ]..sort();
    final modules = [
      for (final export in module.exports)
        if (export case ModuleReexport(:final type)) type,
    ]..sort((a, b) => a.display.compareTo(b.display));
    // The core accepts a re-exported module only as an instance (like an
    // entry of `imports`), and the module classes may have no const
    // constructor, so a list with a module is not const.
    final values = [
      for (final key in keys)
        CoreReferences.key(TypeEmitter.reference(key.type), key.name),
      for (final type in modules) TypeEmitter.reference(type).newInstance([]),
    ];
    return modules.isEmpty ? literalConstList(values) : literalList(values);
  }
}
```

**`packages/grund_generator/lib/src/emit/override_getter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

/// Writes the overridden getters of generated modules and APIs.
abstract final class OverrideGetter {
  /// `@override [type] get [name] => [value];`.
  static Method emit(String name, Reference type, Expression value) => Method(
    (b) => b
      ..annotations.add(refer('override'))
      ..returns = type
      ..type = MethodType.getter
      ..name = name
      ..lambda = true
      ..body = value.code,
  );

  /// `List<[element]>`.
  static TypeReference list(Reference element) => TypeReference(
    (b) => b
      ..symbol = 'List'
      ..types.add(element),
  );
}
```

**`packages/grund_generator/lib/src/emit/param_emitter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/body_kind.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/validator_model.dart';
import '../model/value_kind.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes the expression that produces one argument of a route handler from
/// the `HttpCtx` named `c`: a `Params` reader call, the request body, the
/// context itself or a value of the call scope.
abstract final class ParamEmitter {
  /// The argument expression of [param]; it contains `await` exactly when
  /// [awaits] is true.
  static Expression argument(ParamModel param) => switch (param.source) {
    ValueSource() => _value(param, param.source as ValueSource),
    BodySource(:final kind) => _body(param, kind),
    ContextSource() => refer('c'),
    CallScopeSource(:final key) => refer('c').call(
      [if (key.name case final name?) DartString.expression(name)],
      const {},
      [TypeEmitter.reference(key.type)],
    ),
    InvalidSource(:final problem) => throw StateError(
      'An invalid parameter reached generation: $problem',
    ),
  };

  /// Whether [argument] of [param] awaits the body of the request.
  static bool awaits(ParamModel param) => param.source is BodySource;

  static Expression _value(ParamModel param, ValueSource source) {
    final kind = source.kind;
    final reader = refer('c').property(source.location.reader);
    if (kind == ValueKind.stringList) {
      return reader.property('all').call([DartString.expression(source.name)]);
    }
    final optional = param.type.isNullable || param.defaultValue != null;
    final method = '${kind.reader}${optional ? 'OrNull' : ''}';
    final call = reader.property(method).call([
      DartString.expression(source.name),
      if (kind == ValueKind.enumeration)
        TypeEmitter.reference(param.type.nonNullable).property('values'),
    ], _constraints(param.validators));
    return switch (param.defaultValue) {
      final fallback? => call.ifNullThen(ConstantEmitter.expression(fallback)),
      null => call,
    };
  }

  static Map<String, Expression> _constraints(List<ValidatorModel> validators) {
    final named = <String, Expression>{};
    for (final validator in validators) {
      switch (validator) {
        case RangeValidator(:final min, :final max):
          if (min != null) named['min'] = literalNum(min);
          if (max != null) named['max'] = literalNum(max);
        case LengthValidator(:final min, :final max):
          if (min != null) named['minLength'] = literalNum(min);
          if (max != null) named['maxLength'] = literalNum(max);
        case PatternValidator(:final regex):
          named['pattern'] = DartString.expression(regex);
        case OneOfValidator(:final values):
          named['oneOf'] = literalConstList([
            for (final value in values) DartString.expression(value),
          ]);
      }
    }
    return named;
  }

  static Expression _body(ParamModel param, BodyKind kind) {
    final c = refer('c');
    final type = param.type;
    return switch (kind) {
      BodyKind.object => c.property('body').call([
        TypeEmitter.reference(type).property('fromJson'),
      ]).awaited,
      BodyKind.list => c.property('bodyList').call([
        TypeEmitter.reference(type.typeArguments.single).property('fromJson'),
      ]).awaited,
      BodyKind.jsonObject => c.property('body').call([
        Method(
          (b) => b
            ..requiredParameters.add(Parameter((p) => p..name = 'json'))
            ..lambda = true
            ..body = const Code('json'),
        ).closure,
      ]).awaited,
      BodyKind.bytes => c.property('bytes').call(const []).awaited,
      BodyKind.unsupported => throw StateError(
        'An unsupported body reached generation: ${param.name}.',
      ),
    };
  }
}
```

**`packages/grund_generator/lib/src/emit/route_emitter.dart`** (новий):

```dart
import 'package:code_builder/code_builder.dart';

import '../model/return_kind.dart';
import '../model/route_model.dart';
import 'constant_emitter.dart';
import 'core_references.dart';
import 'dart_string.dart';
import 'param_emitter.dart';

/// Writes one `Route.get(...)` (or `post`, `put`, `patch`, `delete`) of a
/// generated `HttpApi`, whose handler calls the method of the user's API
/// class held in the field `_api`.
abstract final class RouteEmitter {
  /// The route expression of [route].
  static Expression emit(RouteModel route) => CoreReferences.http('Route')
      .property(route.method.toLowerCase())
      .call(
        [DartString.expression(route.path), _handler(route)],
        {
          if (route.status case final status?) 'status': literalNum(status),
          if (route.use.isNotEmpty)
            'use': ConstantEmitter.list([
              for (final hook in route.use) hook.expression,
            ]),
        },
      );

  static Expression _handler(RouteModel route) {
    final parameters = route.parameters;
    final positional = [
      for (final param in parameters)
        if (!param.isNamed) ParamEmitter.argument(param),
    ];
    final named = {
      for (final param in parameters)
        if (param.isNamed) param.name: ParamEmitter.argument(param),
    };
    final call = refer(
      '_api',
    ).property(route.handlerName).call(positional, named);
    final awaitsBody = parameters.any(ParamEmitter.awaits);
    final returnsFuture = route.returnType.name == 'Future';
    return switch (route.returnKind) {
      ReturnKind.value || ReturnKind.byteStream => _closure(
        call.code,
        isAsync: awaitsBody,
        isLambda: true,
      ),
      ReturnKind.none => _closure(
        Block.of([
          (returnsFuture ? call.awaited : call).statement,
          literalNull.returned.statement,
        ]),
        isAsync: awaitsBody || returnsFuture,
        isLambda: false,
      ),
      ReturnKind.stream || ReturnKind.unsupported => throw StateError(
        'Route ${route.handlerName} has an unsupported result.',
      ),
    };
  }

  static Expression _closure(
    Code body, {
    required bool isAsync,
    required bool isLambda,
  }) => Method(
    (b) => b
      ..requiredParameters.add(Parameter((p) => p..name = 'c'))
      ..modifier = isAsync ? MethodModifier.async : null
      ..lambda = isLambda
      ..body = body,
  ).closure;
}
```


- [ ] **Крок 4: запуск, лінт, коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test
cd ../.. && dart format packages && git add -A && git commit -m "feat(generator): emit HttpApi routes"
```

Очікувано: чисто, `+124: All tests passed!`.

Фрагмент виходу (`cases_app/lib/apis/tasks.dart`):

```dart
http.Route.post(
  '/',
  (c) async => _api.create(
    await c.body(i1.CreateTask.fromJson),
    c<i1.CurrentUser>(),
  ),
  status: 201,
  use: const [
    http.HookRef<i1.RolesHook>.instance(i1.RolesHook(i1.Priority.high)),
  ],
),
```

---

### Задача 18: golden `users_app`, діагностики `cases_app`, еквівалентність, детермінізм, e2e

**Мета.** Fixture `users_app` переписано під нову модель; його `lib/users_app.grund.dart` — golden (генерується, комітиться, руками не редагується). Згенерований код компілюється проти ядра й `grund_http` і відповідає на запити через `TestClient`; анотована форма поводиться як рукописна явна. Після задачі: generator `dart analyze` чистий, 142 тести зелені; `users_app` — 11 тестів (їх також запускає `dart test` генератора).

> **Знахідка перевірки в прототипі (діагностика, не код емісії).** Ядро дозволяє асинхронними лише `Singleton`: `Scoped`/`Transient` із фабрикою, що повертає `Future`, при першому читанні кидає `AsyncProviderNotReadyError`. Тому `@Provides(scope: Scope.call)` з `Future<T>` (приклад у узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17), «async-сесія») генератор має відхиляти: крок 1 додає перевірку `invalid_provides`. Якщо потрібна асинхронна сесія на виклик, її відкриває хук і кладе в call-скоуп через `c.set`.

**Files.** Крок 1: Modify `lib/src/constructs/binding_check.dart`, `test/construct/checks_test.dart`, `test/helpers/graph_models.dart`, `test/fixtures/cases_app/lib/emit/modules.dart`. Крок 2: Create `test/golden/golden_test.dart`, `test/construct/cases_diagnostics_test.dart`, у `test/fixtures/users_app`: `lib/src/{users,auth,app_module}.dart`, `lib/users_app.grund.dart` (golden), `test/{generated_app_test,equivalence_test}.dart`, `test/support/{fake_adapter,explicit_users}.dart`; Modify `lib/users_app.dart`, `pubspec.yaml`.

**Як тест запускається у справжньому репозиторії.** `users_app` — член workspace із залежностями `grund`, `grund_annotations`, `grund_http`, тож `cd packages/grund_generator/test/fixtures/users_app && dart test` і `cd packages/grund_generator && dart test` (знаходить і ці тести) працюють без обгортки. У прототипі `repo_c` для цього синхронізовано `packages/grund` і `packages/grund_http` із `S/proto/core` та `S/proto/http` (окремий scaffold-коміт, не частина плану: у справжньому репозиторії їх дають частини A і B). Паралельно перевірено окремий пакет-обгортку (`S/e2e_users_app`, path-залежності на прототипи): ті самі 11 тестів зелені.

- [ ] **Крок 1: перевірка асинхронного `@Provides` (тест падає, потім код).** Тест у `checks_test.dart` (повний файл нижче) падає, поки `BindingCheck._provides` не знає про `isAsync`. Fixture `cases_app/lib/emit/modules.dart` теж змінено: асинхронний лише singleton (`config`), `session` синхронний `Scoped`.

**`packages/grund_generator/test/construct/checks_test.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/graph_models.dart';

void main() {
  late PackageModel cases; // Set in setUpAll.

  setUpAll(() async {
    cases = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']);
  });

  List<String> codes(PackageModel package) => [
    for (final d in const GrundGenerator.core().generate(package).diagnostics)
      d.code.id,
  ];

  test('a cycle between two bindings is circular_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', needs: ['A']),
      ],
    );

    expect(
      codes(GraphModels.package([module])),
      contains('circular_dependency'),
    );
  });

  test('a singleton on a call-scoped binding is captive_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', lifetime: Lifetime.scoped),
      ],
    );

    expect(codes(GraphModels.package([module])), ['captive_dependency']);
  });

  test('a dependency nobody binds is missing_provider', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([module])), ['missing_provider']);
  });

  test('a binding exported by another module needs an import', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final app = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );
    final imported = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([lib, app])), ['missing_provider']);
    expect(codes(GraphModels.package([lib, imported])), isEmpty);
  });

  test('an asynchronous call-scoped provides is invalid_provides', () {
    ModuleModel moduleWith(Lifetime lifetime) => GraphModels.module(
      'App',
      provides: [
        GraphModels.provides(
          'App',
          'Session',
          lifetime: lifetime,
          isAsync: true,
        ),
      ],
    );

    expect(codes(GraphModels.package([moduleWith(Lifetime.scoped)])), [
      'invalid_provides',
    ]);
    expect(codes(GraphModels.package([moduleWith(Lifetime.transient)])), [
      'invalid_provides',
    ]);
    expect(
      codes(GraphModels.package([moduleWith(Lifetime.singleton)])),
      isEmpty,
    );
  });

  test('two bindings of one key are duplicate_binding', () {
    final module = GraphModels.module(
      'App',
      providers: [GraphModels.provider('A'), GraphModels.provider('A')],
    );

    expect(codes(GraphModels.package([module])), ['duplicate_binding']);
  });

  test('the invalid api routes report their stable codes', () {
    expect(
      codes(cases).toSet(),
      containsAll([
        'invalid_route_handler',
        'parameter_without_source',
        'missing_from_json',
        'unknown_path_parameter',
        'invalid_handler_parameter',
        'invalid_validator',
        'unsupported_return_type',
        'stream_return_reserved',
        'duplicate_route',
        'invalid_hook',
        'invalid_status',
        'route_outside_api',
      ]),
    );
  });
}
```

**`packages/grund_generator/test/fixtures/cases_app/lib/emit/modules.dart`** (повний вміст після зміни):

```dart
// Valid modules that exercise every binding form the emitter writes.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

/// A clock.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The system clock.
@Injectable()
final class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// A named binding.
@Injectable()
@Named('primary')
final class PrimaryDb {}

/// A name that needs escaping in generated code.
@Injectable()
@Named(r"a'b$c")
final class OddName {}

/// Lives as long as a call.
@Injectable(scope: Scope.call)
final class Tx {
  /// Creates the transaction.
  Tx(this.clock);

  /// The clock.
  final Clock clock;
}

/// Created on every request for it.
@Injectable(scope: Scope.transient)
final class Counter {}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Named('primary') this.db, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The settings.
  final AppConfig config;
}

/// A session opened asynchronously.
final class Session {
  /// Creates the session.
  const Session();
}

/// Database access.
@Module(
  providers: [
    Repo,
    Bind<Clock, SystemClock>(),
    PrimaryDb,
    Tx,
    Counter,
    OddName,
  ],
  exports: [Repo, PrimaryDb, grund.Key<Session>('main'), grund.Key<Clock>()],
  global: true,
)
final class EmitDbModule extends grund.Module {
  /// Creates the module.
  const EmitDbModule();

  /// The settings, created asynchronously (allowed for a singleton).
  @Provides()
  static Future<AppConfig> config() async => const AppConfig('it\'s demo');

  /// A session per call.
  @Provides(scope: Scope.call)
  @Named('main')
  static Session session(Clock clock, @Named('primary') PrimaryDb db) =>
      const Session();
}

/// Re-exports the database module.
@Module(
  imports: [
    EmitDbModule(),
    EmitExplicitModule(name: 'x'),
  ],
  exports: [EmitDbModule],
)
final class EmitAppModule extends grund.Module {
  /// Creates the module.
  const EmitAppModule();
}

/// A module written with the explicit API.
final class EmitExplicitModule extends grund.Module {
  /// Creates the module.
  const EmitExplicitModule({this.name});

  /// Tells instances apart.
  final String? name;

  @override
  Object? get qualifier => name;
}
```

**`packages/grund_generator/test/helpers/graph_models.dart`** (повний вміст після зміни):

```dart
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/provider_model.dart';
import 'package:grund_generator/src/model/provides_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';

/// Builders of small hand-made module graphs for the check tests.
abstract final class GraphModels {
  /// A class type named [name].
  static TypeModel type(String name) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
  );

  /// The key of the class [name], qualified by [qualifier].
  static BindingKey key(String name, [String? qualifier]) =>
      BindingKey(type(name), qualifier);

  /// A dependency on [need] (`Name` or `Name('qualifier')` is not parsed;
  /// pass the key).
  static DependencyModel need(BindingKey need) => DependencyModel.injected(
    name: need.type.name.toLowerCase(),
    isNamed: false,
    location: SourceLocation('lib/app.dart', 2, need.type.name.length),
    key: need,
  );

  /// A class provider of [name] that needs the classes [needs].
  static ProviderModel provider(
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
  }) => ProviderModel(
    key(name),
    InjectableModel(
      type: type(name),
      lifetime: lifetime,
      isAnnotated: true,
      location: SourceLocation('lib/app.dart', 1, name.length),
      constructor: ConstructorModel([for (final n in needs) need(key(n))]),
    ),
  );

  /// A `@Provides` method of [owner] that provides [name].
  static ProvidesModel provides(
    String owner,
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
    bool isAsync = false,
    String? problem,
  }) => ProvidesModel(
    owner: type(owner),
    methodName: name.toLowerCase(),
    location: SourceLocation('lib/app.dart', 6, name.length),
    key: problem == null ? key(name) : null,
    lifetime: lifetime,
    isAsync: isAsync,
    dependencies: [for (final n in needs) need(key(n))],
    problem: problem,
  );

  /// A module named [name].
  static ModuleModel module(
    String name, {
    List<ModuleReference> imports = const [],
    List<ProviderModel> providers = const [],
    List<ProvidesModel> provides = const [],
    List<ModuleExport> exports = const [],
    bool isGlobal = false,
  }) => ModuleModel(
    type: type(name),
    location: SourceLocation('lib/app.dart', 3, name.length),
    imports: imports,
    providers: providers,
    provides: provides,
    exports: exports,
    isGlobal: isGlobal,
  );

  /// A reference to the module [name] from this package.
  static LocalModuleReference reference(String name) =>
      LocalModuleReference(type(name), _instance(name));

  /// A reference to the module [name] from elsewhere.
  static OpaqueModuleReference opaque(String name) =>
      OpaqueModuleReference(type(name), _instance(name));

  /// An export of the class [name].
  static KeyExport export(String name, [String? qualifier]) =>
      KeyExport(key(name, qualifier));

  /// A package of [modules].
  static PackageModel package(List<ModuleModel> modules) => PackageModel(
    packageName: 'app',
    languageVersion: Version(3, 8, 0),
    modules: modules,
  );

  static ObjectConstant _instance(String name) =>
      ObjectConstant(type: type(name), constructorName: '');
}
```

**`packages/grund_generator/lib/src/constructs/binding_check.dart`** (повний вміст після зміни):

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/binding_key.dart';
import '../model/dependency_model.dart';
import '../model/injectable_model.dart';
import '../model/lifetime.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/type_model.dart';

/// Checks that every provider class and `@Provides` method can be called by
/// generated code and that its names are usable.
abstract final class BindingCheck {
  /// The problems of the providers of [package].
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    final checked = <TypeModel>{};
    for (final module in package.modules) {
      yield* _providers(module, checked);
      for (final provides in module.provides) {
        yield* _provides(provides);
      }
    }
    for (final injectable in package.injectables) {
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
    for (final provides in package.strayProvides) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        '@Provides method ${provides.owner}.${provides.methodName} is in a '
        'class that is not annotated with @Module; it is never called.',
      );
    }
  }

  static Iterable<Diagnostic> _providers(
    ModuleModel module,
    Set<TypeModel> checked,
  ) sync* {
    for (final provider in module.providers) {
      final injectable = provider.injectable;
      if (!injectable.isAnnotated) {
        yield Diagnostic(
          DiagnosticCode.notInjectable,
          injectable.location,
          '${injectable.type} is a provider of module ${module.type} but is '
          'not annotated with @Injectable().',
        );
      }
      yield* _name(provider.key, injectable.location);
      if (checked.add(injectable.type)) yield* _injectable(injectable);
    }
  }

  static Iterable<Diagnostic> _injectable(InjectableModel injectable) sync* {
    if (injectable.constructor.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidConstructor,
        injectable.location,
        problem,
      );
    }
    yield* _dependencies(injectable.constructor.dependencies);
  }

  static Iterable<Diagnostic> _provides(ProvidesModel provides) sync* {
    if (provides.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        problem,
      );
    }
    if (provides.isAsync && provides.lifetime != Lifetime.singleton) {
      yield Diagnostic(
        DiagnosticCode.invalidProvides,
        provides.location,
        '@Provides method ${provides.owner}.${provides.methodName} returns '
        'a Future but its scope is ${provides.lifetime.name}; only a '
        'singleton may be created asynchronously.',
      );
    }
    if (provides.key case final key?) yield* _name(key, provides.location);
    yield* _dependencies(provides.dependencies);
  }

  static Iterable<Diagnostic> _dependencies(
    List<DependencyModel> dependencies,
  ) sync* {
    for (final dependency in dependencies) {
      if (dependency.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidDependency,
          dependency.location,
          problem,
        );
      }
      if (dependency.key case final key?) {
        yield* _name(key, dependency.location);
      }
    }
  }

  static Iterable<Diagnostic> _name(
    BindingKey key,
    SourceLocation location,
  ) sync* {
    if (key.name != '') return;
    yield Diagnostic(
      DiagnosticCode.invalidName,
      location,
      'The name of ${key.type} is empty; give @Named a non-empty name.',
    );
  }
}
```


```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test test/construct test/emit
cd ../.. && git add -A && git commit -m "fix(generator): reject an asynchronous provides that is not a singleton"
```

- [ ] **Крок 2: fixture, тести, golden.** Спершу тести й `lib/src/*` (golden-тест падає: файла `users_app.grund.dart` немає), потім згенерувати golden:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && GRUND_UPDATE_GOLDENS=1 dart test test/golden
git diff --stat   # lib/users_app.grund.dart створено; перегляньте його перед комітом
```

Блок `users_app.grund.dart` нижче — результат цієї команди, показаний цілком. Він **не пишеться руками**: якщо генерація дала інше, правильним є згенероване.

**`packages/grund_generator/test/construct/cases_diagnostics_test.dart`** (новий):

```dart
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// The diagnostics of the invalid libraries of `cases_app`, with their exact
/// position: a user finds the problem by `path:line:col`.
void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<List<String>> problems(List<String> paths) async {
    final package = await fixture.collect(paths);
    return [
      for (final d in const GrundGenerator.core().generate(package).diagnostics)
        '${d.location} ${d.code.id}',
    ];
  }

  test(
    'every invalid route of apis/invalid.dart is found where it is',
    () async {
      expect(await problems(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']), [
        'lib/apis/invalid.dart:11:13 invalid_hook',
        'lib/apis/invalid.dart:15:8 invalid_route_handler',
        'lib/apis/invalid.dart:19:15 invalid_route_handler',
        'lib/apis/invalid.dart:23:16 stream_return_reserved',
        'lib/apis/invalid.dart:27:21 parameter_without_source',
        'lib/apis/invalid.dart:31:28 missing_from_json',
        'lib/apis/invalid.dart:35:32 unknown_path_parameter',
        'lib/apis/invalid.dart:39:34 invalid_handler_parameter',
        'lib/apis/invalid.dart:43:45 invalid_validator',
        'lib/apis/invalid.dart:47:28 invalid_handler_parameter',
        'lib/apis/invalid.dart:51:19 unsupported_return_type',
        'lib/apis/invalid.dart:59:8 duplicate_route',
        'lib/apis/invalid.dart:63:8 invalid_hook',
        'lib/apis/invalid.dart:63:8 invalid_status',
        'lib/apis/invalid.dart:74:8 route_outside_api',
      ]);
    },
  );

  test('the broken modules and providers are found where they are', () async {
    expect(
      await problems([
        'lib/modules/invalid_entries.dart',
        'lib/modules/basic.dart',
      ]),
      [
        'lib/modules/basic.dart:75:26 invalid_provides',
        'lib/modules/basic.dart:79:8 invalid_provides',
        'lib/modules/basic.dart:83:15 invalid_provides',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_class',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_entry',
        'lib/modules/invalid_entries.dart:8:7 invalid_module_entry',
      ],
    );
  });

  test(
    'the valid libraries of cases_app generate without a diagnostic',
    () async {
      expect(
        await problems([
          'lib/emit/modules.dart',
          'lib/modules/with_api.dart',
          'lib/apis/tasks.dart',
        ]),
        isEmpty,
      );
    },
  );
}
```

**`packages/grund_generator/test/fixtures/users_app/lib/src/app_module.dart`** (новий):

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

import '../users_app.grund.dart';
import 'auth.dart';
import 'users.dart';

/// The root of the users application.
@Module(imports: [AuthModule(), UsersModule()])
final class AppModule extends grund.Module with $AppModule {
  /// Creates the module.
  const AppModule();
}
```

**`packages/grund_generator/test/fixtures/users_app/lib/src/auth.dart`** (новий):

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

import '../users_app.grund.dart';
import 'users.dart';

/// The role of the caller, set by [AuthHook].
final class CurrentRole {
  /// Creates the value.
  CurrentRole(this.name);

  /// The role.
  final String name;
}

/// Accepts `authorization: Bearer <role>` and sets [CurrentRole].
@Injectable()
final class AuthHook extends HttpHook {
  /// Creates the hook.
  const AuthHook();

  @override
  void before(HttpCtx c) {
    final header = c.headers.stringOrNull('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    c.set<CurrentRole>(CurrentRole(header.substring('Bearer '.length)));
  }
}

/// Allows a route only for the given roles; the roles are the hook's
/// parameters, so it is used as a constant instance.
final class RolesHook extends HttpHook {
  /// Creates the hook.
  const RolesHook(this.names);

  /// The roles that may pass.
  final List<String> names;

  @override
  void before(HttpCtx c) {
    if (!names.contains(c<CurrentRole>().name)) {
      throw const ForbiddenException(code: 'role_not_allowed');
    }
  }
}

/// Translates [UserMissing] into a 404.
@Injectable()
final class UserMissingHook extends HttpHook {
  /// Creates the hook.
  const UserMissingHook();

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is UserMissing) {
      throw NotFoundException(
        message: 'No user ${error.id}',
        code: 'user_not_found',
      );
    }
    return null;
  }
}

/// The hooks every API of the application may use.
@Module(
  providers: [AuthHook, UserMissingHook],
  exports: [AuthHook, UserMissingHook],
  global: true,
)
final class AuthModule extends grund.Module with $AuthModule {
  /// Creates the module.
  const AuthModule();
}
```

**`packages/grund_generator/test/fixtures/users_app/lib/src/users.dart`** (новий):

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

import '../users_app.grund.dart';
import 'auth.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  /// Creates the error.
  UserMissing(this.id);

  /// The id that has no user.
  final int id;
}

/// A user.
final class User {
  /// Creates the user.
  User(this.id, this.name);

  /// The identifier.
  final int id;

  /// The name.
  final String name;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// The body of `POST /users`.
final class CreateUser {
  /// Creates the body.
  CreateUser(this.name);

  /// Reads the body, or throws a [FormatException] for a bad one.
  factory CreateUser.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUser(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  /// The name of the new user.
  final String name;
}

/// Where users live.
abstract interface class UserStore {
  /// Every user, in id order.
  List<User> all();

  /// The user [id], or `null`.
  User? find(int id);

  /// Adds a user named [name].
  User add(String name);

  /// Removes the user [id]; whether there was one.
  bool remove(int id);
}

/// Keeps users in memory, seeded with two.
@Injectable()
final class InMemoryUserStore implements UserStore {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  @override
  List<User> all() => _users.values.toList();

  @override
  User? find(int id) => _users[id];

  @override
  User add(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }

  @override
  bool remove(int id) => _users.remove(id) != null;
}

/// Settings of the users module.
final class UsersConfig {
  /// Creates the settings.
  const UsersConfig({required this.greeting});

  /// What the users service says.
  final String greeting;
}

/// Identifies one request; one is created per call.
final class RequestInfo {
  /// Creates the value.
  RequestInfo(this.number);

  /// The running number of the request.
  final int number;
}

/// The users use cases.
@Injectable()
final class UsersService {
  /// Creates the service.
  UsersService(this.store, this.config, {@Named('audit') required this.audit});

  /// Where users live.
  final UserStore store;

  /// The settings.
  final UsersConfig config;

  /// Receives the name of every change.
  final StringBuffer audit;

  /// The first [limit] users whose name contains [query].
  List<User> list({required int limit, String? query}) => [
    for (final user in store.all())
      if (query == null || user.name.contains(query)) user,
  ].take(limit).toList();

  /// The user [id], or throws [UserMissing].
  User find(int id) => store.find(id) ?? (throw UserMissing(id));

  /// Adds a user.
  User create(String name) {
    audit.writeln('create $name');
    return store.add(name);
  }

  /// Removes the user [id], or throws [UserMissing].
  void remove(int id) {
    if (!store.remove(id)) throw UserMissing(id);
    audit.writeln('remove $id');
  }
}

/// Users: bindings, settings and the API.
@Module(
  imports: [AuthModule()],
  providers: [UsersService, UsersApi, Bind<UserStore, InMemoryUserStore>()],
  exports: [UsersService, grund.Key<StringBuffer>('audit')],
)
final class UsersModule extends grund.Module with $UsersModule {
  /// Creates the module.
  const UsersModule();

  static int _requests = 0;

  /// The settings.
  @Provides()
  static UsersConfig config() => const UsersConfig(greeting: 'hello');

  /// Where changes are written; a singleton may be created asynchronously.
  @Provides()
  @Named('audit')
  static Future<StringBuffer> audit() async => StringBuffer();

  /// One value per call.
  @Provides(scope: Scope.call)
  static RequestInfo requestInfo() => RequestInfo(++_requests);
}

/// The users API.
@Api('/users', use: [HookRef<UserMissingHook>.type()])
final class UsersApi {
  /// Creates the API.
  UsersApi(this.users);

  /// The use cases.
  final UsersService users;

  /// Lists users.
  @Get('/')
  List<User> list({
    @Query() @Range(min: 1, max: 100) int limit = 10,
    @Query(name: 'q') @Length(min: 1, max: 20) String? query,
  }) => users.list(limit: limit, query: query);

  /// Describes the current request.
  @Get('/me')
  Map<String, Object?> me(RequestInfo info, @Header() String? accept) => {
    'request': info.number,
    'greeting': users.config.greeting,
    'accept': accept,
  };

  /// Streams the names of all users.
  @Get('/export')
  Stream<List<int>> export() => Stream.value(
    users.list(limit: 100).map((u) => u.name).join('\n').codeUnits,
  );

  /// Returns one user.
  @Get('/:id')
  User find(@Path() int id) => users.find(id);

  /// Creates a user.
  @Post(
    '/',
    status: 201,
    use: [
      HookRef<AuthHook>.type(),
      HookRef<RolesHook>.instance(RolesHook(['admin'])),
    ],
  )
  Future<User> create(@Body() CreateUser body) async => users.create(body.name);

  /// Removes a user.
  @Delete(
    '/:id',
    use: [
      HookRef<AuthHook>.type(),
      HookRef<RolesHook>.instance(RolesHook(['admin'])),
    ],
  )
  void remove(@Path() int id) => users.remove(id);
}
```

**`packages/grund_generator/test/fixtures/users_app/lib/users_app.dart`** (повний вміст після зміни):

```dart
/// The users application of the generator's tests, written with annotations.
///
/// `users_app.grund.dart` is generated and committed (the golden file of
/// `grund_generator`); it is never edited by hand.
library;

export 'src/app_module.dart';
export 'src/auth.dart';
export 'src/users.dart';
```

**`packages/grund_generator/test/fixtures/users_app/lib/users_app.grund.dart`** (новий):

```dart
// GENERATED BY grund_generator. DO NOT EDIT.

/// Generated from the annotations of package:users_app.
library;

import 'package:grund/grund.dart' as grund;
import 'package:grund_http/grund_http.dart' as http;
import 'package:users_app/src/auth.dart' as i1;
import 'package:users_app/src/users.dart' as i2;

/// The generated declarations of [AppModule].
mixin $AppModule on grund.Module {
  @override
  List<grund.Module> get imports => [i1.AuthModule(), i2.UsersModule()];
}

/// The generated declarations of [AuthModule].
mixin $AuthModule on grund.Module {
  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<i1.AuthHook>((i) => i1.AuthHook(), dependsOn: const []),
    grund.Singleton<i1.UserMissingHook>(
      (i) => i1.UserMissingHook(),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [
    grund.Key<i1.AuthHook>(),
    grund.Key<i1.UserMissingHook>(),
  ];

  @override
  bool get global => true;
}

/// The generated declarations of [UsersModule].
mixin $UsersModule on grund.Module {
  @override
  List<grund.Module> get imports => [i1.AuthModule()];

  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<i2.UsersService>(
      (i) => i2.UsersService(
        i<i2.UserStore>(),
        i<i2.UsersConfig>(),
        audit: i<StringBuffer>('audit'),
      ),
      dependsOn: const [
        grund.Key<StringBuffer>('audit'),
        grund.Key<i2.UserStore>(),
        grund.Key<i2.UsersConfig>(),
      ],
    ),
    grund.Singleton<i2.UsersApi>(
      (i) => i2.UsersApi(i<i2.UsersService>()),
      dependsOn: const [grund.Key<i2.UsersService>()],
    ),
    grund.Singleton<i2.UserStore>(
      (i) => i2.InMemoryUserStore(),
      dependsOn: const [],
    ),
    grund.Singleton<i2.UsersConfig>(
      (i) => i2.UsersModule.config(),
      dependsOn: const [],
    ),
    grund.Singleton<StringBuffer>(
      (i) => i2.UsersModule.audit(),
      name: 'audit',
      dependsOn: const [],
    ),
    grund.Scoped<i2.RequestInfo>(
      (i) => i2.UsersModule.requestInfo(),
      dependsOn: const [],
    ),
    grund.Singleton<UsersApiRoutes>(
      (i) => UsersApiRoutes(i, i<i2.UsersApi>()),
      dependsOn: const [grund.Key<i2.UsersApi>()],
    ),
  ];

  @override
  List<Object> get exports => const [
    grund.Key<StringBuffer>('audit'),
    grund.Key<i2.UsersService>(),
  ];
}

/// The routes of [UsersApi].
final class UsersApiRoutes extends http.HttpApi {
  /// Creates the routes over an instance of the API.
  UsersApiRoutes(super.injector, this._api);

  final i2.UsersApi _api;

  @override
  String get path => '/users';

  @override
  List<http.HookRef<http.HttpHook>> get use => const [
    http.HookRef<i1.UserMissingHook>.type(),
  ];

  @override
  List<http.Route> get routes => [
    http.Route.get(
      '/',
      (c) => _api.list(
        limit: c.query.integerOrNull('limit', min: 1, max: 100) ?? 10,
        query: c.query.stringOrNull('q', minLength: 1, maxLength: 20),
      ),
    ),
    http.Route.get(
      '/me',
      (c) => _api.me(c<i2.RequestInfo>(), c.headers.stringOrNull('accept')),
    ),
    http.Route.get('/export', (c) => _api.export()),
    http.Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    http.Route.post(
      '/',
      (c) async => _api.create(await c.body(i2.CreateUser.fromJson)),
      status: 201,
      use: const [
        http.HookRef<i1.AuthHook>.type(),
        http.HookRef<i1.RolesHook>.instance(i1.RolesHook(<String>['admin'])),
      ],
    ),
    http.Route.delete(
      '/:id',
      (c) {
        _api.remove(c.path.integer('id'));
        return null;
      },
      use: const [
        http.HookRef<i1.AuthHook>.type(),
        http.HookRef<i1.RolesHook>.instance(i1.RolesHook(<String>['admin'])),
      ],
    ),
  ];
}
```

**`packages/grund_generator/test/fixtures/users_app/pubspec.yaml`** (повний вміст після зміни):

```yaml
name: users_app
description: >-
  The core e2e users application written with annotations; its generated
  library is the golden file of grund_generator.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  grund: ^0.1.0
  grund_annotations: ^0.1.0
  grund_http: ^0.1.0

dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0

# Task 19 adds the build_runner way of generating lib/users_app.grund.dart:
# the integration test of grund_build checks the golden with it.
```

**`packages/grund_generator/test/fixtures/users_app/test/equivalence_test.dart`** (новий):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/users_app.dart' as annotated;

import 'support/explicit_users.dart';
import 'support/fake_adapter.dart';

/// The annotated application and the one written with the explicit API are
/// the same application: same graph, same routes, same answers.
void main() {
  const annotatedRoot = annotated.AppModule();
  const explicitRoot = ExplicitAppModule();

  /// Keys of the bindings of [module], sorted; routes classes differ in name
  /// only, so they are folded into one entry.
  List<String> bindingKeys(Module module) => [
    for (final binding in module.bindings)
      if ('${binding.key}'.endsWith('Routes') ||
          '${binding.key}' == 'ExplicitUsersApi')
        'routes'
      else
        '${binding.key}',
  ]..sort();

  List<String> exportsOf(Module module) =>
      [for (final export in module.exports) '$export']..sort();

  test('the auth modules bind and export the same keys', () {
    const generated = annotated.AuthModule();
    const written = ExplicitAuthModule();

    expect(bindingKeys(generated), bindingKeys(written));
    expect(exportsOf(generated), exportsOf(written));
    expect(generated.global, written.global);
  });

  test('the users modules bind and export the same keys', () {
    const generated = annotated.UsersModule();
    const written = ExplicitUsersModule();

    expect(bindingKeys(generated), bindingKeys(written));
    expect(exportsOf(generated), exportsOf(written));
    expect(generated.imports.length, written.imports.length);
  });

  test('both applications import the same modules', () {
    expect(annotatedRoot.imports, hasLength(explicitRoot.imports.length));
  });

  test('both applications serve the same routes and answers', () async {
    final generated = await TestApp.start(root: TestRoot(annotatedRoot));
    final written = await TestApp.start(root: TestRoot(explicitRoot));
    addTearDown(generated.close);
    addTearDown(written.close);
    final requests = <(String, String, Object?, Map<String, String>)>[
      ('GET', '/users', null, {}),
      ('GET', '/users?limit=1', null, {}),
      ('GET', '/users?limit=0', null, {}),
      ('GET', '/users/2', null, {}),
      ('GET', '/users/99', null, {}),
      ('GET', '/users/me', null, {'accept': 'a/b'}),
      ('GET', '/users/export', null, {}),
      ('POST', '/users', {'name': 'cy'}, {}),
      ('POST', '/users', {'name': 'cy'}, {'authorization': 'Bearer admin'}),
      ('POST', '/users', {'x': 1}, {'authorization': 'Bearer admin'}),
      ('DELETE', '/users/1', null, {'authorization': 'Bearer admin'}),
      ('PUT', '/users', null, {}),
    ];

    expect(_routes(generated), _routes(written));
    for (final (method, target, json, headers) in requests) {
      final a = await TestClient.of(
        generated,
      ).request(method, target, json: json, headers: headers);
      final b = await TestClient.of(
        written,
      ).request(method, target, json: json, headers: headers);
      expect((a.status, a.text), (b.status, b.text), reason: '$method $target');
    }
  });
}

List<String> _routes(TestApp app) =>
    app.app.container.all<HttpServer>().single.routes;
```

**`packages/grund_generator/test/fixtures/users_app/test/generated_app_test.dart`** (новий):

```dart
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/users_app.dart';

import 'support/fake_adapter.dart';

/// The generated library compiles against the real core and HTTP packages,
/// and the application it wires answers requests.
void main() {
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: TestRoot(const AppModule()));
    client = TestClient.of(app);
  });

  tearDown(() => app.close());

  const admin = {'authorization': 'Bearer admin'};

  test('lists users, with a default and a validated limit', () async {
    final all = await client.get('/users');
    final one = await client.get('/users?limit=1&q=a');
    final tooMany = await client.get('/users?limit=101');

    expect(all.json, [
      {'id': 1, 'name': 'ann'},
      {'id': 2, 'name': 'bob'},
    ]);
    expect(one.json, [
      {'id': 1, 'name': 'ann'},
    ]);
    expect(tooMany.status, 400);
    expect((tooMany.json as Map)['code'], 'parameter_out_of_range');
  });

  test('a path parameter is an integer, a missing user is a 404', () async {
    final found = await client.get('/users/2');
    final missing = await client.get('/users/99');
    final bad = await client.get('/users/x');

    expect(found.json, {'id': 2, 'name': 'bob'});
    expect(missing.status, 404);
    expect((missing.json as Map)['code'], 'user_not_found');
    expect(bad.status, 400);
  });

  test('create answers 201 with a typed body, behind its hooks', () async {
    final anonymous = await client.post('/users', json: {'name': 'cy'});
    final viewer = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: {'authorization': 'Bearer viewer'},
    );
    final created = await client.post(
      '/users',
      json: {'name': 'cy'},
      headers: admin,
    );
    final invalid = await client.post('/users', json: {'x': 1}, headers: admin);

    expect(anonymous.status, 401);
    expect(viewer.status, 403);
    expect(created.status, 201);
    expect(created.json, {'id': 3, 'name': 'cy'});
    expect(invalid.status, 400);
    expect((invalid.json as Map)['code'], 'body_invalid');
  });

  test('a void result is a 204', () async {
    final removed = await client.delete('/users/1', headers: admin);
    final again = await client.delete('/users/1', headers: admin);

    expect(removed.status, 204);
    expect(again.status, 404);
    final audit = app.app.container.all<StringBuffer>().single;
    expect(audit.toString(), 'remove 1\n');
  });

  test('a call-scoped provider is created for every call', () async {
    final first = await client.get('/users/me', headers: {'accept': 'text/x'});
    final second = await client.get('/users/me');

    final one = first.json as Map;
    final two = second.json as Map;
    expect(one['greeting'], 'hello');
    expect(one['accept'], 'text/x');
    expect(two['accept'], isNull);
    expect(two['request'], (one['request'] as int) + 1);
  });

  test('a byte stream is sent as the body', () async {
    final response = await client.get('/users/export');

    expect(response.status, 200);
    expect(response.text, 'ann\nbob');
  });

  test('the server lists the routes of the generated API', () {
    expect(app.app.container.all<HttpServer>().single.routes, [
      'DELETE /users/:id',
      'GET /users',
      'GET /users/:id',
      'GET /users/export',
      'GET /users/me',
      'POST /users',
    ]);
  });
}
```

**`packages/grund_generator/test/fixtures/users_app/test/support/explicit_users.dart`** (новий):

```dart
// The users application written with the explicit API: what the generator is
// expected to write for lib/src/*.dart, by hand. It reuses the classes of
// users_app, so only the wiring differs.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:users_app/users_app.dart';

/// `AuthModule` without annotations.
final class ExplicitAuthModule extends Module {
  /// Creates the module.
  const ExplicitAuthModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AuthHook>((i) => const AuthHook(), dependsOn: const []),
    Singleton<UserMissingHook>(
      (i) => const UserMissingHook(),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<AuthHook>(), Key<UserMissingHook>()];
}

/// `UsersModule` without annotations.
final class ExplicitUsersModule extends Module {
  /// Creates the module.
  const ExplicitUsersModule();

  @override
  List<Module> get imports => const [ExplicitAuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UsersService>(
      (i) => UsersService(
        i<UserStore>(),
        i<UsersConfig>(),
        audit: i<StringBuffer>('audit'),
      ),
      dependsOn: const [
        Key<UserStore>(),
        Key<UsersConfig>(),
        Key<StringBuffer>('audit'),
      ],
    ),
    Singleton<UsersApi>(
      (i) => UsersApi(i<UsersService>()),
      dependsOn: const [Key<UsersService>()],
    ),
    Singleton<UserStore>((i) => InMemoryUserStore(), dependsOn: const []),
    Singleton<UsersConfig>(
      (i) => const UsersConfig(greeting: 'hello'),
      dependsOn: const [],
    ),
    Singleton<StringBuffer>(
      (i) async => StringBuffer(),
      name: 'audit',
      dependsOn: const [],
    ),
    Scoped<RequestInfo>((i) => RequestInfo(++_requests), dependsOn: const []),
    Singleton<ExplicitUsersApi>(
      (i) => ExplicitUsersApi(i, i<UsersApi>()),
      dependsOn: const [Key<UsersApi>()],
    ),
  ];

  @override
  List<Object> get exports => const [
    Key<UsersService>(),
    Key<StringBuffer>('audit'),
  ];

  static int _requests = 0;
}

/// The routes of `UsersApi`, written by hand.
final class ExplicitUsersApi extends HttpApi {
  /// Creates the routes.
  ExplicitUsersApi(super.injector, this._api);

  final UsersApi _api;

  @override
  String get path => '/users';

  @override
  List<HookRef<HttpHook>> get use => const [HookRef<UserMissingHook>.type()];

  @override
  List<Route> get routes => [
    Route.get(
      '/',
      (c) => _api.list(
        limit: c.query.integerOrNull('limit', min: 1, max: 100) ?? 10,
        query: c.query.stringOrNull('q', minLength: 1, maxLength: 20),
      ),
    ),
    Route.get(
      '/me',
      (c) => _api.me(c<RequestInfo>(), c.headers.stringOrNull('accept')),
    ),
    Route.get('/export', (c) => _api.export()),
    Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _api.create(await c.body(CreateUser.fromJson)),
      status: 201,
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
    Route.delete(
      '/:id',
      (c) {
        _api.remove(c.path.integer('id'));
        return null;
      },
      use: const [
        HookRef<AuthHook>.type(),
        HookRef<RolesHook>.instance(RolesHook(['admin'])),
      ],
    ),
  ];
}

/// `AppModule` without annotations.
final class ExplicitAppModule extends Module {
  /// Creates the module.
  const ExplicitAppModule();

  @override
  List<Module> get imports => const [
    ExplicitAuthModule(),
    ExplicitUsersModule(),
  ];
}
```

**`packages/grund_generator/test/fixtures/users_app/test/support/fake_adapter.dart`** (новий):

```dart
// An HttpAdapter that never opens a socket, and the module that provides it.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Accepts `listen` and `close` without doing anything: the tests drive the
/// server through `TestClient`.
final class FakeAdapter implements HttpAdapter {
  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {}

  @override
  Future<void> close({bool force = false}) async {}
}

/// The application root of a test: HTTP, the fake adapter and [app].
final class TestRoot extends Module {
  /// Creates the root over the application module [app].
  TestRoot(this.app);

  /// The module under test.
  final Module app;

  @override
  List<Module> get imports => [const HttpModule(), _AdapterModule(), app];
}

final class _AdapterModule extends Module {
  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((i) => FakeAdapter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
```

**`packages/grund_generator/test/golden/golden_test.dart`** (новий):

```dart
import 'dart:io';

import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// `GRUND_UPDATE_GOLDENS=1 dart test test/golden` rewrites the golden file
/// after a deliberate change of the generated output.
void main() {
  late FixturePackage fixture; // Set in setUpAll.
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    fixture = FixturePackage.open('users_app');
    package = await fixture.collect();
  });

  String generated() {
    final result = const GrundGenerator.core().generate(package);
    expect(result.diagnostics, isEmpty);
    return result.library ?? '';
  }

  test('users_app generates exactly the committed golden file', () {
    final golden = File(p.join(fixture.root, 'lib', 'users_app.grund.dart'));
    if (Platform.environment['GRUND_UPDATE_GOLDENS'] == '1') {
      golden.writeAsStringSync(generated());
    }

    expect(generated(), golden.readAsStringSync());
  });

  test('generating twice gives the same bytes', () {
    expect(generated(), generated());
  });

  test('generating from a fresh analysis gives the same bytes', () async {
    final again = await FixturePackage.open('users_app').collect();

    final result = const GrundGenerator.core().generate(again);

    expect(result.library, generated());
  });
}
```


- [ ] **Крок 3: запуск і коміт.**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_generator && dart analyze && dart test
cd test/fixtures/users_app && dart analyze && dart test
cd ../../../../.. && dart format packages && git add -A && git commit -m "test(generator): golden, equivalence, determinism and e2e for users_app"
```

Очікувано: чисто, generator `+142`, `users_app` `+11`.

**Що покриває.**
- Golden: `golden_test.dart` порівнює `GrundGenerator.core().generate(PackageCollector(users_app))` із файлом; `GRUND_UPDATE_GOLDENS=1` переписує.
- Детермінізм: дві генерації з однієї моделі й дві з двох незалежних аналізів дають однакові байти (`golden_test.dart`, `module_emitter_test.dart`).
- «Анотована ≡ явна»: `equivalence_test.dart` порівнює множини ключів bindings/exports модулів, число імпортів і — через `TestClient` — статус і тіло відповіді для 12 запитів до обох застосунків, плюс `HttpServer.routes`.
- e2e: `generated_app_test.dart` — валідований `@Range` → 400 `parameter_out_of_range`, `@Path` не число → 400, відсутній користувач → 404 `user_not_found` (хук `onError`), 401/403 від хуків, `201` зі `status`, `204` для `void`, `body_invalid`, call-скоуп `c<RequestInfo>()` різний на кожен виклик, байтовий потік, асинхронний singleton `@Named('audit')`, `HttpServer.routes`.
- Діагностики: `cases_diagnostics_test.dart` фіксує точні `path:line:col` і коди для `apis/invalid.dart` (15 діагностик) і `modules/invalid_entries.dart`/`basic.dart` (9), а також що валідні бібліотеки `cases_app` не дають діагностик.

---

## Частина D (2/2): CLI, приклад, документація

### Задача 19: `grund_cli` і `grund_build` на новому API

**Мета:** `init` створює проєкт на `App(root:)`/`@Module`/`@Api`/`HttpModule`/`IoAdapterModule`; `dev` читає відповідь `ext.grund.reassemble` у новому форматі (`added`/`removed` замість `addedRoutes`/`removedRoutes`) і друкує, що додалося/зникло; тестові зразки джерел (`shop`, `hello`, `bench`) переписані на `@Api`/`$Module`; `grund_build` пише ті самі байти й заголовок, що й CLI (код білдера не міняється, міняються лише зразки й виклики, якщо задача 15/18 змінила `GrundGenerator`/`PackageCollector`).

**Передумови:** задачі 1-6 (ядро, `App`, `ext.grund.*`), 13-18 (анотації, генератор: форма виводу `mixin $X on grund.Module`, `lib/<package>.grund.dart`), 12.

**Files:**
- Modify: `packages/grund_cli/lib/src/init/project_template.dart`
- Create: `packages/grund_cli/lib/src/dev/served_changes.dart`, `packages/grund_cli/test/served_changes_test.dart`
- Modify: `packages/grund_cli/lib/src/dev/{reload_result,reload_client,dev_printer,shape_tracker}.dart`, `packages/grund_cli/test/{dev_printer_test,reload_client_test,reload_client_timeouts_test,generation_session_test,gen_command_test,watch_loop_test,gen_watch_test}.dart`, `packages/grund_cli/test/helpers/{shop_sources,dev_sources}.dart`, `packages/grund_cli/benchmark/{benchmark_sources,generation_benchmark_test}.dart`, `packages/grund_cli/integration/dev_test.dart`, `packages/grund_cli/README.md`, `packages/grund_cli/CHANGELOG.md`
- Modify: `packages/grund_cli/pubspec.yaml`, `packages/grund_build/pubspec.yaml` (залежності на `grund_http` лише якщо їх вимагає код; `GrundGenerator` лишається у `grund_generator`)
- Modify (тестові зразки): `packages/grund_build/test/helpers/shop_sources.dart`, `packages/grund_build/README.md`, `packages/grund_build/CHANGELOG.md`
- Test: `cd packages/grund_cli && dart test`, `cd packages/grund_build && dart test`, `dart test integration` у обох

**Interfaces:**
- Consumes: відповідь `ext.grund.reassemble` = `{"applications": n, "added": [...], "removed": [...]}` (контракт: `ReassembleReport.toJson`), `ext.grund.close` = `{"applications": n}`; генератор: `mixin $X on grund.Module`, діагностика з кодом `missing_provider` (задача 15); `App`, `Runners.fromArgs`, `HttpModule`, `IoAdapterModule`.
- Produces: `ServedChanges({added, removed})`, `ServedChanges.fromResponse(Map<String, Object?>?)`, `Reloaded(libraries, elapsed, changes: ServedChanges?, reassembleError)`; шаблон `init` з `lib/src/app_module.dart`.

- [ ] **Крок 1: знайти всі місця старого API**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages
grep -rnE "Controller|Application\b|controllers:|appModule|changedRoutes|routes? changed|addedRoutes|removedRoutes|Token<|Value\(" \
  grund_cli grund_build --include=*.dart --include=*.md --include=*.yaml | grep -v ".dart_tool"
```

Очікуваний перелік (на момент написання плану): `lib/src/init/project_template.dart`, `lib/src/dev/{reload_result,reload_client,dev_printer}.dart`, `lib/src/dev/app_launcher.dart` (лише `closeApplications`, не міняється), `test/helpers/{shop_sources,dev_sources}.dart`, `benchmark/benchmark_sources.dart`, `test/{generation_session,gen_command,watch_loop,gen_watch,dev_printer,reload_client,reload_client_timeouts}_test.dart`, `integration/dev_test.dart`, `grund_build/test/helpers/shop_sources.dart`, `README.md` обох пакетів. Що знайдено понад цей перелік — виправити за тим самим принципом. `StreamController` та `closeApplications` — не ціль.

- [ ] **Крок 2: `dev` — формат змін (тест, збій, реалізація)**

Новий клас читає відповідь розширення (відсутня/інша форма -> порожні зміни, бо старший застосунок не відповідає форматом, і `dev` не падає):

Файл `packages/grund_cli/test/served_changes_test.dart`:

```dart
import 'package:grund_cli/src/dev/served_changes.dart';
import 'package:test/test.dart';

void main() {
  group('ServedChanges.fromResponse', () {
    test('reads what the reassemble extension answers', () {
      final changes = ServedChanges.fromResponse({
        'applications': 1,
        'added': ['GET /tasks/:id', 7],
        'removed': ['DELETE /old'],
      });

      expect(changes.added, ['GET /tasks/:id', '7']);
      expect(changes.removed, ['DELETE /old']);
      expect(changes.count, 3);
    });

    test('an answer without the lists means nothing changed', () {
      for (final json in <Map<String, Object?>?>[
        null,
        <String, Object?>{},
        {'applications': 0},
        {'added': 'GET /x', 'removed': <Object?>[]},
      ]) {
        final changes = ServedChanges.fromResponse(json);

        expect(changes.count, 0, reason: '$json');
      }
    });
  });
}
```

Запустити `dart test test/served_changes_test.dart`: збій компіляції. Реалізація:

Файл `packages/grund_cli/lib/src/dev/served_changes.dart`:

```dart
/// What a reassemble added to and removed from what the application's
/// runners serve, as the strings the runners chose (the HTTP server uses
/// `GET /tasks/:id`).
final class ServedChanges {
  /// Creates the changes.
  const ServedChanges({this.added = const [], this.removed = const []});

  /// Reads the answer of the `ext.grund.reassemble` extension
  /// (`{"applications": n, "added": [...], "removed": [...]}`). An answer
  /// without the two lists is read as no changes.
  factory ServedChanges.fromResponse(Map<String, Object?>? json) =>
      switch (json) {
        {
          'added': final List<Object?> added,
          'removed': final List<Object?> removed,
        } =>
          ServedChanges(
            added: [for (final entry in added) '$entry'],
            removed: [for (final entry in removed) '$entry'],
          ),
        _ => const ServedChanges(),
      };

  /// What is served now and was not before.
  final List<String> added;

  /// What was served before and is not now.
  final List<String> removed;

  /// How many entries were added or removed.
  int get count => added.length + removed.length;
}
```

Файл `packages/grund_cli/lib/src/dev/reload_result.dart`:

```dart
import 'served_changes.dart';

/// The outcome of one hot reload of the application process.
sealed class ReloadResult {
  const ReloadResult();
}

/// The VM took the new code; the applications were then reassembled.
final class Reloaded extends ReloadResult {
  /// Creates the result.
  const Reloaded({
    required this.libraries,
    required this.elapsed,
    this.changes,
    this.reassembleError,
  });

  /// How many libraries the VM loaded.
  final int libraries;

  /// How long the reload and the reassemble took.
  final Duration elapsed;

  /// What the reassemble added to and removed from what the application
  /// serves; `null` when no grund application was reassembled.
  final ServedChanges? changes;

  /// Why the reassemble failed (the previous application state keeps
  /// serving); `null` when it succeeded or did not run.
  final String? reassembleError;
}

/// The new code does not compile; the process keeps running the previous
/// code.
final class ReloadFailed extends ReloadResult {
  /// Creates the result.
  const ReloadFailed(this.message);

  /// The compiler's errors, or why the VM service could not reload.
  final String message;
}

/// The VM cannot apply the change to the running process (a limitation of
/// hot reload, for example changed type parameters); it needs a restart.
final class ReloadRejected extends ReloadResult {
  /// Creates the result.
  const ReloadRejected(this.reason);

  /// The VM's reason.
  final String reason;
}
```

У `reload_client.dart` змінюється `_reassemble` (повертає `(ServedChanges?, String?)`) і поле `changes:` у `Reloaded`; повний файл:

Файл `packages/grund_cli/lib/src/dev/reload_client.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'reload_result.dart';
import 'reload_timeouts.dart';
import 'served_changes.dart';

/// Drives the application process through its VM service: hot reload
/// followed by the `ext.grund.reassemble` extension, and the
/// `ext.grund.close` extension before a restart.
final class ReloadClient {
  ReloadClient._(this._service, this._timeouts);

  /// The extension `App` registers to reassemble after a reload.
  static const reassembleMethod = 'ext.grund.reassemble';

  /// The extension `App` registers to close before a restart.
  static const closeMethod = 'ext.grund.close';

  final VmService _service;
  final ReloadTimeouts _timeouts;

  /// Connects to the VM service at [serviceUri] (the `http://` URI the
  /// child printed); `null` when the child is already gone or does not
  /// answer within [ReloadTimeouts.connect].
  static Future<ReloadClient?> connect(
    Uri serviceUri, {
    ReloadTimeouts timeouts = const ReloadTimeouts(),
  }) async {
    // The banner URI ends with `/`, so `ws` resolves below its token.
    final webSocket = serviceUri.resolve('ws').replace(scheme: 'ws');
    final connecting = vmServiceConnectUri('$webSocket');
    try {
      return ReloadClient._(
        await connecting.timeout(timeouts.connect),
        timeouts,
      );
    } on SocketException {
      return null;
    } on WebSocketException {
      return null;
    } on TimeoutException {
      // A connection that completes late is not used by anyone: close it.
      unawaited(
        connecting.then((service) => service.dispose(), onError: (Object _) {}),
      );
      return null;
    }
  }

  /// Reloads the changed sources of the process, then reassembles its
  /// grund applications; a service that does not answer within
  /// [ReloadTimeouts.reload] is a [ReloadFailed].
  Future<ReloadResult> reload() async {
    try {
      return await _reload().timeout(_timeouts.reload);
    } on TimeoutException {
      return const ReloadFailed(
        'The VM service did not answer; the reload timed out.',
      );
    } on RPCError catch (error) {
      return ReloadFailed('The VM service failed: ${error.message}.');
    } on SentinelException catch (error) {
      return ReloadFailed('The VM service failed: $error.');
    }
  }

  Future<ReloadResult> _reload() async {
    final stopwatch = Stopwatch()..start();
    final isolates = await _isolateIds();
    final grund = await _isolateWith(reassembleMethod, isolates);
    final target = grund ?? await _isolateNamed('main', isolates);
    if (target == null) return const ReloadFailed('No isolate to reload.');
    final report = await _service.reloadSources(target);
    if (report.success != true) return _failure(report);
    final (changes, error) = grund == null
        ? (null, null)
        : await _reassemble(grund);
    return Reloaded(
      libraries: _loadedLibraries(report),
      elapsed: stopwatch.elapsed,
      changes: changes,
      reassembleError: error,
    );
  }

  /// Closes the grund applications of the process (they finish their
  /// requests in flight), waiting up to [ReloadTimeouts.close] for the
  /// whole exchange; any failure is left to the restart, which ends the
  /// process anyway.
  Future<void> closeApplications() async {
    try {
      await _close().timeout(_timeouts.close);
    } on RPCError {
      return;
    } on SentinelException {
      return;
    } on TimeoutException {
      return;
    }
  }

  Future<void> _close() async {
    final isolate = await _isolateWith(closeMethod, await _isolateIds());
    if (isolate == null) return;
    await _service.callServiceExtension(closeMethod, isolateId: isolate);
  }

  /// Closes the connection; a service that does not answer is dropped
  /// after [ReloadTimeouts.close].
  Future<void> dispose() =>
      _service.dispose().timeout(_timeouts.close, onTimeout: () {});

  Future<List<String>> _isolateIds() async => [
    for (final isolate in (await _service.getVM()).isolates ?? <IsolateRef>[])
      if (isolate.id case final id?) id,
  ];

  Future<String?> _isolateWith(String method, List<String> isolates) async {
    for (final id in isolates) {
      final isolate = await _isolate(id);
      if (isolate?.extensionRPCs?.contains(method) ?? false) return id;
    }
    return null;
  }

  Future<String?> _isolateNamed(String name, List<String> isolates) async {
    for (final id in isolates) {
      if ((await _isolate(id))?.name == name) return id;
    }
    return null;
  }

  // An isolate that exited between getVM and getIsolate answers with a
  // sentinel; it is not a candidate, and must not fail the whole reload.
  Future<Isolate?> _isolate(String id) async {
    try {
      return await _service.getIsolate(id);
    } on SentinelException {
      return null;
    }
  }

  /// The changes, or the error, of the reassemble in [isolate]. The reload
  /// itself succeeded, so a failure here is the reassemble's.
  Future<(ServedChanges?, String?)> _reassemble(String isolate) async {
    try {
      final response = await _service.callServiceExtension(
        reassembleMethod,
        isolateId: isolate,
      );
      return (ServedChanges.fromResponse(response.json), null);
    } on RPCError catch (error) {
      return (null, error.details ?? error.message);
    } on SentinelException catch (error) {
      return (null, 'The VM service failed: $error.');
    }
  }

  static int _loadedLibraries(ReloadReport report) =>
      switch (report.json?['details']) {
        {'loadedLibraryCount': final int count} => count,
        _ => 0,
      };

  /// A failed reload: notices of type `ReasonForCancellingReload` are
  /// limitations of hot reload, any other notice is a compile error.
  static ReloadResult _failure(ReloadReport report) {
    final notices = switch (report.json?['notices']) {
      final List<Object?> list => list.whereType<Map<String, Object?>>(),
      _ => const <Map<String, Object?>>[],
    };
    final message = [
      for (final notice in notices)
        if (notice['message'] case final String text) text,
    ].join('\n');
    final isLimitation = notices.any(
      (notice) => notice['type'] == 'ReasonForCancellingReload',
    );
    return isLimitation ? ReloadRejected(message) : ReloadFailed(message);
  }
}
```

Друк (`+ GET /hello/bye` / `- ...` після підсумку):

Файл `packages/grund_cli/lib/src/dev/dev_printer.dart`:

```dart
import 'reload_result.dart';

/// Prints what `dev` does with the application at [target] (the entry
/// point relative to the package root): results to [out], failures and
/// why the previous code keeps running to [err].
final class DevPrinter {
  /// Creates the printer.
  const DevPrinter(this.target, this.out, this.err);

  /// The entry point, relative to the package root (`bin/main.dart`).
  final String target;

  /// Where results go.
  final StringSink out;

  /// Where failures go.
  final StringSink err;

  /// The application started as process [pid] with its VM service at
  /// [serviceUri].
  void started(int pid, Uri serviceUri) =>
      out.writeln('Started $target (pid $pid, VM service $serviceUri).');

  /// The application is restarted because of [reason].
  void restarting(String reason) => out.writeln('Restarting $target: $reason.');

  /// The application exited on its own with [code].
  void exited(int code) => err.writeln(
    '$target exited with code $code; it starts again after the next change.',
  );

  /// The VM service of the application could not be reached, so the
  /// application was stopped.
  void unreachable() => err.writeln(
    '$target: could not connect to the VM service; stopped the application, '
    'it starts again after the next change.',
  );

  /// The sources have problems: nothing was started or reloaded.
  void waiting({required bool isRunning}) => err.writeln(
    isRunning
        ? '$target keeps running the previous code.'
        : '$target starts when the problems are fixed.',
  );

  /// The outcome of a hot reload that did not need a restart.
  void reloaded(ReloadResult result) {
    switch (result) {
      case Reloaded(reassembleError: final error?):
        err
          ..writeln(error)
          ..writeln(
            '${_summary(result)}, but the application could not be '
            'reassembled; it keeps its previous modules.',
          );
      case Reloaded(:final changes?):
        out
          ..writeln(
            '${_summary(result)}, ${changes.added.length} added, '
            '${changes.removed.length} removed.',
          )
          ..writeAll([
            for (final entry in changes.added) '  + $entry\n',
            for (final entry in changes.removed) '  - $entry\n',
          ]);
      case Reloaded():
        out.writeln('${_summary(result)}.');
      case ReloadFailed(:final message):
        err
          ..writeln(message)
          ..writeln(
            'Hot reload failed; $target keeps running the previous code.',
          );
      case ReloadRejected(:final reason):
        restarting('hot reload is not possible: $reason');
    }
  }

  static String _summary(Reloaded result) =>
      'Reloaded ${_count(result.libraries, 'library', 'libraries')} '
      'in ${result.elapsed.inMilliseconds} ms';

  static String _count(int count, String one, [String? many]) =>
      '$count ${count == 1 ? one : many ?? '${one}s'}';
}
```

Тести друку (два нових: зміни зі списками, збій reassemble — «keeps its previous modules»):

Файл `packages/grund_cli/test/dev_printer_test.dart`:

```dart
import 'package:grund_cli/src/dev/dev_printer.dart';
import 'package:grund_cli/src/dev/reload_result.dart';
import 'package:grund_cli/src/dev/served_changes.dart';
import 'package:test/test.dart';

/// What [print] wrote to stdout and stderr through a [DevPrinter].
(String, String) printed(void Function(DevPrinter printer) print) {
  final out = StringBuffer();
  final err = StringBuffer();
  print(DevPrinter('bin/main.dart', out, err));
  return ('$out', '$err');
}

const _elapsed = Duration(milliseconds: 180);

void main() {
  test('a reload with a reassemble counts and lists what changed', () {
    expect(
      printed(
        (printer) => printer.reloaded(
          const Reloaded(
            libraries: 3,
            elapsed: _elapsed,
            changes: ServedChanges(
              added: ['GET /hello/bye', 'GET /hello/hi'],
              removed: ['GET /hello/old'],
            ),
          ),
        ),
      ),
      (
        'Reloaded 3 libraries in 180 ms, 2 added, 1 removed.\n'
            '  + GET /hello/bye\n'
            '  + GET /hello/hi\n'
            '  - GET /hello/old\n',
        '',
      ),
    );
  });

  test('a reassemble that changed nothing says so in one line', () {
    expect(
      printed(
        (printer) => printer.reloaded(
          const Reloaded(
            libraries: 1,
            elapsed: _elapsed,
            changes: ServedChanges(),
          ),
        ),
      ),
      ('Reloaded 1 library in 180 ms, 0 added, 0 removed.\n', ''),
    );
  });

  test('a reload without a grund application has no change counts', () {
    expect(
      printed(
        (printer) =>
            printer.reloaded(const Reloaded(libraries: 1, elapsed: _elapsed)),
      ),
      ('Reloaded 1 library in 180 ms.\n', ''),
    );
  });

  test('a failed reassemble prints the error and the kept state', () {
    final (out, err) = printed(
      (printer) => printer.reloaded(
        const Reloaded(
          libraries: 1,
          elapsed: _elapsed,
          reassembleError: 'MissingProviderError: ...',
        ),
      ),
    );

    expect(out, isEmpty);
    expect(
      err,
      'MissingProviderError: ...\n'
      'Reloaded 1 library in 180 ms, but the application could not be '
      'reassembled; it keeps its previous modules.\n',
    );
  });

  test('a compile error keeps the previous code', () {
    expect(
      printed(
        (printer) => printer.reloaded(const ReloadFailed('x.dart: Error')),
      ),
      (
        '',
        'x.dart: Error\n'
            'Hot reload failed; bin/main.dart keeps running the previous code.\n',
      ),
    );
  });

  test('a rejected reload announces the restart with the reason', () {
    expect(
      printed(
        (printer) => printer.reloaded(const ReloadRejected('Limitation: x')),
      ),
      (
        'Restarting bin/main.dart: hot reload is not possible: Limitation: x.\n',
        '',
      ),
    );
  });

  test('start, exit and problems are one line each', () {
    final (out, err) = printed(
      (printer) => printer
        ..started(42, Uri.parse('http://127.0.0.1:1/a=/'))
        ..exited(255)
        ..waiting(isRunning: true)
        ..waiting(isRunning: false),
    );

    expect(
      out,
      'Started bin/main.dart (pid 42, VM service http://127.0.0.1:1/a=/).\n',
    );
    expect(
      err,
      'bin/main.dart exited with code 255; it starts again after the next '
      'change.\n'
      'bin/main.dart keeps running the previous code.\n'
      'bin/main.dart starts when the problems are fixed.\n',
    );
  });

  test('an unreachable VM service says the application was stopped', () {
    expect(printed((printer) => printer.unreachable()), (
      '',
      'bin/main.dart: could not connect to the VM service; stopped the '
          'application, it starts again after the next change.\n',
    ));
  });
}
```

Правки в інших тестах `dev` (точні заміни):
- `test/reload_client_test.dart`, рядок 63: `expect(reloaded.changedRoutes, 0);` -> `expect(reloaded.changes?.count, 0);`
- `test/reload_client_timeouts_test.dart`, рядок 80: `expect((result as Reloaded).changedRoutes, isNull);` -> `expect((result as Reloaded).changes, isNull);`
- `lib/src/dev/shape_tracker.dart`, коментар класу: слова «the providers kept by `Container.reassemble`» -> «the singletons kept by `App.reassemble`».

Запустити `dart test test/served_changes_test.dart test/dev_printer_test.dart test/reload_client_test.dart test/reload_client_timeouts_test.dart test/shape_tracker_test.dart`. Очікування: зелені (на прототипі це проходило; `reload_client_test` потребує, щоб застосунок з кроку 4 вже збирався, тож цей пункт повторити після кроку 4).

- [ ] **Крок 3: шаблон `init`**

Нові `pubspec` (додано `grund_http`), `lib/src/app_module.dart` (`@Module(imports: [HttpModule(), IoAdapterModule()], providers: [...])`, ядро з префіксом `grund`), `HelloApi` замість контролера, `bin/main.dart` на `App(root:).run(only: Runners.fromArgs(arguments))`:

Файл `packages/grund_cli/lib/src/init/project_template.dart`:

```dart
/// The files of a new grund application, as `init` writes them.
///
/// A flat catalog of file contents without logic.
abstract final class ProjectTemplate {
  /// The version constraint of the grund packages in a new pubspec: the
  /// first published release.
  static const grundVersion = '^0.1.0';

  /// The files of application [name] (relative path to content), sorted by
  /// path.
  ///
  /// [name] is interpolated into the files as is: it must be a valid Dart
  /// package name (`[a-z_][a-z0-9_]*`), which `ProjectScaffold` checks.
  static Map<String, String> files(String name) => {
    '.gitignore': '.dart_tool/\n',
    'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
    'bin/main.dart': _main(name),
    'lib/src/app_module.dart': _appModule(name),
    'lib/src/hello.dart': _hello,
    'pubspec.yaml': _pubspec(name),
  };

  static String _pubspec(String name) =>
      '''
name: $name
description: A grund application.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  grund: $grundVersion
  grund_annotations: $grundVersion
  grund_http: $grundVersion
  grund_io: $grundVersion

dev_dependencies:
  grund_cli: $grundVersion
  lints: ^5.1.0
''';

  static const _hello = '''
import 'package:grund_annotations/grund_annotations.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, \$name!'};
}

/// `GET /hello?name=...`.
@Api('/hello')
final class HelloApi {
  /// Creates the API.
  HelloApi(this.service);

  /// The service.
  final HelloService service;

  /// Greets [name], or the world.
  @Get('/')
  Map<String, String> hello(@Query() String? name) =>
      service.greet(name ?? 'world');
}
''';

  static String _appModule(String name) =>
      '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:$name/$name.grund.dart';

import 'hello.dart';

/// The root module: the HTTP server over dart:io and the hello API.
@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [HelloService, HelloApi],
)
final class AppModule extends grund.Module with \$AppModule {
  /// Creates the module.
  const AppModule();
}
''';

  static String _main(String name) =>
      '''
import 'package:grund/grund.dart';
import 'package:$name/src/app_module.dart';

/// Serves the application until Ctrl+C; `--only=http` selects runners.
Future<void> main(List<String> arguments) async {
  print('Listening on http://localhost:8080/hello');
  await App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
}
''';
}
```

Тест `test/init_command_test.dart` не змінюється (він створює проєкт, запускає `gen` і `dart analyze` над результатом: падає, доки генератор з задач 13-18 не готовий; запускати після кроку 5).

- [ ] **Крок 4: зразки джерел у тестах**

Зміни проти старих: `@Controller` -> `@Api`, `@Get()` -> `@Get('/')`, `@Param`->`@Path`, `@Module(id:, controllers:)` -> `@Module(providers:)` + `extends grund.Module with $AppModule` + user `const`-конструктор; ядро з префіксом `grund`; файли `*_controller.dart` перейменовано на `*_api.dart`.

Файл `packages/grund_cli/test/helpers/shop_sources.dart`:

```dart
/// Sources of a small annotated package `shop`: a clock service, an API
/// that uses it and the root module.
abstract final class ShopSources {
  /// The generated library of `shop`.
  static const output = 'lib/shop.grund.dart';

  /// `lib/src/clock.dart`.
  static const clock = '''
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class Clock {
  DateTime now() => DateTime.utc(2026);
}
''';

  /// `lib/src/time_api.dart`.
  static const api = '''
import 'package:grund_annotations/grund_annotations.dart';

import 'clock.dart';

@Api('/time')
final class TimeApi {
  TimeApi(this.clock);

  final Clock clock;

  @Get('/')
  Map<String, String> now() => {'now': clock.now().toIso8601String()};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:shop/shop.grund.dart';

import 'clock.dart';
import 'time_api.dart';

@Module(providers: [Clock, TimeApi])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// `lib/src/app_module.dart` without the clock: a `missing_provider`.
  static const moduleWithoutClock = '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:shop/shop.grund.dart';

import 'time_api.dart';

@Module(providers: [TimeApi])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_api.dart': api,
    'lib/src/app_module.dart': module,
  };
}
```

`dev_sources.dart` (застосунок `hello`; `main` бере порт з аргумента через override `HttpConfig`, друкує `listening on <port>`; рядок `final adapter` збережений, бо тести `dev_session_failures`/`dev_test` редагують `'final adapter'` у `bin/main.dart`):

Файл `packages/grund_cli/test/helpers/dev_sources.dart`:

```dart
/// Sources of a small annotated application `hello` with a `bin/main.dart`
/// that serves it on a loopback port (its first argument, an ephemeral
/// port without one) and prints
/// `listening on <port>`; `GET /hello` answers the greeting and the pid.
abstract final class DevSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:hello/src/app_module.dart';

Future<void> main(List<String> arguments) async {
  final port = arguments.isEmpty ? 0 : int.parse(arguments.first);
  final app = App(
    root: const AppModule(),
    overrides: [
      Singleton<HttpConfig>(
        (_) => HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
        dependsOn: const [],
      ),
    ],
  );
  await app.start();
  final adapter = app.container.root<HttpAdapter>();
  print('listening on \${adapter is IoAdapter ? adapter.port : port}');
}
''';

  /// `lib/src/greeter.dart`.
  static const greeter = '''
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class Greeter {
  String greet() => 'hello v1';
}
''';

  /// `lib/src/hello_api.dart`.
  static const api = '''
import 'dart:io';

import 'package:grund_annotations/grund_annotations.dart';

import 'greeter.dart';

@Api('/hello')
final class HelloApi {
  HelloApi(this.greeter);

  final Greeter greeter;

  @Get('/')
  Map<String, Object> hello() => {'text': greeter.greet(), 'pid': pid};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:hello/hello.grund.dart';

import 'greeter.dart';
import 'hello_api.dart';

@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [Greeter, HelloApi],
)
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// The files of the application.
  static const files = {
    'bin/main.dart': main,
    'lib/src/greeter.dart': greeter,
    'lib/src/hello_api.dart': api,
    'lib/src/app_module.dart': module,
  };
}
```

Бенчмарк (`package bench`):

Файл `packages/grund_cli/benchmark/benchmark_sources.dart`:

```dart
/// A generated annotated package of `4 * features + 1` libraries: per
/// feature a repository, a service, an API and a module, plus the root
/// module that imports every feature.
abstract final class BenchmarkSources {
  /// The files of the package (relative path to content).
  static Map<String, String> files(int features) => {
    for (var i = 0; i < features; i++) ..._feature(i),
    'lib/app.dart': _root(features),
  };

  /// The API of feature [i] with one more route.
  static String changedApi(int i) =>
      _api(i).replaceFirst("@Get('/')", "@Get('/v2')");

  /// The path of feature [i]'s API.
  static String apiPath(int i) => 'lib/src/f$i/api.dart';

  static Map<String, String> _feature(int i) => {
    'lib/src/f$i/repository.dart':
        '''
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class Repository$i {
  List<String> all() => ['item $i'];
}
''',
    'lib/src/f$i/service.dart':
        '''
import 'package:grund_annotations/grund_annotations.dart';

import 'repository.dart';

@Injectable()
final class Service$i {
  Service$i(this.repository);

  final Repository$i repository;

  List<String> list() => repository.all();
}
''',
    apiPath(i): _api(i),
    'lib/src/f$i/module.dart':
        '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:bench/bench.grund.dart';

import 'api.dart';
import 'repository.dart';
import 'service.dart';

@Module(providers: [Repository$i, Service$i, Feature${i}Api])
final class Feature${i}Module extends grund.Module with \$Feature${i}Module {
  const Feature${i}Module();
}
''',
  };

  static String _api(int i) =>
      '''
import 'package:grund_annotations/grund_annotations.dart';

import 'service.dart';

@Api('/f$i')
final class Feature${i}Api {
  Feature${i}Api(this.service);

  final Service$i service;

  @Get('/')
  List<String> list() => service.list();

  @Get('/:id')
  Map<String, Object?> one(@Path() int id) => {'id': id};
}
''';

  static String _root(int features) {
    final imports = [
      for (var i = 0; i < features; i++) "import 'src/f$i/module.dart';",
    ];
    final modules = [for (var i = 0; i < features; i++) 'Feature${i}Module()'];
    return '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:bench/bench.grund.dart';

${imports.join('\n')}

@Module(imports: [${modules.join(', ')}])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';
  }
}
```

Правки тестів, що посилаються на зразки (точні):

```bash
cd packages/grund_cli
sed -i 's#hello_controller#hello_api#g' test/*.dart integration/*.dart
sed -i "s#ShopSources.controller.replaceFirst('@Get()', \"@Get('/now')\")#ShopSources.api.replaceFirst(\"@Get('/')\", \"@Get('/now')\")#" test/gen_watch_test.dart test/watch_loop_test.dart
sed -i 's#BenchmarkSources.changedController#BenchmarkSources.changedApi#; s#BenchmarkSources.controllerPath#BenchmarkSources.apiPath#' benchmark/generation_benchmark_test.dart
sed -i 's#time_controller#time_api#g' test/*.dart
```

`test/gen_watch_test.dart` і `watch_loop_test.dart` пишуть змінений `ShopSources.api` у `lib/src/time_api.dart` (перевірити, що в обох уживається саме цей шлях).

`test/generation_session_test.dart`: рядок `expect(generated, contains('grund.Module appModule()'));` -> `expect(generated, contains('mixin \$AppModule on grund.Module'));`. Діагностика: повний текст і позиція (`7:23`, формулювання) належать задачі 15 і можуть змінитися, тому тести закріплюють лише стабільне — код і місце:

```dart
    expect(report.problemLines, hasLength(1));
    expect(
      report.problemLines.single,
      allOf(
        startsWith('lib/src/time_api.dart:'),
        contains('Clock'),
        endsWith('[missing_provider]'),
      ),
    );
```

(замість `expect(report.problemLines, [ ... ])`), а в `test/gen_command_test.dart` замість точного `run.err` (рядки 39-46):

```dart
    final lines = run.err.trimRight().split('\n');
    expect(lines, hasLength(2));
    expect(
      lines.first,
      allOf(
        startsWith('lib/src/time_api.dart:'),
        contains('Clock'),
        endsWith('[missing_provider]'),
      ),
    );
    expect(lines.last, '1 problem; lib/shop.grund.dart was not changed.');
```

`test/watch_loop_test.dart` (рядок 95) вже перевіряє `endsWith('[missing_provider]')` — не міняється. Якщо задача 15 перейменувала код діагностики — підставити його скрізь однаково (`grep -rn missing_provider packages/grund_cli`).

`integration/dev_test.dart` (рядки 112-118): редагування маршруту й очікування:

```dart
    dev.app.edit(
      'lib/src/hello_api.dart',
      "  @Get('/')",
      "  @Get('/bye')\n  Map<String, Object> bye() => {'text': 'bye'};\n\n"
          "  @Get('/')",
    );
    await until(dev.lines, (line) => line.endsWith(', 1 added, 0 removed.'));
    await until(dev.lines, (line) => line == '  + GET /hello/bye');
```

- [ ] **Крок 5: перевірка `grund_cli`**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_cli && dart analyze && dart test && dart test integration
```

Очікування: `No issues found!`; кількість тестів не менша за до змін (+3 нових); `integration` (потребує задач 1-18) зелений, зокрема «dev reloads bodies and routes and restarts on a new field» (RF-4: `main` падає після редагування `final adapter` -> `dev` лишається). Бенчмарк: `dart test benchmark` (пороги 10 с/1 с).

- [ ] **Крок 6: `grund_build`**

Код білдера (`GrundBuilder`, `PackageSources`, `GrundBuildOptions`) не міняється: він викликає `PackageCollector`/`GrundGenerator.core()` тією ж формою, що й `GenerationSession` у CLI, і тому пише ті самі байти й заголовок. Якщо задача 18 змінила сигнатури `PackageCollector(...)`/`GrundGenerator` — однаково підправити `packages/grund_cli/lib/src/generate/generation_session.dart` і `packages/grund_build/lib/src/grund_builder.dart` (різниця між ними має лишатися нульовою: `conformance_test` порівнює результат білдера з CLI на `users_app`). Зразки:

Файл `packages/grund_build/test/helpers/shop_sources.dart`:

```dart
/// Sources of a small annotated package `shop`: a clock service, an API
/// that uses it, the root module, and the variants the builder tests need.
abstract final class ShopSources {
  /// The package name.
  static const package = 'shop';

  /// `lib/src/clock.dart`.
  static const clock = '''
import 'package:grund_annotations/grund_annotations.dart';

@Injectable()
final class Clock {
  DateTime now() => DateTime.utc(2026);
}
''';

  /// `lib/src/time_api.dart`.
  static const api = '''
import 'package:grund_annotations/grund_annotations.dart';

import 'clock.dart';

@Api('/time')
final class TimeApi {
  TimeApi(this.clock);

  final Clock clock;

  @Get('/')
  Map<String, String> now() => {'now': clock.now().toIso8601String()};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:shop/shop.grund.dart';

import 'clock.dart';
import 'time_api.dart';

@Module(providers: [Clock, TimeApi])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_api.dart': api,
    'lib/src/app_module.dart': module,
  };

  /// `lib/src/broken.dart`: two syntax errors on one line.
  static const broken = 'final class Broken { void f( }\n';

  /// `lib/src/user.dart`: a request body whose `fromJson` lives in a part
  /// that another builder (json_serializable) generates.
  static const user = '''
part 'user.g.dart';

final class User {
  const User(this.name);

  factory User.fromJson(Map<String, Object?> json) => _\$UserFromJson(json);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}
''';

  /// `lib/src/user.g.dart`, the generated part of [user].
  static const userPart = '''
part of 'user.dart';

User _\$UserFromJson(Map<String, Object?> json) => User(json['name'] as String);
''';

  /// `lib/src/users.dart`: an API and a module that take a [user].
  static const users = '''
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:shop/shop.grund.dart';

import 'user.dart';

@Api('/users')
final class UsersApi {
  @Post('/')
  User create(@Body() User user) => user;
}

@Module(providers: [UsersApi])
final class UsersModule extends grund.Module with \$UsersModule {
  const UsersModule();
}
''';
}
```

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd packages/grund_build && sed -i 's#time_controller#time_api#g' test/*.dart
dart analyze && dart test && dart test integration
```

Очікування: зелені; `integration/build_runner_test.dart` генерує справжній build_runner над `users_app` з задачі 18 і порівнює з голденом.

- [ ] **Крок 7: README і CHANGELOG пакетів**

`packages/grund_cli/README.md` (три місця):
1. приклад виводу `dev` (рядок 83) замінити на
```text
Reloaded 3 libraries in 180 ms, 2 added, 0 removed.
  + GET /hello/bye
  + GET /hello/hi
```
2. пункт «reassembled (`ext.grund.reassemble`...)»: «provider instances keep their state, controllers and routes are rebuilt» -> «singletons keep their state when their module is unchanged, the modules, `HttpApi`s and routes are rebuilt, the process and its port stay. The line lists what changed in what the runners serve (for `http`: the routes added and removed)».
3. розділ `init` (рядки ~137-160): «(a service, a controller and the root `AppModule`)» -> «(a service, an `@Api` and the root `AppModule` that imports `HttpModule` and `IoAdapterModule`)»; перелік залежностей додає `grund_http`; приклад `dependency_overrides` додає `grund_http: {path: ../grund/packages/grund_http}`.
`packages/grund_build/README.md`: у прикладах з анотаціями замінити `@Controller`/`id:` на `@Api`/`@Module(providers: ...)`; решта (build.yaml, `package` option) без змін.

CHANGELOG-и обох пакетів (версія лишається `0.1.0`, пакет не публікувався): у `grund_cli` у список `0.1.0` дописати «`grund dev` prints what a reload added to and removed from what the application serves (for the HTTP server: routes).» і «`grund init` scaffolds an `App` with `HttpModule`, `IoAdapterModule` and an `@Api`.»; у `grund_build` — рядок «Writes the same bytes as `grund_cli gen` for the annotations of `grund_annotations` 0.1.0 (modules as `extends Module with $Module`).»

- [ ] **Крок 8: самоперевірка і коміти**

`wc -l` змінених файлів `lib/` (<= 300; `dev_printer.dart` і `reload_client.dart` мають лишитися меншими), `dart format packages` (0 змін), `dart analyze` з кореня. Коміти: `refactor(cli): dev reads the added/removed reassemble report`, `feat(cli): init scaffolds an App with HttpModule`, `test(cli): shop, hello and bench samples on @Api`, `test(build): shop samples on @Api`, `docs(cli): README and changelogs for the new API`.

**Review Focus цієї задачі:** RF-4 (збій `main` після правки -> `dev` тримає попередній код і перезапускає; `reassembleError` друкується «keeps its previous modules»).


### Задача 20: Приклад `tasks_api` — дві форми, обидва адаптери

**Мета:** переписати `example/` на новий API: анотована форма (`@Module`/`@Injectable`/`@Api`/`@Provides`/`Bind` + згенерований `lib/tasks_api.grund.dart`) і явна форма (`lib/explicit.dart`), хуки `ApiKeyHook`/`RolesHook`/`LocationHook`/`TaskNotFoundHook`/`TimingHook`, `RequestIdMiddleware`, `bin/main.dart`, спільний e2e-набір для {анотації, явна} x {io, shelf}, golden-перевірка «згенерований файл актуальний», README. Поведінка старого прикладу зберігається (ті самі маршрути, ключі, коди), крім тіл помилок: тепер `application/problem+json`.

**Передумови:** задачі 1-19; генератор (13-18) уміє емітити форму з узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17).

**Files:**
- Delete: `example/lib/src/**` старих файлів: `auth/{api_key_guard,api_keys,roles,roles_guard,auth_module}.dart`, `common/{timing_interceptor,trim_strings_pipe,request_id_middleware}.dart`, `config/config_module.dart`, `health/{health_controller,health_module}.dart`, `tasks/{create_task_dto,update_task_dto,task_not_found_filter,tasks_controller,tasks_module,tasks_service,task,task_store,in_memory_task_store,task_not_found}.dart`, `server/tasks_app.dart`, `test/helpers/loopback_server.dart`, `test/in_process_test.dart` (усі перезаписуються нижче; `git rm`, потім Create)
- Create/Modify: `example/pubspec.yaml`, `example/lib/tasks_api.dart`, `example/lib/explicit.dart`, `example/lib/tasks_api.grund.dart` (генерується), `example/lib/src/**` (файли нижче), `example/bin/main.dart`, `example/README.md`
- Test: `example/test/{e2e,in_process,tasks_service,server_options,main_process,generated_library}_test.dart`, `example/test/helpers/*`

**Interfaces:**
- Consumes: `Module`, `Singleton`, `Key`, `App`, `Runners.fromArgs`, `StopSignals`, `RunnerError`, `TestApp` (ядро); `HttpApi`, `Route`, `HttpHook`, `HookRef`, `Middleware`, `HttpModule`, `HttpConfig`, `HttpCtx`, `HttpException`-родина, `ErrorLog`, `TestClient.of` (`grund_http`); `IoAdapterModule`, `ShelfAdapterModule`, `IoAdapter`, `ShelfAdapter` (задача 12); анотації задачі 13; вивід генератора (узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17)).
- Produces: `AppModule`, `ExplicitAppModule`, `ServingModule(application, kind, {address, port, onError})`, `TasksApp.create(ServerOptions)`/`TasksApp.graph(ModuleStyle)`, `ServerOptions.parse`.

**Рішення в дизайні:**
- Застосунок (`AppModule`/`ExplicitAppModule`) не знає, чим його обслуговують: `ServingModule` обгортає будь-який корінь у `HttpModule` + модуль адаптера (вибір `--shelf` під час запуску). Глобальні хук (`TimingHook`) і middleware (`RequestIdMiddleware`, зі станом лічильника, тому не `const`) живуть саме там.
- `Location` ставить `LocationHook` (`after`): handler лишається чистим, `status: 201` задає маршрут.
- `TrimStringsPipe` прибрано: обрізання й валідація — у `CreateTask.fromJson`/`UpdateTask.fromJson` (кидають `FormatException`, `HttpCtx.body` відповідає 400 `body_invalid` із `pointer: /body`).
- `TaskNotFoundHook.onError` кидає `NotFoundException(code: 'task_not_found')` — виняток з `onError` переходить далі й стає problem-відповіддю (перевіряється e2e).
- `main` підписується на сигнали ДО старту (інакше SIGTERM у вікні між `print` і підпискою вбиває процес кодом -15), а при невдалому старті (порт зайнятий -> `RunnerError` з `SocketException`) друкує один рядок у stderr і `exit(1)`.

- [ ] **Крок 1: pubspec і видалення старого**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
cd example
git rm -r -q lib/src lib/tasks_api.grund.dart test/helpers/loopback_server.dart test/in_process_test.dart
```

Файл `example/pubspec.yaml` (до `dependencies` додано `grund_http`; `resolution: workspace` лишається):

```yaml
name: tasks_api
description: The grund example application, a small tasks API; see README.md.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  grund: ^0.1.0
  grund_annotations: ^0.1.0
  grund_http: ^0.1.0
  grund_io: ^0.1.0
  grund_shelf: ^0.1.0

dev_dependencies:
  grund_cli: ^0.1.0
  lints: ^5.1.0
  path: ^1.9.0
  test: ^1.25.0
```

- [ ] **Крок 2: предметна область (не залежить від HTTP)**

Файл `example/lib/src/tasks/task.dart`:

```dart
/// A task of the tasks API.
final class Task {
  /// Creates a task.
  const Task({required this.id, required this.title, this.done = false});

  /// The id the store assigned.
  final int id;

  /// What to do.
  final String title;

  /// Whether the task is done.
  final bool done;

  /// This task with [title] and [done] replaced where given.
  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  /// The JSON form; grund serializes results through `toJson()`.
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};
}
```
Файл `example/lib/src/tasks/task_not_found.dart`:

```dart
/// Thrown by `TasksService` for an id no task has.
final class TaskNotFound implements Exception {
  /// Creates the error.
  const TaskNotFound(this.id);

  /// The unknown id.
  final int id;

  @override
  String toString() => 'TaskNotFound($id)';
}
```
Файл `example/lib/src/tasks/task_store.dart`:

```dart
import 'task.dart';

/// Where tasks live. The example binds it to `InMemoryTaskStore`; a real
/// application binds a database-backed class instead.
abstract interface class TaskStore {
  /// Every task, by id.
  List<Task> all();

  /// The task [id], or `null`.
  Task? find(int id);

  /// Stores a new task titled [title] and returns it.
  Task add(String title);

  /// Replaces the stored task with the same id; returns whether it existed.
  bool replace(Task task);

  /// Removes the task [id]; returns whether it existed.
  bool remove(int id);
}
```
Файл `example/lib/src/tasks/in_memory_task_store.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';

import 'task.dart';
import 'task_store.dart';

/// A [TaskStore] in memory, starting with two tasks. Its state survives a
/// hot reload, because grund keeps provider instances.
@Injectable()
final class InMemoryTaskStore implements TaskStore {
  final Map<int, Task> _tasks = {
    1: const Task(id: 1, title: 'Read the grund README'),
    2: const Task(id: 2, title: 'Run grund dev', done: true),
  };
  int _lastId = 2;

  // Ids only grow and a replaced task keeps its place, so insertion order
  // is id order.
  @override
  List<Task> all() => List.unmodifiable(_tasks.values);

  @override
  Task? find(int id) => _tasks[id];

  @override
  Task add(String title) {
    final task = Task(id: ++_lastId, title: title);
    _tasks[task.id] = task;
    return task;
  }

  @override
  bool replace(Task task) {
    if (!_tasks.containsKey(task.id)) return false;
    _tasks[task.id] = task;
    return true;
  }

  @override
  bool remove(int id) => _tasks.remove(id) != null;
}
```
Файл `example/lib/src/tasks/create_task.dart`:

```dart
/// The body of `POST /tasks`.
final class CreateTask {
  /// Creates the body.
  const CreateTask(this.title);

  /// Reads the body: the title is trimmed, then it must have 1 to
  /// [maxTitleLength] characters. Anything else is a [FormatException],
  /// which `HttpCtx.body` answers with 400.
  factory CreateTask.fromJson(Map<String, Object?> json) => switch (json) {
    {'title': final String title}
        when title.trim().isNotEmpty && title.trim().length <= maxTitleLength =>
      CreateTask(title.trim()),
    _ => throw const FormatException(
      '"title" must be a string of 1 to $maxTitleLength characters',
    ),
  };

  /// The longest accepted title.
  static const maxTitleLength = 200;

  /// What to do.
  final String title;
}
```
Файл `example/lib/src/tasks/update_task.dart`:

```dart
import 'create_task.dart';

/// The body of `PATCH /tasks/:id`: the fields to change.
final class UpdateTask {
  /// Creates the body.
  const UpdateTask({this.title, this.done});

  /// Reads the body; a field of the wrong type is a [FormatException]
  /// (400 from `HttpCtx.body`).
  factory UpdateTask.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final done = json['done'];
    final validTitle =
        title == null ||
        title is String &&
            title.trim().isNotEmpty &&
            title.trim().length <= CreateTask.maxTitleLength;
    if (!validTitle || (done != null && done is! bool)) {
      throw const FormatException(
        '"title" must be a non-empty string and "done" a boolean',
      );
    }
    return UpdateTask(title: (title as String?)?.trim(), done: done as bool?);
  }

  /// The new title, or `null` to keep it.
  final String? title;

  /// The new state, or `null` to keep it.
  final bool? done;
}
```
Файл `example/lib/src/tasks/tasks_service.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';

import 'create_task.dart';
import 'task.dart';
import 'task_not_found.dart';
import 'task_store.dart';
import 'update_task.dart';

/// The task use cases; knows nothing about HTTP.
@Injectable()
final class TasksService {
  /// Works on [store].
  TasksService(this.store);

  /// Where the tasks live.
  final TaskStore store;

  /// Every task, or only those whose state is [done].
  List<Task> list({bool? done}) => [
    for (final task in store.all())
      if (done == null || task.done == done) task,
  ];

  /// The task [id]; throws [TaskNotFound].
  Task find(int id) => store.find(id) ?? (throw TaskNotFound(id));

  /// Adds a task.
  Task create(CreateTask body) => store.add(body.title);

  /// Changes the fields of task [id] that [body] gives; throws
  /// [TaskNotFound].
  Task update(int id, UpdateTask body) {
    final task = find(id).copyWith(title: body.title, done: body.done);
    store.replace(task);
    return task;
  }

  /// Deletes task [id]; throws [TaskNotFound].
  void delete(int id) {
    if (!store.remove(id)) throw TaskNotFound(id);
  }
}
```

- [ ] **Крок 3: конфігурація, авторизація, хуки**

Файл `example/lib/src/auth/role.dart`:

```dart
/// What a caller may do.
enum Role {
  /// Reads tasks.
  reader,

  /// Reads, creates, changes and deletes tasks.
  editor,
}
```
Файл `example/lib/src/auth/current_user.dart`:

```dart
import 'role.dart';

/// The caller of a request, stored in the call scope by `ApiKeyHook`.
final class CurrentUser {
  /// A caller with [role].
  const CurrentUser(this.role);

  /// What the caller may do.
  final Role role;
}
```
Файл `example/lib/src/config/app_config.dart`:

```dart
import '../auth/role.dart';

/// The application name and the API keys, with the role each one grants.
final class AppConfig {
  /// Creates the configuration.
  const AppConfig({required this.name, required this.apiKeys});

  /// The configuration of the example; a real application reads the keys
  /// from a secret store.
  static const demo = AppConfig(
    name: 'tasks_api',
    apiKeys: {'reader-key': Role.reader, 'editor-key': Role.editor},
  );

  /// The name the health check reports.
  final String name;

  /// The role each API key grants.
  final Map<String, Role> apiKeys;
}
```
Файл `example/lib/src/config/config_module.dart`:

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:tasks_api/tasks_api.grund.dart';

import 'app_config.dart';

/// The configuration every module sees: [global] makes its export visible
/// without an import.
@Module(global: true, exports: [AppConfig])
final class ConfigModule extends grund.Module with $ConfigModule {
  /// Creates the module.
  const ConfigModule();

  /// The configuration value; a `@Provides` method is a singleton.
  @Provides()
  static AppConfig appConfig() => AppConfig.demo;
}
```
Файл `example/lib/src/auth/api_key_hook.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

import '../config/app_config.dart';
import 'current_user.dart';

/// Lets a request through when its `x-api-key` header is a known key, and
/// stores the caller for the hooks and handlers after it.
@Injectable()
final class ApiKeyHook extends HttpHook {
  /// Checks keys with [config].
  ApiKeyHook(this.config);

  /// The known keys.
  final AppConfig config;

  @override
  void before(HttpCtx c) {
    final key = c.headers.stringOrNull('x-api-key');
    final role = key == null ? null : config.apiKeys[key];
    if (role == null) {
      throw const UnauthorizedException(
        message: 'Send a valid x-api-key.',
        code: 'api_key_invalid',
      );
    }
    c.set<CurrentUser>(CurrentUser(role));
  }
}
```
Файл `example/lib/src/auth/roles_hook.dart`:

```dart
import 'package:grund_http/grund_http.dart';

import 'current_user.dart';
import 'role.dart';

/// Allows a route only for [role]; runs after `ApiKeyHook`, which stores
/// the caller. An instance hook: `HookRef<RolesHook>.instance(...)`.
final class RolesHook extends HttpHook {
  /// Allows [role].
  const RolesHook(this.role);

  /// The role a route needs.
  final Role role;

  @override
  void before(HttpCtx c) {
    if (c<CurrentUser>().role != role) {
      throw ForbiddenException(
        message: 'This route needs the ${role.name} role.',
        code: 'role_required',
      );
    }
  }
}
```
Файл `example/lib/src/auth/auth_module.dart`:

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:tasks_api/tasks_api.grund.dart';

import 'api_key_hook.dart';

/// The API key check; modules that protect routes import it.
@Module(providers: [ApiKeyHook], exports: [ApiKeyHook])
final class AuthModule extends grund.Module with $AuthModule {
  /// Creates the module.
  const AuthModule();
}
```
Файл `example/lib/src/tasks/location_hook.dart`:

```dart
import 'package:grund_http/grund_http.dart';

import 'task.dart';

/// Adds `location: /tasks/<id>` to the response of a handler that returned
/// a [Task]. `after` runs only when the handler succeeded.
final class LocationHook extends HttpHook {
  /// Creates the hook.
  const LocationHook();

  @override
  void after(HttpCtx c, Object? result) {
    if (result case Task(:final id)) {
      c.response.headers.set('location', '/tasks/$id');
    }
  }
}
```
Файл `example/lib/src/tasks/task_not_found_hook.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

import 'task_not_found.dart';

/// Answers [TaskNotFound] with 404, so the service stays free of HTTP.
@Injectable()
final class TaskNotFoundHook extends HttpHook {
  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is! TaskNotFound) return null;
    throw NotFoundException(
      message: 'No task ${error.id}.',
      code: 'task_not_found',
    );
  }
}
```
Файл `example/lib/src/common/timing_hook.dart`:

```dart
import 'package:grund_http/grund_http.dart';

/// Adds `server-timing: handler;dur=<ms>` to every routed response, also to
/// an error one: the time the hooks after it and the handler took. Global:
/// `HttpModule(use:)` in `ServingModule`.
final class TimingHook extends HttpHook {
  /// Creates the hook.
  const TimingHook();

  @override
  void before(HttpCtx c) => c.set<Stopwatch>(Stopwatch()..start());

  @override
  void after(HttpCtx c, Object? result) => _stamp(c);

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    _stamp(c);
    return null;
  }

  void _stamp(HttpCtx c) {
    final milliseconds = c<Stopwatch>().elapsedMicroseconds / 1000;
    c.response.headers.set(
      'server-timing',
      'handler;dur=${milliseconds.toStringAsFixed(1)}',
    );
  }
}
```
Файл `example/lib/src/common/request_id_middleware.dart`:

```dart
import 'package:grund_http/grund_http.dart';

/// Answers every request, routed or not, with an `x-request-id` header:
/// the caller's own or `req-<n>`.
final class RequestIdMiddleware implements Middleware {
  int _count = 0;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    final id = request.headers['x-request-id'] ?? 'req-${++_count}';
    final response = await next();
    return response.mergeHeaders(HeaderMap.of({'x-request-id': id}));
  }
}
```

- [ ] **Крок 4: API, модулі, корінь (анотована форма)**

Файл `example/lib/src/tasks/tasks_api.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

import '../auth/api_key_hook.dart';
import '../auth/role.dart';
import '../auth/roles_hook.dart';
import 'create_task.dart';
import 'location_hook.dart';
import 'task.dart';
import 'task_not_found_hook.dart';
import 'tasks_service.dart';
import 'update_task.dart';

/// `/tasks`: every route needs an API key; changes need the editor role.
@Api(
  '/tasks',
  use: [HookRef<ApiKeyHook>.type(), HookRef<TaskNotFoundHook>.type()],
)
final class TasksApi {
  /// Serves [service].
  TasksApi(this.service);

  /// The use cases.
  final TasksService service;

  /// `GET /tasks`, optionally `?done=true` or `?done=false`.
  @Get('/')
  List<Task> list({@Query() bool? done}) => service.list(done: done);

  /// `GET /tasks/:id`.
  @Get('/:id')
  Task find(@Path() int id) => service.find(id);

  /// `POST /tasks`: 201 with the new task and its `location`.
  @Post(
    '/',
    status: 201,
    use: [
      HookRef<RolesHook>.instance(RolesHook(Role.editor)),
      HookRef<LocationHook>.instance(LocationHook()),
    ],
  )
  Task create(@Body() CreateTask body) => service.create(body);

  /// `PATCH /tasks/:id`: changes the title or the state.
  @Patch(
    '/:id',
    use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))],
  )
  Task update(@Path() int id, @Body() UpdateTask body) =>
      service.update(id, body);

  /// `DELETE /tasks/:id`: 204.
  @Delete(
    '/:id',
    use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))],
  )
  void remove(@Path() int id) => service.delete(id);
}
```
Файл `example/lib/src/tasks/tasks_module.dart`:

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:tasks_api/tasks_api.grund.dart';

import '../auth/auth_module.dart';
import 'in_memory_task_store.dart';
import 'task_not_found_hook.dart';
import 'task_store.dart';
import 'tasks_api.dart';
import 'tasks_service.dart';

/// Tasks: the store, the service, the API and its error hook.
@Module(
  imports: [AuthModule()],
  providers: [
    Bind<TaskStore, InMemoryTaskStore>(),
    TasksService,
    TaskNotFoundHook,
    TasksApi,
  ],
)
final class TasksModule extends grund.Module with $TasksModule {
  /// Creates the module.
  const TasksModule();
}
```
Файл `example/lib/src/health/health_api.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';

import '../config/app_config.dart';

/// `GET /health`, public: whether the application answers.
@Api('/health')
final class HealthApi {
  /// Reports the name from [config].
  HealthApi(this.config);

  /// The configuration.
  final AppConfig config;

  /// The status and the application name.
  @Get('/')
  Map<String, String> check() => {'status': 'ok', 'name': config.name};
}
```
Файл `example/lib/src/health/health_module.dart`:

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:tasks_api/tasks_api.grund.dart';

import 'health_api.dart';

/// The health check; its `AppConfig` comes from the global `ConfigModule`.
@Module(providers: [HealthApi])
final class HealthModule extends grund.Module with $HealthModule {
  /// Creates the module.
  const HealthModule();
}
```
Файл `example/lib/src/app_module.dart`:

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:tasks_api/tasks_api.grund.dart';

import 'config/config_module.dart';
import 'health/health_module.dart';
import 'tasks/tasks_module.dart';

/// The application: what it does, not how it is served. `ServingModule`
/// adds the HTTP server and the adapter around it.
@Module(imports: [ConfigModule(), TasksModule(), HealthModule()])
final class AppModule extends grund.Module with $AppModule {
  /// Creates the module.
  const AppModule();
}
```

- [ ] **Крок 5: обслуговування, опції, `main`**

Файл `example/lib/src/server/adapter_kind.dart`:

```dart
/// Which adapter `bin/main.dart` serves with.
enum AdapterKind {
  /// `IoAdapter` from `grund_io`.
  io,

  /// `ShelfAdapter` from `grund_shelf`.
  shelf,
}
```
Файл `example/lib/src/server/module_style.dart`:

```dart
/// Which module graph `bin/main.dart` serves.
enum ModuleStyle {
  /// `AppModule`, declared with annotations (its glue is generated).
  annotations,

  /// `ExplicitAppModule`, written by hand with the explicit API.
  explicit,
}
```
Файл `example/lib/src/server/serving_module.dart`:

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_shelf/grund_shelf.dart';

import '../common/request_id_middleware.dart';
import '../common/timing_hook.dart';
import 'adapter_kind.dart';

/// Serves [application] over HTTP: the same wrapper for both module forms
/// and both adapters, so the application itself does not know how it is
/// served.
final class ServingModule extends Module {
  /// Serves [application] with the adapter [kind] on [address] and [port].
  ServingModule(
    this.application,
    this.kind, {
    this.address = 'localhost',
    this.port = 8080,
    this.onError,
  });

  /// The application module, `AppModule` or `ExplicitAppModule`.
  final Module application;

  /// Which adapter serves.
  final AdapterKind kind;

  /// The address to listen on.
  final Object address;

  /// The port to listen on; 0 picks a free one.
  final int port;

  /// Receives failures an adapter cannot turn into a response.
  final ErrorLogger? onError;

  @override
  List<Module> get imports => [
    application,
    switch (kind) {
      AdapterKind.io => IoAdapterModule(onError: onError),
      AdapterKind.shelf => ShelfAdapterModule(onError: onError),
    },
    HttpModule(
      use: const [HookRef<TimingHook>.instance(TimingHook())],
      middleware: [RequestIdMiddleware()],
      config: HttpConfig(address: address, port: port),
    ),
  ];
}
```
Файл `example/lib/src/server/server_options.dart`:

```dart
import 'adapter_kind.dart';
import 'module_style.dart';

/// The command line of `bin/main.dart`: `[--explicit] [--shelf]
/// [--only=<runner>,...]`, and the port from the `PORT` environment
/// variable (8080 by default).
final class ServerOptions {
  /// Creates the options.
  const ServerOptions({
    this.style = ModuleStyle.annotations,
    this.adapter = AdapterKind.io,
    this.port = defaultPort,
  });

  /// Reads [arguments] and [environment]; throws a [FormatException] for
  /// an unknown argument or a `PORT` outside 1 to 65535. `--only=...` is
  /// left to `Runners.fromArgs`.
  factory ServerOptions.parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    final unknown = arguments.where(
      (a) => !_flags.contains(a) && !a.startsWith('--only='),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown argument ${unknown.first}.\n$usage');
    }
    return ServerOptions(
      style: arguments.contains('--explicit')
          ? ModuleStyle.explicit
          : ModuleStyle.annotations,
      adapter: arguments.contains('--shelf')
          ? AdapterKind.shelf
          : AdapterKind.io,
      port: _port(environment['PORT']),
    );
  }

  /// The port without `PORT`.
  static const defaultPort = 8080;

  /// How to call `bin/main.dart`.
  static const usage =
      'Usage: dart run bin/main.dart [--explicit] [--shelf] [--only=http]\n'
      '  --explicit  serve the module graph written with the explicit API\n'
      '  --shelf     serve with ShelfAdapter instead of IoAdapter\n'
      '  --only=...  start only the named runners\n'
      'The port is PORT from the environment, 8080 by default.';

  static const _flags = {'--explicit', '--shelf'};

  /// The module graph to serve.
  final ModuleStyle style;

  /// The adapter to serve with.
  final AdapterKind adapter;

  /// The port to listen on.
  final int port;

  static int _port(String? value) {
    if (value == null) return defaultPort;
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('PORT must be 1 to 65535, not "$value".');
    }
    return port;
  }
}
```
Файл `example/lib/src/server/tasks_app.dart`:

```dart
import 'package:grund/grund.dart';

import '../app_module.dart';
import 'module_style.dart';
import 'serving_module.dart';
import 'server_options.dart';
import '../../explicit.dart';

/// Creates the tasks application the same way for `bin/main.dart` and the
/// tests.
abstract final class TasksApp {
  /// The module graph [style] names.
  static Module graph(ModuleStyle style) => switch (style) {
    ModuleStyle.annotations => const AppModule(),
    ModuleStyle.explicit => const ExplicitAppModule(),
  };

  /// The application for [options], served over HTTP.
  static App create(ServerOptions options) => App(
    root: ServingModule(
      graph(options.style),
      options.adapter,
      port: options.port,
    ),
  );
}
```
Файл `example/lib/tasks_api.dart`:

```dart
/// The tasks API of the grund example: the classes both module graphs
/// share. The graphs themselves are `AppModule` (annotations, with
/// `tasks_api.grund.dart` generated from them) and `ExplicitAppModule`
/// (`explicit.dart`, written by hand with the explicit API).
library;

export 'src/app_module.dart';
export 'src/auth/api_key_hook.dart';
export 'src/auth/auth_module.dart';
export 'src/auth/current_user.dart';
export 'src/auth/role.dart';
export 'src/auth/roles_hook.dart';
export 'src/common/request_id_middleware.dart';
export 'src/common/timing_hook.dart';
export 'src/config/app_config.dart';
export 'src/config/config_module.dart';
export 'src/health/health_api.dart';
export 'src/health/health_module.dart';
export 'src/server/adapter_kind.dart';
export 'src/server/module_style.dart';
export 'src/server/server_options.dart';
export 'src/server/serving_module.dart';
export 'src/server/tasks_app.dart';
export 'src/tasks/create_task.dart';
export 'src/tasks/in_memory_task_store.dart';
export 'src/tasks/location_hook.dart';
export 'src/tasks/task.dart';
export 'src/tasks/task_not_found.dart';
export 'src/tasks/task_not_found_hook.dart';
export 'src/tasks/task_store.dart';
export 'src/tasks/tasks_api.dart';
export 'src/tasks/tasks_module.dart';
export 'src/tasks/tasks_service.dart';
export 'src/tasks/update_task.dart';
```
Файл `example/bin/main.dart`:

```dart
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:tasks_api/tasks_api.dart';

/// Serves the tasks API until Ctrl+C or SIGTERM; see [ServerOptions.usage].
Future<void> main(List<String> arguments) async {
  final ServerOptions options;
  try {
    options = ServerOptions.parse(arguments, Platform.environment);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final app = TasksApp.create(options);
  // Listen for the signals before the port opens, so a signal sent right
  // after the announcement closes gracefully.
  final stopped = StopSignals().wait();
  try {
    await app.start(only: Runners.fromArgs(arguments));
  } on RunnerError catch (error) {
    // A port in use arrives as the SocketException of the http runner.
    stderr.writeln('Cannot start: ${error.message}');
    // The pending signal subscription would keep the process alive.
    exit(1);
  }
  print(
    'Serving the ${options.style.name} module graph with '
    '${options.adapter.name} on http://localhost:${options.port}',
  );
  await stopped;
  await app.close();
}
```

- [ ] **Крок 6: згенерувати glue і закомітити**

`lib/tasks_api.grund.dart` до цього кроку не існує, пакет не збирається (у модулях `with $...`). Згенерувати й дивитися:

```bash
cd example && dart run grund_cli gen
```

Очікувана діагностика на цьому кроці — жодної. Файл `lib/tasks_api.grund.dart` — вивід генератора; нижче форма, яку очікуємо (написана вручну за угода частин плану розділом 3 і ПЕРЕВІРЕНА компіляцією та e2e-набором на прототипі; заголовок і порядок імпортів/декларацій визначає генератор — комітити те, що записав `gen`, а не цей текст; якщо логіка відрізняється семантично, а не форматом — це знахідка для задач 16-17, не правити вручну):

Файл `example/lib/tasks_api.grund.dart`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Written by grund_cli gen; the exact header is the generator's.
// ignore_for_file: type=lint

import 'package:grund/grund.dart' as grund;
import 'package:grund_http/grund_http.dart';
import 'package:tasks_api/src/auth/api_key_hook.dart';
import 'package:tasks_api/src/auth/auth_module.dart';
import 'package:tasks_api/src/config/app_config.dart';
import 'package:tasks_api/src/config/config_module.dart';
import 'package:tasks_api/src/health/health_api.dart';
import 'package:tasks_api/src/health/health_module.dart';
import 'package:tasks_api/src/tasks/create_task.dart';
import 'package:tasks_api/src/tasks/in_memory_task_store.dart';
import 'package:tasks_api/src/tasks/location_hook.dart';
import 'package:tasks_api/src/tasks/task_not_found_hook.dart';
import 'package:tasks_api/src/tasks/task_store.dart';
import 'package:tasks_api/src/tasks/tasks_api.dart';
import 'package:tasks_api/src/tasks/tasks_module.dart';
import 'package:tasks_api/src/tasks/tasks_service.dart';
import 'package:tasks_api/src/tasks/update_task.dart';
import 'package:tasks_api/src/auth/role.dart';
import 'package:tasks_api/src/auth/roles_hook.dart';

mixin $AppModule on grund.Module {
  @override
  List<grund.Module> get imports => [
    ConfigModule(),
    HealthModule(),
    TasksModule(),
  ];
}

mixin $AuthModule on grund.Module {
  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<ApiKeyHook>(
      (i) => ApiKeyHook(i<AppConfig>()),
      dependsOn: const [grund.Key<AppConfig>()],
    ),
  ];

  @override
  List<Object> get exports => const [grund.Key<ApiKeyHook>()];
}

mixin $ConfigModule on grund.Module {
  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<AppConfig>(
      (i) => ConfigModule.appConfig(),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [grund.Key<AppConfig>()];
}

mixin $HealthModule on grund.Module {
  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<HealthApi>(
      (i) => HealthApi(i<AppConfig>()),
      dependsOn: const [grund.Key<AppConfig>()],
    ),
    grund.Singleton<HealthApiRoutes>(
      (i) => HealthApiRoutes(i, i<HealthApi>()),
      dependsOn: const [grund.Key<HealthApi>()],
    ),
  ];
}

mixin $TasksModule on grund.Module {
  @override
  List<grund.Module> get imports => [AuthModule()];

  @override
  List<grund.Binding<Object>> get bindings => [
    grund.Singleton<TaskStore>(
      (i) => InMemoryTaskStore(),
      dependsOn: const [],
    ),
    grund.Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [grund.Key<TaskStore>()],
    ),
    grund.Singleton<TaskNotFoundHook>(
      (i) => TaskNotFoundHook(),
      dependsOn: const [],
    ),
    grund.Singleton<TasksApi>(
      (i) => TasksApi(i<TasksService>()),
      dependsOn: const [grund.Key<TasksService>()],
    ),
    grund.Singleton<TasksApiRoutes>(
      (i) => TasksApiRoutes(i, i<TasksApi>()),
      dependsOn: const [grund.Key<TasksApi>()],
    ),
  ];
}

final class HealthApiRoutes extends HttpApi {
  HealthApiRoutes(super.injector, this._api);

  final HealthApi _api;

  @override
  String get path => '/health';

  @override
  List<Route> get routes => [Route.get('/', (c) => _api.check())];
}

final class TasksApiRoutes extends HttpApi {
  TasksApiRoutes(super.injector, this._api);

  final TasksApi _api;

  @override
  String get path => '/tasks';

  @override
  List<HookRef<HttpHook>> get use => const [
    HookRef<ApiKeyHook>.type(),
    HookRef<TaskNotFoundHook>.type(),
  ];

  @override
  List<Route> get routes => [
    Route.get('/', (c) => _api.list(done: c.query.booleanOrNull('done'))),
    Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _api.create(await c.body(CreateTask.fromJson)),
      status: 201,
      use: [
        HookRef<RolesHook>.instance(RolesHook(Role.editor)),
        HookRef<LocationHook>.instance(LocationHook()),
      ],
    ),
    Route.patch(
      '/:id',
      (c) async =>
          _api.update(c.path.integer('id'), await c.body(UpdateTask.fromJson)),
      use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))],
    ),
    Route.delete('/:id', (c) {
      _api.remove(c.path.integer('id'));
      return null;
    }, use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))]),
  ];
}
```

- [ ] **Крок 7: явна форма**

Той самий застосунок з явним API: модулі-класи, `HttpApi` з маршрутами, без анотацій і без генерації (використовує ті ж `TasksService`, хуки, `TasksApi`/`HealthApi` як класи-обробники):

Файл `example/lib/explicit.dart`:

```dart
/// The same application as `AppModule`, written with the explicit API: no
/// annotations, no generated code. Compare with `tasks_api.grund.dart`,
/// which is what the generator writes for the annotated form.
library;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:tasks_api/tasks_api.dart';

/// [AppConfig] for every module (`global`).
final class ExplicitConfigModule extends Module {
  /// Creates the module.
  const ExplicitConfigModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AppConfig>((_) => AppConfig.demo, dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<AppConfig>()];
}

/// The API key check.
final class ExplicitAuthModule extends Module {
  /// Creates the module.
  const ExplicitAuthModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ApiKeyHook>(
      (i) => ApiKeyHook(i<AppConfig>()),
      dependsOn: const [Key<AppConfig>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<ApiKeyHook>()];
}

/// The routes of [TasksApi] written by hand.
final class ExplicitTasksRoutes extends HttpApi {
  /// Serves [_api] from the module that declares it.
  ExplicitTasksRoutes(super.injector, this._api);

  final TasksApi _api;

  @override
  String get path => '/tasks';

  @override
  List<HookRef<HttpHook>> get use => const [
    HookRef<ApiKeyHook>.type(),
    HookRef<TaskNotFoundHook>.type(),
  ];

  @override
  List<Route> get routes => [
    Route.get('/', (c) => _api.list(done: c.query.booleanOrNull('done'))),
    Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _api.create(await c.body(CreateTask.fromJson)),
      status: 201,
      use: _editorOnly([const HookRef<LocationHook>.instance(LocationHook())]),
    ),
    Route.patch(
      '/:id',
      (c) async =>
          _api.update(c.path.integer('id'), await c.body(UpdateTask.fromJson)),
      use: _editorOnly(),
    ),
    Route.delete('/:id', (c) {
      _api.remove(c.path.integer('id'));
      return null;
    }, use: _editorOnly()),
  ];

  static List<HookRef<HttpHook>> _editorOnly([
    List<HookRef<HttpHook>> more = const [],
  ]) => [const HookRef<RolesHook>.instance(RolesHook(Role.editor)), ...more];
}

/// Tasks: the store, the service, the API and its error hook.
final class ExplicitTasksModule extends Module {
  /// Creates the module.
  const ExplicitTasksModule();

  @override
  List<Module> get imports => const [ExplicitAuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((_) => InMemoryTaskStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
    Singleton<TaskNotFoundHook>(
      (_) => TaskNotFoundHook(),
      dependsOn: const [],
    ),
    Singleton<TasksApi>(
      (i) => TasksApi(i<TasksService>()),
      dependsOn: const [Key<TasksService>()],
    ),
    Singleton<ExplicitTasksRoutes>(
      (i) => ExplicitTasksRoutes(i, i<TasksApi>()),
      dependsOn: const [Key<TasksApi>()],
    ),
  ];
}

/// The health check, with an inline `HttpApi`.
final class ExplicitHealthModule extends Module {
  /// Creates the module.
  const ExplicitHealthModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HealthApi>(
      (i) => HealthApi(i<AppConfig>()),
      dependsOn: const [Key<AppConfig>()],
    ),
    Singleton<_HealthRoutes>(
      (i) => _HealthRoutes(i, i<HealthApi>()),
      dependsOn: const [Key<HealthApi>()],
    ),
  ];
}

final class _HealthRoutes extends HttpApi {
  _HealthRoutes(super.injector, this._api);

  final HealthApi _api;

  @override
  String get path => '/health';

  @override
  List<Route> get routes => [Route.get('/', (c) => _api.check())];
}

/// The application with the explicit API.
final class ExplicitAppModule extends Module {
  /// Creates the module.
  const ExplicitAppModule();

  @override
  List<Module> get imports => const [
    ExplicitConfigModule(),
    ExplicitTasksModule(),
    ExplicitHealthModule(),
  ];
}
```

- [ ] **Крок 8: тести**

Допоміжні файли (`api_response`, `temp_dir`, `workspace_package_config`, `example_sources` не змінюються відносно старого прикладу):

Файл `example/test/helpers/recording_error_log.dart`:

```dart
import 'package:grund_http/grund_http.dart';

/// An [ErrorLog] that keeps what it was given, for a test to assert on.
final class RecordingErrorLog implements ErrorLog {
  /// Records into [errors].
  RecordingErrorLog(this.errors);

  /// The reported errors, in order.
  final List<Object> errors;

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
```
Файл `example/test/helpers/loopback_server.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:tasks_api/tasks_api.dart';

import 'api_response.dart';
import 'recording_error_log.dart';

/// The tasks application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the errors reported on the way.
final class LoopbackServer {
  LoopbackServer._(this.app, this.port, this.errors);

  /// Serves the module graph [style] names with the adapter [kind].
  static Future<LoopbackServer> start(
    ModuleStyle style,
    AdapterKind kind,
  ) async {
    final errors = <Object>[];
    final app = App(
      root: ServingModule(
        TasksApp.graph(style),
        kind,
        address: InternetAddress.loopbackIPv4,
        port: 0,
        onError: (error, _) => errors.add(error),
      ),
      overrides: [
        Singleton<ErrorLog>(
          (_) => RecordingErrorLog(errors),
          dependsOn: const [],
        ),
      ],
    );
    await app.start();
    final port = switch (app.container.root<HttpAdapter>()) {
      IoAdapter(:final port) => port,
      ShelfAdapter(:final port) => port,
      final other => throw StateError('Unexpected adapter $other.'),
    };
    return LoopbackServer._(app, port, errors);
  }

  /// The served application.
  final App app;

  /// The port the adapter bound.
  final int port;

  /// What the application and the adapter reported as unexpected.
  final List<Object> errors;

  final HttpClient _client = HttpClient();

  /// Sends [method] to [target] with [headers] and [json] as the body;
  /// reads the whole response.
  Future<ApiResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    Object? json,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$target'),
    );
    headers.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final first = <String, String>{};
    response.headers.forEach((name, values) => first[name] = values.first);
    return ApiResponse(response.statusCode, first, body);
  }

  /// Closes the client and the application.
  Future<void> close() async {
    _client.close(force: true);
    await app.container.root<HttpAdapter>().close(force: true);
    await app.close();
  }
}
```

E2E (RF-3: тіла помилок — problem+json з `detail`/`code`/`errors[].pointer`; 404 без маршруту теж problem+json; хук часу працює і на помилці):

Файл `example/test/e2e_test.dart`:

```dart
// One suite, four servers: the annotated and the hand-written module graph,
// each served by dart:io and by shelf on a loopback port.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';

const _reader = {'x-api-key': 'reader-key'};
const _editor = {'x-api-key': 'editor-key'};

void main() {
  for (final style in ModuleStyle.values) {
    for (final kind in AdapterKind.values) {
      group('${style.name} on ${kind.name}', () => _suite(style, kind));
    }
  }
}

void _suite(ModuleStyle style, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.
  setUp(() async => server = await LoopbackServer.start(style, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  _public(() => server);
  _reading(() => server);
  _writing(() => server);
}

/// What needs no API key: the health check, the middleware, the hook.
void _public(LoopbackServer Function() server) {
  test('GET /health answers without a key', () async {
    final response = await server().send('GET', '/health');

    expect(response.status, 200);
    expect(response.json, {'status': 'ok', 'name': 'tasks_api'});
  });

  test('middleware adds x-request-id, also to unrouted requests', () async {
    final own = await server().send(
      'GET',
      '/health',
      headers: {'x-request-id': 'abc'},
    );
    final unrouted = await server().send('GET', '/nowhere');

    expect(own.headers['x-request-id'], 'abc');
    expect(unrouted.status, 404);
    expect(unrouted.headers['content-type'], contains('problem+json'));
    expect(unrouted.headers['x-request-id'], startsWith('req-'));
  });

  test('the global hook times routed requests, also failed ones', () async {
    final ok = await server().send('GET', '/health');
    final failed = await server().send('GET', '/tasks');
    final timing = matches(RegExp(r'^handler;dur=\d+\.\d$'));

    expect(ok.headers['server-timing'], timing);
    expect(failed.status, 401);
    expect(failed.headers['server-timing'], timing);
  });
}

/// Reading tasks: the key hook, query and path parameters, the error hook.
void _reading(LoopbackServer Function() server) {
  test('a missing or unknown key is a 401 problem', () async {
    final missing = await server().send('GET', '/tasks');
    final unknown = await server().send(
      'GET',
      '/tasks',
      headers: {'x-api-key': 'nope'},
    );

    expect(missing.status, 401);
    expect(missing.headers['content-type'], contains('problem+json'));
    expect(missing.json, containsPair('detail', 'Send a valid x-api-key.'));
    expect(missing.json, containsPair('code', 'api_key_invalid'));
    expect(unknown.status, 401);
  });

  test('a reader lists tasks, filtered by ?done=', () async {
    final all = await server().send('GET', '/tasks', headers: _reader);
    final done = await server().send(
      'GET',
      '/tasks?done=true',
      headers: _reader,
    );
    final invalid = await server().send(
      'GET',
      '/tasks?done=maybe',
      headers: _reader,
    );

    expect(all.json, hasLength(2));
    expect(done.json, [
      {'id': 2, 'title': 'Run grund dev', 'done': true},
    ]);
    expect(invalid.status, 400);
    expect(invalid.json, containsPair('status', 400));
  });

  test('GET /tasks/:id finds a task; the hook maps a miss to 404', () async {
    final found = await server().send('GET', '/tasks/1', headers: _reader);
    final missing = await server().send('GET', '/tasks/99', headers: _reader);
    final invalid = await server().send('GET', '/tasks/one', headers: _reader);

    expect((found.json as Map)['title'], 'Read the grund README');
    expect(missing.status, 404);
    expect(missing.json, containsPair('detail', 'No task 99.'));
    expect(missing.json, containsPair('code', 'task_not_found'));
    expect(invalid.status, 400);
  });
}

/// Changing tasks: the roles hook, the bodies, the location hook.
void _writing(LoopbackServer Function() server) {
  test('a reader cannot create a task: 403', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _reader,
      json: {'title': 'Nope'},
    );

    expect(response.status, 403);
    expect(response.json, containsPair('code', 'role_required'));
  });

  test('an editor creates a task: 201, location, trimmed title', () async {
    final created = await server().send(
      'POST',
      '/tasks',
      headers: _editor,
      json: {'title': '  Write the docs  '},
    );
    final read = await server().send('GET', '/tasks/3', headers: _reader);

    expect(created.status, 201);
    expect(created.headers['location'], '/tasks/3');
    expect(created.json, {'id': 3, 'title': 'Write the docs', 'done': false});
    expect(read.json, created.json);
  });

  test('a title of blanks is trimmed first, then rejected: 400', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _editor,
      json: {'title': '   '},
    );

    expect(response.status, 400);
    expect(
      response.json,
      containsPair('errors', contains(containsPair('pointer', '/body'))),
    );
  });

  test('PATCH changes the state; a wrong type is 400', () async {
    final changed = await server().send(
      'PATCH',
      '/tasks/1',
      headers: _editor,
      json: {'done': true},
    );
    final invalid = await server().send(
      'PATCH',
      '/tasks/1',
      headers: _editor,
      json: {'done': 'yes'},
    );

    expect(changed.json, {
      'id': 1,
      'title': 'Read the grund README',
      'done': true,
    });
    expect(invalid.status, 400);
  });

  test('DELETE answers 204, then the task is gone', () async {
    final deleted = await server().send('DELETE', '/tasks/2', headers: _editor);
    final again = await server().send('DELETE', '/tasks/2', headers: _editor);

    expect(deleted.status, 204);
    expect(deleted.body, isEmpty);
    expect(again.status, 404);
  });
}
```
Файл `example/test/in_process_test.dart`:

```dart
// Without a socket: TestClient sends requests straight to the HttpServer of
// a TestApp, the fastest way to test routes, hooks and the error hook. The
// adapter module is in the graph but never listens.
import 'package:grund/testing.dart';
import 'package:grund_http/testing.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

void main() {
  late TestApp app; // Set in setUp before every test.
  late TestClient client; // Set together with app.

  setUp(() async {
    app = await TestApp.start(
      root: ServingModule(const AppModule(), AdapterKind.io),
    );
    client = TestClient.of(app);
  });
  tearDown(() => app.close());

  test('an editor creates a task, a reader reads it', () async {
    final created = await client.post(
      '/tasks',
      json: {'title': 'Ship 0.1.0'},
      headers: {'x-api-key': 'editor-key'},
    );
    final read = await client.get(
      '/tasks/3',
      headers: {'x-api-key': 'reader-key'},
    );

    expect(created.status, 201);
    expect(read.json, {'id': 3, 'title': 'Ship 0.1.0', 'done': false});
  });

  test('singletons are shared: a delete is seen by the next request', () async {
    await client.delete('/tasks/1', headers: {'x-api-key': 'editor-key'});
    final list = await client.get(
      '/tasks',
      headers: {'x-api-key': 'reader-key'},
    );

    expect(list.json, [
      {'id': 2, 'title': 'Run grund dev', 'done': true},
    ]);
  });
}
```
Файл `example/test/tasks_service_test.dart`:

```dart
// Unit tests: the service is a plain class, and a test module written with
// the explicit API swaps the store for a fake, even though the application
// itself is wired with annotations.
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

/// A store that is always empty and refuses every change.
final class _EmptyStore implements TaskStore {
  @override
  List<Task> all() => const [];

  @override
  Task? find(int id) => null;

  @override
  Task add(String title) => throw UnsupportedError('read-only');

  @override
  bool replace(Task task) => false;

  @override
  bool remove(int id) => false;
}

/// A test module written with the explicit API.
final class _FakeStoreModule extends Module {
  const _FakeStoreModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((_) => _EmptyStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
  ];
}

void main() {
  test('list filters by state', () {
    final service = TasksService(InMemoryTaskStore());

    expect(service.list(done: false).map((task) => task.id), [1]);
    expect(service.list().map((task) => task.id), [1, 2]);
  });

  test('update changes only the given fields', () {
    final service = TasksService(InMemoryTaskStore());

    final task = service.update(2, const UpdateTask(title: 'Run it again'));

    expect(task.toJson(), {'id': 2, 'title': 'Run it again', 'done': true});
  });

  test('a test module provides a fake store through DI', () async {
    final app = await TestApp.start(root: const _FakeStoreModule());
    addTearDown(app.close);
    final service = app<TasksService>();

    expect(service.list(), isEmpty);
    expect(() => service.find(1), throwsA(isA<TaskNotFound>()));
    expect(() => service.delete(1), throwsA(isA<TaskNotFound>()));
  });
}
```
Файл `example/test/server_options_test.dart`:

```dart
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

void main() {
  test('no arguments: annotations, dart:io, port 8080', () {
    final options = ServerOptions.parse(const [], const {});

    expect(options.style, ModuleStyle.annotations);
    expect(options.adapter, AdapterKind.io);
    expect(options.port, 8080);
  });

  test('--explicit --shelf and PORT', () {
    final options = ServerOptions.parse(
      const ['--shelf', '--explicit'],
      const {'PORT': '9090'},
    );

    expect(options.style, ModuleStyle.explicit);
    expect(options.adapter, AdapterKind.shelf);
    expect(options.port, 9090);
  });

  test('--only=... is left to Runners.fromArgs', () {
    final options = ServerOptions.parse(const ['--only=http'], const {});

    expect(options.port, 8080);
  });

  test('an unknown argument is a FormatException with the usage', () {
    expect(
      () => ServerOptions.parse(const ['--port=1'], const {}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('--port=1'), contains(ServerOptions.usage)),
        ),
      ),
    );
  });

  test('a PORT outside 1 to 65535 is a FormatException', () {
    for (final port in ['0', '65536', 'http']) {
      expect(
        () => ServerOptions.parse(const [], {'PORT': port}),
        throwsFormatException,
        reason: port,
      );
    }
  });
}
```

`test/main_process_test.dart` і `test/generated_library_test.dart` не змінюються відносно старого прикладу (перший перевіряє «порт зайнятий: один рядок у stderr, код 1» і «SIGTERM: код 0»; другий генерує бібліотеку в `TempDir` з поточних джерел і порівнює з закоміченим `lib/tasks_api.grund.dart`).

- [ ] **Крок 9: README прикладу**

Файл `example/README.md`:

```markdown
# tasks_api — the grund example

A small tasks API that uses every part of grund: modules with imports,
exports and a global module, a `@Provides` method, an interface bound to an
implementation (`Bind`), `HttpApi` classes with typed path, query and body
readers, `HttpHook`s (by type and by instance, per route, per API and
global), a middleware, both adapters and hot reload.

The same application is wired twice:

- with **annotations** (`lib/src/**`), turned by `grund_cli gen` into the
  committed `lib/tasks_api.grund.dart` (the `$Module` mixins and the
  `HttpApi` classes); the root is `AppModule`;
- with the **explicit API** by hand in `lib/explicit.dart`; the root is
  `ExplicitAppModule`, and it reuses the same services, hooks and handler
  classes.

`ServingModule` wraps either root with `HttpModule` and the adapter module
(`IoAdapterModule` or `ShelfAdapterModule`), so the application does not
know how it is served. `test/e2e_test.dart` runs one suite against both
graphs, each served by `dart:io` and by shelf on a loopback port.

## Run it

From the repository root, once: `dart pub get`. Then in `example/`:

```sh
dart run bin/main.dart                      # annotations, dart:io, port 8080
dart run bin/main.dart --explicit --shelf   # the explicit graph on shelf
PORT=9090 dart run bin/main.dart
```

```sh
curl localhost:8080/health
curl -H 'x-api-key: reader-key' localhost:8080/tasks
curl -H 'x-api-key: reader-key' 'localhost:8080/tasks?done=true'
curl -X POST -H 'x-api-key: editor-key' -H 'content-type: application/json' \
  -d '{"title": "  Write the docs  "}' localhost:8080/tasks
curl -X PATCH -H 'x-api-key: editor-key' -H 'content-type: application/json' \
  -d '{"done": true}' localhost:8080/tasks/3
curl -X DELETE -H 'x-api-key: editor-key' localhost:8080/tasks/3
```

Errors are `application/problem+json` (RFC 9457): a `status`, a `detail`, a
stable `code` and, for a bad body, `errors` with a JSON `pointer`.

| Request | Answer |
| --- | --- |
| `GET /health` | `{"status": "ok", "name": "tasks_api"}`, no key needed |
| `/tasks` without `x-api-key`, or an unknown key | 401, `code: api_key_invalid` |
| `GET /tasks`, `GET /tasks/:id` with `reader-key` or `editor-key` | the tasks; `?done=maybe` or `/tasks/one` is 400, an unknown id 404 (`task_not_found`) |
| `POST`, `PATCH`, `DELETE` with `reader-key` | 403, `code: role_required` |
| `POST /tasks` with `editor-key` | 201, `location: /tasks/3`, the title trimmed |
| every response | `x-request-id` (middleware); routed ones also `server-timing` (global hook) |

## Where each feature is

| Feature | File |
| --- | --- |
| Global module, `@Provides` | `lib/src/config/config_module.dart` |
| Module with imports and exports | `lib/src/tasks/tasks_module.dart`, `lib/src/auth/auth_module.dart` |
| Interface bound to an implementation (`Bind`) | `lib/src/tasks/tasks_module.dart` (`TaskStore` to `InMemoryTaskStore`) |
| `@Api`, routes, `@Path`/`@Query`/`@Body` | `lib/src/tasks/tasks_api.dart`, `create_task.dart`, `update_task.dart` |
| Hook by type (resolved from DI) | `lib/src/auth/api_key_hook.dart` (`HookRef<ApiKeyHook>.type()`) |
| Hook by instance, per route | `lib/src/auth/roles_hook.dart`, `lib/src/tasks/location_hook.dart` |
| Hook that turns a domain error into a problem | `lib/src/tasks/task_not_found_hook.dart` |
| Global hook and middleware | `lib/src/common/timing_hook.dart`, `request_id_middleware.dart`, `lib/src/server/serving_module.dart` |
| Adapter choice | `lib/src/server/serving_module.dart`, `bin/main.dart` |
| The generated glue | `lib/tasks_api.grund.dart` |
| The explicit-API twin | `lib/explicit.dart` |

## Change the annotations

After editing an annotated class, regenerate and commit the library:

```sh
dart run grund_cli gen
```

`test/generated_library_test.dart` fails while the committed file is out
of date.

## Hot reload

```sh
dart run grund_cli dev                   # or: dart run grund_cli dev -- --shelf
```

`dev` generates, starts `bin/main.dart` and watches `lib/` and `bin/`:

- Change the body of `HealthApi.check` and save: the next `GET /health`
  answers with the new code, the process id stays and the tasks you created
  are still there (`Reloaded 7 libraries in 82 ms, 0 added, 0 removed.`;
  the timing and the library count vary).
- Add a route (`@Get('/live')` on `HealthApi`): the library is regenerated
  and reloaded (`1 added, 0 removed` and the line `+ GET /health/live`).
- Add a field to a class: `dev` restarts the process instead (`Restarting
  bin/main.dart: ... changed a field, a constructor or a top-level
  variable.`) and the in-memory tasks start over.

Press `r` to reload and `R` to restart by hand; Ctrl+C stops.

## Tests

```sh
dart test
```

- `test/e2e_test.dart`: both graphs on both adapters, over loopback.
- `test/in_process_test.dart`: `TestApp` and `TestClient`, no socket.
- `test/tasks_service_test.dart`: the service alone, and a test module
  with a fake store.
- `test/server_options_test.dart`, `test/main_process_test.dart`: the
  command line, a port in use (exit 1) and SIGTERM (exit 0).
- `test/generated_library_test.dart`: the committed generated library is
  what `grund_cli gen` writes.
```

- [ ] **Крок 10: перевірка**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
dart pub get && cd example && dart analyze && dart test
wc -l lib/*.dart lib/src/*/*.dart bin/main.dart test/*.dart test/helpers/*.dart | sort -n | tail -5
cd .. && dart format packages example
```

Очікування: `No issues found!`; тести зелені: e2e 4 x 11 = 44, in_process 2, tasks_service 3, server_options 5, main_process 2, generated_library 1 (на прототипі без `generated_library_test`: 56 зелених); жоден файл `lib/` > 300 (найбільший `explicit.dart` ~158, `tasks_api.grund.dart` ~153); `dart format` — 0 змін. Коміт: `feat(example): tasks_api on the new API, annotations and explicit form`.

**Review Focus цієї задачі:** RF-1 (хуки: `ApiKeyHook` -> `RolesHook` -> handler; `onError` у зворотному порядку: `TaskNotFoundHook` дає 404 `task_not_found`, `TimingHook.onError` лишає відповідь і ставить `server-timing`), RF-3 (400 `body_invalid` з `pointer`, 400 для `?done=maybe` і `/tasks/one`, 404 problem+json), RF-5 (`SIGTERM` -> `close` -> код 0, у `main_process_test`).


### Задача 21: Документація, CLAUDE.md, CHANGELOG-и, ROADMAP, фінальна перевірка

**Мета:** уся користувацька документація, CLAUDE.md і CHANGELOG-и описують нову модель (`App`, `Module`, `Injector`, `grund_http`, `HttpApi`/`HttpHook`, `$Module`, `as grund`); ROADMAP позначає G1 зробленим; фінальна перевірка G1 за критеріями spec розділу 1 пройдена.

**Передумови:** задачі 1-20 зелені. Документи англійською (CLAUDE.md: «new user-facing documentation is English»); проза цього плану — українською.

**Files:**
- Modify: `README.md`, `packages/grund/README.md`, `packages/grund_io/README.md`, `packages/grund_shelf/README.md`, `packages/grund_annotations/README.md`, `packages/grund_generator/README.md`, `CLAUDE.md`, `docs/{getting-started,modules-and-di,annotations-and-codegen,adapters,dev-mode,testing,faq,build-runner,RELEASING}.md`, `docs/superpowers/ROADMAP.md`, `packages/*/CHANGELOG.md`
- Create: `packages/grund_http/README.md`, `packages/grund_http/CHANGELOG.md` (якщо ще немає з задачі 1), `docs/http-and-hooks.md`
- Move+Delete: `docs/controllers-and-pipeline.md` -> `docs/http-and-hooks.md` (`git mv`, далі повний новий текст)

- [ ] **Крок 1: `packages/grund/README.md` (ядро без HTTP) — повний новий текст**

````markdown
# grund

The core of grund: modules, typed dependency injection, a call scope, the
runners that start and stop an application, and the hooks for hot reload.
It depends only on the Dart SDK and `package:meta`: no HTTP, no `dart:io`
server. HTTP lives in [`grund_http`](../grund_http), the servers in
[`grund_io`](../grund_io) and [`grund_shelf`](../grund_shelf).

```yaml
dependencies:
  grund: ^0.1.0
```

## A module

A module is a value (a `const` object). It lists what it imports, the
bindings it provides, and what it exports:

```dart
import 'package:grund/grund.dart';

final class TasksModule extends Module {
  const TasksModule();

  @override
  List<Module> get imports => const [AuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((i) => InMemoryTaskStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<TasksService>()];
}
```

- `Singleton<T>`, `Scoped<T>` (one per call) and `Transient<T>` take the
  type argument explicitly (`T == Object` is an `ArgumentError`) and the
  `Key`s they read in `dependsOn`, so the graph can be checked before any
  factory runs. `Singleton<T>.factory(...)` is the escape hatch with
  unknown dependencies.
- A binding is identified by `Key<T>([name])`. A module sees its own
  bindings, the exports of the modules it imports (a re-exported module's
  exports included) and the exports of `global` modules.
- `qualifier` tells two instances of the same module class apart;
  `onInit(Injector)` and `onShutdown(Injector)` run once, after the module's
  singletons exist and before they are disposed.
- A singleton may implement `Disposable`; `dispose()` runs on `App.close`.

## An application

```dart
final app = App(root: const AppModule());
await app.start();            // validates the graph, creates singletons, starts the runners
// ...
await app.close();            // stops the runners (reverse order), disposes
```

`App.run()` starts, waits for SIGINT/SIGTERM and closes. `start(only:)` /
`run(only:)` select runners by name (`Runners.fromArgs(args)` reads
`--only=a,b`; `--only=` starts none: the graph is built and the runners are
prepared only). `overrides:` replace bindings by exact `Key`, which is how
tests and the command line change configuration.

Everything that can be checked is checked **before** the first factory runs
and reported as a typed `GrundError` with a stable message: a missing or
ambiguous binding, a cycle, a singleton that depends on a `Scoped` binding
(`CaptiveDependencyError`), an export that does not exist, a binding that a
module cannot see. A factory or hook of yours that throws is wrapped
(`ProviderCreationError`, `ModuleLifecycleError`, `RunnerError`) with the
cause and its stack trace; a failed start leaves nothing running.

A `Runner` is anything the application starts and stops (the HTTP server of
`grund_http` is one): `prepare(Injector)`, `start(Injector)`, `stop()`,
`reassemble(Injector)`. Runners are the bindings of type `Runner` in the
graph, started in graph order and stopped in reverse.

## The call scope

`Injector.openCall()` opens a `CallScope`: `Scoped` bindings are created
once per call and disposed when the scope closes; `set<T>(value)` puts a
value into the scope (a hook stores the current user this way). A
`CallContext` wraps a scope and a `CancelSignal`; `grund_http` builds its
`HttpCtx` on it.

## Testing

```dart
import 'package:grund/testing.dart';

final app = await TestApp.start(root: const TasksModule());
final service = app<TasksService>();
// ...
await app.close();
```

`TestApp.start(root:, overrides:)` starts an application with `only: const {}`
(runners prepared, none started) and reads any binding of the root.

## Hot reload

`App` registers the VM service extensions `ext.grund.reassemble` and
`ext.grund.close` (outside product mode). A reassemble rebuilds the module
graph from the root, keeps the singletons whose module (identity) and key
are unchanged, applies the new graph to the runners, and answers
`{"applications": n, "added": [...], "removed": [...]}`; when anything
fails, the previous state keeps serving and the error is reported.
`grund_cli dev` calls it after every reload.
````

- [ ] **Крок 2: `packages/grund_http/README.md` (новий) — повний текст**

````markdown
# grund_http

HTTP for grund: request and response values, routing, hooks, RFC 9457
errors, the server runner and a `TestClient`. It depends on
[`grund`](../grund) only; a server is a separate package
([`grund_io`](../grund_io), [`grund_shelf`](../grund_shelf)).

```yaml
dependencies:
  grund: ^0.1.0
  grund_http: ^0.1.0
  grund_io: ^0.1.0      # or grund_shelf
```

## Putting it together

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(config: HttpConfig(port: 8080)),
    IoAdapterModule(),
    TasksModule(),
  ];
}

Future<void> main(List<String> arguments) =>
    App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
```

`HttpModule` binds the `HttpServer` (a `Runner` named `http`), the
`HttpConfig` and the `ErrorLog` and exports them. The server needs an
`HttpAdapter` in the graph: the global module of an adapter package
provides it. Without one, `App.start` fails with a `MissingProviderError`.
`HttpModule` takes `use` (global hooks), `middleware`, `codecs`
(`ResponseCodec<T>`, to serialize types without `toJson()`) and `config`
(`address`, `port`, `maxBodyBytes`, `debug`).

## APIs and routes

```dart
final class UsersApi extends HttpApi {
  UsersApi(super.injector, this._users);
  final UserStore _users;

  @override String get path => '/users';
  @override List<HookRef<HttpHook>> get use => const [HookRef<ApiKeyHook>.type()];

  @override
  List<Route> get routes => [
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _users.add(await c.body(NewUser.fromJson)),
      status: 201,
    ),
  ];
}
```

Bind it in a module (`Singleton<UsersApi>((i) => UsersApi(i, i<UserStore>()),
dependsOn: const [Key<UserStore>()])`); the server collects every `HttpApi`
of the graph. `routes` returns a new list each time (hot reload calls it
again). A handler returns a value: `null` is 204, `Stream`/bytes/text are
sent as they are, anything else is JSON (`toJson()` or a registered
`ResponseCodec`). Two routes with the same method and shape are a
`DuplicateRouteError` at start, before the port is opened.

## Reading the request

`HttpCtx` (the `c` of a handler or a hook): `c.path`, `c.query`,
`c.headers`, `c.cookies` are `Params` readers (`string`, `integer`,
`decimal`, `boolean`, `dateTime`, `uri`, `enumOf`, with `...OrNull`
variants and `min`/`max`/`pattern`/`oneOf` checks; `all(name)` for repeated
values). A missing or invalid value is a 400 problem with a `code`
(`parameter_missing`, `parameter_invalid`, `parameter_out_of_range`) and a
JSON `pointer` (`/query/page_size`). `await c.body(fromJson)` decodes a JSON
object (`bodyList` an array, `bytes()` the raw body); not JSON, not an
object, or a `fromJson` that throws `FormatException`/`TypeError` is a 400
`body_invalid` with the pointer `/body`, a body above `maxBodyBytes` a 413.
`c.response.status` and `c.response.headers` change the response;
`c.set<T>(value)` / `c<T>()` pass values between hooks and the handler
(the call scope).

## Hooks and middleware

An `HttpHook` has three optional methods: `before(c)`, `after(c, result)`
and `onError(c, error, stack)`. Hooks are listed per route (`use:`), per
API (`HttpApi.use`) and globally (`HttpModule(use:)`), outermost first;
`before` runs outside in, `after` and `onError` inside out. A hook throws to
stop the request: nothing after it runs (not even `after`), and the `onError`
of the hooks before it sees the error; the first `onError` that returns a
response answers, an exception thrown from `onError` replaces the error for
the rest. `HookRef<T>.type()` resolves the hook from DI in the module of the
API (so it can have dependencies), `HookRef<T>.instance(hook)` is a `const`
value. A `Middleware` wraps the whole request, also an unrouted one (a 404):
`handle(request, next)`.

## Errors

Every failure is a response with `Content-Type: application/problem+json`
([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)): `type`, `title`,
`status`, `detail`, `instance`, plus `code`, `errors[{detail, pointer,
code}]` and the extensions you add. Throw `HttpException(status, message:,
code:, pointer:, details:, headers:)` or one of
`BadRequestException`, `UnauthorizedException`, `ForbiddenException`,
`NotFoundException`, `MethodNotAllowedException` (the response has `Allow`),
`PayloadTooLargeException`, `UnprocessableContentException`,
`ServiceUnavailableException`. Anything else is a 500 with the detail
"Internal server error" (with `debug: true`, the error and a stack), and is
reported to the bound `ErrorLog` (`PrintErrorLog` writes to stderr; override
`Key<ErrorLog>` to send it elsewhere). `ProblemResponder` is the same
translation as a class, for a hook that builds a response itself.

## Testing

```dart
import 'package:grund/testing.dart';
import 'package:grund_http/testing.dart';

final app = await TestApp.start(
  root: ServingModule(const AppModule(), AdapterKind.io), // any root that has an adapter module
);
final client = TestClient.of(app);
final response = await client.get('/users/1', headers: {'x-api-key': 'k'});
expect(response.status, 200);
```

`TestClient` sends requests straight to `HttpServer.handle`: no socket, the
same hooks, middleware, serialization and problem bodies.

## Writing an adapter

`import 'package:grund_http/adapter.dart'`: implement `HttpAdapter`
(`listen(handler, address:, port:)`, `close({force})`), use
`AdapterLifecycle` and `InFlightRequests`, bind it in a global module that
exports `Key<HttpAdapter>()`, and run `grund_conformance` against it.
````

- [ ] **Крок 3: `docs/http-and-hooks.md` (заміна `controllers-and-pipeline.md`)**

```bash
git mv docs/controllers-and-pipeline.md docs/http-and-hooks.md
grep -rln "controllers-and-pipeline" README.md docs packages | xargs sed -i 's#controllers-and-pipeline\.md#http-and-hooks.md#g'
```

Повний текст нового `docs/http-and-hooks.md`:

````markdown
# HTTP: APIs, hooks and errors

The HTTP layer is the package `grund_http`; the core `grund` knows nothing
about it. This page walks one request through it. The API reference is the
[`grund_http` README](../packages/grund_http/README.md).

## APIs and routes

An `HttpApi` is a class with a path prefix and a list of routes. A route is
a method, a path with `:parameters`, and a handler that gets an `HttpCtx`:

```dart
final class TasksApi extends HttpApi {
  TasksApi(super.injector, this._service);
  final TasksService _service;

  @override String get path => '/tasks';

  @override
  List<Route> get routes => [
    Route.get('/', (c) => _service.list(done: c.query.booleanOrNull('done'))),
    Route.get('/:id', (c) => _service.find(c.path.integer('id'))),
    Route.post('/', (c) async => _service.create(await c.body(CreateTask.fromJson)),
        status: 201),
  ];
}
```

The handler returns a value; `null` becomes 204, text, bytes and streams
are sent as they are, everything else is JSON. Reading a parameter is
validating it: `c.path.integer('id')` on `/tasks/one` is a 400 problem with
`code: parameter_invalid` and `pointer: /path/id`, never a 500.

## The request, step by step

1. **Middleware** (`HttpModule(middleware: [...])`) wraps everything below,
   also requests that match no route.
2. **Routing**: an unknown path is a 404 problem, a known path with another
   method a 405 with `Allow`.
3. **Hooks**, outermost first: global (`HttpModule(use:)`), the API's
   (`HttpApi.use`), the route's (`Route(use:)`). Every `before(c)` runs in
   that order.
4. **The handler.**
5. Every `after(c, result)` runs in reverse order.
6. The result is serialized.

If something throws in 3-5, nothing after the failing step runs, and the
`onError(c, error, stack)` of the hooks that are outside of it are offered
the error, innermost first. The first one that returns an `HttpResponse`
answers; if one throws, the thrown error replaces the original for the
rest. When none answers, an `HttpException` becomes its own status and
anything else a 500 (see [Errors](#errors)).

## Hooks

```dart
@Injectable()
final class ApiKeyHook extends HttpHook {
  ApiKeyHook(this.config);
  final AppConfig config;

  @override
  void before(HttpCtx c) {
    final role = config.apiKeys[c.headers.stringOrNull('x-api-key')];
    if (role == null) {
      throw const UnauthorizedException(
        message: 'Send a valid x-api-key.', code: 'api_key_invalid');
    }
    c.set<CurrentUser>(CurrentUser(role));       // visible to later hooks and the handler
  }
}

final class RolesHook extends HttpHook {
  const RolesHook(this.role);
  final Role role;

  @override
  void before(HttpCtx c) {
    if (c<CurrentUser>().role != role) {
      throw ForbiddenException(message: 'Needs the ${role.name} role.', code: 'role_required');
    }
  }
}
```

Reference a hook with `HookRef<ApiKeyHook>.type()` (created by DI in the
module that declares the API, so it can have dependencies) or
`HookRef<RolesHook>.instance(RolesHook(Role.editor))` (a const value):
`Route.post('/', ..., use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))])`.
A hook that turns a domain error into a response uses `onError`:

```dart
@Injectable()
final class TaskNotFoundHook extends HttpHook {
  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is! TaskNotFound) return null;
    throw NotFoundException(message: 'No task ${error.id}.', code: 'task_not_found');
  }
}
```

`after` only runs when the handler succeeded; a hook that must stamp every
response (timing, request ids) implements `after` and `onError` and changes
`c.response.headers` — headers set so far are kept on an error response.

## Errors

All errors are `application/problem+json` ([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)):

```json
{
  "type": "about:blank",
  "title": "Bad Request",
  "status": 400,
  "detail": "Invalid request body: \"title\" must be a string of 1 to 200 characters",
  "instance": "/tasks",
  "code": "body_invalid",
  "errors": [{"detail": "...", "pointer": "/body", "code": "body_invalid"}]
}
```

`code` is stable and meant for programs; `detail` is for people. Throw an
`HttpException` (or `BadRequestException`, `NotFoundException`, ...) with a
`code`; an unexpected error is a 500 whose body hides the internals and
which is reported to the `ErrorLog` (stderr by default; override
`Key<ErrorLog>`). `HttpConfig(debug: true)` adds the error and its stack to
a 500 for development.

## The same with annotations

```dart
@Api('/tasks', use: [HookRef<ApiKeyHook>.type(), HookRef<TaskNotFoundHook>.type()])
final class TasksApi {
  TasksApi(this.service);
  final TasksService service;

  @Get('/')
  List<Task> list({@Query() bool? done}) => service.list(done: done);

  @Get('/:id')
  Task find(@Path() int id) => service.find(id);

  @Post('/', status: 201, use: [HookRef<RolesHook>.instance(RolesHook(Role.editor))])
  Task create(@Body() CreateTask body) => service.create(body);
}
```

`grund gen` writes the `HttpApi` subclass with exactly the routes above
(`c.path.integer('id')`, `c.query.booleanOrNull('done')`,
`await c.body(CreateTask.fromJson)`); see
[annotations-and-codegen.md](annotations-and-codegen.md). `@Query` and
`@Path` take the parameter name from the Dart name (`@Query(name: 'page_size')
int pageSize`); `@Range`, `@Length`, `@Pattern` and `@OneOf` add the checks
of the `Params` readers.
````

- [ ] **Крок 4: `docs/modules-and-di.md` — повний новий текст**

````markdown
# Modules and dependency injection

A module is a `const` value that says what it imports, what it provides and
what it exports. The graph of modules is validated before any provider is
created.

## Bindings

```dart
final class TasksModule extends Module {
  const TasksModule();

  @override
  List<Module> get imports => const [AuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((i) => InMemoryTaskStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
    Scoped<RequestLog>((i) => RequestLog(), dependsOn: const []),
    Transient<IdGenerator>((i) => IdGenerator(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<TasksService>()];
}
```

- **Lifetime**: `Singleton` (one per application), `Scoped` (one per call,
  disposed when the call ends), `Transient` (one per resolution).
- **Type argument**: always explicit and never `Object`; it is the type the
  binding is found by. A named binding is `Singleton<Db>(..., name: 'read')`
  and `i<Db>('read')`.
- **`dependsOn`** lists the `Key`s the factory reads. The validator checks
  them without running anything. `Singleton<T>.factory(...)` skips the list
  (the dependencies are then not checked ahead; use it only when you must).
- Resolve with `i<T>()`, `i.maybe<T>()` (null when absent) or
  `i.all<T>()` (every binding of that type, visibility ignored; this is how
  the HTTP server finds every `HttpApi`).
- `Disposable.dispose()` of a singleton runs at `App.close`; async factories
  are allowed (`FutureOr<T>`).

## Visibility

A module sees its own bindings, the exports of the modules it imports, and
the exports of `global` modules (`@override bool get global => true`). An
export is a `Key<T>()` or an imported `Module` (re-export). A binding no one
exports is private. Two instances of the same module class with different
configuration are told apart by `qualifier`.

## Dynamic modules

A module with parameters is a class with a `const` constructor (or a
function that returns one); the parameters are fields:

```dart
final class DatabaseModule extends Module {
  const DatabaseModule({required this.url});
  final String url;

  @override List<Binding<Object>> get bindings => [
    Singleton<Database>((i) => Database.connect(url), dependsOn: const []),
  ];
  @override List<Object> get exports => const [Key<Database>()];
  @override FutureOr<void> onShutdown(Injector i) => i<Database>().close();
}
```

## Errors

Everything checkable is checked in `App.start`, before a factory runs, and
is a `GrundError` with the module path: `MissingProviderError` (with the
visibility reason and a hint), a cycle, a `CaptiveDependencyError` (a
singleton that depends on a `Scoped` binding), a duplicate binding, an
export that is not provided, an override of a key that does not exist.
A factory that throws becomes a `ProviderCreationError` (cause and stack
included); a failing `onInit` a `ModuleLifecycleError`. A failed start
disposes what it created and starts nothing.

## Overrides

`App(root: ..., overrides: [Singleton<Clock>((_) => FakeClock(), dependsOn: const [])])`
replaces the binding with the same `Key` wherever it is. The override must
name the exact type argument. Tests use this to swap a store or the
`ErrorLog`.

## The same with annotations

```dart
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';
import 'package:my_app/my_app.grund.dart';

@Module(
  imports: [AuthModule()],
  providers: [TasksService, Bind<TaskStore, InMemoryTaskStore>(), TasksApi],
  exports: [TasksService],
)
final class TasksModule extends grund.Module with $TasksModule {
  const TasksModule();

  @Provides()
  static TasksConfig config(AppConfig app) => TasksConfig(pageSize: app.pageSize);
}
```

The core is imported `as grund` because `Module` is also the annotation.
`@Injectable()` classes become `Singleton`s whose constructor parameters are
resolved by type (`@Injectable(scope: Scope.call)` is `Scoped`, `Scope.transient`
`Transient`); `@Named('read')` on a parameter selects a named binding;
`Bind<I, C>()` binds an interface to an implementation. The generator writes
`mixin $TasksModule on grund.Module` with `imports`, `bindings` and
`exports` — the same API as above, so annotated and hand-written modules mix
in one graph.
````

- [ ] **Крок 5: кореневий `README.md`**

Замінити розділи «Quick start» (обидва підрозділи) і таблицю «Packages»; решту (Requirements, Development, License) лишити.

````markdown
## Quick start

### With annotations

```sh
dart pub global activate grund_cli
grund init my_app
cd my_app
dart pub get
grund gen          # writes lib/my_app.grund.dart
grund dev          # runs bin/main.dart and hot reloads it
curl 'http://localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
```

`init` writes this API (`lib/src/hello.dart`) and the root module
(`lib/src/app_module.dart`):

```dart
@Api('/hello')
final class HelloApi {
  HelloApi(this.service);
  final HelloService service;

  @Get('/')
  Map<String, String> hello(@Query() String? name) =>
      service.greet(name ?? 'world');
}

@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [HelloService, HelloApi],
)
final class AppModule extends grund.Module with $AppModule {
  const AppModule();
}
```

The generator writes `$AppModule` (the module's `bindings`) and the `HttpApi`
that calls `HelloApi`; `bin/main.dart` is one line:
`App(root: const AppModule()).run(only: Runners.fromArgs(args))`. The core is
imported `as grund`, because `Module` is also the annotation.

### Without code generation

```yaml
# pubspec.yaml
dependencies:
  grund: ^0.1.0
  grund_http: ^0.1.0
  grund_io: ^0.1.0
```

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

final class HelloApi extends HttpApi {
  HelloApi(super.injector);

  @override
  String get path => '/hello';

  @override
  List<Route> get routes => [
    Route.get('/', (c) => {'message': 'Hello, ${c.query.stringOrNull('name') ?? 'world'}!'}),
  ];
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [HttpModule(), IoAdapterModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HelloApi>((i) => HelloApi(i), dependsOn: const []),
  ];
}

Future<void> main(List<String> arguments) =>
    App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
```

The two styles mix freely: a generated module can import a hand-written one
and the other way round.

## Packages

| Package | What it is |
| --- | --- |
| [`grund`](packages/grund) | The core: modules, typed DI, call scope, runners, `App`, hot reload hooks, `TestApp`. No HTTP, no `dart:io` server. |
| [`grund_http`](packages/grund_http) | HTTP: `HttpApi`, routes, hooks, middleware, RFC 9457 errors, `HttpModule`, `TestClient`, the adapter contract. |
| [`grund_io`](packages/grund_io) | `IoAdapterModule`: serves an application on a `dart:io` `HttpServer`. |
| [`grund_shelf`](packages/grund_shelf) | `ShelfAdapterModule`, and `shelfHandler(app)` to mount an application in a shelf pipeline. |
| [`grund_annotations`](packages/grund_annotations) | `@Module`, `@Injectable`, `@Api`, `@Get`, ... No dependencies. |
| [`grund_generator`](packages/grund_generator) | Turns the annotations into modules and `HttpApi`s and validates the module graph. A library for the drivers below. |
| [`grund_cli`](packages/grund_cli) | The `grund` command: `gen`, `gen --watch`, `dev` (hot reload), `init`. |
| [`grund_build`](packages/grund_build) | The same generator as a build_runner builder. |
````

Розділ «Coming from NestJS» (таблиця) переписати так:

````markdown
| NestJS | grund (explicit API) | grund (annotations) |
| --- | --- | --- |
| `@Module({imports, providers, exports})` | a `const` class `extends Module` with `imports`/`bindings`/`exports` | `@Module(imports:, providers:, exports:)` on `extends grund.Module with $X` |
| `@Injectable()` provider | `Singleton<T>((i) => T(i<Dep>()), dependsOn: [...])` | `@Injectable()` |
| request scope | `Scoped<T>` | `@Injectable(scope: Scope.call)` |
| `@Controller('/x')` + `@Get()` | `HttpApi` with `Route.get(...)` | `@Api('/x')` + `@Get('/')` |
| `@Param` / `@Query` / `@Body` | `c.path.integer('id')`, `c.query...`, `await c.body(Dto.fromJson)` | `@Path()`, `@Query()`, `@Body()` |
| Guard, Interceptor, Pipe, ExceptionFilter | one `HttpHook` (`before`/`after`/`onError`) | the same, `use: [HookRef<...>]` |
| Middleware | `Middleware` in `HttpModule(middleware:)` | the same |
| `HttpException` | `HttpException` (RFC 9457 problem+json) | the same |
| `Test.createTestingModule` | `TestApp.start(root:, overrides:)` + `TestClient.of` | the same |
````

- [ ] **Крок 6: решта README й docs — точні правки**

Для кожного файлу: знайти старі терміни `grep -n "Controller\|Application\|Provider<\|Provider(\|Token\|Enhancers\|Use<\|Guard\|Interceptor\|Pipe\b\|ExceptionFilter\|appModule\|Container\.create\|app\.listen\|IoAdapter()\|ShelfAdapter()" <файл>` і замінити за таблицею відповідності (як у README вище). Змістовні зміни:

| Файл | Що змінити (новий текст) |
| --- | --- |
| `packages/grund_io/README.md` | Заголовок і приклад: `IoAdapterModule(securityContext:, closeTimeout:, onError:)` у `imports` разом з `HttpModule(config: HttpConfig(port: ...))`; `IoAdapter` лишається публічним (адаптер, `port` після старту: `app.container.root<HttpAdapter>()`). Залежності: `grund`, `grund_http`. Правила: «`App.close` чекає запити, що виконуються, до `closeTimeout`; `adapter.close(force: true)` обриває». |
| `packages/grund_shelf/README.md` | `ShelfAdapterModule(closeTimeout:, onError:)`; `shelfHandler(App app, {onError})`: «застосунок стартує з `only: const {}`, корінь імпортує `HttpModule` і `ShelfAdapterModule` (адаптер лише конструюється й не слухає); до `App.close` обробник відповідає, після — 503; на нестартованому `App` — `ApplicationStateError`». Приклад вбудови в існуючий `shelf.Pipeline`. |
| `packages/grund_annotations/README.md` | Таблиця анотацій з узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17): `Module(imports, providers, exports)`, `Injectable({scope})`, `Provides({scope})`, `Bind<I,C>()`, `Named(name)`, `Scope`, `Api(path, {use})`, `Get/Post/Put/Patch/Delete(path, {status, use})`, `Path/Query/Header/Cookie({name})`, `Body()`, `Range`, `Length`, `Pattern`, `OneOf`. Видалені: `Controller`, `Param`, `Inject`, `Value`, `RouteMetadata`, `UseGuards`... Правило: «`import 'package:grund/grund.dart' as grund;` у файлі з `@Module`». |
| `packages/grund_generator/README.md` | Що генерує (див. `docs/annotations-and-codegen.md`), повний список кодів діагностик (скопіювати з `DiagnosticCode`, задача 15, і з таблиці в Додатку C), детермінізм, `mixin $X on grund.Module`, `XRoutes extends HttpApi`. |
| `docs/getting-started.md` | Дерево `init` (додано `lib/src/app_module.dart`), `bin/main.dart` з одного рядка, `curl`, пояснення `HttpModule + IoAdapterModule`, `--only=`. |
| `docs/annotations-and-codegen.md` | Нова форма виводу (`$X` домішка, `as grund`, `XRoutes`), що таке `@Provides` (статичний метод модуля; `Future<T>` у результаті дозволений лише для singleton, для `Scope.call` — діагностика `invalid_provides`), `Bind`, `Scope`, діагностики з кодами, `grund gen` / `build_runner` дають однакові байти. |
| `docs/adapters.md` | Адаптер — глобальний модуль (`IoAdapterModule`/`ShelfAdapterModule`), експортує `Key<HttpAdapter>()`; вибір адаптера в `imports`; зупинка: `App.close` -> `HttpServer.stop` -> `adapter.close`; «Writing an adapter»: `grund_http/adapter.dart`, глобальний модуль, `grund_conformance` (`AdapterUnderTest.of<A>(module, port:)`). |
| `docs/dev-mode.md` | Формат рядка після reload: `Reloaded 3 libraries in 180 ms, 2 added, 0 removed.` і рядки `+ GET /x`/`- GET /y`; `ext.grund.reassemble` відповідає `{applications, added, removed}`; singleton-и зберігаються за (модуль, `Key`). |
| `docs/testing.md` | `TestApp.start(root:, overrides:)`, `app<T>()`, `TestClient.of(app)` (у корені має бути модуль адаптера, `only: const {}` не слухає порт), підміна `Key<ErrorLog>` для перевірки 500, e2e через `ServingModule`-подібну обгортку (посилання на `example/test/helpers/loopback_server.dart`). |
| `docs/faq.md` | Питання «Where is the controller/guard/pipe?» -> `HttpApi`/`HttpHook`; «Why `as grund`?»; «Why does `HttpServer` need an adapter module?». |
| `docs/build-runner.md`, `docs/RELEASING.md` | У `build-runner.md` приклади анотацій на `@Api`; у `RELEASING.md` — вісім опублікованих пакетів у порядку `grund`, `grund_annotations`, `grund_http`, `grund_generator`, `grund_io`, `grund_shelf`, `grund_cli`, `grund_build` (залежності: `grund_http` перед адаптерами; `grund_conformance` не публікується) та `publish --dry-run` для кожного. |

- [ ] **Крок 7: CHANGELOG-и (версія лишається `0.1.0`: нічого не публікувалось)**

`packages/grund/CHANGELOG.md` (замінює вміст):

```markdown
## 0.1.0

Initial release.

- Modules as `const` values (`imports`, `bindings`, `exports`, `qualifier`,
  `global`, `onInit`, `onShutdown`) and typed bindings (`Singleton`,
  `Scoped`, `Transient`) with explicit type arguments and declared
  dependencies; the module graph is validated before any factory runs
  (missing and ambiguous bindings, cycles, captive dependencies, visibility).
- `App`: `start`/`run`/`close`/`reassemble`, runners selected by name
  (`Runners.fromArgs`), overrides by `Key`, `TestApp` for tests.
- `CallScope`/`CallContext` with per-call `Scoped` bindings and cancellation.
- Hot reload: `App.reassemble` and the `ext.grund.*` VM service extensions
  used by `grund_cli dev`.
- No HTTP: see `grund_http`.
```

`packages/grund_http/CHANGELOG.md`:

```markdown
## 0.1.0

Initial release.

- `HttpApi` and `Route`, `HttpCtx` with validating `Params` readers and
  typed bodies, `HttpHook` (`before`/`after`/`onError`) with `HookRef`,
  `Middleware`.
- Errors as RFC 9457 `application/problem+json` with stable `code` and
  JSON `pointer`; `ErrorLog`.
- `HttpModule`, `HttpServer` (a `Runner`), `HttpConfig`, `TestClient`.
- The adapter contract: `HttpAdapter`, `AdapterLifecycle`,
  `InFlightRequests`, `ErrorLogger`.
```

`packages/grund_io/CHANGELOG.md` і `grund_shelf/CHANGELOG.md`: додати рядок `- IoAdapterModule: a global module that provides the adapter (HttpAdapter).` / `- ShelfAdapterModule: a global module that provides the adapter; shelfHandler(App) now takes an App whose graph contains an adapter module.`. Решта пакетів (текст англійською, під версією, у якій вони вийдуть):
- `grund_annotations`: `- Annotations Api, Get/Post/Put/Patch/Delete, Path/Query/Header/Cookie/Body, Range/Length/Pattern/OneOf, Injectable(scope), Provides(scope), Bind, Named; Module gains global. Removed: Controller, Param, Inject, Value, RouteMetadata and the guard/interceptor/pipe/filter annotations.`
- `grund_generator`: `- Generates mixin $X on grund.Module (imports, bindings, exports, global) and XRoutes extends HttpApi; new diagnostics, e.g. missing_provider and invalid_provides.`
- `grund_cli`: `- gen, init and dev work with the new generator output; dev reports added/removed routes from the ReassembleReport.`
- `grund_build`: `- The builder writes the new generator output; identical bytes to grund gen.`

- [ ] **Крок 8: `CLAUDE.md`**

Правки (текст замінюється повністю там, де показано):

1. «Project» — перший абзац: `grund` — *"NestJS-style modular backend framework for Dart without `dart:mirrors`: explicit typed core (modules, DI, runners, `App`), an HTTP package on top of it (`grund_http`: APIs, hooks, problem+json), optional annotations turned into that same API by a generator, pluggable HTTP adapters."* Spec: додати `docs/superpowers/specs/2026-10-15-grund-core-design.md` (binding, замінює розділи про ядро й HTTP у `...dartnest-design.md`). Додати план `docs/superpowers/plans/2026-10-15-grund-g1-core-http-generator.md`.
2. «Releases»: `The seven published packages` -> `The eight published packages` (додано `grund_http`); `grund_conformance` і `example` не публікуються.
3. «Design rules», пункт про ядро замінити на:

> - **The core has no HTTP, no codegen and no server.** `grund` depends only on the Dart SDK and `package:meta`: no `dart:mirrors`, no `dart:io` server, no shelf, no analyzer. `grund_http` depends only on `grund` (and `meta`). Adapters (`grund_io`, `grund_shelf`) depend on `grund` and `grund_http` (shelf also on `shelf`). Annotations live in their own dependency-free package; `analyzer` is allowed only in `grund_generator`/`grund_cli`/`grund_build`, `vm_service` only in `grund_cli`, and `build` only in `grund_build`. `dart:developer` (SDK) is allowed in the core for the hot reload service extensions, which register only outside product mode.

4. «Design rules», останній пункт (`Annotations share names with the explicit API`) замінити на:

> - **Annotations share names with the explicit API** (`Module`): a library that uses `@Module` imports the core as `import 'package:grund/grund.dart' as grund;` and writes `final class X extends grund.Module with $X`; a module written with the explicit API lives in a file that imports the core without a prefix (and without `grund_annotations`). `$X` comes from the generated `lib/<package>.grund.dart`, which the user's library imports.

5. «Design rules», «The user's HTTP stack is not ours»: без змін по суті, але `Application` -> `App`: `shelfHandler(app)` вбудовується в чужий shelf-конвеєр; `app` стартує з `only: const {}`.
6. «Code rules» -> блок *Tests*: `grund_cli` тести — без змін; додати: «`grund_http` tests use `TestApp` + `TestClient`; adapter tests use `grund_conformance` (`AdapterUnderTest.of`), and an adapter module in the graph is required wherever `HttpServer` is created.»
7. «Code quality rules» -> перелік boundaries `catch`: **повністю замінити** (старі пункти `ModuleInjector`/`Controller.instantiate`, `Pipeline.run`, `RequestDispatcher.dispatch`/`Application.handle`/`HttpErrorResponder`, `ResponseSerializer` v1, `HotReloadExtension.handle` v1 вилучити) таким переліком (прописати в тому ж місці, перед фразою «`rethrow` keeps the stack trace»):

> - factory and lifecycle boundaries in the core: `injection_runtime` (two places: provider factories of a module are wrapped in `ProviderCreationError` with the cause and the original stack trace), `Container.create` (a failing factory or `onInit` disposes what was created, then rethrows), `container_lifecycle` (`onInit` of user modules is wrapped in `ModuleLifecycleError`; a `GrundError` is rethrown as is), `shutdown_steps` (a failing `dispose`/`onShutdown` is collected, the other steps still run, and `ShutdownError` lists them);
> - `App.start` (a graph or factory failure closes the application and rethrows; a failing runner start stops those already started and rethrows), `App._reassemble` (the next state is abandoned, the previous one keeps serving, the error is thrown), `App._close` (swallows the failure of a pending reassemble, which its own caller sees);
> - `RunnerSet.start` (stops what was started, rethrows), `RunnerSet.reassembleInto` (the previous set keeps serving), `RunnerSet._guard` (wraps a runner's failure in `RunnerError`; a `GrundError` is rethrown unchanged);
> - the hot reload boundary: `HotReloadExtension.handle` turns any failure of `reassemble`/`close` (user module functions and factories run there) into a `ServiceExtensionResponse.error` carrying the error (plus the stack trace unless it is a `GrundError`), so `dev` prints it and the application keeps serving;
> - request boundaries in `grund_http`: `HttpServer._answer` (a middleware is user code: its failure becomes a problem response, the adapter never sees a throw), `RouteExecutor.execute` (hooks, the handler and the serializer are user code: the failure becomes a problem response that keeps the headers set so far), `HookChain` (`_recover` hands the failure to the `onError` of the hooks outside of it, innermost first; a failure thrown from an `onError` replaces the error for the rest; if none answers the error is rethrown with its stack trace), `HttpServer.start` (an adapter failure, e.g. a port in use, resets the listening flag and is rethrown unchanged);
> - exact exceptions that are not `on Object`: `RequestBody` catches `FormatException` while decoding the body, and `BodyReader` additionally catches `TypeError` (the `Error` a failed cast in a user's `fromJson` throws for client data); both answer 400 `body_invalid`; `RequestDispatcher._segments` catches `FormatException` of a malformed percent-encoding (the route is not found, 404); `App` (`_close` and its helper) catches `ShutdownError` from the container and reports it after the runners are stopped; `HttpServer._stop` has only `try/finally`, no `catch`; `ResponseSerializer` and `ProblemResponder` catch `JsonUnsupportedObjectError` (an `Error` the JSON encoder throws for a user value) and respectively throw `SerializationError` with the original stack trace / fall back to a body without `details`; `RouteExecutor` catches `ShutdownError` while closing the call scope and reports it to the `ErrorLog` (the response is already decided);
> - adapter boundaries (unchanged from the adapters work): `IoAdapter` reports a failure of the request handler (only possible when the application's own `ErrorLog` throws) to its `onError` and answers 500 without a body, and reports a failure while writing the response to its `onError` and drops the connection itself (`detachSocket` + `destroy`); `ShelfBridge` and `ShelfAdapter` do the same for shelf (plus the failure while discarding the body of a `HEAD` response); the reporter boundaries (`IoAdapter` and `GuardedReporter`) catch a failure of their own `onError` and write it to stderr with its stack trace, so reporting never stops the 500 or the server.

8. «Commands»: рядок `cd packages/grund && dart test     # same for every package` лишити; додати `cd packages/grund_http && dart test` у перелік публікації (порядок: `grund`, `grund_annotations`, `grund_http`, ...).

- [ ] **Крок 9: `docs/superpowers/ROADMAP.md`**

У таблиці етапів рядок G1 доповнити фактом виконання: у колонку «Готово, коли» додати в кінець « — **зроблено** (план `2026-10-15-grund-g1-core-http-generator.md`, гілка `grund-g1`)» і в абзац нагорі (`Етапи 1–7 ...`) дописати «G1 (ядро `App`/`Module`, `grund_http`, генератор `$Module`) зроблено». Не змінювати G2 і далі.

- [ ] **Крок 10: фінальна перевірка G1**

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"
dart pub get
dart analyze                                   # No issues found!
for p in grund grund_annotations grund_http grund_generator grund_io grund_shelf grund_conformance grund_cli grund_build; do
  (cd packages/$p && echo "== $p" && dart test 2>&1 | tail -2)
done
(cd example && dart test 2>&1 | tail -2)
dart format packages example                   # a second run must change 0 files
for p in grund grund_annotations grund_http grund_generator grund_io grund_shelf grund_cli grund_build; do
  (cd packages/$p && dart pub publish --dry-run 2>&1 | tail -3)   # "0 warnings"
done
```

Очікування: кожен пакет зелений; кількості тестів порівняти з тими, що записані на початку G1 (v1.0: до змін); публікаційний dry-run — `0 warnings` для кожного опублікованого пакета (`grund_conformance` і `example` не публікуються — `publish_to: none`).

Критерії spec розділу 1 (виконати й відмітити):
- [ ] `tasks_api` у двох формах: `ls example/lib/explicit.dart example/lib/tasks_api.grund.dart`; `cd example && dart test test/e2e_test.dart` — 44 зелених (2 форми x 2 адаптери x 11).
- [ ] «HTTP відсутній у залежностях `grund`»: `grep -nE "grund_http|shelf|dart:io" packages/grund/pubspec.yaml` порожньо; `grep -rn "dart:io" packages/grund/lib` порожньо (виняток: `stop_signals.dart`, SDK-залежність `ProcessSignal`; у CLAUDE.md це «SDK only, no server»); `dart pub deps -s list` у `packages/grund` не містить `shelf`.
- [ ] Golden-фікстура на новій моделі: `cd packages/grund_generator && dart test test/golden`.
- [ ] Залишки старого API:

```bash
grep -rnE "dartnest|\bController\b|\bGuard\b|Interceptor|ExceptionFilter|\bApplication\b|Enhancers|RouteMetadata|UseGuards" \
  README.md CLAUDE.md docs packages example --include=*.dart --include=*.md --include=*.yaml \
  | grep -v "docs/superpowers/\|CHANGELOG\|StreamController\|\.dart_tool"
```

Очікування: порожньо або лише допустимі збіги — `StreamController` (відфільтровано), слово «Controller» у таблиці «Coming from NestJS» (ліва колонка), «Guard/Interceptor/ExceptionFilter/Pipe» там само і в `faq.md` («Where is the guard?»). Кожен інший збіг виправити.

- [ ] **Крок 11: коміти**

`docs: http-and-hooks replaces controllers-and-pipeline`, `docs: READMEs and guides for the new core`, `docs: CLAUDE.md for grund_http and the new boundaries`, `docs: changelogs and roadmap for G1`.

**Review Focus цієї задачі:** немає нових RF; документація описує RF-1 (порядок хуків), RF-3 (problem+json) і RF-4 (`--only`, `MissingProviderError` без адаптера) в `grund_http` README і `modules-and-di.md`.

---

---

# Додатки: зведення частин

Залишки, залишені авторами частин: стан дерева, відхилення від контракту, непроведена перевірка. Виконавець читає їх разом із відповідною задачею.


## Додаток A

### Стан дерева після кожної задачі

Зняте фактично в `repo_a` на комітах кожної задачі (`analyze` / `test`).

| Після задачі | `grund` | `grund_http` | `grund_annotations` | Решта (`grund_io`, `grund_shelf`, `grund_conformance`, `grund_generator`, `grund_cli`, `grund_build`, `example`) |
|---|---|---|---|---|
| 1 | чисто, 80 (старий DI) | чисто, 69 | чисто, 6 | червоні |
| 2 | чисто, 109 | чисто, 69 | 6 | червоні |
| 3 | чисто, 130 | чисто, 69 | 6 | червоні |
| 4 | чисто, 144 | чисто, 69 | 6 | червоні |
| 5 | чисто, 189 | чисто, 69 | 6 | червоні |
| 6 | чисто, 166 (нове ядро) | чисто, 69 | чисто, 6 | червоні: `analyze` — io 46, shelf 78, conformance 95, generator 188, example 197 проблем; `grund_cli`/`grund_build` `analyze` чисті, але їхні тести падають |

### Фінальні кількості тестів

`grund` 166 (276 −69 перенесено в `grund_http` −127 видалено HTTP/конвеєр = 80; +29 задача 2, +21 задача 3, +14 задача 4, +45 задача 5 = 189; −80 старий DI (`legacy_di`) +57 задача 6 = 166), `grund_http` після задачі 1 — 69, далі за задачами 7–11: 82, 112, 129, 164, 206 (лише на кінці задачі 11 це 206), `grund_annotations` 6; решта пакетів на цей момент не запускаються успішно.

### Review Focus: тести частини A

RF-2: `container_scopes_test.dart` (3 тести, див. задачу 5). RF-4: `app_test.dart` (unknown `only`, збій prepare, збій start), `runner_set_test.dart` (unknown name, відкат), `container_lifecycle_test.dart` (відкат фабрики). RF-5: `app_test.dart` (idempotent close, збір у `ShutdownError`), `container_lifecycle_test.dart`. Позначки `// RF-n:` стоять у коді тестів.

### Відхилення від угоди частин плану

- `CallScope` в окремому файлі `call_scope.dart`; barrel експортує його так само.
- Додаткові типи помилок: `StartupRollbackError`, `DuplicateRunnerError`; `Container` має ще `reassemble`, `abandon`.
- `test/helpers/di_fixtures.dart` перенесено в задачу 3 (потрібен тестам графа).
- Додатковий приклад `packages/grund/example/grund_example.dart` і `test/example_test.dart` (3 тести).
- Старий `SerializationError` лишається з текстом про `app.serializers`.

### Не перевірено

- Плани виконано через скрипт збирання, що вставляє файли прототипу; повторний прогін усіх bash-блоків саме з тексту плану на свіжій копії (включно із задачею 1) **не робився** — команди перевірялися у `repo_a` послідовно, але вручну; точні числа в очікуваних виводах кроків 3/4 задачі 1 (`31` перейменувань) і «+45» в задачі 5 (у ранніх чернетках було «+75») треба звірити при виконанні.
- Методи ≤ 40 рядків, вкладеність ≤ 3 і ≤ 5 параметрів перевірено евристичним скриптом, не аналізатором; `main()`/`group()` тестів довші за 40 рядків (як і в наявних тестах репозиторію).
- `dart pub publish --dry-run` — лише для `grund` (0 warnings); для `grund_http` не запускався.
- Стан тестів `grund_cli`/`grund_build`/`example` — лише «падають».


## Додаток B

#### Нові межі для CLAUDE.md (частина B)

Додати до списку винятків «catch лише на межах, де працює користувацький код» (кожен — `on Object`, якщо не сказано інше; коментар із назвою межі в коді є; жодне не ковтає збій мовчки). Замінити старі записи про `Pipeline.run`, `RequestDispatcher.dispatch`, `Application.handle`, `HttpErrorResponder` і `ResponseSerializer`.

| Клас.метод | Що ловить | Що робить |
| --- | --- | --- |
| `HookChain.run` | `on Object` (хук або handler) | віддає збій у `_recover` (хуки `onError` у зворотному порядку); `after` не викликається |
| `HookChain._recover` | `on Object` (кинуте самим `onError`) | перший не-null `onError` відповідає; кинутий з `onError` виняток передається наступному хуку; жоден не відповів — `Error.throwWithStackTrace` останнього |
| `RouteExecutor.execute` | `on Object` (виняток handler-а/хука) | перетворює на problem-відповідь через `ProblemResponder`, додає `head.headers`; call-скоуп закривається у `finally` |
| `RouteExecutor._close` | `on ShutdownError` (збій `dispose` Scoped-ресурсу) | логує через `ErrorLog`; відповідь уже сформована |
| `BodyReader._build` | `on FormatException`, `on TypeError` (точний підтип `Error` від `fromJson` користувача) | 400 `body_invalid` з `pointer` `/body` або `/body/<index>` |
| `ProblemResponder._encode` | `on JsonUnsupportedObjectError` (точний `Error` від кодувальника) | відповідь без `details`; 500 завжди створюється |
| `HttpServer._answer` | `on Object` (middleware) | problem-відповідь; адаптер ніколи не отримує виняток запиту; `release` сигналу у `finally` |
| `HttpServer.start` | `on Object` (`adapter.listen`) | скидає `_listening`, `rethrow` (App обгортає в `RunnerError`) |
| `HttpServer._stop` | `try/finally` без `catch` | `adapter.close` і очікування in flight; `cancelAll()` у `finally` |
| тестовий `DispatchHarness.start` | `on Object` | закриває застосунок і `rethrow` (лише `test/helpers`) |

Видаляються з CLAUDE.md: `Pipeline.run`, `HttpErrorResponder`, `Application.handle`, межа `ResponseSerializer` (тепер `RouteExecutor` обгортає `SerializationError` як будь-який виняток; сам `ResponseSerializer` ловить `JsonUnsupportedObjectError`, як і раніше — перенести рядок без змін).

#### Review Focus: покриття

- **RF-1** (відмова хука посеред ланцюга): `test/hook/hook_chain_test.dart` (група RF-1: хук №2 кидає в `before` — `after` ні в кого, `onError` у зворотному порядку, перший не-null відповідає, виняток з `onError` передається далі); `test/server/route_executor_test.dart` (група «a failing hook (RF-1)»: неочікуваний виняток — 500 без внутрішніх деталей, `HttpException` зберігає статус і не логується).
- **RF-2** (ізоляція call-скоупу): `test/server/parallel_requests_test.dart` (20 паралельних запитів із різними `c.set`, різні `Tx`, `created == disposed == 20`); `test/server/route_executor_test.dart` (Scoped dispose після запиту навіть коли handler кинув; збій `dispose` не ламає відповідь); `test/ctx/http_ctx_test.dart`.
- **RF-3** (погані вхідні дані → 4xx): `test/ctx/params_test.dart` (невалідне число/enum/дата/uri/boolean, діапазони, довжина, pattern), `test/ctx/http_ctx_test.dart` (зламаний JSON, JSON не-об'єкт, `fromJson` кидає `FormatException`/`TypeError`, 413), `test/http/*` (форма problem), `test/server/request_dispatcher_test.dart` (404 problem, 405 + `Allow`, `HEAD`, зайві слеші, percent-encoding), `test/e2e/users_app_test.dart` (група RF-3 крізь `TestClient`).
- **RF-4** (збої старту): `test/server/http_server_test.dart`, група «startup failures (RF-4)»: дубль роуту між API падає до `listen`; немає `HttpAdapter` — `MissingProviderError`, що згадує `HttpAdapter`; невідоме ім'я в `only` — `UnknownRunnerError`; збій `listen` — `RunnerError` (phase `start`) і закритий застосунок; нерозв'язний хук падає до `listen`; `only: const {}` не слухає, але будує роути.
- **RF-5** (зупинка): `test/server/http_server_test.dart`, група «close (RF-5)»: `close` чекає запити in flight, нові — 503; запит від адаптера не блокує `close`, його `c.cancel` спрацьовує; `close` ідемпотентний, `adapter.close` один раз; збій `adapter.close` — `ShutdownError`, контейнер закривається; запит після `close` — 503; `test/e2e/users_app_test.dart` (503 після `close`).
- Додатково: `test/server/reassemble_test.dart` (report added/removed, запит in flight довершується на старій таблиці, збій зберігає стару таблицю, singleton-и збережені), `test/server/module_options_test.dart` (middleware, codecs, глобальні хуки, `debug`, `maxBodyBytes`).

#### Відхилення від угоди частин плану

1. Конструктор `HttpServer(HttpModule module, {adapter, config, log})`: перший параметр — модуль (джерело `use`, `middleware`, `codecs`); контракт цього не фіксує.
2. Глобальні хуки (`HttpModule.use`) розв'язуються в call-скоупі модуля API, а не кореневого інжектора; `middleware`/`use` вже створеного `HttpModule` змінюються лише перезапуском (hot reload їх не перечитує).
3. `Middleware.handle(request, next)`: `Next` без аргументів — middleware не підміняє запит; відповідь змінюється через `mergeHeaders`/нову відповідь.
4. `MissingProviderError` для відсутнього `HttpAdapter` не має додаткової підказки (для неї потрібна зміна ядра); повідомлення називає ключ `HttpAdapter`.
5. `RequestDispatcher.dispatch(request, table, cancel)`: таблиця й `CancelSignal` передаються параметрами (для атомарної заміни при `reassemble`); `RouteTableBuilder.build(apis, globalHooks)` — статичний.
6. `ErrorLogger` (typedef із задачі 1) лишається; `ErrorLog` (задача 7) — окремий binding `HttpModule`, замінюваний overrides.
7. Додаткові публічні типи: `ProblemCode` (константи кодів), `ParamLocation`; `HttpCtx` також відкриває `Params.all`.
8. Тіло-потік (`StreamBody`) не може використовувати Scoped-ресурси: call-скоуп закривається, коли handler повернув значення.
9. `HttpModule.onShutdown` викликає `HttpServer.stop()` (додано, щоб `only: const {}` теж давав 503 після `close`).
10. `HttpConfig.address` — `Object` (назва хоста або адресний об'єкт адаптера), `HttpModule` лишається `const`.

#### Не перевірено

- Справжні адаптери (`grund_io`, `grund_shelf`) — їх проганяє частина D; тут лише `FakeAdapter`.
- CI на Dart 3.8.0: прототип запускався на SDK з fvm 3.47.6.
- Поведінка під справжнім hot reload (VM service): `reassemble` перевірено лише викликом `App.reassemble()`.
- Публікація (`dart pub publish --dry-run`) і `public_member_api_docs` у `analysis_options.yaml` пакета: прототип має лише кореневі лінти; `///` на публічних членах написано, але лінт `public_member_api_docs` проганяє задача 1/21.
- Запуск у робочому дереві репозиторію (workspace-залежність замість `path: ../core`): прототип використовує `publish_to: none` і path-залежність.


## Додаток C

### Перелік діагностик (код → повідомлення)

Коди, що збереглися без змін: `circular_module_import`, `invalid_export`, `invalid_module_entry`, `missing_provider`, `circular_dependency`, `not_injectable`, `invalid_constructor`, `invalid_dependency`, `unsupported_constant`, `invalid_route_handler`, `invalid_handler_parameter`, `missing_from_json`, `unknown_path_parameter`, `duplicate_route`, `duplicate_generated_name`.
**Перейменовано:** `duplicate_provider` → `duplicate_binding`. **Вилучено:** `duplicate_module_id` (модулі більше не мають `id`), `invalid_component` (немає `@UseGuards…`).
**Нові:**

| Код | Повідомлення (скорочено) |
| --- | --- |
| `invalid_module_class` | `X is annotated with @Module but does not extend Module of package:grund/grund.dart…` |
| `invalid_name` | `The name of T is empty; give @Named a non-empty name.` |
| `captive_dependency` | `Singleton A depends on the call-scoped B (A -> T -> B); a singleton outlives every call…` |
| `invalid_provides` | `@Provides method O.m is not static / is private / is generic / returns void…`, `…is in a class that is not annotated with @Module` або `…returns a Future but its scope is scoped; only a singleton may be created asynchronously.` (задача 18) |
| `invalid_api` | `X is an @Api but its @Injectable has scope call; an API is created once…` |
| `duplicate_api` | `X is provided by modules [A, B]; its routes would be registered twice…` |
| `invalid_hook` | `use: a value of type T is not a HookRef.` |
| `route_outside_api` | `Route m is in a class that is not annotated with @Api; it is never served.` |
| `parameter_without_source` | `Parameter p (T) has no source: annotate it with @Path, @Query, @Header, @Cookie or @Body, or give it the class type of a value of the call scope.` |
| `invalid_validator` | `@Range on parameter p: it can only be used on a int or double value parameter.` / `min (…) is greater than max (…)` / невалідний RegExp |
| `invalid_status` | `Route m (/p) has status N, which is not an HTTP status code (100 to 599).` |
| `unsupported_return_type` | `Route m (/p) returns T, which cannot be sent: return a value, void, or a Stream<List<int>>.` |
| `stream_return_reserved` | `Route m returns Stream<T>; streams of events are reserved for grund_sse…` |

`invalid_handler_parameter` тепер також: другий `@Body`, `@Path` з nullable-типом, кілька джерел на параметрі, непідтримуваний тип. `missing_from_json` — коли `BodyKind.unsupported` (тип без `fromJson`, nullable).

### Review Focus: покриття

- **RF-3 (генератор, приватні/непублічні константи):** `constant_reader_test` — приватна константа `_secret` перебудовується з виклику конструктора; приватний клас → `UnsupportedConstant('_Hidden is private')`; іменований конструктор `Ref<Holder>.instance(...)` зберігає `constructorName` і аргументи типу; `Key<Holder>('main')` зберігає ім'я. `ModuleStructureCheck` і `RouteCheck.hookConstants` перетворюють такі значення на `unsupported_constant`.
- Усі нові коди задачі 15 мають тест: фікстурний (`checks_test.dart`, список кодів `BadApi`) або на моделях (`circular_dependency`, `captive_dependency`, `missing_provider`, `duplicate_binding`, видимість через `exports`/`imports`).
- **Емісія (задачі 16–18):** `module_emitter_test` (імпорти як екземпляри, `dependsOn` відсортовано, `Bind`, три скоупи, `@Provides`, `@Named` + екранування, `exports` ключі й реекспорт, `global`, детермінізм); `api_emitter_test` (по тесту на рядок таблиці параметрів, `async` лише з `await`, `void` → `return null`, префікс `http`); `golden_test` (golden, дві генерації, свіжий аналіз); `equivalence_test` (граф і відповіді анотованої ≡ явної); `generated_app_test` (RF-3: 400 для `@Range`, нечислового `@Path`, зламаного тіла, 401/403/404; RF-2 у частині call-скоупа: `RequestInfo` різний на кожен виклик); `cases_diagnostics_test` (точні `path:line:col`).
- Детермінізм колектора: порядок модулів — за URI бібліотек (`module_collector_test`).

### Відхилення від угоди частин плану

- До `@Module` додано поле `global` (узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17) його не перелічує); міксин перевизначає `global`.
- `Api(path, {use})`, `Get(path, {status, use})`: `path` — обов'язковий позиційний.
- Префікс імпорту `package:grund_http/…` у згенерованому коді — `http`.
- **Порядок bindings у міксині** (узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17) показує `TasksApi` одразу перед `TasksApiRoutes`): спочатку `providers` за порядком анотації, потім `@Provides`, потім `XRoutes` усіх API модуля. `dependsOn` відсортовано за ключем, а не за порядком параметрів.
- **`@Provides(scope: Scope.call)` з `Future<T>` не підтримується** (узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17) згадує «async-сесію»): ядро (`InjectionRuntime`) дозволяє асинхронними лише singleton-и, і генератор відхиляє такий метод діагностикою `invalid_provides` (задача 18, крок 1). `Future<T>` з `Scope.singleton` дозволено й емітується без `async`: фабрика просто повертає `Future<T>` (`create` ядра приймає `FutureOr<T>`), тому `Singleton.factory` генератору не потрібен.
- Імена: міксин `$X`, клас маршрутів `XRoutes` (`GeneratedNames`); конструктор `XRoutes(super.injector, this._api)` з приватним полем `_api`.
- `GrundGenerator.core()` = `[ModuleConstruct(), ApiConstruct()]` (задача 15); обидва тепер ще й емітують.
- `InvalidSource` має `reason`; `Lifetime.scoped` у моделі відповідає `Scope.call`.
- Двозначність видимості (`AmbiguousProviderError`) генератор не діагностує.
- Обмеження ядра, що вплинуло на fixture `users_app`: значення зі scoped-біндингу (`RequestInfo`) береться параметром маршруту (`c<RequestInfo>()`), а не конструктором API (singleton не може залежати від call-скоупа: `captive_dependency`). `c<T>()` резолвить з модуля, що оголошує API, тож експортувати такий біндинг не треба.

### Не перевірено

- Справжні пакети частин A і B замінено в `repo_c` їхніми прототипами (`S/proto/core`, `S/proto/http`) окремим scaffold-комітом; коли частини A/B потраплять у план, шляхи й `pubspec.yaml` fixture-ів збігатимуться (`resolution: workspace`), але повного прогону плану «з нуля» (A → B → C) не робилося.
- `build_runner`/`grund_build` у `users_app` (dev-залежність, `build.yaml` для `grund_build`): прототип не будує `grund_build`; це задача 19 (частина D). Поки що `pubspec.yaml` fixture-а без `build_runner`.
- Узгодженість golden-файла з версією `dart_style` стабільна лише для тієї, з якою його згенеровано (`dart_style ^3.1.2` у `pubspec.yaml` генератора); CI на Dart 3.8.0 не запускався (локально Dart 3.11).
- `Stream<T>` (не `Stream<List<int>>`) відхиляється `stream_return_reserved` і в емісію не доходить; байтовий потік перевірено e2e (`GET /users/export`).
- Не перевірено `@Header()`/`@Cookie()` з `DateTime`/`Uri`/enum у e2e (лише текстом емісії в `api_emitter_test`), `@OneOf` і `Length`/`Pattern` на рівні HTTP-відповіді (покриває `params_test` у `grund_http`).
- Пакети `grund_cli`, `grund_build`, `grund_io`, `grund_shelf`, `example` у цій частині не збираються за задумом (частина D, задача 19+).


## Додаток D

### Review Focus тестів, доданих частиною D

| RF | Де | Тест |
| --- | --- | --- |
| RF-1 | задача 20 | `example/test/e2e_test.dart`: «a missing or unknown key is a 401 problem» (хук №1 кидає, handler не викликається), «a reader cannot create a task: 403» (`RolesHook`), «GET /tasks/:id ... the hook maps a miss to 404» (`onError` у зворотному порядку), «the global hook times ... also failed ones» (`onError` глобального хука лишає відповідь і ставить заголовок) |
| RF-3 | задачі 12, 20 | `request_conformance` (404 `problem+json`), `conformance_app_test` (content-type 404), e2e: `?done=maybe`, `/tasks/one`, пустий title (`pointer: /body`) -> 4xx |
| RF-4 | задачі 12, 19, 20 | `lifecycle_conformance` «a failed bind fails the start; another application serves» (`RunnerError(SocketException)`, `app.isClosed`); `shelf_handler_test` (`ApplicationStateError` на нестартованому `App`); `main_process_test` (порт зайнятий -> один рядок, код 1); `dev_test` (збій `main` -> `dev` лишається) |
| RF-5 | задачі 12, 20 | `lifecycle_conformance` (close чекає in-flight/slow handler/streaming, `closeTimeout`, force, повторний close); `main_process_test` (SIGTERM -> код 0) |

### Відхилення від угоди частин плану

1. **`ErrorLogger` лишається в `grund_http`** (задача 1 створює, задача 7 не видаляє, задача 12 лише перевіряє). Прототип B його не мав, але `onError`-колбеки адаптерів публічні; тип нічого не ламає.
2. **`shelfHandler(App)` вимагає модуль адаптера в графі** (угода частин плану: «`only: const {}`»; модуль потрібен, бо `HttpServer` має `Key<HttpAdapter>` у `dependsOn`).
3. **`AdapterUnderTest`** — `AdapterUnderTest.of<A extends HttpAdapter>(Module, {required int Function(A) port})` (статичний метод: конструктор не може мати параметрів типу); `AdapterFactory = AdapterUnderTest Function(ErrorLogger, Duration?)`.
4. **«force close»** у conformance викликає `adapter.close(force: true)`, бо `App.close()` не має `force` (угода частин плану: `Future<void> close()`).
5. **Приклад**: `ServingModule` (не з угода частин плану) обгортає корінь; adapter обирається прапорцем; `TrimStringsPipe` вилучено (обрізання в `fromJson`); `Location` — через `LocationHook` (handler не бачить `ResponseHead`, бо угода частин плану не визначає, як згенерований код передає `c.response` у метод `@Api`).
6. **`dev`**: `ext.grund.reassemble` читається як `{applications, added, removed}` (угода частин плану: `ReassembleReport.toJson`); `Reloaded.changedRoutes` замінено на `Reloaded.changes: ServedChanges?`.
7. **Діагностики в тестах CLI** закріплюють лише префікс шляху, ім'я `Clock` і код `[missing_provider]`, бо текст і колонка належать задачі 15.

### Не перевірено

- Усе, що залежить від генератора (задачі 13-18), на момент написання не існувало: `init` + `gen` + `analyze` (`init_command_test`), зразки `shop`/`hello`/`bench` у `grund_cli`/`grund_build`, `integration/dev_test.dart`, `generated_library_test.dart`, `build_runner_test.dart`, бенчмарк. Їхній код написано за угода частин плану розділом 3 і не компілювався. `lib/tasks_api.grund.dart` написано вручну за контрактом і перевірено компіляцією та 56 тестами проти прототипів ядра й `grund_http`, але на прототипі анотації підставлено заглушкою (`proto/d/annotations_stub`); справжній вивід `gen` може відрізнятися форматом (крок 6 задачі 20 каже комітити вивід генератора).
- Перевірено проти прототипів (`proto/core`, `proto/http`) тестами: адаптери (`grund_io` 52, `grund_shelf` 74 разом із conformance, `grund_conformance` 14), CLI-частина `dev` (served_changes, dev_printer, reload_client*, shape_tracker — на копії старого репозиторію), приклад `tasks_api` без `generated_library_test` (56).
- Не запускались: `grund_cli`/`grund_build` повні набори й `integration`; `dart pub publish --dry-run`; `dart format` по всьому репо; кількості тестів «до змін» для порівняння в кроці 10 треба зняти на початку G1.
- Тексти документації (задача 21) і правки `CLAUDE.md` не перевірялися машинно; приклади коду в них скопійовано з перевірених (`explicit.dart`, `e2e`), а сніпети README (`HelloApi extends HttpApi` у «Without code generation», `TestApp`/`TestClient` у `grund_http/README.md`) не компілювалися окремо.
- Припущення про B: виняток, кинутий з `HttpHook.onError`, переходить далі й стає problem-відповіддю (підтверджено прототипом B і e2e); `TestClient.of(TestApp)` і `HttpServer` з адаптером у графі (підтверджено).

### Залежності від інших частин

- **A:** `Key<HttpAdapter>` в `dependsOn` `HttpServer`; `App.container.root<T>()`; `RunnerError` з `SocketException` при зайнятому порті; `ApplicationStateError`; `ReassembleReport.toJson` = `{applications, added, removed}` (відповідь розширення збирає `HotReloadExtension`); `StopSignals().wait()` можна викликати до `start`.
- **B:** `ErrorLogger` (див. відхилення 1) або його заміна; `HttpServer.stop` не чекає вічно на обірвані handler-и після `adapter.close(force)`; `ErrorLog`, що кидає, не валить відповідь (адаптер лишає 500 без тіла) — підтверджено `lifecycle_conformance`; `TestClient.of`; `HttpModule(use: [HookRef<T>.instance(...)], middleware:)`.
- **C:** форма виводу з узгодженою формою анотацій і згенерованого коду (задачі 13, 16, 17) (`mixin $X on grund.Module`, `XRoutes`), константи-вирази `const` модулів у `imports` (`HttpModule()`, `AuthModule()`) повторюються в `imports => [...]` генерованого коду як `non-const` екземпляри; `@Provides` статичні методи; `@Api(use: [HookRef<...>...])` та `@Post(status:, use:)`; код діагностики `missing_provider`; сигнатури `GrundGenerator.core()`/`PackageCollector` (`GenerationSession`, `GrundBuilder`); голден `users_app` для `grund_build` integration; модуль `UsersModule`, що не підключений до кореня, не повинен давати помилку (зразок `ShopSources.users`).
