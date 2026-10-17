# grund_jaspr: гідратація клієнтських компонентів — дизайн

Дата: 2026-10-17. Стан: чернетка на перегляд. Це частина етапу G7b
(`ROADMAP.md`): гідратація в `grund_jaspr`; `grund_ws` і решта шаблонів `init`
лишаються окремими. Закриває «клієнтський бандл і гідратація» зі spec
`2026-10-16-grund-jaspr-pages-design.md` (§1 «не цілі», §8).
Походження: питання споживача (портфоліо) про клієнтський бандл; рішення
користувача зібрані в §3, перевірені факти в §2.

## 1. Мета й межі

**Мета.** Компонент Jaspr, відрендерений на сервері, стає інтерактивним у
браузері (`StatefulComponent` з `setState`, обробники подій) без окремого
процесу й без інструментів Jaspr (`jaspr_cli`, `jaspr_builder`,
`build_runner`, `build_web_compilers`), які прив'язують користувача до
Dart 3.13.x.

**Цілі.**
- Користувач оголошує клієнтські компоненти одним спільним списком у своєму
  коді (явний, типізований API); сервер і клієнт читають той самий запис,
  тож розбіжність імен між ними неможлива.
- Клієнт збирається звичайним `dart compile js` командою `grund bundle`;
  `grund dev` збирає його сам і оновлює сторінку.
- Збій оголошення гучний: дубль імені, непридатне ім'я, параметри, що не
  кодуються в JSON, дають типізовану помилку (старт або 500 першого
  рендеру), а не мовчки негідратовану сторінку.
- Жодних змін у `grund` і `grund_http`.

**Не цілі (перший зріз).**
- Анотація `@client` і генератор, що пише реєстр. Це цукор над цим API, і він
  з'явиться, коли буде перший конструкт, який і так вимагає генератора (§7).
- dart2wasm: spike довів, що працює (з loader і запасним JS-бандлом), але
  це окремий зріз `bundle --wasm`.
- Відкладене завантаження коду компонентів (deferred import), `@encoder`/
  `@decoder` для складних типів параметрів, обгортка `ClientParams` з
  іменами ключів у помилках, вимкнення скрипта для окремої сторінки.
- Режим `jaspr serve` і `<base>`, відмінний від `/`.

**Анти-цілі.** Друге джерело правди про компонент (список на сервері й
окремий на клієнті); мовчазне вгадування; новий пакет-генератор; залежність
`grund_jaspr` від `analyzer`, `build_runner` або `jaspr_builder`.

## 2. Вхідні факти

**Jaspr 0.23.5** (джерела в pub cache, перевірено читанням і spike):
- Сервер обгортає `@client`-компонент у маркери
  `<!--@<name> data=<json>-->…<!--/@<name>-->`; скрипт
  `<script src=… defer>` кладе в `<head>` для кожної сторінки, коли в
  `ServerOptions` заданий `clientId`. Опції читаються з `Jaspr.options` під
  час рендеру. `ServerOptions.clients` ключується точним `runtimeType`;
  клас, якого немає в мапі, рендериться без маркерів і без помилки.
- Клієнт шукає маркери й будує компонент за іменем:
  `ClientOptions.clients[name]!` (відсутнє ім'я: збій у браузері).
- `ClientScriptAdapter`: якщо в `<head>` немає `<base>`, перед `clientId`
  ставиться `/`; якщо є, `clientId` лишається відносним до `<base>`.
  `Document` за замовчуванням має `<base href="/">`. Тож `clientId` має бути
  **відносним** (`static/…`), а `/static/…` без `<base>` дало б
  `//static/…` (хост `static`).
- Конструктори `ServerOptions`, `ClientTarget`, `ClientOptions`,
  `ClientLoader` публічні, хоч документація каже «не використовувати
  напряму». Версія jaspr зафіксована на `>=0.23.5 <0.24.0`; зміна мінору
  jaspr вимагає повторної перевірки формату маркерів.

**Spike** (`scratchpad/hydration-spike/REPORT.md`, опубліковані пакети,
Dart 3.13.5, справжній браузер): власні опції + `dart compile js` гідратують
лічильник з параметрами `int` і `String`; `grund_jaspr` 0.2.0 поважає
попередньо ініціалізовані опції; бандл віддається з `/static/…` разом з
допоміжними `*.part.js`; `-O0` компілюється, але **не** гідратується (record
rtti), мінімум `-O1`; компіляція займає 1,4–2 с у всіх режимах.

**Наш код.** `JasprSetup.ensureInitialized` викликає `Jaspr.initializeApp()` без
опцій лише коли Jaspr ще не ініціалізований. `JasprConfig.staticPath`
(`/static`) і `staticDirectory` (`web`); `StaticApi` віддає
`${staticPath}/*` без хуків, `.js` має content type. `grund dev` стежить за
`*.dart` у `lib/` і каталозі точки входу та шле live reload після кожного
перезавантаження. Головна бібліотека `grund_jaspr` залежить від `dart:io`,
тож клієнтська бібліотека мусить бути окремою. Генератори вбудовані в
`grund_cli` і `grund_build` статично (`StandardGenerator`).

## 3. Рішення користувача й архітектури

1. Власний конвеєр на `dart compile js`, не інструменти Jaspr (шлях 2).
2. Поріг SDK `^3.13.0` для всього workspace (зроблено 2026-10-17).
3. **Явний API першим, генератора поки немає** (рев'ю архітектури на Opus:
   пакет-генератор на кожну фішку дав би 4–5 зайвих пакетів; користувач
   проти розростання пакетів-генераторів). Нових пакетів `*_generator`
   не буде; конструкти нових фіч житимуть у `grund_generator` каталогами, а
   `grund_http_generator` зіллється туди з першим новим конструктом (§7).
4. Wasm і `@client`-цукор не входять у перший зріз.

## 4. Дизайн

### 4.1 Спільний список компонентів

Нова бібліотека `package:grund_jaspr/client_components.dart`. Вона імпортує
лише `package:jaspr/jaspr.dart` (платформо-нейтральна: компілюється і для VM,
і для вебу), не імпортує `grund`, `grund_http` і `dart:io`. Користувач пише
один файл, спільний для сервера й клієнта:

```dart
// lib/clients.dart
import 'package:grund_jaspr/client_components.dart';
import 'src/web/counter.dart';

final clients = ClientComponents([
  ClientComponent<Counter>(
    'counter',
    encode: Counter.toParams,
    decode: Counter.fromParams,
  ),
  ClientComponent<Clock>('clock', decode: Clock.fromParams), // без параметрів
]);
```

- `ClientComponent<T extends Component>(name, {required decode, encode})`:
  `name` відповідає `[a-z0-9_-]+`; `decode: T Function(Map<String, Object?>)`
  будує компонент на клієнті; `encode: Map<String, Object?> Function(T)?`
  віддає параметри на сервері (без `encode` у маркера немає `data=`).
- `ClientComponents(List<ClientComponent<Component>>)` перевіряє список при
  створенні: дубль імені, два записи для одного типу, тип `T`, виведений як
  `Component` (запис без явного типу), непридатне ім'я → `JasprSetupError`.
- **Пастка типів (вимога).** Перетворення запису на типи Jaspr
  (`ClientTarget<T>` на сервері, `ClientLoader` на клієнті) відбувається там,
  де `T` відомий (узагальнений метод запису, наприклад відвідувач
  `visit<T>`), а не через поле `Function(T)` невідомого `T`: читання такого
  поля через `ClientComponent<Component>` падає на перевірці коваріантності.
  Поля `encode`/`decode` приватні.
- Компонент (`Counter`) має компілюватися для вебу: його імпорти не можуть
  тягнути `dart:io` чи серверний API. Це відповідальність користувача;
  збій видно при `grund bundle` як помилку компілятора.

### 4.2 Сервер

`JasprConfig` отримує поле `clients: ClientComponents?` (за замовчуванням
`null`). `JasprModule.onInit` через `JasprSetup` ініціалізує Jaspr з
`ServerOptions(clientId, clients)`:
- `clientId` виводиться з конфігурації без початкового `/`:
  `${staticPath без початкового '/'}/client/main.client.dart.js`, за
  замовчуванням `static/client/main.client.dart.js`. Користувач його не
  задає. `staticPath` уже гарантовано починається з `/` і не закінчується
  ним (`JasprConfig.validate`), тож результат ніколи не абсолютний і не
  порожній.
- Коли `clients` порожній чи `null`, `clientId` теж `null`: скрипта немає,
  поведінка 0.2.0.
- Ініціалізація повторюється на кожному `onInit` (hot reload: список міг
  змінитися); стан Jaspr процесо-глобальний, тож якщо `main` уже ініціалізував
  Jaspr своїми опціями (чи інший застосунок процесу з іншими `clients`),
  `JasprSetup` кидає `JasprSetupError` з поясненням. `main` більше не
  викликає `Jaspr.initializeApp`.
- Скрипт додається на кожну сторінку, коли `clients` задано (так працює
  Jaspr); вимкнення для окремої сторінки поза цим зрізом. Вимога до
  користувача: `<base>` відсутній або `/`.
- Параметри, що не кодуються в JSON, дають `JsonUnsupportedObjectError` під час
  рендеру, який `ProblemResponder` перетворює на 500 і лог на `grund.http`.

### 4.3 Клієнт

Нова бібліотека `package:grund_jaspr/client.dart` (імпортує
`package:jaspr/client.dart` і спільну бібліотеку):
`GrundClient.run(ClientComponents)` складає `ClientOptions` з тих самих
записів, викликає `Jaspr.initializeApp(options)` і `runApp(ClientApp())`.
Точка входу користувача тримає три рядки (за конвенцією Jaspr
`lib/main.client.dart`, щоб проєкт лишався придатним для інструментів Jaspr):

```dart
import 'package:grund_jaspr/client.dart';
import 'clients.dart';

void main() => GrundClient.run(clients);
```

Помилка списку (дубль тощо) на клієнті кидає ту саму `JasprSetupError`.

### 4.4 Збірка: `grund bundle`

Нова команда `grund_cli`: `grund bundle [--release] [--output <dir>] [--directory <dir>]`.
Бандл не є виходом `gen`: це артефакт, залежний від версії SDK, а не
детермінований закомічений код.
- Запускає `<Platform.resolvedExecutable> compile js -O1 -o
  web/client/main.client.dart.js lib/main.client.dart` (з `--release`:
  `-O2 -Djaspr.flags.release=true`). `-O0` не використовується (§2).
- Вихідний каталог `web/client/` відповідає значенню за замовчуванням
  `JasprConfig.staticDirectory` (`web`) і виводу `clientId` (§4.2).
  Користувач зі своїм `staticDirectory` передає `--output <каталог>`
  (моє рішення: CLI не читає конфігурацію рантайму).
- Каталог виводу належить команді повністю: перед збіркою видаляються
  застарілі `*.part.js`/`.map`/`.deps`; він ігнорується git (скаффолд
  `init` додає рядок у `.gitignore`).
- Немає `lib/main.client.dart`: повідомлення й код виходу 0 (нічого збирати).
- `Platform.resolvedExecutable` не є Dart VM (AOT-скомпільований `grund`) або
  `dart compile js` завершився помилкою: `CliFailure` з виводом компілятора.
- `dart` береться з того ж виконуваного файлу, під яким працює CLI; окремих
  припущень про `PATH` немає.

### 4.5 `grund dev`

Якщо є `lib/main.client.dart`, `dev`:
- збирає бандл (`-O1`) до першого «serving» (перше завантаження сторінки
  одразу має працювати);
- після зміни `.dart` запускає збірку бандла паралельно з hot reload, а
  подію live reload шле **після завершення обох**;
- помилка компіляції друкується, старий бандл лишається; сесія не падає.

`dev_session.dart` (259/300 рядків) і `dev_command.dart` (231/300) уже на межі
ліміту, тому спершу виноситься колаборатор `ClientBundler` (окремий коміт
рефакторингу), потім додається поведінка.

### 4.6 Шаблон, приклад, документація

- `example/` отримує клієнтський лічильник: `lib/clients.dart`,
  `lib/main.client.dart`, компонент, сторінка його використовує; e2e
  перевіряє розмітку (маркери, `data=`, тег скрипта) на обох адаптерах.
- `grund init --template fullstack` отримує ті самі файли, `.gitignore` з
  `web/client/` і рядок про `grund dev`/`grund bundle` у README шаблону.
- `docs/jaspr.md` (розділ «Клієнтські компоненти»: реєстр, вимоги до
  компонента, `grund bundle`, `<base>`, обмеження), `packages/grund_jaspr/
  README.md`, `docs/faq.md` (рядки «no hydration, no client bundle»
  оновити), `ROADMAP.md`, CHANGELOG.

## 5. Помилки

Нові випадки використовують наявну сімʼю `JasprSetupError` (старт: список
компонентів, `clientId`, конфлікт ініціалізації Jaspr) і наявний шлях 500 для
рантайм-збою кодування параметрів. Нова типізована помилка потрібна лише
якщо спільний список вимагає розрізняти причини; решту вирішує план.

## 6. Тестування

- Юніт: перевірки `ClientComponents` (дубль імені, дубль типу, `T` =
  `Component`, непридатне ім'я); пастка коваріантності (запис через
  `ClientComponent<Component>` не падає); `JasprConfig.validate` для
  `clientId`/`staticPath`.
- HTTP через `TestApp`: HTML сторінки містить маркери, `data=` і
  `<script src="static/client/main.client.dart.js" defer>`; параметри з
  лапками, `<`, `&`, не-ASCII проходять; без `clients` скрипта немає;
  параметр, що не кодується в JSON, дає 500; конфлікт ініціалізації Jaspr кидає
  `JasprSetupError`.
- Інтеграція (`integration/`, не в `dart test`): `dart compile js` клієнта
  прикладу, `GET /static/client/main.client.dart.js` дає 200, `grund bundle`
  у `TempDir`-пакеті, `grund dev` перезбирає бандл після правки. Дочірній
  процес `dart compile js` — виняток для `grund_cli`/інтеграційних тестів, його
  називає CLAUDE.md (§8).
- Перевірка в браузері лишається ручною (процедура в `docs/jaspr.md`), як у
  spike.

## 7. Рішення поза цим етапом

- **Політика про генератори.** Нових пакетів `*_generator` немає. З першим
  новим конструктом (WebSocket `@Channel` або `@client`-цукор) `grund_http_
  generator` зливається в `grund_generator` (`src/core`, `src/http`,
  `src/<фіча>`); `boundary_test` стає тестом імпортів між каталогами;
  правило CLAUDE.md «ядро генератора не знає HTTP» стає правилом про
  каталоги (core-design вже описує його так). Тут це лише фіксується
  (ROADMAP і CLAUDE.md отримують речення), без виконання.
- `@client`-цукор, коли з'явиться, лишається на рівні бібліотеки: дескриптор
  пишеться в `X.g.dart` самої бібліотеки компонента, користувач додає його в
  список; діагностика `unregistered_client_component`; агрегатних файлів
  пакета немає (вони ламають модель `grund_build` «вихід на вхід»).
- Wasm: `bundle --wasm` збирає `.wasm`, `.mjs` і запасний JS-бандл, а
  `main.client.dart.js` стає loader-ом на ~15 рядків (перевіряє WasmGC,
  підтягує wasm або запасний JS). Деталі в `hydration-spike/REPORT.md`.
- Відкладене завантаження компонентів повертається разом із генератором.

## 8. Відхилення від CLAUDE.md і релізи

- Виняток тестового правила: дочірній процес `dart compile js` у
  `integration/` (`grund_cli`, приклад). Додається в CLAUDE.md тим самим
  комітом, що й `bundle`.
- Версії: `grund_jaspr` 0.3.0 (нові бібліотеки й `JasprConfig.clients`;
  CHANGELOG уже має секцію 0.3.0 через поріг SDK), `grund_cli` 0.2.0
  (`bundle`, `dev`, шаблон). Піднімати їх і публікувати мейнтейнер.
- Пакет `grund_jaspr` не отримує нових залежностей (`jaspr` уже є).

## 9. Не перевірено (перші перевірки плану)

1. `ClientComponents` зі статичних tear-off'ів компілюється в JS і
   гідратується (пастка коваріантності не повторюється на клієнті).
2. `int` у `Map<String, Object?>` зберігає тип після JSON-кола в dart2js
   (`p['start'] as int`).
3. Справжня помилка dart2js, якщо компонент тягне `dart:io`; текст
   діагностики для `grund bundle`.
4. Поведінка при `useIsolates: true` вже відхиляється `JasprSetup`;
   повторна ініціалізація опцій при hot reload не ламає рендер у польоті.
