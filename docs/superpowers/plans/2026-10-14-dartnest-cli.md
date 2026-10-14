# dartnest CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 5 роадмапу: пакет `dartnest_cli` з командами `gen` (пише `lib/<package>.dartnest.dart` з анотацій пакета), `gen --watch` (перегенерація на кожну зміну `lib/` з analyzer-контекстом у пам'яті) і `init` (каркас нового застосунку), з кодами виходу, тестом «зміна файлу без перезапуску» і бенчмарком: холодний прогін < 10 с, інкремент < 1 с на 200 файлах.

**Architecture:** П'ять шарів у `packages/dartnest_cli/lib/src/`. **package/** — `PackageRoot`: корінь пакета, ім'я з `pubspec.yaml`, шлях виходу, відображення шляхів з `/`. **generate/** — `PackageAnalysis` тримає `AnalysisContextCollection` над `lib/` і перечитує лише змінені файли (`changeFile` + `applyPendingFileChanges`), повертає синтаксичні помилки (`SyntaxProblem`) і резолвлені бібліотеки; `OutputWriter` пише вихід лише при зміні, через `<file>.tmp` + rename, ніколи поверх файлу без заголовка генератора; `GenerationSession` склеює це з `PackageCollector` і `DartnestGenerator` у `run({changed})` → `GenerationReport`. **watch/** — `WatchLoop`: debounce подій `package:watcher`, послідовні прогони, ігнор власного виходу. **init/** — `ProjectTemplate` (каталог файлів) і `ProjectScaffold` (запис у порожню теку). **cli/** — `DartnestCli` на `CommandRunner` з `package:args`, `GenCommand`, `InitCommand`, `ReportPrinter`, `CliExitCode`, `CliFailure`. `GenerationSession` експортується з barrel, щоб `dev` етапу 5b перевикористав ту саму генерацію.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors), `analyzer` `'>=8.1.1 <15.0.0'` (той самий діапазон, що в `dartnest_generator`), `args` ^2.7.0, `watcher` ^1.2.1, `yaml` ^3.1.3, `path` ^1.9.0, `dartnest_generator` ^0.1.0-dev; `package:test` ^1.25.0, `package:lints` ^5.1.0 + strict-casts/inference/raw-types.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (розділ 2 — пакет `dartnest_cli`; розділ 6 «Вихід», «Архітектура генератора» — `tool/dartnest.dart`, «Статична валідація» — ненульовий код виходу, «Драйвери» — CLI; розділ 7 — «watch продовжує працювати після помилки»; розділ 10 — лише як вимога не закрити шлях `dev`); `docs/superpowers/ROADMAP.md`, етап 5 і ризики; рішення C-11 етапу 4 (модулі інших пакетів).

## Open points

Рішення, які план приймає сам, але які автор може змінити до виконання. Для кожного — таблиця компромісів і рекомендація; план написано за рекомендованим варіантом (позначено ✔). Кожна рекомендація відкочується в межах однієї-двох задач.

### OP1. Діапазон `analyzer` і «пінінг»

Роадмап: «етап 5 пінить версію analyzer і має тест „зміна файлу без перезапуску“». `pubspec.lock` у репозиторії не комітиться (`.gitignore`).

| Варіант | Що фіксує | Хто може поставити CLI | Ризик |
|---|---|---|---|
| A ✔ той самий діапазон, що в генератора: `'>=8.1.1 <15.0.0'`; обидва краї перевірено (як в етапі 4); тест «зміна файлу без перезапуску» (Task 6) і бенчмарк (Task 7) ловлять нестабільність | верхню межу мажорної версії | будь-хто з генератором | новий мінор analyzer до перевірки потрапляє в CI |
| B точний пін `analyzer: 14.5.0` у `dartnest_cli` | одну версію | лише проєкти без інших інструментів на analyzer | конфлікт версій з build_runner, freezed тощо; розходиться з генератором |
| C A + закомітити кореневий `pubspec.lock` | CI репозиторію | як A | правка `.gitignore`; користувачів пакета не стосується |

**Варіанти:** A — діапазон генератора, обидва краї перевірено; B — точний пін; C — A + закомічений `pubspec.lock`. **Рекомендація: A** (C можна додати окремим комітом без зміни коду).

### OP2. Пакет, виконуваний файл і командний рядок

| Варіант | Як викликати | Відповідність специфікації |
|---|---|---|
| A ✔ `bin/dartnest_cli.dart` + `executables: {dartnest: dartnest_cli}`; `CommandRunner` з `package:args`; `gen [--watch] [--directory/-C <path>]`, `init <directory>` | `dart run dartnest_cli gen`; після `dart pub global activate` — `dartnest gen` | повна: розділ 2 і 6 пишуть `dart run dartnest_cli gen [--watch]`, роадмап — `dartnest_cli dev` |
| B `bin/dartnest.dart` | `dart run dartnest_cli:dartnest gen` | відхилення від прикладів |

`--directory` (а не позиційний аргумент) потрібен монорепо й тестам; за замовчуванням `.`. **Варіанти:** A — `bin/dartnest_cli.dart` + executable `dartnest`; B — `bin/dartnest.dart`. **Рекомендація: A.**

### OP3. Модулі з інших пакетів (рішення C-11)

Зараз `@Module` з іншого пакета — `OpaqueModuleReference`: генератор вимикає `missing_provider`/`circular_dependency` для всього пакета. C-11 віддав «читання інших пакетів» етапу 5. Перевірка коду показала: CLI нічого не треба читати — `AnalysisContextCollection` вже резолвить елементи залежностей (клас `@Module` пакета `billing` з його анотацією доступний `ModuleReferenceReader` через той самий `InterfaceType`). Отже, варіант «бачити крізь пакети» — це зміна генератора, а не CLI.

| Варіант | Що робить етап 5 | Хибні `missing_provider` | Пропущені помилки | Ціна |
|---|---|---|---|---|
| A ✔ лишити непрозорими; `gen` — один пакет за прогін; README пояснює порядок (спершу залежність) і що перевірку робить `Application.create` | нічого в генераторі | немає | ловить старт | 0 |
| B генератор читає `@Module` чужого пакета з резолвленого елемента: новий `ForeignModuleReference` з `ModuleModel` (лише для перевірки, код — виклик функції з `package:<owner>/<owner>.dartnest.dart`), `ModuleScope`/`DependencyCheck` ходять крізь нього | 1–2 задачі в `dartnest_generator` + фікстура з двох пакетів | немає | лише модулі з функцій | середня; дасть те саме і build_runner (етап 6), тому краще окремим етапом перед 6 |
| C `gen --workspace`: усі члени workspace у порядку залежностей | порядок генерації | як A | як A | мала, але без B не додає перевірок |

**Варіанти:** A — непрозорі, один пакет за прогін; B — генератор бачить `@Module` інших пакетів; C — `gen --workspace`. **Рекомендація: A** для етапу 5; B — окремий малий етап «5a» перед етапом 6 (рядок роадмапу додає автор).

### OP4. Коди виходу

| Варіант | Коди |
|---|---|
| A ✔ підмножина BSD `sysexits.h` | `0` успіх (і «нічого генерувати», і зупинений `--watch`), `1` проблеми в джерелах (діагностики, синтаксичні помилки), `64` неправильний командний рядок, `66` немає пакета (`pubspec.yaml` з валідним `name`, `lib/`), `73` файл не записується (і `init` у непорожню теку) |
| B `0`/`1`/`2` | скрипти не відрізнять «помилка в коді» від «не той каталог» |

**Варіанти:** A — `0`/`1`/`64`/`66`/`73`; B — `0`/`1`/`2`. **Рекомендація: A** (`CliExitCode` — один enum; змінити числа — одна правка).

### OP5. Вихід, коли в джерелах проблеми

| Варіант | Застосунок під час правки | `dev` (5b) |
|---|---|---|
| A ✔ попередній `lib/<pkg>.dartnest.dart` лишається як був (`WriteOutcome.kept`), код виходу `1` | компілюється зі старим графом | старий процес живе далі, як у специфікації 10.1 п. 5 |
| B видалити вихід | не компілюється, доки не виправлено | падає разом з помилкою |

**Варіанти:** A — лишити попередній файл; B — видалити. **Рекомендація: A.**

### OP6. Застарілий і чужий файл виходу

| Варіант | Немає анотацій у `lib/` | Файл без заголовка `// GENERATED BY dartnest_generator. DO NOT EDIT.` на шляху виходу | `FileUnit` (з v1.1) |
|---|---|---|---|
| A ✔ | згенерований файл видаляється (`WriteOutcome.deleted`), інакше `none` | ніколи не перезаписується й не видаляється: код `73` з порадою перейменувати | пишеться «лише якщо змінився», шлях не виходить за корінь пакета; застарілі не видаляються (немає маніфесту, жоден конструкт v1 їх не створює) |
| B | файл лишається | перезаписується | — |

**Варіанти:** A — видаляти застарілий, не чіпати чужий; B — лишати застарілий, перезаписувати чужий. **Рекомендація: A.**

### OP7. Синтаксичні помилки користувача

| Варіант | Що бачить користувач | Ризик |
|---|---|---|
| A ✔ CLI парсить кожен файл `lib/` (`getParsedUnit`); будь-яка помилка парсера → `path:line:col: error: message [syntax_error]`, генератор не запускається; семантичні помилки ігноруються (на першому прогоні `lib/<pkg>.dartnest.dart` ще не існує, тож код, що його імпортує, не компілюється) | точне місце помилки | — |
| B лише діагностики генератора | collector бачить відновлений парсером AST: хибні або пропущені діагностики, «напівфайл» під час збереження може згенерувати неправильний граф | високий |

Ціна A — повторний парсинг змінених файлів; інкремент на 201 бібліотеці разом з ним — 0.35–0.41 с (OP11). **Варіанти:** A — CLI перевіряє синтаксис; B — лише діагностики генератора. **Рекомендація: A.**

### OP8. `--watch`: debounce, черга, збої

| Варіант | Шторм подій | Збій запису | Інший виняток (баг, analyzer) |
|---|---|---|---|
| A ✔ debounce 100 мс після останньої події `.dart` у `lib/` (крім `*.dartnest.dart` і не-Dart), прогони строго послідовні, зміни під час прогону — у наступний | один прогін на пакет змін | `CliFailure` друкується, watch триває | процес падає з трасою (без нової межі `on Object`) |
| B те саме + межа `on Object` у `WatchLoop`: друкує, перевідкриває `GenerationSession`, триває | так само | так само | watch виживає; потрібен новий пункт у списку меж `CLAUDE.md` |

**Варіанти:** A — debounce, черга, без нової межі; B — те саме + межа `on Object`. **Рекомендація: A** (B — одна задача, якщо стабільність analyzer виявиться проблемою на практиці).

### OP9. Обсяг `init`

| Варіант | Що створюється | Ризик |
|---|---|---|
| A ✔ `init <directory>`: новий пакет у новій або порожній теці, ім'я = ім'я теки | 5 файлів: `pubspec.yaml` (`dartnest`, `dartnest_annotations`, `dartnest_io` — `^0.1.0`, константа `ProjectTemplate.dartnestVersion`; dev: `dartnest_cli`, `lints`), `analysis_options.yaml`, `.gitignore`, `lib/src/hello.dart` (сервіс, контролер, `AppModule`), `bin/server.dart`; `pub get` і `gen` не запускаються, CLI друкує наступні кроки | — |
| B `init` у наявному пакеті (`dart create` → додати залежності й модуль) | правки наявних файлів | правка чужого `pubspec.yaml` |
| C A + `tool/dartnest.dart` і `test/` | 7+ файлів | `tool/dartnest.dart` потрібен лише з власними конструктами, яких у v1 немає |

`^0.1.0` — перший публікований реліз (етап 7); до публікації `pub get` у створеному пакеті не пройде, тест Task 8 резолвить його проти workspace. **Варіанти:** A — новий пакет з 5 файлів; B — `init` у наявному пакеті; C — A + `tool/dartnest.dart` і `test/`. **Рекомендація: A**; шаблон `tool/dartnest.dart` (специфікація, розділ 6) — у README `dartnest_cli`.

### OP10. Публічний API для розширень і для `dev`

| Варіант | `tool/dartnest.dart` | `dev` (5b) |
|---|---|---|
| A ✔ `DartnestCli({out, err, generator, untilStopped}).run(arguments)` замість `DartnestGen([core, graphql]).run(args)` зі специфікації; barrel експортує `DartnestCli`, `CliExitCode`, `CliFailure`, `GenerationSession`, `GenerationReport`, `SyntaxProblem`, `WriteOutcome`, `PackageRoot`; `WatchLoop` лишається внутрішнім, доки `dev` не стане другим користувачем | `DartnestCli(generator: DartnestGenerator([...const DartnestGenerator.core().constructs, MyConstruct()]))` | `GenerationSession.run(changed:)` — та сама генерація; `dev` додасть свою команду в `DartnestCli` |
| B клас `DartnestGen(List<Construct>)` як у специфікації | `DartnestGen([core, graphql])` | те саме |

**Варіанти:** A — `DartnestCli(generator:)`; B — `DartnestGen(List<Construct>)`. **Рекомендація: A** (одне ім'я для командного рядка; перейменування — одна правка).

### OP11. Де живе бенчмарк

Виміряно на цій машині (Dart 3.13.5, 201 бібліотека): холодний прогін 2.4 с, інкремент 0.35–0.41 с окремо; у загальному `dart test` (паралельно з іншими файлами) — 4.5 с і 0.78 с.

| Варіант | Звичайний `dart test` | Стабільність порогу 1 с |
|---|---|---|
| A ✔ `packages/dartnest_cli/benchmark/generation_benchmark_test.dart`, поза `test/`; запуск `dart test benchmark`; пороги роадмапу — `expect` | не входить | вимірюється без конкуренції |
| B у `test/` | входить | 0.78 с під навантаженням — близько до межі, флейки |
| C тег `benchmark` + `exclude_tags` | не входить | `-t benchmark` не перекриває `exclude_tags` (перевірено), потрібні presets |

**Варіанти:** A — `benchmark/`; B — `test/`; C — тег. **Рекомендація: A.**

## Рішення

1. **Один пакет за прогін.** `PackageRoot.open(directory)` читає `name` з `pubspec.yaml` (`^[a-z_][a-z0-9_]*$`, той самий шаблон, що в `LibraryWriter`), вимагає `lib/`; вихід — `lib/<name>.dartnest.dart` (`GeneratedNames.library` дає його URI). Шляхи в повідомленнях — відносно кореня з `/` (`PackageRoot.display`, та сама ідіома, що `SourceLocations` генератора).
2. **Analyzer у пам'яті.** `PackageAnalysis` створює `AnalysisContextCollection(includedPaths: [lib/])` один раз на сесію; `changed(paths)` — `changeFile` для кожного шляху й `applyPendingFileChanges` для кожного контексту. Файли — усі `*.dart` у `lib/` (рекурсивно, без переходу за symlink), крім `*.dartnest.dart`, відсортовані; `part`-файли парсяться (синтаксис), але не резолвляться (`NotLibraryButPartResult`). Після запису чи видалення виходу сесія сама повідомляє analyzer про зміну виходу.
3. **Прогін** (`GenerationSession.run`): `changed` → список файлів → синтаксичні помилки (є → `kept`) → резолв → `PackageCollector(name, root).collect` → порожня модель (немає модулів, injectable, контролерів) → `deleteLibrary` → `DartnestGenerator.generate` (діагностики → `kept`) → `FileUnit`-и → `writeLibrary`. Результат — `GenerationReport(output, outcome, elapsed, syntaxProblems, diagnostics)`.
4. **Запис** (`OutputWriter`): порівняння з наявним вмістом (однаковий → `unchanged`, mtime не змінюється); файл без `LibraryWriter.header` — `CliFailure(cannotCreate)`; запис — `<file>.tmp` з `flush: true` + `renameSync`; будь-який `FileSystemException` → `CliFailure(cannotCreate, 'Cannot write <path>: <os message>.')`. Ловляться лише `PathNotFoundException`, `FileSystemException`, `YamlException` — конкретні винятки, не межі `on Object`.
5. **Друк** (`ReportPrinter`): проблеми — у stderr, по одній на рядок (спершу `SyntaxProblem`, потім `Diagnostic`, кожне відсортоване), останній рядок — `N problem(s); lib/x.dartnest.dart was not changed.`; результат — у stdout: `Generated lib/x.dartnest.dart in N ms.`, `lib/x.dartnest.dart is up to date (N ms).`, `No annotations in lib/; deleted lib/x.dartnest.dart.`, `No annotations in lib/; nothing to generate.`; watch — `Watching lib/ for changes; press Ctrl+C to stop.`
6. **Командний рядок** (`DartnestCli`): `CommandRunner<int>` з перевизначеним `printUsage` (довідка йде в `out`, а не в `print`); `UsageException` → повідомлення й usage у stderr, `64`; `CliFailure` → повідомлення в stderr, його код. `gen --watch` чекає на `untilStopped()` — за замовчуванням перший `SIGINT` (`ProcessSignal.sigint.watch().first`, підписка лише під час watch, тож Ctrl+C поза watch працює як звичайно).
7. **Watch** (`WatchLoop.run(watcher, stop)`): підписка на `watcher.events` до першого прогону (жодна зміна під час холодного старту не губиться), `await watcher.ready`, перший прогін, рядок `Watching ...`, далі debounce → `session.run(changed: batch)`; `stop` → скасування підписки й таймера, очікування останнього прогону; `GenCommand` закриває сесію в `finally`.
8. **Тести без мережі й без дочірніх процесів.** `TempDir` (тека в системному temp, видаляється `addTearDown`), `WorkspacePackageConfig.write(root, name)` пише `.dart_tool/package_config.json` тимчасового пакета з усіма пакетами конфігурації тестового ізоляту (`Isolate.packageConfig`, абсолютні `rootUri`) + сам пакет — analyzer резолвить `package:dartnest_annotations` без `pub get`; `TempPackage` збирає з цього пакет; `CliRun` запускає `DartnestCli` у процесі з `StringBuffer`; `LineSink` (`StringSink`) дає watch-тестам чекати на наступний рядок; `FakeWatcher` — події від тесту.
9. **Поза планом**: `dev`, hot reload/restart (етап 5b), build_runner (етап 6), читання модулів інших пакетів (OP3 B), `gen --workspace`, маніфест `FileUnit`-ів, CI-конфігурація (у репозиторії її немає; «входить у CI» = команда `dart test benchmark` у `CLAUDE.md`).

## Global Constraints

- Ядро `dartnest`, `dartnest_annotations` і `dartnest_generator` не змінюються. `analyzer` дозволений лише в `dartnest_generator`/`dartnest_cli` (`CLAUDE.md`).
- Новий пакет: `version: 0.1.0-dev`, `publish_to: none`, `environment: sdk: ^3.8.0`, `resolution: workspace`; додається до `workspace:` кореневого `pubspec.yaml` у Task 1. Залежності — рівно ті, що в Tech Stack; `analyzer` — `'>=8.1.1 <15.0.0'` (OP1).
- Код використовує лише API, спільне для analyzer 8.1.1 і 14.x: `AnalysisContextCollection(includedPaths:)`, `contextFor`, `contexts`, `currentSession`, `getResolvedLibrary`, `getParsedUnit`, `getErrors`, `changeFile`, `applyPendingFileChanges`, `dispose`, `ResolvedLibraryResult.element`, `NotLibraryButPartResult`, `ParsedUnitResult.diagnostics/lineInfo`, `Diagnostic.message/offset/diagnosticCode.severity`, `DiagnosticSeverity`.
- Детермінізм: файли сортуються, діагностики сортуються; вихід CLI для фікстури `users_app` байт-у-байт дорівнює golden (Task 5, крок перевірки).
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/`, ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів, ≤ 3 рівні вкладеності; один публічний клас або enum на файл (приватний `_Runner` ділить файл з `DartnestCli`); немає top-level функцій у `lib/src` (`main` у `bin/` — виняток `CLAUDE.md`); без `!`, `dynamic`, `late`; жодного `catch` без `on`, жодного `on Object` (нових меж немає, OP8); позиційних `bool` немає; dartdoc на кожному публічному члені.
- Тести: temp-файли лише через `TempDir`; мережі немає; CLI запускається в процесі (`CliRun`, `DartnestCli(out:, err:, untilStopped:)`); бенчмарк — поза `test/` (OP11).
- Публічний API, dartdoc, повідомлення CLI, README і повідомлення комітів — англійською.
- Перед кожним комітом: з кореня `dart analyze` — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів; `cd packages/dartnest_cli && dart test` зелений.
- `dart` не завжди в `PATH`: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після зміни будь-якого `pubspec.yaml` — `dart pub get` з кореня.
- Відхилення від специфікації, зафіксовані планом: `DartnestCli(generator:)` замість `DartnestGen([...])` (OP10); `init` не створює `tool/dartnest.dart` (OP9); перевірка графа крізь пакети не робиться (OP3).

## Review Focus

1. Запуск поза пакетом (немає `pubspec.yaml`, `name` невалідний, немає `lib/`): одне речення з шляхом і кодом `66`, жодного стеку. Закріплено в Task 1 (`a directory without pubspec.yaml is not a package`, `// Review Focus 1`) і Task 5 (`a directory without a package exits with 66`).
2. Вихід не записується (тека на місці файлу чи `.tmp`, тека тільки для читання): `Cannot write lib/x.dartnest.dart: <причина>.`, код `73`, без напівзаписаного файлу; у `--watch` — повідомлення й watch триває. Закріплено в Task 3 (`a path that cannot be written is a cannot-create failure`, `// Review Focus 2`), Task 5 (`exits with 73`) і Task 6 (`a failure to write is reported and watching goes on`).
3. Синтаксична помилка в файлі користувача (зокрема файл, збережений наполовину): `path:line:col: error: ... [syntax_error]`, код `1`, попередній вихід не змінюється, після виправлення генерація відновлюється. Закріплено в Task 4 (`syntax errors stop generation until they are fixed`, `// Review Focus 3`) і Task 2 (точна позиція).
4. Останню анотацію прибрано / анотацій ніколи не було: згенерований файл видаляється, а не лишається з мертвим графом; без анотацій і без файлу — `nothing to generate`, код `0`. Закріплено в Task 4 (`a package without annotations has no generated library`, `// Review Focus 4`) і Task 5.
5. На шляху виходу лежить файл, написаний людиною: ані `gen`, ані «немає анотацій» його не перезаписують і не видаляють. Закріплено в Task 3 (`a file the generator did not write is never replaced`, `// Review Focus 5`).
6. Шторм подій watch (редактор пише через тимчасовий файл, кілька MODIFY поспіль, власний запис виходу): один прогін на пакет подій, власний вихід і не-Dart файли прогону не запускають. Закріплено в Task 6 (`a burst of events gives one run`, `// Review Focus 6`; `its own output and other files do not start a run`).
7. Файлова система віддає файли в довільному порядку: вихід байт-у-байт той самий. Закріплено в Task 4 (`the output does not depend on the order files were created`, `// Review Focus 7`).
8. Windows: шляхи в діагностиках і повідомленнях — з `/`. Закріплено в Task 5 (`paths are printed with / separators`, `// Review Focus 8`; на Windows тест падає, якщо `display` поверне `\`).
9. Неправильний командний рядок (невідома команда, невідома опція, зайвий аргумент, `init` без теки чи з невалідним ім'ям): usage у stderr і код `64`; `--help` — у stdout і `0`. Закріплено в Task 5 (`a wrong command line exits with 64 and prints usage`, `// Review Focus 9`) і Task 8.

---

## File Structure

```
pubspec.yaml                                         # workspace: + packages/dartnest_cli (T1)
CLAUDE.md                                            # commands, CLI output rule, CLI test rule (T9)
docs/superpowers/ROADMAP.md                          # stage 5 row links this plan; risks (T9)
packages/dartnest_cli/                               # NEW
  pubspec.yaml, analysis_options.yaml (T1), README.md (T9)
  bin/dartnest_cli.dart                              # main: exitCode = await DartnestCli().run(args) (T5)
  lib/dartnest_cli.dart                              # barrel (T1, T5)
  lib/src/cli/cli_exit_code.dart, cli_failure.dart   # CliExitCode, CliFailure (T1)
  lib/src/package/package_root.dart                  # PackageRoot (T1)
  lib/src/generate/syntax_problem.dart               # SyntaxProblem (T2)
  lib/src/generate/package_analysis.dart             # PackageAnalysis (T2)
  lib/src/generate/write_outcome.dart                # WriteOutcome (T3)
  lib/src/generate/output_writer.dart                # OutputWriter (T3)
  lib/src/generate/generation_report.dart            # GenerationReport (T4)
  lib/src/generate/generation_session.dart           # GenerationSession (T4)
  lib/src/cli/report_printer.dart                    # ReportPrinter (T5, T6)
  lib/src/cli/dartnest_cli.dart                      # DartnestCli + private _Runner (T5, T6, T8)
  lib/src/cli/gen_command.dart                       # GenCommand (T5, T6)
  lib/src/watch/watch_loop.dart                      # WatchLoop (T6)
  lib/src/init/project_template.dart                 # ProjectTemplate (T8)
  lib/src/init/project_scaffold.dart                 # ProjectScaffold (T8)
  lib/src/cli/init_command.dart                      # InitCommand (T8)
  test/helpers/temp_dir.dart                         # TempDir (T1)
  test/helpers/workspace_package_config.dart         # WorkspacePackageConfig (T2)
  test/helpers/temp_package.dart                     # TempPackage (T2)
  test/helpers/shop_sources.dart                     # ShopSources: the annotated test package (T2)
  test/helpers/cli_run.dart                          # CliRun (T5)
  test/helpers/line_sink.dart, fake_watcher.dart     # LineSink, FakeWatcher (T6)
  test/package_root_test.dart (T1), package_analysis_test.dart (T2), output_writer_test.dart (T3),
  test/generation_session_test.dart (T4), gen_command_test.dart (T5),
  test/watch_loop_test.dart, gen_watch_test.dart (T6), init_command_test.dart (T8)
  benchmark/benchmark_sources.dart, generation_benchmark_test.dart   # `dart test benchmark` (T7)
```

Залежності задач: 1 → 2 → 3 → 4 → 5 → 6 → 7, 5 → 8, 1–8 → 9 (7 і 8 незалежні між собою). Кількості тестів у кроках «Expected» — для `cd packages/dartnest_cli && dart test` наростаючим підсумком: T1 `+4`, T2 `+8`, T3 `+14`, T4 `+19`, T5 `+28`, T6 `+33`, T7 `+33` (і `+1` у `dart test benchmark`), T8 `+36`.

### Task 1: Пакет `dartnest_cli`, `PackageRoot`, коди виходу

Пакет одразу отримує всі runtime-залежності етапу (OP1, OP2). `PackageRoot.open` — єдине місце, що вирішує, чи є тека пакетом: `pubspec.yaml` з `name` за шаблоном `PackageRoot.validName` і тека `lib/`; кожна відмова — `CliFailure(CliExitCode.noInput, ...)` з одним реченням (Review Focus 1). `display` дає шлях відносно кореня з `/` (Review Focus 8). Barrel поки експортує лише типи цієї задачі; Task 5 доповнює його.

**Files:**
- Create: `packages/dartnest_cli/pubspec.yaml`
- Create: `packages/dartnest_cli/analysis_options.yaml`
- Create: `packages/dartnest_cli/lib/src/cli/cli_exit_code.dart`
- Create: `packages/dartnest_cli/lib/src/cli/cli_failure.dart`
- Create: `packages/dartnest_cli/lib/src/package/package_root.dart`
- Create: `packages/dartnest_cli/lib/dartnest_cli.dart`
- Modify: `pubspec.yaml`
- Test: `packages/dartnest_cli/test/helpers/temp_dir.dart`
- Test: `packages/dartnest_cli/test/package_root_test.dart`

**Interfaces:**
- Consumes: нічого з попередніх задач; `package:yaml` (`loadYaml`, `YamlMap`, `YamlException`), `package:path`.
- Produces:
  - `enum CliExitCode { success(0), problems(1), usage(64), noInput(66), cannotCreate(73) }` з полем `final int code`.
  - `final class CliFailure implements Exception { const CliFailure(CliExitCode exitCode, String message); }`, `toString()` = `message`.
  - `final class PackageRoot`: `factory PackageRoot.open(String directory)` (кидає `CliFailure` з `noInput`), `static final RegExp validName`, `String path` (абсолютний, нормалізований), `String name`, `String libPath`, `String outputPath` (`lib/<name>.dartnest.dart`), `String display(String file)` (відносно `path`, з `/`).
  - Тестовий хелпер `TempDir`: `factory TempDir.create()` (видалення через `addTearDown`), `String path`, `String resolve(String relative)`, `String write(String relative, String content)`, `String read(String relative)`, `bool exists(String relative)`.

- [ ] **Step 1: Create the package and write the failing test**

Кореневий `pubspec.yaml` (повний файл; новий рядок — `packages/dartnest_cli`):

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
  - packages/dartnest_cli
  - packages/dartnest_conformance
  - packages/dartnest_generator
  - packages/dartnest_generator/test/fixtures/cases_app
  - packages/dartnest_generator/test/fixtures/users_app
  - packages/dartnest_io
  - packages/dartnest_shelf
```

Файл `packages/dartnest_cli/pubspec.yaml`:

```yaml
name: dartnest_cli
description: >-
  Command line tool of dartnest: generates the code of annotated packages
  (gen, gen --watch) and scaffolds new applications (init).
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
executables:
  dartnest: dartnest_cli
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  args: ^2.7.0
  dartnest_generator: ^0.1.0-dev
  path: ^1.9.0
  watcher: ^1.2.1
  yaml: ^3.1.3
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

Файл `packages/dartnest_cli/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

Файл `packages/dartnest_cli/test/helpers/temp_dir.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh directory under the system temp directory, deleted when the
/// test that created it ends.
final class TempDir {
  TempDir._(this.path);

  /// Creates the directory and registers its deletion with [addTearDown].
  factory TempDir.create() {
    final directory = Directory.systemTemp.createTempSync('dartnest_cli_');
    final temp = TempDir._(directory.resolveSymbolicLinksSync());
    addTearDown(temp._delete);
    return temp;
  }

  /// Absolute path of the directory, symbolic links resolved.
  final String path;

  /// The absolute path of [relative] (with `/` separators) in the directory.
  String resolve(String relative) => p.joinAll([path, ...relative.split('/')]);

  /// Writes [content] to [relative], creating parent directories; returns
  /// the absolute path.
  String write(String relative, String content) {
    final file = File(resolve(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  /// The content of [relative].
  String read(String relative) => File(resolve(relative)).readAsStringSync();

  /// Whether a file exists at [relative].
  bool exists(String relative) => File(resolve(relative)).existsSync();

  void _delete() {
    final directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
```

Файл `packages/dartnest_cli/test/package_root_test.dart`:

```dart
import 'package:dartnest_cli/src/cli/cli_exit_code.dart';
import 'package:dartnest_cli/src/cli/cli_failure.dart';
import 'package:dartnest_cli/src/package/package_root.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

Matcher _noInput(String message) => isA<CliFailure>()
    .having((f) => f.exitCode, 'exitCode', CliExitCode.noInput)
    .having((f) => f.message, 'message', contains(message));

void main() {
  test('a package is read from its pubspec name', () {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: shop\n');
    dir.write('lib/shop.dart', '');

    final package = PackageRoot.open(dir.path);

    expect(package.name, 'shop');
    expect(package.path, dir.path);
    expect(package.outputPath, dir.resolve('lib/shop.dartnest.dart'));
    expect(package.display(package.outputPath), 'lib/shop.dartnest.dart');
  });

  // Review Focus 1: run outside a package.
  test('a directory without pubspec.yaml is not a package', () {
    final dir = TempDir.create();

    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('No pubspec')));
  });

  test('a pubspec without a valid name is rejected', () {
    final dir = TempDir.create();
    dir.write('lib/a.dart', '');

    dir.write('pubspec.yaml', 'name: Shop-App\n');
    expect(
      () => PackageRoot.open(dir.path),
      throwsA(_noInput('no valid package name')),
    );

    dir.write('pubspec.yaml', '- not a map\n');
    expect(
      () => PackageRoot.open(dir.path),
      throwsA(_noInput('no valid package name')),
    );

    dir.write('pubspec.yaml', 'name: [\n');
    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('Cannot read')));
  });

  test('a package without lib/ has nothing to generate from', () {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: shop\n');

    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('No lib/')));
  });
}
```

Run: `dart pub get`
Expected: `Resolving dependencies...`, exit code 0 (з кореня репозиторію)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test`
Expected: FAIL: компіляція — `package:dartnest_cli/dartnest_cli.dart` не існує

- [ ] **Step 3: Write the exit codes, the failure and `PackageRoot`**

Файл `packages/dartnest_cli/lib/src/cli/cli_exit_code.dart`:

```dart
/// The exit codes of `dartnest_cli`, taken from BSD `sysexits.h` where one
/// fits.
enum CliExitCode {
  /// The command did what it was asked.
  success(0),

  /// The sources have problems: generator diagnostics or syntax errors.
  problems(1),

  /// The command line is wrong.
  usage(64),

  /// The package to work on is missing or unreadable.
  noInput(66),

  /// A file cannot be written.
  cannotCreate(73);

  const CliExitCode(this.code);

  /// The process exit code.
  final int code;
}
```

Файл `packages/dartnest_cli/lib/src/cli/cli_failure.dart`:

```dart
import 'cli_exit_code.dart';

/// A failure that ends a command: [message] goes to stderr and the process
/// exits with [exitCode].
final class CliFailure implements Exception {
  /// Creates the failure.
  const CliFailure(this.exitCode, this.message);

  /// How the process exits.
  final CliExitCode exitCode;

  /// One sentence for the user, naming the file and the fix.
  final String message;

  @override
  String toString() => message;
}
```

Файл `packages/dartnest_cli/lib/src/package/package_root.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';

/// The package a command works on: its root directory and the name from
/// its `pubspec.yaml`.
final class PackageRoot {
  const PackageRoot._(this.path, this.name);

  /// Reads the package at [directory].
  ///
  /// Throws a [CliFailure] with [CliExitCode.noInput] when there is no
  /// readable `pubspec.yaml` with a valid `name`, or no `lib/` directory.
  factory PackageRoot.open(String directory) {
    final root = p.normalize(p.absolute(directory));
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw CliFailure(
        CliExitCode.noInput,
        'No pubspec.yaml in $root; run the command in a package directory '
        'or pass --directory.',
      );
    }
    final name = _name(pubspec);
    if (!Directory(p.join(root, 'lib')).existsSync()) {
      throw CliFailure(CliExitCode.noInput, 'No lib/ directory in $root.');
    }
    return PackageRoot._(root, name);
  }

  /// A valid Dart package name.
  static final validName = RegExp(r'^[a-z_][a-z0-9_]*$');

  /// Absolute, normalized path of the package root.
  final String path;

  /// The package name.
  final String name;

  /// Absolute path of `lib/`.
  String get libPath => p.join(path, 'lib');

  /// Absolute path of the generated library `lib/<name>.dartnest.dart`.
  String get outputPath => p.join(libPath, '$name.dartnest.dart');

  /// [file] relative to the package root with `/` separators, the way
  /// diagnostics print paths on every platform.
  String display(String file) =>
      p.posix.joinAll(p.split(p.relative(file, from: path)));

  static String _name(File pubspec) {
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on YamlException catch (error) {
      throw CliFailure(
        CliExitCode.noInput,
        'Cannot read ${pubspec.path}: ${error.message}.',
      );
    } on FileSystemException catch (error) {
      throw CliFailure(
        CliExitCode.noInput,
        'Cannot read ${pubspec.path}: ${error.message}.',
      );
    }
    final name = document is YamlMap ? document['name'] : null;
    if (name is String && validName.hasMatch(name)) return name;
    throw CliFailure(
      CliExitCode.noInput,
      '${pubspec.path} has no valid package name '
      '(a "name:" in lowercase_with_underscores).',
    );
  }
}
```

Файл `packages/dartnest_cli/lib/dartnest_cli.dart` (barrel; Task 5 доповнює):

```dart
/// The command line tool of dartnest: `gen` and `gen --watch` write
/// `lib/<package>.dartnest.dart` from the annotations of a package, `init`
/// scaffolds a new application.
library;

export 'src/cli/cli_exit_code.dart';
export 'src/cli/cli_failure.dart';
export 'src/package/package_root.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/pubspec.yaml \
  packages/dartnest_cli/analysis_options.yaml \
  pubspec.yaml \
  packages/dartnest_cli/test/helpers/temp_dir.dart \
  packages/dartnest_cli/test/package_root_test.dart \
  packages/dartnest_cli/lib/src/cli/cli_exit_code.dart \
  packages/dartnest_cli/lib/src/cli/cli_failure.dart \
  packages/dartnest_cli/lib/src/package/package_root.dart \
  packages/dartnest_cli/lib/dartnest_cli.dart
git commit -m "feat(cli): add the dartnest_cli package and PackageRoot"
```

---

### Task 2: `PackageAnalysis`: analyzer у пам'яті й синтаксичні помилки

`PackageAnalysis` тримає одну `AnalysisContextCollection` над `lib/` на всю сесію (рішення 2): `changed` передає analyzer змінені шляхи, `syntaxProblems` парсить кожен файл і повертає помилки парсера (OP7, Review Focus 3), `libraries` резолвить бібліотеки й пропускає `part`-файли. `SyntaxProblem` друкується як діагностика генератора (`path:line:col: error: message [syntax_error]`) і сортується за `SourceLocation`.

Тут з'являються хелпери тимчасових пакетів (рішення 8): `WorkspacePackageConfig` пише `.dart_tool/package_config.json` з пакетами конфігурації тестового ізоляту, тож analyzer резолвить `package:dartnest_annotations` без `pub get` і мережі; `ShopSources` — маленький анотований пакет `shop` (сервіс `Clock`, контролер `TimeController`, `AppModule`), яким користуються Tasks 4–6.

**Files:**
- Create: `packages/dartnest_cli/lib/src/generate/syntax_problem.dart`
- Create: `packages/dartnest_cli/lib/src/generate/package_analysis.dart`
- Test: `packages/dartnest_cli/test/helpers/workspace_package_config.dart`
- Test: `packages/dartnest_cli/test/helpers/temp_package.dart`
- Test: `packages/dartnest_cli/test/helpers/shop_sources.dart`
- Test: `packages/dartnest_cli/test/package_analysis_test.dart`

**Interfaces:**
- Consumes: `PackageRoot` (Task 1), `TempDir` (Task 1); з `dartnest_generator` — `SourceLocation(path, line, column)` (`Comparable`, `toString()` = `path:line:column`).
- Produces:
  - `final class SyntaxProblem implements Comparable<SyntaxProblem> { const SyntaxProblem(SourceLocation location, String message); static const code = 'syntax_error'; }`.
  - `final class PackageAnalysis`: `PackageAnalysis(PackageRoot package)`, `List<String> sourceFiles()` (абсолютні шляхи `*.dart` у `lib/` без `*.dartnest.dart`, відсортовані), `Future<void> changed(Iterable<String> paths)`, `List<SyntaxProblem> syntaxProblems(List<String> files)` (відсортовані), `Future<List<LibraryElement>> libraries(List<String> files)`, `Future<void> dispose()`.
  - Хелпери: `WorkspacePackageConfig.write(String root, String name)`, `TempPackage.create(String name, [Map<String, String> files])` → `Future<TempPackage>` з `String name`, `TempDir dir`, `PackageRoot get root`; `ShopSources.output` (`'lib/shop.dartnest.dart'`), `.clock`, `.controller`, `.module`, `.moduleWithoutClock`, `.files` (шлях → вміст).

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/helpers/workspace_package_config.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Writes `.dart_tool/package_config.json` for a package outside the
/// workspace, so the analyzer resolves `package:dartnest`,
/// `package:dartnest_annotations` and the rest from this checkout without
/// `dart pub get` (tests do not touch the network).
abstract final class WorkspacePackageConfig {
  /// Writes the config of package [name] at [root]: every package of the
  /// test's own config (with absolute root URIs) plus [name] itself.
  static Future<void> write(String root, String name) async {
    final source = await Isolate.packageConfig;
    if (source == null) {
      throw StateError('The test isolate has no package config.');
    }
    final json = jsonDecode(File.fromUri(source).readAsStringSync());
    final entries = (json as Map<String, Object?>)['packages'] as List<Object?>;
    final packages = [
      for (final entry in entries.cast<Map<String, Object?>>())
        if (entry['name'] != name)
          {
            ...entry,
            'rootUri': '${source.resolve(entry['rootUri'] as String)}',
          },
      {
        'name': name,
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.8',
      },
    ];
    final file = File(p.join(root, '.dart_tool', 'package_config.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'configVersion': 2, 'packages': packages}),
    );
  }
}
```

Файл `packages/dartnest_cli/test/helpers/temp_package.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/src/package/package_root.dart';

import 'temp_dir.dart';
import 'workspace_package_config.dart';

/// A package in a [TempDir] that resolves against this workspace: a
/// `pubspec.yaml` named [name], a package config, an empty `lib/` and the
/// given files.
final class TempPackage {
  TempPackage._(this.name, this.dir);

  /// Creates the package with [files] (relative path → content).
  static Future<TempPackage> create(
    String name, [
    Map<String, String> files = const {},
  ]) async {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.8.0\n');
    Directory(dir.resolve('lib')).createSync();
    await WorkspacePackageConfig.write(dir.path, name);
    files.forEach(dir.write);
    return TempPackage._(name, dir);
  }

  /// The package name.
  final String name;

  /// The package directory.
  final TempDir dir;

  /// The package as the CLI opens it.
  PackageRoot get root => PackageRoot.open(dir.path);
}
```

Файл `packages/dartnest_cli/test/helpers/shop_sources.dart`:

```dart
/// Sources of a small annotated package `shop`: a clock service, a
/// controller that uses it and the root module.
abstract final class ShopSources {
  /// The generated library of `shop`.
  static const output = 'lib/shop.dartnest.dart';

  /// `lib/src/clock.dart`.
  static const clock = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Clock {
  DateTime now() => DateTime.utc(2026);
}
''';

  /// `lib/src/time_controller.dart`.
  static const controller = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'clock.dart';

@Controller('/time')
final class TimeController {
  TimeController(this.clock);

  final Clock clock;

  @Get()
  Map<String, String> now() => {'now': clock.now().toIso8601String()};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'clock.dart';
import 'time_controller.dart';

@Module(id: 'app', providers: [Clock], controllers: [TimeController])
final class AppModule {}
''';

  /// `lib/src/app_module.dart` without the clock: a `missing_provider`.
  static const moduleWithoutClock = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'time_controller.dart';

@Module(id: 'app', controllers: [TimeController])
final class AppModule {}
''';

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };
}
```

Файл `packages/dartnest_cli/test/package_analysis_test.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/src/generate/package_analysis.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

PackageAnalysis _open(TempPackage package) {
  final analysis = PackageAnalysis(package.root);
  addTearDown(analysis.dispose);
  return analysis;
}

void main() {
  test(
    'source files are the Dart files of lib/ except generated ones',
    () async {
      final package = await TempPackage.create('shop', {
        'lib/b.dart': '',
        'lib/a/z.dart': '',
        'lib/shop.dartnest.dart': '',
        'lib/notes.txt': '',
        'bin/main.dart': '',
      });
      final analysis = _open(package);

      expect(analysis.sourceFiles(), [
        package.dir.resolve('lib/a/z.dart'),
        package.dir.resolve('lib/b.dart'),
      ]);
    },
  );

  test('libraries are resolved and part files are skipped', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/money.dart': "part 'money_part.dart';\n",
      'lib/src/money_part.dart': "part of 'money.dart';\nclass Cents {}\n",
    });
    final analysis = _open(package);

    final libraries = await analysis.libraries(analysis.sourceFiles());

    expect(
      [for (final l in libraries) '${l.uri}'],
      [
        'package:shop/src/app_module.dart',
        'package:shop/src/clock.dart',
        'package:shop/src/money.dart',
        'package:shop/src/time_controller.dart',
      ],
    );
  });

  test('syntax errors are reported with a package-relative location', () async {
    final package = await TempPackage.create('shop', {
      'lib/src/broken.dart': 'class Broken {\n  int x = ;\n}\n',
      'lib/src/fine.dart': "import 'package:shop/shop.dartnest.dart';\n",
    });
    final analysis = _open(package);

    final problems = analysis.syntaxProblems(analysis.sourceFiles());

    expect(problems, hasLength(1));
    expect(
      problems.single.location,
      const SourceLocation('lib/src/broken.dart', 2, 11),
    );
    expect(
      '${problems.single}',
      matches(
        RegExp(r'^lib/src/broken\.dart:2:11: error: .+ \[syntax_error\]$'),
      ),
    );
  });

  test(
    'a change is seen after it is reported, without a new analysis',
    () async {
      final package = await TempPackage.create('shop', ShopSources.files);
      final analysis = _open(package);
      final file = package.dir.resolve('lib/src/clock.dart');
      await analysis.libraries(analysis.sourceFiles());

      File(file).writeAsStringSync('final class Watch {}\n');
      await analysis.changed([file]);
      final libraries = await analysis.libraries([file]);

      expect([for (final c in libraries.single.classes) c.name], ['Watch']);
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/package_analysis_test.dart`
Expected: FAIL: компіляція — `lib/src/generate/package_analysis.dart` не існує

- [ ] **Step 3: Write `SyntaxProblem` and `PackageAnalysis`**

`libraries` — єдиний рядок, що на analyzer 8.1.1 дає `experimental_member_use` (`ResolvedLibraryResult.element`); на 14.x — без попереджень, як у генераторі етапу 4.

Файл `packages/dartnest_cli/lib/src/generate/syntax_problem.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';

/// A syntax error in a source file of `lib/`; nothing is generated while
/// one exists.
///
/// Printed like a generator `Diagnostic`:
/// `path:line:column: error: message [syntax_error]`.
final class SyntaxProblem implements Comparable<SyntaxProblem> {
  /// Creates the problem.
  const SyntaxProblem(this.location, this.message);

  /// The code printed after the message.
  static const code = 'syntax_error';

  /// Where the error is; the path is relative to the package root.
  final SourceLocation location;

  /// The parser's message.
  final String message;

  /// Orders by location, then by message, so output is stable.
  @override
  int compareTo(SyntaxProblem other) {
    final byLocation = location.compareTo(other.location);
    return byLocation != 0 ? byLocation : message.compareTo(other.message);
  }

  @override
  String toString() => '$location: error: $message [$code]';
}
```

Файл `packages/dartnest_cli/lib/src/generate/package_analysis.dart`:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'syntax_problem.dart';

/// The analyzer's view of a package's `lib/`, kept in memory between
/// generations so that a later run re-reads only the files it is told
/// about.
final class PackageAnalysis {
  /// Opens the analysis of [package]'s `lib/`.
  PackageAnalysis(this.package)
    : _collection = AnalysisContextCollection(includedPaths: [package.libPath]);

  /// The analyzed package.
  final PackageRoot package;

  final AnalysisContextCollection _collection;

  /// Absolute paths of the Dart files of `lib/` except generated
  /// `*.dartnest.dart` files, sorted.
  List<String> sourceFiles() {
    final files = [
      for (final entity in Directory(
        package.libPath,
      ).listSync(recursive: true, followLinks: false))
        if (entity is File && _isSource(entity.path)) entity.path,
    ];
    return files..sort();
  }

  /// Tells the analyzer that [paths] were added, modified or removed, and
  /// waits until it has read them.
  Future<void> changed(Iterable<String> paths) async {
    for (final path in paths) {
      _collection.contextFor(path).changeFile(path);
    }
    for (final context in _collection.contexts) {
      await context.applyPendingFileChanges();
    }
  }

  /// The syntax errors of [files], sorted by location.
  List<SyntaxProblem> syntaxProblems(List<String> files) {
    final problems = [for (final file in files) ..._syntaxProblemsOf(file)];
    return problems..sort();
  }

  /// The resolved libraries among [files]; part files are skipped.
  ///
  /// Throws a [CliFailure] with [CliExitCode.noInput] for a file the
  /// analyzer cannot read.
  Future<List<LibraryElement>> libraries(List<String> files) async {
    final libraries = <LibraryElement>[];
    for (final file in files) {
      final session = _collection.contextFor(file).currentSession;
      switch (await session.getResolvedLibrary(file)) {
        case ResolvedLibraryResult(:final element):
          libraries.add(element);
        case NotLibraryButPartResult():
          continue;
        case final other:
          throw CliFailure(
            CliExitCode.noInput,
            'Cannot analyze ${package.display(file)}: ${other.runtimeType}.',
          );
      }
    }
    return libraries;
  }

  /// Releases the analyzer's resources.
  Future<void> dispose() => _collection.dispose();

  Iterable<SyntaxProblem> _syntaxProblemsOf(String file) {
    final session = _collection.contextFor(file).currentSession;
    final result = session.getParsedUnit(file);
    if (result is! ParsedUnitResult) return const [];
    return [
      for (final diagnostic in result.diagnostics)
        SyntaxProblem(
          _location(file, result, diagnostic.offset),
          diagnostic.message,
        ),
    ];
  }

  SourceLocation _location(String file, ParsedUnitResult unit, int offset) {
    final position = unit.lineInfo.getLocation(offset);
    return SourceLocation(
      package.display(file),
      position.lineNumber,
      position.columnNumber,
    );
  }

  static bool _isSource(String path) =>
      path.endsWith('.dart') && !path.endsWith('.dartnest.dart');
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+8: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/test/helpers/workspace_package_config.dart \
  packages/dartnest_cli/test/helpers/temp_package.dart \
  packages/dartnest_cli/test/helpers/shop_sources.dart \
  packages/dartnest_cli/test/package_analysis_test.dart \
  packages/dartnest_cli/lib/src/generate/syntax_problem.dart \
  packages/dartnest_cli/lib/src/generate/package_analysis.dart
git commit -m "feat(cli): keep the analysis of lib/ in memory and report syntax errors"
```

---

### Task 3: `OutputWriter`

Запис виходу за рішенням 4 і OP6: однаковий вміст не чіпається (`unchanged`, mtime не змінюється); файл без заголовка `LibraryWriter.header` ніколи не перезаписується й не видаляється (Review Focus 5); запис іде в `<file>.tmp` з `flush: true` і `renameSync`, тож читач ніколи не бачить напівфайлу; будь-яка помилка файлової системи — `CliFailure(CliExitCode.cannotCreate, 'Cannot write <path>: <os message>.')` (Review Focus 2). `writeFile` пише `FileUnit` генератора (з v1.1) і відмовляє шляхам поза пакетом.

**Files:**
- Create: `packages/dartnest_cli/lib/src/generate/write_outcome.dart`
- Create: `packages/dartnest_cli/lib/src/generate/output_writer.dart`
- Test: `packages/dartnest_cli/test/output_writer_test.dart`

**Interfaces:**
- Consumes: `PackageRoot`, `CliFailure`, `CliExitCode` (Task 1); `TempPackage`, `TempDir` (Tasks 1–2); з `dartnest_generator` — `LibraryWriter.header`, `FileUnit({path, contentType, content})`, `ContentType`.
- Produces:
  - `enum WriteOutcome { written, unchanged, deleted, none, kept }` (`none` — нічого не було й нема; `kept` — попередній вихід лишено через проблеми, ставить Task 4).
  - `final class OutputWriter`: `const OutputWriter(PackageRoot package)`, `WriteOutcome writeLibrary(String source)` (`written` / `unchanged`), `WriteOutcome deleteLibrary()` (`deleted` / `none`), `WriteOutcome writeFile(FileUnit unit)` (`written` / `unchanged`); усі кидають `CliFailure` з `cannotCreate`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/output_writer_test.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/src/cli/cli_exit_code.dart';
import 'package:dartnest_cli/src/cli/cli_failure.dart';
import 'package:dartnest_cli/src/generate/output_writer.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:dartnest_cli/src/package/package_root.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

const _output = 'lib/shop.dartnest.dart';

const _source = '${LibraryWriter.header}\n\nlibrary;\n';

(TempDir, OutputWriter) _package() {
  final dir = TempDir.create();
  dir.write('pubspec.yaml', 'name: shop\n');
  Directory(dir.resolve('lib')).createSync();
  return (dir, OutputWriter(PackageRoot.open(dir.path)));
}

Matcher _cannotCreate(String message) => throwsA(
  isA<CliFailure>()
      .having((f) => f.exitCode, 'exitCode', CliExitCode.cannotCreate)
      .having((f) => f.message, 'message', contains(message)),
);

void main() {
  test('the library is written once and then left untouched', () {
    final (dir, writer) = _package();

    expect(writer.writeLibrary(_source), WriteOutcome.written);
    final modified = File(dir.resolve(_output)).lastModifiedSync();
    expect(writer.writeLibrary(_source), WriteOutcome.unchanged);

    expect(dir.read(_output), _source);
    expect(File(dir.resolve(_output)).lastModifiedSync(), modified);
    expect(dir.exists('$_output.tmp'), isFalse);
  });

  test('a changed library replaces the old one', () {
    final (dir, writer) = _package();
    writer.writeLibrary(_source);

    expect(writer.writeLibrary('$_source// v2\n'), WriteOutcome.written);
    expect(dir.read(_output), '$_source// v2\n');
  });

  // Review Focus 5: a hand-written file at the generated path.
  test('a file the generator did not write is never replaced', () {
    final (dir, writer) = _package();
    dir.write(_output, '// my own code\n');

    expect(() => writer.writeLibrary(_source), _cannotCreate('not generated'));
    expect(writer.deleteLibrary, _cannotCreate('not generated'));
    expect(dir.read(_output), '// my own code\n');
  });

  test('a stale generated library is deleted', () {
    final (dir, writer) = _package();
    writer.writeLibrary(_source);

    expect(writer.deleteLibrary(), WriteOutcome.deleted);
    expect(dir.exists(_output), isFalse);
    expect(writer.deleteLibrary(), WriteOutcome.none);
  });

  // Review Focus 2: the output cannot be written.
  test('a path that cannot be written is a cannot-create failure', () {
    final (dir, writer) = _package();
    Directory(dir.resolve('$_output.tmp')).createSync();

    expect(
      () => writer.writeLibrary(_source),
      _cannotCreate('Cannot write $_output'),
    );

    Directory(dir.resolve('$_output.tmp')).deleteSync();
    Directory(dir.resolve(_output)).createSync();
    expect(
      () => writer.writeLibrary(_source),
      _cannotCreate('Cannot write $_output'),
    );
  });

  test('other generated files stay inside the package', () {
    final (dir, writer) = _package();
    const unit = FileUnit(
      path: 'doc/api/openapi.json',
      contentType: ContentType.json,
      content: '{}',
    );
    const escaping = FileUnit(
      path: 'doc/../../outside.json',
      contentType: ContentType.json,
      content: '{}',
    );

    expect(writer.writeFile(unit), WriteOutcome.written);
    expect(writer.writeFile(unit), WriteOutcome.unchanged);
    expect(dir.read('doc/api/openapi.json'), '{}');
    expect(() => writer.writeFile(escaping), _cannotCreate('outside'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/output_writer_test.dart`
Expected: FAIL: компіляція — `lib/src/generate/output_writer.dart` не існує

- [ ] **Step 3: Write `WriteOutcome` and `OutputWriter`**

Файл `packages/dartnest_cli/lib/src/generate/write_outcome.dart`:

```dart
/// What a generation did to the generated library on disk.
enum WriteOutcome {
  /// The library was written: it was missing or its content changed.
  written,

  /// The library already had the generated content; it was not touched.
  unchanged,

  /// The package has no annotations any more; the library was deleted.
  deleted,

  /// The package has no annotations and there is no library.
  none,

  /// The sources have problems; the library was left as it was.
  kept,
}
```

Файл `packages/dartnest_cli/lib/src/generate/output_writer.dart`:

```dart
import 'dart:io';

import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:path/path.dart' as p;

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'write_outcome.dart';

/// Writes the generator's output into a package: only when the content
/// changed, through a temporary file and a rename (a reader never sees a
/// half-written file), and never over a library the generator did not
/// write.
///
/// Every failure is a [CliFailure] with [CliExitCode.cannotCreate].
final class OutputWriter {
  /// Creates the writer for [package].
  const OutputWriter(this.package);

  /// The package written to.
  final PackageRoot package;

  /// Writes [source] to the package's generated library.
  WriteOutcome writeLibrary(String source) {
    final target = File(package.outputPath);
    final existing = _read(target);
    if (existing == source) return WriteOutcome.unchanged;
    if (existing != null) _checkGenerated(target, existing);
    _replace(target, source);
    return WriteOutcome.written;
  }

  /// Deletes the package's generated library, if there is one.
  WriteOutcome deleteLibrary() {
    final target = File(package.outputPath);
    final existing = _read(target);
    if (existing == null) return WriteOutcome.none;
    _checkGenerated(target, existing);
    try {
      target.deleteSync();
    } on FileSystemException catch (error) {
      throw _cannotWrite(target, error);
    }
    return WriteOutcome.deleted;
  }

  /// Writes [unit] at its path relative to the package root.
  WriteOutcome writeFile(FileUnit unit) {
    final segments = p.posix.split(p.posix.normalize(unit.path));
    if (p.posix.isAbsolute(unit.path) || segments.first == '..') {
      throw CliFailure(
        CliExitCode.cannotCreate,
        'Generated file "${unit.path}" is outside the package.',
      );
    }
    final target = File(p.joinAll([package.path, ...segments]));
    if (_read(target) == unit.content) return WriteOutcome.unchanged;
    _replace(target, unit.content);
    return WriteOutcome.written;
  }

  String? _read(File file) {
    try {
      return file.readAsStringSync();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      throw _cannotWrite(file, error);
    }
  }

  void _checkGenerated(File file, String content) {
    if (content.startsWith(LibraryWriter.header)) return;
    throw CliFailure(
      CliExitCode.cannotCreate,
      '${package.display(file.path)} was not generated by dartnest '
      '(no "${LibraryWriter.header}" header); rename it, the generator '
      'owns this path.',
    );
  }

  void _replace(File target, String content) {
    final temporary = File('${target.path}.tmp');
    try {
      target.parent.createSync(recursive: true);
      temporary.writeAsStringSync(content, flush: true);
      temporary.renameSync(target.path);
    } on FileSystemException catch (error) {
      if (temporary.existsSync()) temporary.deleteSync();
      throw _cannotWrite(target, error);
    }
  }

  CliFailure _cannotWrite(File file, FileSystemException error) => CliFailure(
    CliExitCode.cannotCreate,
    'Cannot write ${package.display(file.path)}: '
    '${error.osError?.message ?? error.message}.',
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+14: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/test/output_writer_test.dart \
  packages/dartnest_cli/lib/src/generate/write_outcome.dart \
  packages/dartnest_cli/lib/src/generate/output_writer.dart
git commit -m "feat(cli): write generated files only when they change"
```

---

### Task 4: `GenerationSession` і `GenerationReport`

`GenerationSession.run` — один прогін за рішенням 3; його ж викличе `--watch` (Task 6) і `dev` етапу 5b (OP10). Синтаксичні помилки або діагностики лишають попередній вихід (`WriteOutcome.kept`, OP5, Review Focus 3); пакет без модулів, injectable і контролерів видаляє згенерований файл (Review Focus 4); вихід не залежить від порядку створення файлів (Review Focus 7). Після запису чи видалення виходу сесія повідомляє analyzer, щоб наступний прогін бачив актуальний `lib/<pkg>.dartnest.dart`.

**Files:**
- Create: `packages/dartnest_cli/lib/src/generate/generation_report.dart`
- Create: `packages/dartnest_cli/lib/src/generate/generation_session.dart`
- Test: `packages/dartnest_cli/test/generation_session_test.dart`

**Interfaces:**
- Consumes: `PackageRoot` (Task 1), `PackageAnalysis`, `SyntaxProblem` (Task 2), `OutputWriter`, `WriteOutcome` (Task 3); з `dartnest_generator` — `PackageCollector(String packageName, String packageRoot).collect(List<LibraryElement>)` → `PackageModel`, `DartnestGenerator.generate(PackageModel)` → `GenerationResult` (`library`, `diagnostics`, `files`, `isSuccess`), `Diagnostic`.
- Produces:
  - `final class GenerationReport`: `const GenerationReport({required String output, required WriteOutcome outcome, required Duration elapsed, List<SyntaxProblem> syntaxProblems = const [], List<Diagnostic> diagnostics = const []})`, `bool hasProblems`, `List<String> problemLines` (синтаксичні, потім діагностики; кожне відсортоване). `output` — шлях виходу відносно кореня, з `/`.
  - `final class GenerationSession`: `GenerationSession(PackageRoot package, {DartnestGenerator generator = const DartnestGenerator.core()})`, `Future<GenerationReport> run({Iterable<String> changed = const []})` (кидає `CliFailure` з `cannotCreate`), `Future<void> close()`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/generation_session_test.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/src/generate/generation_report.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

const _module = 'lib/src/app_module.dart';

GenerationSession _open(TempPackage package) {
  final session = GenerationSession(package.root);
  addTearDown(session.close);
  return session;
}

/// Rewrites [path] of [package] and runs [session] with that change.
Future<GenerationReport> _change(
  GenerationSession session,
  TempPackage package,
  String path,
  String content,
) => session.run(changed: [package.dir.write(path, content)]);

void main() {
  test('the library is generated, then reported up to date', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);

    final first = await session.run();
    final generated = package.dir.read(ShopSources.output);
    final second = await session.run();

    expect(first.outcome, WriteOutcome.written);
    expect(first.output, ShopSources.output);
    expect(generated, startsWith(LibraryWriter.header));
    expect(generated, contains('dartnest.Module appModule()'));
    expect(second.outcome, WriteOutcome.unchanged);
    expect(package.dir.read(ShopSources.output), generated);
  });

  test('diagnostics keep the previous library', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();
    final generated = package.dir.read(ShopSources.output);

    final report = await _change(
      session,
      package,
      _module,
      ShopSources.moduleWithoutClock,
    );

    expect(report.outcome, WriteOutcome.kept);
    expect(report.hasProblems, isTrue);
    expect(report.problemLines, [
      'lib/src/time_controller.dart:7:23: error: No provider for Clock in '
          'module "app" (resolving: TimeController). [missing_provider]',
    ]);
    expect(package.dir.read(ShopSources.output), generated);
  });

  // Review Focus 3: a syntax error, e.g. a file saved half-way.
  test('syntax errors stop generation until they are fixed', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final broken = await _change(session, package, _module, 'class {');
    final fixed = await _change(session, package, _module, ShopSources.module);

    expect(broken.outcome, WriteOutcome.kept);
    expect(broken.diagnostics, isEmpty);
    expect(broken.problemLines, everyElement(startsWith('$_module:1:')));
    expect(fixed.outcome, WriteOutcome.unchanged);
    expect(fixed.hasProblems, isFalse);
  });

  // Review Focus 4: the last annotation is removed.
  test('a package without annotations has no generated library', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final changed = [
      for (final path in ShopSources.files.keys) package.dir.resolve(path),
    ];
    for (final path in changed) {
      File(path).deleteSync();
    }
    final first = await session.run(changed: changed);
    final second = await session.run();

    expect(first.outcome, WriteOutcome.deleted);
    expect(package.dir.exists(ShopSources.output), isFalse);
    expect(second.outcome, WriteOutcome.none);
  });

  // Review Focus 7: the file system lists files in any order.
  test('the output does not depend on the order files were created', () async {
    final forward = await TempPackage.create('shop', ShopSources.files);
    final backward = await TempPackage.create('shop', {
      for (final entry in ShopSources.files.entries.toList().reversed)
        entry.key: entry.value,
    });

    await _open(forward).run();
    await _open(backward).run();

    expect(
      backward.dir.read(ShopSources.output),
      forward.dir.read(ShopSources.output),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/generation_session_test.dart`
Expected: FAIL: компіляція — `lib/src/generate/generation_session.dart` не існує

- [ ] **Step 3: Write `GenerationReport` and `GenerationSession`**

Файл `packages/dartnest_cli/lib/src/generate/generation_report.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';

import 'syntax_problem.dart';
import 'write_outcome.dart';

/// The result of one generation: the problems found, what happened to the
/// generated library and how long it took.
final class GenerationReport {
  /// Creates the report.
  const GenerationReport({
    required this.output,
    required this.outcome,
    required this.elapsed,
    this.syntaxProblems = const [],
    this.diagnostics = const [],
  });

  /// The generated library, relative to the package root
  /// (`lib/shop.dartnest.dart`).
  final String output;

  /// What happened to [output].
  final WriteOutcome outcome;

  /// How long the generation took.
  final Duration elapsed;

  /// Syntax errors in `lib/`, sorted; the generator did not run.
  final List<SyntaxProblem> syntaxProblems;

  /// The generator's diagnostics, sorted.
  final List<Diagnostic> diagnostics;

  /// Whether the sources have problems ([outcome] is then
  /// [WriteOutcome.kept]).
  bool get hasProblems => syntaxProblems.isNotEmpty || diagnostics.isNotEmpty;

  /// Every problem as printed, one per line: syntax errors, then
  /// diagnostics.
  List<String> get problemLines => [
    for (final problem in syntaxProblems) '$problem',
    for (final diagnostic in diagnostics) '$diagnostic',
  ];
}
```

Файл `packages/dartnest_cli/lib/src/generate/generation_session.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';

import '../package/package_root.dart';
import 'generation_report.dart';
import 'output_writer.dart';
import 'package_analysis.dart';
import 'syntax_problem.dart';
import 'write_outcome.dart';

/// Generates one package again and again with the analyzer state kept in
/// memory: the first [run] resolves everything, later runs re-read only
/// the files they are told about. `gen`, `gen --watch` and `dev` drive it.
final class GenerationSession {
  /// Opens the session for [package], generating with [generator].
  GenerationSession(
    this.package, {
    this.generator = const DartnestGenerator.core(),
  }) : _analysis = PackageAnalysis(package),
       _writer = OutputWriter(package);

  /// The generated package.
  final PackageRoot package;

  /// The constructs that run.
  final DartnestGenerator generator;

  final PackageAnalysis _analysis;
  final OutputWriter _writer;

  /// Generates the package; [changed] lists the absolute paths added,
  /// modified or removed since the previous run of this session.
  ///
  /// Throws a `CliFailure` when an output file cannot be written.
  Future<GenerationReport> run({Iterable<String> changed = const []}) async {
    final stopwatch = Stopwatch()..start();
    await _analysis.changed(changed);
    final files = _analysis.sourceFiles();
    final syntaxProblems = _analysis.syntaxProblems(files);
    if (syntaxProblems.isNotEmpty) {
      return _report(stopwatch, WriteOutcome.kept, syntax: syntaxProblems);
    }
    final libraries = await _analysis.libraries(files);
    final model = PackageCollector(
      package.name,
      package.path,
    ).collect(libraries);
    if (_isEmpty(model)) {
      return _report(stopwatch, await _written(_writer.deleteLibrary()));
    }
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) {
      return _report(
        stopwatch,
        WriteOutcome.kept,
        diagnostics: result.diagnostics,
      );
    }
    for (final file in result.files) {
      _writer.writeFile(file);
    }
    return _report(stopwatch, await _written(_writer.writeLibrary(library)));
  }

  /// Releases the analyzer's resources; the session cannot run again.
  Future<void> close() => _analysis.dispose();

  Future<WriteOutcome> _written(WriteOutcome outcome) async {
    if (outcome == WriteOutcome.written || outcome == WriteOutcome.deleted) {
      await _analysis.changed([package.outputPath]);
    }
    return outcome;
  }

  GenerationReport _report(
    Stopwatch stopwatch,
    WriteOutcome outcome, {
    List<SyntaxProblem> syntax = const [],
    List<Diagnostic> diagnostics = const [],
  }) => GenerationReport(
    output: package.display(package.outputPath),
    outcome: outcome,
    elapsed: stopwatch.elapsed,
    syntaxProblems: syntax,
    diagnostics: diagnostics,
  );

  static bool _isEmpty(PackageModel model) =>
      model.modules.isEmpty &&
      model.injectables.isEmpty &&
      model.controllers.isEmpty;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+19: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/test/generation_session_test.dart \
  packages/dartnest_cli/lib/src/generate/generation_report.dart \
  packages/dartnest_cli/lib/src/generate/generation_session.dart
git commit -m "feat(cli): add GenerationSession"
```

---

### Task 5: `DartnestCli`, команда `gen`, `bin/dartnest_cli.dart`

Командний рядок за OP2, OP4 і рішеннями 5–6. `DartnestCli` — `CommandRunner<int>` з потоками `out`/`err` і генератором як параметрами (OP10), тож тести запускають його в процесі (`CliRun`), а `tool/dartnest.dart` користувача підставляє свої конструкти. `UsageException` (невідома команда, опція, зайвий аргумент) — повідомлення й usage у stderr, код `64` (Review Focus 9); `--help` — stdout і `0`. `ReportPrinter` друкує проблеми в stderr і результат у stdout; шляхи — з `/` (Review Focus 8). У цій задачі `gen` — один прогін; `--watch` додає Task 6.

**Files:**
- Create: `packages/dartnest_cli/lib/src/cli/report_printer.dart`
- Create: `packages/dartnest_cli/lib/src/cli/gen_command.dart`
- Create: `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart`
- Create: `packages/dartnest_cli/bin/dartnest_cli.dart`
- Modify: `packages/dartnest_cli/lib/dartnest_cli.dart`
- Test: `packages/dartnest_cli/test/helpers/cli_run.dart`
- Test: `packages/dartnest_cli/test/gen_command_test.dart`

**Interfaces:**
- Consumes: `CliExitCode`, `CliFailure`, `PackageRoot` (Task 1), `GenerationSession`, `GenerationReport`, `WriteOutcome`, `SyntaxProblem` (Tasks 2–4), `TempPackage`, `ShopSources` (Task 2); `package:args` (`CommandRunner`, `Command`, `UsageException`).
- Produces:
  - `final class ReportPrinter`: `const ReportPrinter(StringSink out, StringSink err)`, `void report(GenerationReport report)`.
  - `final class DartnestCli`: `DartnestCli({StringSink? out, StringSink? err, DartnestGenerator generator = const DartnestGenerator.core()})` (Task 6 додає `untilStopped`), `StringSink out`, `StringSink err`, `DartnestGenerator generator`, `Future<int> run(List<String> arguments)` (код виходу; не кидає `UsageException` і `CliFailure`).
  - `final class GenCommand extends Command<int>`: `GenCommand(DartnestCli cli)`; опція `--directory`/`-C` (за замовчуванням `.`).
  - `bin/dartnest_cli.dart`: `exitCode = await DartnestCli().run(arguments)`.
  - Barrel `package:dartnest_cli/dartnest_cli.dart` експортує `CliExitCode`, `CliFailure`, `DartnestCli`, `GenerationReport`, `GenerationSession`, `SyntaxProblem`, `WriteOutcome`, `PackageRoot`.
  - Хелпер `CliRun.run(List<String> arguments)` → `Future<CliRun>` з `int exitCode`, `String out`, `String err`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/helpers/cli_run.dart`:

```dart
import 'package:dartnest_cli/dartnest_cli.dart';

/// One in-process run of [DartnestCli] with what it printed.
final class CliRun {
  CliRun._(this.exitCode, this.out, this.err);

  /// Runs `dartnest_cli` with [arguments].
  static Future<CliRun> run(List<String> arguments) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await DartnestCli(out: out, err: err).run(arguments);
    return CliRun._(code, '$out', '$err');
  }

  /// The exit code.
  final int exitCode;

  /// What went to stdout.
  final String out;

  /// What went to stderr.
  final String err;
}
```

Файл `packages/dartnest_cli/test/gen_command_test.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/temp_package.dart';

Future<CliRun> _gen(TempPackage package) =>
    CliRun.run(['gen', '--directory', package.dir.path]);

void main() {
  test('gen writes the library and exits with 0', () async {
    final package = await TempPackage.create('shop', ShopSources.files);

    final first = await _gen(package);
    final second = await _gen(package);

    expect(first.exitCode, CliExitCode.success.code);
    expect(
      first.out,
      matches(RegExp(r'^Generated lib/shop\.dartnest\.dart in \d+ ms\.\n$')),
    );
    expect(package.dir.exists(ShopSources.output), isTrue);
    expect(second.exitCode, 0);
    expect(second.out, contains('lib/shop.dartnest.dart is up to date'));
  });

  test('diagnostics are printed one per line and exit with 1', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/app_module.dart': ShopSources.moduleWithoutClock,
    });

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.out, isEmpty);
    expect(
      run.err,
      'lib/src/time_controller.dart:7:23: error: No provider for Clock in '
      'module "app" (resolving: TimeController). [missing_provider]\n'
      '1 problem; lib/shop.dartnest.dart was not changed.\n',
    );
    expect(package.dir.exists(ShopSources.output), isFalse);
  });

  test('a syntax error is a problem too', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/clock.dart': 'final class Clock {',
    });

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.err, startsWith('lib/src/clock.dart:1:'));
    expect(run.err, contains('[syntax_error]'));
  });

  test('a package without annotations has nothing to generate', () async {
    final package = await TempPackage.create('shop', {
      'lib/shop.dart': 'int answer() => 42;\n',
    });

    final run = await _gen(package);

    expect(run.exitCode, 0);
    expect(run.out, 'No annotations in lib/; nothing to generate.\n');
  });

  test('a directory without a package exits with 66', () async {
    final dir = TempDir.create();

    final run = await CliRun.run(['gen', '-C', dir.path]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, startsWith('No pubspec.yaml in ${dir.path}'));
  });

  test('an output that cannot be written exits with 73', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    Directory(package.dir.resolve(ShopSources.output)).createSync();

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.cannotCreate.code);
    expect(run.err, startsWith('Cannot write lib/shop.dartnest.dart: '));
  });

  // Review Focus 9: every way the command line can be wrong.
  test('a wrong command line exits with 64 and prints usage', () async {
    final unknown = await CliRun.run(['generate']);
    final option = await CliRun.run(['gen', '--fast']);
    final positional = await CliRun.run(['gen', 'lib']);

    for (final run in [unknown, option, positional]) {
      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.err, contains('Usage: dartnest_cli'));
    }
    expect(positional.err, startsWith('gen takes no positional arguments.'));
  });

  test('help goes to stdout and exits with 0', () async {
    final top = await CliRun.run(['--help']);
    final gen = await CliRun.run(['gen', '--help']);

    expect(top.exitCode, 0);
    expect(top.out, contains('gen'));
    expect(gen.exitCode, 0);
    expect(gen.out, contains('--directory'));
  });

  // Review Focus 8: diagnostics print `/` on every platform.
  test('paths are printed with / separators', () async {
    final package = await TempPackage.create('shop');
    final nested = p.join(package.dir.path, 'lib', 'src', 'deep', 'a.dart');

    expect(package.root.display(nested), 'lib/src/deep/a.dart');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/gen_command_test.dart`
Expected: FAIL: компіляція — `DartnestCli` не існує

- [ ] **Step 3: Write the printer, the command, the runner and the executable**

Файл `packages/dartnest_cli/lib/src/cli/report_printer.dart` (Task 6 доповнює):

```dart
import '../generate/generation_report.dart';
import '../generate/write_outcome.dart';

/// Prints [GenerationReport]s: problems and their count to [err], the
/// outcome of a clean run to [out].
final class ReportPrinter {
  /// Creates the printer.
  const ReportPrinter(this.out, this.err);

  /// Where results go.
  final StringSink out;

  /// Where problems go.
  final StringSink err;

  /// Prints [report].
  void report(GenerationReport report) {
    if (report.hasProblems) {
      report.problemLines.forEach(err.writeln);
      final count = report.problemLines.length;
      err.writeln(
        '$count ${count == 1 ? 'problem' : 'problems'}; '
        '${report.output} was not changed.',
      );
      return;
    }
    final milliseconds = report.elapsed.inMilliseconds;
    out.writeln(switch (report.outcome) {
      WriteOutcome.written => 'Generated ${report.output} in $milliseconds ms.',
      WriteOutcome.unchanged =>
        '${report.output} is up to date ($milliseconds ms).',
      WriteOutcome.deleted =>
        'No annotations in lib/; deleted ${report.output}.',
      WriteOutcome.none => 'No annotations in lib/; nothing to generate.',
      WriteOutcome.kept => '${report.output} was not changed.',
    });
  }
}
```

Файл `packages/dartnest_cli/lib/src/cli/gen_command.dart` (Task 6 доповнює):

```dart
import 'package:args/command_runner.dart';

import '../generate/generation_session.dart';
import '../package/package_root.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `gen`: writes `lib/<package>.dartnest.dart` from the annotations of
/// `lib/`.
final class GenCommand extends Command<int> {
  /// Creates the command of [cli].
  GenCommand(this.cli) {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      valueHelp: 'path',
      help: 'The package to generate.',
    );
  }

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'gen';

  @override
  String get description =>
      'Generates lib/<package>.dartnest.dart from the annotations in lib/.';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('gen was not parsed.'));
    if (options.rest.isNotEmpty) {
      usageException('gen takes no positional arguments.');
    }
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final session = GenerationSession(package, generator: cli.generator);
    try {
      final report = await session.run();
      ReportPrinter(cli.out, cli.err).report(report);
      return report.hasProblems
          ? CliExitCode.problems.code
          : CliExitCode.success.code;
    } finally {
      await session.close();
    }
  }
}
```

Файл `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart` (Tasks 6 і 8 доповнюють):

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'gen_command.dart';

/// The `dartnest_cli` command line.
///
/// `bin/dartnest_cli.dart` runs it with the core constructs; a package
/// with constructs of its own runs it from `tool/dartnest.dart`:
/// `DartnestCli(generator: DartnestGenerator([...])).run(arguments)`.
final class DartnestCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default) and `gen` runs [generator].
  DartnestCli({
    StringSink? out,
    StringSink? err,
    this.generator = const DartnestGenerator.core(),
  }) : out = out ?? stdout,
       err = err ?? stderr;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final DartnestGenerator generator;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)..addCommand(GenCommand(this));
    try {
      return await runner.run(arguments) ?? CliExitCode.success.code;
    } on UsageException catch (error) {
      err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return CliExitCode.usage.code;
    } on CliFailure catch (failure) {
      err.writeln(failure.message);
      return failure.exitCode.code;
    }
  }
}

final class _Runner extends CommandRunner<int> {
  _Runner(this._out)
    : super('dartnest_cli', 'Generates and scaffolds dartnest applications.');

  final StringSink _out;

  @override
  void printUsage() => _out.writeln(usage);
}
```

Файл `packages/dartnest_cli/bin/dartnest_cli.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';

/// Runs `dartnest_cli` with the core constructs.
Future<void> main(List<String> arguments) async {
  exitCode = await DartnestCli().run(arguments);
}
```

Файл `packages/dartnest_cli/lib/dartnest_cli.dart` (повний файл):

```dart
/// The command line tool of dartnest: `gen` and `gen --watch` write
/// `lib/<package>.dartnest.dart` from the annotations of a package, `init`
/// scaffolds a new application.
///
/// [DartnestCli] is the command line itself; [GenerationSession] is the
/// generation it drives, kept in memory between runs, for tools that
/// regenerate on their own schedule.
library;

export 'src/cli/cli_exit_code.dart';
export 'src/cli/cli_failure.dart';
export 'src/cli/dartnest_cli.dart';
export 'src/generate/generation_report.dart';
export 'src/generate/generation_session.dart';
export 'src/generate/syntax_problem.dart';
export 'src/generate/write_outcome.dart';
export 'src/package/package_root.dart';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+28: All tests passed!`

- [ ] **Step 5: Check the executable on the generator's golden fixture**

Вихід CLI для фікстури етапу 4 мусить збігатися з її golden байт-у-байт (Global Constraints), тож `gen` нічого не переписує:

Run: `cd packages/dartnest_cli && dart run dartnest_cli gen --directory ../dartnest_generator/test/fixtures/users_app`
Expected: `lib/users_app.dartnest.dart is up to date`, exit code 0

Run: `cd packages/dartnest_cli && dart run dartnest_cli gen --directory /nonexistent; echo "exit $?"`
Expected: `No pubspec.yaml in /nonexistent`, `exit 66`

Run: `git status --porcelain packages/dartnest_generator`
Expected: порожній вивід

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest_cli/test/helpers/cli_run.dart \
  packages/dartnest_cli/test/gen_command_test.dart \
  packages/dartnest_cli/lib/src/cli/report_printer.dart \
  packages/dartnest_cli/lib/src/cli/gen_command.dart \
  packages/dartnest_cli/lib/src/cli/dartnest_cli.dart \
  packages/dartnest_cli/bin/dartnest_cli.dart \
  packages/dartnest_cli/lib/dartnest_cli.dart
git commit -m "feat(cli): add the gen command"
```

---

### Task 6: `gen --watch`: `WatchLoop`

Watch за OP8 і рішенням 7. `WatchLoop` підписується на події до першого прогону, збирає шляхи `.dart` у `lib/` (без `*.dartnest.dart`) у відсортовану множину, після 100 мс тиші запускає один `session.run(changed: ...)`; прогони йдуть строго один за одним, зміни під час прогону потрапляють у наступний (Review Focus 6). `CliFailure` (наприклад, вихід не записується) друкується, і watch триває; інші винятки не ловляться. `DartnestCli` отримує `untilStopped` — за замовчуванням перший `SIGINT`; тести передають власний future.

`watch_loop_test.dart` керує подіями через `FakeWatcher`; `gen_watch_test.dart` — тест роадмапу «зміна файлу без перезапуску» на справжньому `DirectoryWatcher`: `gen --watch` у процесі, зміна файлу, новий вихід, зупинка, код `0`.

**Files:**
- Create: `packages/dartnest_cli/lib/src/watch/watch_loop.dart`
- Modify: `packages/dartnest_cli/lib/src/cli/report_printer.dart`
- Modify: `packages/dartnest_cli/lib/src/cli/gen_command.dart`
- Modify: `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart`
- Test: `packages/dartnest_cli/test/helpers/line_sink.dart`
- Test: `packages/dartnest_cli/test/helpers/fake_watcher.dart`
- Test: `packages/dartnest_cli/test/watch_loop_test.dart`
- Test: `packages/dartnest_cli/test/gen_watch_test.dart`

**Interfaces:**
- Consumes: `GenerationSession`, `GenerationReport` (Task 4), `ReportPrinter`, `DartnestCli`, `GenCommand` (Task 5), `CliFailure` (Task 1), `TempPackage`, `ShopSources` (Task 2); `package:watcher` (`Watcher`, `DirectoryWatcher`, `WatchEvent`, `ChangeType`).
- Produces:
  - `final class WatchLoop` (внутрішній, не в barrel): `WatchLoop(GenerationSession session, ReportPrinter printer, {Duration debounce = defaultDebounce})`, `static const defaultDebounce = Duration(milliseconds: 100)`, `Future<void> run(Watcher watcher, Future<void> stop)`.
  - `ReportPrinter.watching(String directory)` — рядок `Watching <directory> for changes; press Ctrl+C to stop.`
  - `DartnestCli({..., Future<void> Function()? untilStopped})`, поле `Future<void> Function() untilStopped`.
  - Прапорець `gen --watch`/`-w`.
  - Хелпери: `LineSink implements StringSink` (`List<String> lines`, `Future<String> next({Duration timeout})`, `Future<List<String>> after(Duration quiet)`), `FakeWatcher(String path)` з `void modify(String file)`.

- [ ] **Step 1: Write the failing tests**

Файл `packages/dartnest_cli/test/helpers/line_sink.dart`:

```dart
import 'dart:async';

/// A [StringSink] that records complete lines and lets a test wait for the
/// next one.
final class LineSink implements StringSink {
  final _lines = <String>[];
  final _partial = StringBuffer();
  var _read = 0;
  Completer<void>? _arrived;

  /// Every complete line so far.
  List<String> get lines => List.unmodifiable(_lines);

  /// The next line not returned before, waiting up to [timeout] for it.
  Future<String> next({Duration timeout = const Duration(seconds: 30)}) async {
    while (_read == _lines.length) {
      await (_arrived ??= Completer<void>()).future.timeout(timeout);
    }
    return _lines[_read++];
  }

  /// Waits [quiet] and returns the lines that arrived meanwhile.
  Future<List<String>> after(Duration quiet) async {
    final start = _lines.length;
    await Future<void>.delayed(quiet);
    _read = _lines.length;
    return _lines.sublist(start);
  }

  @override
  void write(Object? object) {
    _partial.write(object);
    final text = '$_partial';
    final end = text.lastIndexOf('\n');
    if (end < 0) return;
    _partial
      ..clear()
      ..write(text.substring(end + 1));
    _lines.addAll(text.substring(0, end).split('\n'));
    _arrived?.complete();
    _arrived = null;
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}
```

Файл `packages/dartnest_cli/test/helpers/fake_watcher.dart`:

```dart
import 'dart:async';

import 'package:watcher/watcher.dart';

/// A [Watcher] whose events the test sends.
final class FakeWatcher implements Watcher {
  /// Creates the watcher of directory [path].
  FakeWatcher(this.path);

  final _events = StreamController<WatchEvent>.broadcast();

  @override
  final String path;

  @override
  Stream<WatchEvent> get events => _events.stream;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready => Future.value();

  /// Reports that [file] was modified.
  void modify(String file) => _events.add(WatchEvent(ChangeType.MODIFY, file));
}
```

Файл `packages/dartnest_cli/test/watch_loop_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:dartnest_cli/src/cli/report_printer.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:dartnest_cli/src/watch/watch_loop.dart';
import 'package:test/test.dart';

import 'helpers/fake_watcher.dart';
import 'helpers/line_sink.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

const _quiet = Duration(milliseconds: 500);

final _generated = RegExp(r'^Generated lib/shop\.dartnest\.dart in \d+ ms\.$');

/// A running [WatchLoop] over a fresh `shop` package.
final class _Loop {
  _Loop._(this.package, this.watcher, this.lines, this._stop, this._done);

  static Future<_Loop> start() async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = GenerationSession(package.root);
    final watcher = FakeWatcher(package.dir.resolve('lib'));
    final lines = LineSink();
    final stop = Completer<void>();
    final done = WatchLoop(
      session,
      ReportPrinter(lines, lines),
    ).run(watcher, stop.future);
    final loop = _Loop._(package, watcher, lines, stop, done);
    addTearDown(() async {
      await loop.stop();
      await session.close();
    });
    expect(await lines.next(), matches(_generated));
    expect(
      await lines.next(),
      'Watching lib/ for changes; press Ctrl+C to stop.',
    );
    return loop;
  }

  final TempPackage package;
  final FakeWatcher watcher;
  final LineSink lines;
  final Completer<void> _stop;
  final Future<void> _done;

  /// Writes [content] to [path] and reports it [times] times.
  void change(String path, String content, {int times = 1}) {
    final file = package.dir.write(path, content);
    for (var i = 0; i < times; i++) {
      watcher.modify(file);
    }
  }

  Future<void> stop() {
    if (!_stop.isCompleted) _stop.complete();
    return _done;
  }
}

void main() {
  // Review Focus 6: an editor's save is a storm of events.
  test('a burst of events gives one run', () async {
    final loop = await _Loop.start();

    loop.change(
      'lib/src/time_controller.dart',
      ShopSources.controller.replaceFirst("@Get()", "@Get('/now')"),
      times: 5,
    );

    expect(await loop.lines.after(_quiet), [matches(_generated)]);
    expect(loop.package.dir.read(ShopSources.output), contains("'/now'"));
  });

  test('its own output and other files do not start a run', () async {
    final loop = await _Loop.start();

    loop.watcher
      ..modify(loop.package.dir.resolve(ShopSources.output))
      ..modify(loop.package.dir.resolve('lib/notes.txt'));

    expect(await loop.lines.after(_quiet), isEmpty);
  });

  test('a problem is reported and the next change recovers', () async {
    final loop = await _Loop.start();

    loop.change('lib/src/app_module.dart', ShopSources.moduleWithoutClock);
    expect(await loop.lines.next(), endsWith('[missing_provider]'));
    expect(
      await loop.lines.next(),
      '1 problem; lib/shop.dartnest.dart was not changed.',
    );

    loop.change('lib/src/app_module.dart', ShopSources.module);
    expect(await loop.lines.next(), contains('is up to date'));
  });

  test('a failure to write is reported and watching goes on', () async {
    final loop = await _Loop.start();
    final output = loop.package.dir.resolve(ShopSources.output);
    File(output).deleteSync();
    Directory(output).createSync();

    loop.change('lib/src/clock.dart', '${ShopSources.clock}// v2\n');
    expect(
      await loop.lines.next(),
      startsWith('Cannot write lib/shop.dartnest.dart: '),
    );

    Directory(output).deleteSync();
    loop.change('lib/src/clock.dart', '${ShopSources.clock}// v3\n');
    expect(await loop.lines.next(), matches(_generated));
  });
}
```

Файл `packages/dartnest_cli/test/gen_watch_test.dart`:

```dart
import 'dart:async';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/line_sink.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

void main() {
  // The roadmap's "file change without restart" test, on the real file
  // system watcher.
  test('gen --watch regenerates on a change until stopped', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final lines = LineSink();
    final stop = Completer<void>();
    final exitCode = DartnestCli(
      out: lines,
      err: lines,
      untilStopped: () => stop.future,
    ).run(['gen', '--watch', '--directory', package.dir.path]);

    expect(await lines.next(), startsWith('Generated lib/shop.dartnest.dart'));
    expect(await lines.next(), startsWith('Watching lib/ for changes'));
    package.dir.write(
      'lib/src/time_controller.dart',
      ShopSources.controller.replaceFirst("@Get()", "@Get('/now')"),
    );
    expect(await lines.next(), startsWith('Generated lib/shop.dartnest.dart'));
    expect(package.dir.read(ShopSources.output), contains("'/now'"));

    stop.complete();
    expect(await exitCode, CliExitCode.success.code);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/dartnest_cli && dart test test/watch_loop_test.dart test/gen_watch_test.dart`
Expected: FAIL: компіляція — `lib/src/watch/watch_loop.dart` не існує, `DartnestCli` не має `untilStopped`

- [ ] **Step 3: Write `WatchLoop` and wire `--watch`**

Файл `packages/dartnest_cli/lib/src/watch/watch_loop.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../cli/cli_failure.dart';
import '../cli/report_printer.dart';
import '../generate/generation_session.dart';

/// Regenerates a package whenever its `lib/` changes, until stopped.
///
/// Events are debounced: a burst (an editor saving through a temporary
/// file, a branch switch) gives one run with every changed path. Runs never
/// overlap; changes during a run go into the next one. Generated
/// `*.dartnest.dart` files (the session's own output) and non-Dart files
/// are ignored. A [CliFailure] of a run is printed and watching goes on;
/// any other failure ends the process.
final class WatchLoop {
  /// Creates the loop over [session], printing through [printer].
  WatchLoop(this.session, this.printer, {this.debounce = defaultDebounce});

  /// How long the loop waits after the last event before it runs.
  static const defaultDebounce = Duration(milliseconds: 100);

  /// The generation that runs.
  final GenerationSession session;

  /// Prints every run.
  final ReportPrinter printer;

  /// The quiet time after the last event that starts a run.
  final Duration debounce;

  final _pending = SplayTreeSet<String>();
  Timer? _timer;
  Future<void> _runs = Future.value();

  /// Generates once, then once per batch of [watcher] events, until [stop]
  /// completes; returns when the last run has finished.
  Future<void> run(Watcher watcher, Future<void> stop) async {
    final subscription = watcher.events.where(_isSource).listen(_add);
    await watcher.ready;
    _runs = _generate(
      const [],
    ).then((_) => printer.watching(session.package.display(watcher.path)));
    await stop;
    await subscription.cancel();
    _timer?.cancel();
    await _runs;
  }

  void _add(WatchEvent event) {
    _pending.add(p.normalize(p.absolute(event.path)));
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    final changed = _pending.toList();
    _pending.clear();
    _runs = _runs.then((_) => _generate(changed));
  }

  Future<void> _generate(List<String> changed) async {
    try {
      printer.report(await session.run(changed: changed));
    } on CliFailure catch (failure) {
      printer.err.writeln(failure.message);
    }
  }

  static bool _isSource(WatchEvent event) =>
      event.path.endsWith('.dart') && !event.path.endsWith('.dartnest.dart');
}
```

Файл `packages/dartnest_cli/lib/src/cli/report_printer.dart` (повний файл; новий метод — `watching`):

```dart
import '../generate/generation_report.dart';
import '../generate/write_outcome.dart';

/// Prints [GenerationReport]s: problems and their count to [err], the
/// outcome of a clean run to [out].
final class ReportPrinter {
  /// Creates the printer.
  const ReportPrinter(this.out, this.err);

  /// Where results go.
  final StringSink out;

  /// Where problems go.
  final StringSink err;

  /// Prints [report].
  void report(GenerationReport report) {
    if (report.hasProblems) {
      report.problemLines.forEach(err.writeln);
      final count = report.problemLines.length;
      err.writeln(
        '$count ${count == 1 ? 'problem' : 'problems'}; '
        '${report.output} was not changed.',
      );
      return;
    }
    final milliseconds = report.elapsed.inMilliseconds;
    out.writeln(switch (report.outcome) {
      WriteOutcome.written => 'Generated ${report.output} in $milliseconds ms.',
      WriteOutcome.unchanged =>
        '${report.output} is up to date ($milliseconds ms).',
      WriteOutcome.deleted =>
        'No annotations in lib/; deleted ${report.output}.',
      WriteOutcome.none => 'No annotations in lib/; nothing to generate.',
      WriteOutcome.kept => '${report.output} was not changed.',
    });
  }

  /// Prints that [directory] (relative to the package root) is watched.
  void watching(String directory) =>
      out.writeln('Watching $directory/ for changes; press Ctrl+C to stop.');
}
```

Файл `packages/dartnest_cli/lib/src/cli/gen_command.dart` (повний файл; нове — `--watch`, `_once`, `_watch`):

```dart
import 'package:args/command_runner.dart';
import 'package:watcher/watcher.dart';

import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `gen`: writes `lib/<package>.dartnest.dart` from the annotations of
/// `lib/`, once or on every change (`--watch`).
final class GenCommand extends Command<int> {
  /// Creates the command of [cli].
  GenCommand(this.cli) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'The package to generate.',
      )
      ..addFlag(
        'watch',
        abbr: 'w',
        negatable: false,
        help: 'Regenerate on every change of lib/ until Ctrl+C.',
      );
  }

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'gen';

  @override
  String get description =>
      'Generates lib/<package>.dartnest.dart from the annotations in lib/.';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('gen was not parsed.'));
    if (options.rest.isNotEmpty) {
      usageException('gen takes no positional arguments.');
    }
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final session = GenerationSession(package, generator: cli.generator);
    final printer = ReportPrinter(cli.out, cli.err);
    try {
      return options.flag('watch')
          ? await _watch(session, printer)
          : await _once(session, printer);
    } finally {
      await session.close();
    }
  }

  Future<int> _once(GenerationSession session, ReportPrinter printer) async {
    final report = await session.run();
    printer.report(report);
    return report.hasProblems
        ? CliExitCode.problems.code
        : CliExitCode.success.code;
  }

  Future<int> _watch(GenerationSession session, ReportPrinter printer) async {
    final watcher = DirectoryWatcher(session.package.libPath);
    await WatchLoop(session, printer).run(watcher, cli.untilStopped());
    return CliExitCode.success.code;
  }
}
```

Файл `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart` (повний файл; нове — `untilStopped`):

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'gen_command.dart';

/// The `dartnest_cli` command line.
///
/// `bin/dartnest_cli.dart` runs it with the core constructs; a package
/// with constructs of its own runs it from `tool/dartnest.dart`:
/// `DartnestCli(generator: DartnestGenerator([...])).run(arguments)`.
final class DartnestCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default), `gen` runs [generator] and `gen --watch` stops
  /// when [untilStopped] completes (the first Ctrl+C by default).
  DartnestCli({
    StringSink? out,
    StringSink? err,
    this.generator = const DartnestGenerator.core(),
    Future<void> Function()? untilStopped,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       untilStopped = untilStopped ?? _interrupted;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final DartnestGenerator generator;

  /// Called when `gen --watch` starts; watching ends when the future
  /// completes.
  final Future<void> Function() untilStopped;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)..addCommand(GenCommand(this));
    try {
      return await runner.run(arguments) ?? CliExitCode.success.code;
    } on UsageException catch (error) {
      err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return CliExitCode.usage.code;
    } on CliFailure catch (failure) {
      err.writeln(failure.message);
      return failure.exitCode.code;
    }
  }

  static Future<void> _interrupted() => ProcessSignal.sigint.watch().first;
}

final class _Runner extends CommandRunner<int> {
  _Runner(this._out)
    : super('dartnest_cli', 'Generates and scaffolds dartnest applications.');

  final StringSink _out;

  @override
  void printUsage() => _out.writeln(usage);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+33: All tests passed!`

Запустити ще двічі: watch-тести залежать від часу, флейк тут — дефект.

Run: `cd packages/dartnest_cli && dart test`
Expected: `+33: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/test/helpers/line_sink.dart \
  packages/dartnest_cli/test/helpers/fake_watcher.dart \
  packages/dartnest_cli/test/watch_loop_test.dart \
  packages/dartnest_cli/test/gen_watch_test.dart \
  packages/dartnest_cli/lib/src/watch/watch_loop.dart \
  packages/dartnest_cli/lib/src/cli/report_printer.dart \
  packages/dartnest_cli/lib/src/cli/gen_command.dart \
  packages/dartnest_cli/lib/src/cli/dartnest_cli.dart
git commit -m "feat(cli): add gen --watch"
```

---

### Task 7: Бенчмарк 200 файлів

Пороги роадмапу як `expect` (OP11): холодний прогін `GenerationSession` (створення сесії, резолв, генерація, запис) < 10 с і прогін після зміни одного контролера < 1 с на пакеті з 201 бібліотеки (50 фіч × репозиторій, сервіс, контролер, модуль + `lib/app.dart`). Тест живе в `benchmark/`, тож звичайний `dart test` (тека `test/`) його не запускає, а `dart test benchmark` вимірює без конкуренції з іншими тестами. Тест друкує виміряні часи.

**Files:**
- Create: `packages/dartnest_cli/benchmark/benchmark_sources.dart`
- Test: `packages/dartnest_cli/benchmark/generation_benchmark_test.dart`

**Interfaces:**
- Consumes: `GenerationSession`, `GenerationReport`, `WriteOutcome` (Task 4), `PackageRoot` (Task 1); хелпери `TempPackage` (Task 2).
- Produces: `BenchmarkSources.files(int features)` → `Map<String, String>`, `BenchmarkSources.controllerPath(int i)`, `BenchmarkSources.changedController(int i)`; команда `cd packages/dartnest_cli && dart test benchmark` (Task 9 вносить її в `CLAUDE.md`).

- [ ] **Step 1: Write the benchmark**

Файл `packages/dartnest_cli/benchmark/generation_benchmark_test.dart`:

```dart
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:test/test.dart';

import 'benchmark_sources.dart';
import '../test/helpers/temp_package.dart';

void main() {
  // The roadmap's targets: a cold run under 10 s and an incremental run
  // under 1 s on a package of about 200 files.
  test('201 libraries: cold run under 10 s, a change under 1 s', () async {
    final package = await TempPackage.create(
      'bench',
      BenchmarkSources.files(50),
    );
    final cold = Stopwatch()..start();
    final session = GenerationSession(package.root);
    addTearDown(session.close);
    final first = await session.run();
    cold.stop();
    final file = package.dir.write(
      BenchmarkSources.controllerPath(7),
      BenchmarkSources.changedController(7),
    );
    final change = await session.run(changed: [file]);
    final timings =
        'cold ${cold.elapsedMilliseconds} ms, '
        'change ${change.elapsed.inMilliseconds} ms';

    expect(
      first.outcome,
      WriteOutcome.written,
      reason: '${first.problemLines}',
    );
    expect(change.outcome, WriteOutcome.written);
    expect(package.dir.read('lib/bench.dartnest.dart'), contains("'/v2'"));
    expect(
      cold.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: timings,
    );
    expect(
      change.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: timings,
    );
    printOnFailure(timings);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/dartnest_cli && dart test benchmark`
Expected: FAIL: компіляція — `benchmark_sources.dart` не існує

- [ ] **Step 3: Write the generated sources**

Файл `packages/dartnest_cli/benchmark/benchmark_sources.dart`:

```dart
/// A generated annotated package of `4 * features + 1` libraries: per
/// feature a repository, a service, a controller and a module, plus the
/// root module that imports every feature.
abstract final class BenchmarkSources {
  /// The files of the package (relative path → content).
  static Map<String, String> files(int features) => {
    for (var i = 0; i < features; i++) ..._feature(i),
    'lib/app.dart': _root(features),
  };

  /// The controller of feature [i] with one more route.
  static String changedController(int i) =>
      _controller(i).replaceFirst('@Get()', "@Get('/v2')");

  /// The path of feature [i]'s controller.
  static String controllerPath(int i) => 'lib/src/f$i/controller.dart';

  static Map<String, String> _feature(int i) => {
    'lib/src/f$i/repository.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Repository$i {
  List<String> all() => ['item $i'];
}
''',
    'lib/src/f$i/service.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'repository.dart';

@Injectable()
final class Service$i {
  Service$i(this.repository);

  final Repository$i repository;

  List<String> list() => repository.all();
}
''',
    controllerPath(i): _controller(i),
    'lib/src/f$i/module.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'controller.dart';
import 'repository.dart';
import 'service.dart';

@Module(
  id: 'f$i',
  providers: [Repository$i, Service$i],
  controllers: [Feature${i}Controller],
)
final class Feature${i}Module {}
''',
  };

  static String _controller(int i) =>
      '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'service.dart';

@Controller('/f$i')
final class Feature${i}Controller {
  Feature${i}Controller(this.service);

  final Service$i service;

  @Get()
  List<String> list() => service.list();

  @Get('/:id')
  Map<String, Object?> one(@Param('id') int id) => {'id': id};
}
''';

  static String _root(int features) {
    final imports = [
      for (var i = 0; i < features; i++) "import 'src/f$i/module.dart';",
    ];
    final modules = [for (var i = 0; i < features; i++) 'Feature${i}Module'];
    return '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

${imports.join('\n')}

@Module(id: 'app', imports: [${modules.join(', ')}])
final class AppModule {}
''';
  }
}
```

- [ ] **Step 4: Run the benchmark and the suite**

Run: `cd packages/dartnest_cli && dart test benchmark`
Expected: `+1: All tests passed!`; надруковані часи — близько 2.5 с і 0.4 с (OP11)

Run: `cd packages/dartnest_cli && dart test`
Expected: `+33: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/benchmark/generation_benchmark_test.dart \
  packages/dartnest_cli/benchmark/benchmark_sources.dart
git commit -m "test(cli): benchmark generation on 200 files"
```

---

### Task 8: `init`

`init <directory>` за OP9: новий пакет у новій або порожній теці, ім'я пакета — ім'я теки (невалідне ім'я — `64`, непорожня тека — `73`). Шаблон — п'ять файлів, найменший застосунок на анотаціях: `HelloService`, `HelloController` (`GET /hello?name=`), `AppModule`, `bin/server.dart` з `IoAdapter`. Головний тест створює пакет, пише йому конфігурацію workspace, запускає `gen` і аналізує результат analyzer-ом без помилок і попереджень — тобто шаблон компілюється разом зі згенерованим кодом.

**Files:**
- Create: `packages/dartnest_cli/lib/src/init/project_template.dart`
- Create: `packages/dartnest_cli/lib/src/init/project_scaffold.dart`
- Create: `packages/dartnest_cli/lib/src/cli/init_command.dart`
- Modify: `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart`
- Test: `packages/dartnest_cli/test/init_command_test.dart`

**Interfaces:**
- Consumes: `DartnestCli` (Tasks 5–6), `CliFailure`, `CliExitCode`, `PackageRoot.validName` (Task 1); хелпери `CliRun` (Task 5), `TempDir` (Task 1), `WorkspacePackageConfig` (Task 2).
- Produces:
  - `abstract final class ProjectTemplate`: `static const dartnestVersion = '^0.1.0'`, `static Map<String, String> files(String name)` (шлях → вміст, ключі відсортовані).
  - `final class ProjectScaffold`: `ProjectScaffold(String directory)`, `String directory` (абсолютний), `String name`, `List<String> write()` (відносні шляхи записаних файлів; кидає `CliFailure`).
  - `final class InitCommand extends Command<int>`: `InitCommand(DartnestCli cli)`; `dartnest_cli init <directory>`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/init_command_test.dart`:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

/// Errors and warnings of the Dart files of [root]'s `lib/` and `bin/`.
Future<List<String>> _analyze(String root) async {
  final collection = AnalysisContextCollection(includedPaths: [root]);
  addTearDown(collection.dispose);
  final files = [
    for (final directory in ['lib', 'bin'])
      for (final entity in Directory(
        '$root/$directory',
      ).listSync(recursive: true))
        if (entity.path.endsWith('.dart')) entity.path,
  ];
  return [
    for (final file in files)
      if (await collection.contextFor(file).currentSession.getErrors(file)
          case final ErrorsResult result)
        for (final diagnostic in result.diagnostics)
          if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.INFO)
            '$file: ${diagnostic.message}',
  ];
}

void main() {
  test('init writes an application that generates and analyzes', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_app');

    final init = await CliRun.run(['init', target]);
    await WorkspacePackageConfig.write(target, 'my_app');
    final gen = await CliRun.run(['gen', '-C', target]);

    expect(init.exitCode, 0, reason: init.err);
    expect(init.out, startsWith('Created package my_app in $target:\n'));
    expect(init.out, contains('  dart run dartnest_cli gen\n'));
    expect(dir.read('my_app/pubspec.yaml'), contains('name: my_app\n'));
    expect(gen.exitCode, 0, reason: gen.err);
    expect(dir.exists('my_app/lib/my_app.dartnest.dart'), isTrue);
    expect(await _analyze(target), isEmpty);
  });

  test('init refuses a directory that is not empty', () async {
    final dir = TempDir.create();
    dir.write('my_app/notes.txt', 'mine');

    final run = await CliRun.run(['init', dir.resolve('my_app')]);

    expect(run.exitCode, CliExitCode.cannotCreate.code);
    expect(run.err, contains('is not an empty directory'));
    expect(dir.exists('my_app/pubspec.yaml'), isFalse);
  });

  test('init needs one directory with a package name', () async {
    final dir = TempDir.create();

    final none = await CliRun.run(['init']);
    final invalid = await CliRun.run(['init', dir.resolve('My-App')]);

    expect(none.exitCode, CliExitCode.usage.code);
    expect(none.err, startsWith('init takes exactly one directory.'));
    expect(invalid.exitCode, CliExitCode.usage.code);
    expect(invalid.err, startsWith('"My-App" is not a valid package name'));
    expect(dir.exists('My-App'), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/init_command_test.dart`
Expected: FAIL: `init` ще не команда — `dartnest_cli init` завершується з кодом `64`

- [ ] **Step 3: Write the template, the scaffold and the command**

Файл `packages/dartnest_cli/lib/src/init/project_template.dart`:

```dart
/// The files of a new dartnest application, as `init` writes them.
///
/// A flat catalog of file contents without logic.
abstract final class ProjectTemplate {
  /// The version constraint of the dartnest packages in a new pubspec: the
  /// first published release.
  static const dartnestVersion = '^0.1.0';

  /// The files of application [name] (relative path → content), sorted by
  /// path.
  static Map<String, String> files(String name) => {
    '.gitignore': '.dart_tool/\n',
    'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
    'bin/server.dart': _server(name),
    'lib/src/hello.dart': _hello,
    'pubspec.yaml': _pubspec(name),
  };

  static String _pubspec(String name) =>
      '''
name: $name
description: A dartnest application.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  dartnest: $dartnestVersion
  dartnest_annotations: $dartnestVersion
  dartnest_io: $dartnestVersion

dev_dependencies:
  dartnest_cli: $dartnestVersion
  lints: ^5.1.0
''';

  static const _hello = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, \$name!'};
}

/// `GET /hello?name=...`.
@Controller('/hello')
final class HelloController {
  /// Creates the controller.
  HelloController(this.service);

  /// The service.
  final HelloService service;

  /// Greets [name], or the world.
  @Get()
  Map<String, String> hello(@Query('name') String? name) =>
      service.greet(name ?? 'world');
}

/// The root module.
@Module(id: 'app', providers: [HelloService], controllers: [HelloController])
final class AppModule {}
''';

  static String _server(String name) =>
      '''
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:$name/$name.dartnest.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:\${adapter.port}/hello');
}
''';
}
```

Файл `packages/dartnest_cli/lib/src/init/project_scaffold.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import '../package/package_root.dart';
import 'project_template.dart';

/// Writes a new application from [ProjectTemplate] into an empty or new
/// directory; the directory name is the package name.
final class ProjectScaffold {
  /// Creates the scaffold of [directory].
  ProjectScaffold(String directory)
    : directory = p.normalize(p.absolute(directory));

  /// Absolute path of the new package.
  final String directory;

  /// The package name: the directory name.
  String get name => p.basename(directory);

  /// Writes the files and returns their paths relative to [directory].
  ///
  /// Throws a [CliFailure]: [CliExitCode.usage] for a directory name that
  /// is not a package name, [CliExitCode.cannotCreate] for a directory that
  /// is not empty or cannot be written.
  List<String> write() {
    if (!PackageRoot.validName.hasMatch(name)) {
      throw CliFailure(
        CliExitCode.usage,
        '"$name" is not a valid package name; name the directory in '
        'lowercase_with_underscores.',
      );
    }
    _checkEmpty();
    final files = ProjectTemplate.files(name);
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File(p.joinAll([directory, ...path.split('/')]));
      try {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      } on FileSystemException catch (error) {
        throw CliFailure(
          CliExitCode.cannotCreate,
          'Cannot write ${file.path}: '
          '${error.osError?.message ?? error.message}.',
        );
      }
    }
    return files.keys.toList();
  }

  void _checkEmpty() {
    final type = FileSystemEntity.typeSync(directory);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        Directory(directory).listSync().isNotEmpty) {
      throw CliFailure(
        CliExitCode.cannotCreate,
        '$directory is not an empty directory; init writes a new package '
        'into an empty or new directory.',
      );
    }
  }
}
```

Файл `packages/dartnest_cli/lib/src/cli/init_command.dart`:

```dart
import 'package:args/command_runner.dart';

import '../init/project_scaffold.dart';
import 'cli_exit_code.dart';
import 'dartnest_cli.dart';

/// `init <directory>`: scaffolds a new application.
final class InitCommand extends Command<int> {
  /// Creates the command of [cli].
  InitCommand(this.cli);

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Creates a dartnest application in a new or empty directory.';

  @override
  String get invocation => 'dartnest_cli init <directory>';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('init was not parsed.'));
    if (options.rest.length != 1) {
      usageException('init takes exactly one directory.');
    }
    final target = options.rest.single;
    final scaffold = ProjectScaffold(target);
    final files = scaffold.write();
    cli.out
      ..writeln('Created package ${scaffold.name} in ${scaffold.directory}:')
      ..writeAll([for (final file in files) '  $file\n'])
      ..writeln('Next:')
      ..writeln('  cd $target')
      ..writeln('  dart pub get')
      ..writeln('  dart run dartnest_cli gen')
      ..writeln('  dart run bin/server.dart');
    return CliExitCode.success.code;
  }
}
```

Файл `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart` (повний файл; нове — `InitCommand`):

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'gen_command.dart';
import 'init_command.dart';

/// The `dartnest_cli` command line.
///
/// `bin/dartnest_cli.dart` runs it with the core constructs; a package
/// with constructs of its own runs it from `tool/dartnest.dart`:
/// `DartnestCli(generator: DartnestGenerator([...])).run(arguments)`.
final class DartnestCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default), `gen` runs [generator] and `gen --watch` stops
  /// when [untilStopped] completes (the first Ctrl+C by default).
  DartnestCli({
    StringSink? out,
    StringSink? err,
    this.generator = const DartnestGenerator.core(),
    Future<void> Function()? untilStopped,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       untilStopped = untilStopped ?? _interrupted;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final DartnestGenerator generator;

  /// Called when `gen --watch` starts; watching ends when the future
  /// completes.
  final Future<void> Function() untilStopped;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)
      ..addCommand(GenCommand(this))
      ..addCommand(InitCommand(this));
    try {
      return await runner.run(arguments) ?? CliExitCode.success.code;
    } on UsageException catch (error) {
      err
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return CliExitCode.usage.code;
    } on CliFailure catch (failure) {
      err.writeln(failure.message);
      return failure.exitCode.code;
    }
  }

  static Future<void> _interrupted() => ProcessSignal.sigint.watch().first;
}

final class _Runner extends CommandRunner<int> {
  _Runner(this._out)
    : super('dartnest_cli', 'Generates and scaffolds dartnest applications.');

  final StringSink _out;

  @override
  void printUsage() => _out.writeln(usage);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+36: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/test/init_command_test.dart \
  packages/dartnest_cli/lib/src/init/project_template.dart \
  packages/dartnest_cli/lib/src/init/project_scaffold.dart \
  packages/dartnest_cli/lib/src/cli/init_command.dart \
  packages/dartnest_cli/lib/src/cli/dartnest_cli.dart
git commit -m "feat(cli): add init"
```

---

### Task 9: Документація

README пакета (англійською): команди, поведінка `gen` (запис лише при зміні, проблеми лишають попередній файл, видалення застарілого, чужий файл), `gen --watch`, `init`, таблиця кодів виходу, модулі інших пакетів (OP3), `tool/dartnest.dart` з власними конструктами (OP10; приклад перевірено: аналізується й запускається). `CLAUDE.md` отримує команди бенчмарка й `gen`, правило «CLI володіє лише своїм виходом» і правило тестів CLI; роадмап — посилання на план і переписані ризики (OP1, OP11).

**Files:**
- Create: `packages/dartnest_cli/README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/ROADMAP.md`

**Interfaces:**
- Consumes: усі команди й публічні типи Tasks 1–8 (README описує їх як є).
- Produces: документацію; коду немає.

- [ ] **Step 1: Write the README**

Файл `packages/dartnest_cli/README.md`:

````markdown
# dartnest_cli

The command line tool of dartnest. `gen` writes `lib/<package>.dartnest.dart`
from the annotations of a package, `gen --watch` keeps it up to date while
you edit, and `init` scaffolds a new application.

```sh
dart run dartnest_cli gen                    # in the package directory
dart run dartnest_cli gen --watch            # regenerate on every change, Ctrl+C stops
dart run dartnest_cli gen --directory packages/shop
dart run dartnest_cli init my_app            # a new package in ./my_app
```

Activated globally (`dart pub global activate dartnest_cli`), the same
commands are `dartnest gen`, `dartnest init`.

## gen

- Reads every Dart file of `lib/` except generated `*.dartnest.dart` files
  and runs the core constructs of `dartnest_generator` (`DartnestGenerator.core()`).
- Problems go to stderr, one per line, as
  `path:line:column: error: message [code]`, with the path relative to the
  package root and `/` separators on every platform; the last line counts
  them. Syntax errors have the code `syntax_error`; the generator's codes
  are listed in the `dartnest_generator` README. While there are problems,
  the generated library is left as it was.
- Only syntax errors stop generation. Other analyzer errors do not: on the
  first run the generated library does not exist yet, so code importing it
  does not compile.
- The library is written only when its content changed, through
  `<file>.tmp` and a rename, so a running analyzer or `dev` never reads
  half a file. A file at that path that does not start with
  `// GENERATED BY dartnest_generator. DO NOT EDIT.` is never overwritten or
  deleted: `gen` fails with exit code 73 instead.
- When `lib/` has no annotations any more, the generated library is
  deleted.
- One package per run. A `@Module` class of another package is imported
  from that package's own generated library, so generate dependencies
  first. The generator cannot see into such a module (or into a module
  built by a function), so `missing_provider` and `circular_dependency` are
  then left to `Application.create` for the whole package.

## gen --watch

- Generates once, then after every change of a Dart file in `lib/`, with
  the analysis kept in memory: only changed files are read again.
- Events are debounced (100 ms): an editor's save or a branch switch gives
  one run. Runs never overlap; changes made during a run go into the next.
- Problems are printed and watching goes on; so does a failure to write
  the output. Any other failure ends the process.
- `dart test benchmark` checks the targets: under 10 s cold and under 1 s
  for a change on a package of 200 files.

## init

`init <directory>` writes a new package into a new or empty directory; the
directory name is the package name (lowercase_with_underscores):
`pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `lib/src/hello.dart`
(a service, a controller and the root `AppModule`) and `bin/server.dart`.
Then:

```sh
cd my_app
dart pub get
dart run dartnest_cli gen
dart run bin/server.dart    # GET http://localhost:8080/hello?name=you
```

## Exit codes

| Code | When |
| --- | --- |
| 0 | done (also when there is nothing to generate, and after `--watch` stops) |
| 1 | problems in the sources: diagnostics or syntax errors |
| 64 | wrong command line (unknown command or option, `init` without a valid directory name) |
| 66 | no `pubspec.yaml` with a valid `name`, or no `lib/` |
| 73 | a file cannot be written, or `init` into a directory that is not empty |

## Own constructs

Dart cannot load constructs at run time, so a package with constructs of
its own runs the command line from `tool/dartnest.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

Future<void> main(List<String> arguments) async {
  final generator = DartnestGenerator([
    ...const DartnestGenerator.core().constructs,
    // MyConstruct(),
  ]);
  exitCode = await DartnestCli(generator: generator).run(arguments);
}
```

and calls `dart run tool/dartnest.dart gen`. `GenerationSession` is the
same generation as a library: `run(changed: [...])` regenerates with the
analysis kept in memory, for tools that decide themselves when to run.
````

- [ ] **Step 2: Update `CLAUDE.md`**

У `CLAUDE.md` замінити:

```markdown
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
```

на:

```markdown
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
# packages/dartnest_cli: the generation benchmark (not part of `dart test`):
dart test benchmark
# generate a package with the CLI, e.g. the generator's golden fixture:
dart run dartnest_cli gen --directory ../dartnest_generator/test/fixtures/users_app
```

У `CLAUDE.md` замінити:

```markdown
  pipeline unchanged.
```

на:

```markdown
  pipeline unchanged.
- **The CLI owns only its output.** `dartnest_cli` writes
  `lib/<package>.dartnest.dart` only when it changed, through a temporary
  file and a rename, never over a file without the generated header, and
  leaves it as it was while the sources have problems.
```

У `CLAUDE.md` замінити:

```markdown
  loopback; temp files only through a `TempDir` test helper.
```

на:

```markdown
  loopback; temp files only through a `TempDir` test helper.
  `dartnest_cli` tests build packages in a `TempDir` and resolve them
  against this workspace with `WorkspacePackageConfig` (no `pub get`); they
  run the command line in-process (`CliRun`, `DartnestCli(out:, err:,
  untilStopped:)`), never as a child process.
```

- [ ] **Step 3: Update the roadmap**

У `docs/superpowers/ROADMAP.md` замінити:

```markdown
| 5 | **CLI** | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
```

на:

```markdown
| 5 | **CLI** (план `2026-10-14-dartnest-cli.md`) | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
```

У `docs/superpowers/ROADMAP.md` замінити:

```markdown
  етап 5 пінить версію analyzer і має тест «зміна файлу без перезапуску».
- Швидкість генерації — бенчмарк етапу 5 входить у CI.
```

на:

```markdown
  етап 5 тримає той самий діапазон analyzer, що й генератор
  (`'>=8.1.1 <15.0.0'`, обидва краї перевірено), і має тест «зміна файлу
  без перезапуску» (`packages/dartnest_cli/test/gen_watch_test.dart`).
- Швидкість генерації — бенчмарк етапу 5
  (`cd packages/dartnest_cli && dart test benchmark`) входить у CI.
```

- [ ] **Step 4: Verify the whole stage**

Run: `cd packages/dartnest_cli && dart test`
Expected: `+36: All tests passed!`

Run: `cd packages/dartnest_cli && dart test benchmark`
Expected: `+1: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+163: All tests passed!` (генератор не змінено)

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/README.md \
  CLAUDE.md \
  docs/superpowers/ROADMAP.md
git commit -m "docs: document dartnest_cli"
```

## Самоперевірка

**Покриття специфікації.**

| Вимога | Задача |
|---|---|
| 2: пакет `dartnest_cli`, `dart run dartnest_cli gen [--watch]`, залежності `dartnest_generator`, `watcher` | 1, 5, 6 (OP2) |
| 6 «Вихід»: `lib/<package>.dartnest.dart`, «записується лише якщо вміст змінився» | 3, 4 (рішення 4) |
| 6: багатопакетні застосунки — кожен пакет генерує свій файл | 5, README (OP3) |
| 6 «Архітектура»: набір конструктів компілюється в CLI статично; `tool/dartnest.dart` | 5 (`DartnestCli(generator:)`), 9 (README) (OP10) |
| 6 «Статична валідація»: `path:line:col: error: message`, ненульовий код виходу | 4, 5 (OP4) |
| 6 «Драйвери»: `AnalysisContextCollection` у пам'яті, `watcher` над `lib/`, `applyPendingFileChanges`, повний прогін конструктів | 2, 4, 6 |
| 6 «Драйвери»: холодна генерація < 10 с, інкремент < 1 с на 200 файлах, бенчмарк | 7 (OP11) |
| 7: генератор — діагностики, не винятки; watch продовжує працювати після помилки | 4, 6 (OP5, OP8) |
| 9 п. 5: `dartnest_cli` (`gen`, `--watch`, `init`), бенчмарк | 1–8 |
| 10: `dev` перевикористовує генерацію «у тому ж процесі CLI» | 4 (`GenerationSession` у barrel), 5 (OP10) |
| Роадмап, ризики: версія analyzer, тест «зміна файлу без перезапуску», бенчмарк у CI | 6 (`gen_watch_test.dart`), 7, 9 (OP1) |
| Роадмап, етап 5 «Готово, коли» | 1–8; посилання на план — 9 |

**Плейсхолдери.** Пошук `TBD`, `TODO`, «similar to Task», «add error handling», «implement later» — нічого. Кожен крок з кодом містить повний файл; файли, які змінюються кількома задачами, наведено повністю в кожній: `lib/dartnest_cli.dart` (1, 5), `lib/src/cli/dartnest_cli.dart` (5, 6, 8), `lib/src/cli/gen_command.dart` (5, 6), `lib/src/cli/report_printer.dart` (5, 6). Зміни `CLAUDE.md` і роадмапу (Task 9) дано точним «було → стало».

**Узгодженість типів.** Імена між задачами взято з того самого коду, що пройшов перевірку нижче: `CliExitCode.success/problems/usage/noInput/cannotCreate` + `.code`, `CliFailure(exitCode, message)`, `PackageRoot.open/validName/path/name/libPath/outputPath/display`, `SyntaxProblem(location, message)` + `.code`, `PackageAnalysis(package).sourceFiles/changed/syntaxProblems/libraries/dispose`, `WriteOutcome.written/unchanged/deleted/none/kept`, `OutputWriter(package).writeLibrary/deleteLibrary/writeFile`, `GenerationReport({output, outcome, elapsed, syntaxProblems, diagnostics}).hasProblems/problemLines`, `GenerationSession(package, {generator}).run({changed})/close`, `ReportPrinter(out, err).report/watching`, `DartnestCli({out, err, generator, untilStopped}).run`, `GenCommand(cli)`, `InitCommand(cli)`, `WatchLoop(session, printer, {debounce}).run(watcher, stop)` + `defaultDebounce`, `ProjectTemplate.files/dartnestVersion`, `ProjectScaffold(directory).write/name/directory`; хелпери `TempDir.create/path/resolve/write/read/exists`, `WorkspacePackageConfig.write`, `TempPackage.create/name/dir/root`, `ShopSources.output/clock/controller/module/moduleWithoutClock/files`, `CliRun.run/exitCode/out/err`, `LineSink.next/after/lines`, `FakeWatcher(path).modify`, `BenchmarkSources.files/controllerPath/changedController`. З генератора використано лише barrel: `PackageCollector`, `DartnestGenerator`(`.core()`, `.constructs`), `PackageModel`, `Diagnostic`, `SourceLocation`, `FileUnit`, `ContentType`, `LibraryWriter.header`.

**Перевірка.** План перевірено скриптом, який читає цей markdown і застосовує його задачу за задачею до чистого клону `master` (`a6639fc`) у `/tmp`: записує кожен файл з блоку коду, застосовує «було → стало», виконує кожен рядок `Run:` (з `TMPDIR` у `/tmp`) і порівнює з `Expected:` (кроки «verify it fails» мусять завершитися з помилкою, кроки з `+N` — дати рівно `+N: All tests passed!`), виконує блок коміту як є й перевіряє, що після нього `git status` чистий. Результат: усі 9 задач, усі кількості (`+4`, `+8`, `+14`, `+19`, `+28`, `+33`, `+33`/`+1`, `+36`), `dart analyze` — «No issues found!» і `dart format` — 0 змінених файлів після кожної задачі; `dart run dartnest_cli gen --directory ../dartnest_generator/test/fixtures/users_app` друкує `lib/users_app.dartnest.dart is up to date` (вихід CLI = golden етапу 4). SDK: Dart 3.13.5 (fvm Flutter 3.47.6) з мовною версією 3.8. Залежності на верхньому краї: `analyzer` 14.5.0, `args` 2.7.0, `watcher` 1.2.1, `yaml` 3.1.4, `test` 1.33.0. Нижній край — окрема копія з `dependency_overrides` (`analyzer` 8.1.1, `code_builder` 4.11.1, `dart_style` 3.1.2, `test` 1.26.3): `dartnest_cli` `+36` і бенчмарк `+1`, `dartnest_generator` `+163`; `dart analyze` на нижньому краї дає лише ті самі `experimental_member_use` для `ResolvedLibraryResult.element`, що й генератор етапу 4 (у CLI — один рядок, `package_analysis.dart`). Вручну: каркас `init` після `gen` запущено з конфігурацією workspace — `GET /hello?name=you` → `{"message":"Hello, you!"}`. Бенчмарк: холодний прогін 2.4 с, інкремент 0.35–0.41 с (OP11). Розміри: найбільший файл у `lib/` — `package_analysis.dart` (105 рядків), у `test/` — `gen_command_test.dart` (124); найдовший метод — `GenerationSession.run` (30 рядків).

**Review Focus.** Кожен пункт закріплено тестом з коментарем `// Review Focus N`: 1 → Task 1; 2, 5 → Task 3; 3, 4, 7 → Task 4; 8, 9 → Task 5; 6 → Task 6.

## Відкриті питання для автора

Усі рішення, які варто переглянути до виконання, винесено в «Open points» (OP1–OP11) з рекомендаціями; план написано за ними. Найбільше на подальші етапи впливають:

1. **OP3** — лишити модулі інших пакетів непрозорими в етапі 5 і зробити «бачення крізь пакети» окремим етапом генератора перед build_runner (варіант B), чи відмовитися від цього взагалі.
2. **OP1** — чи достатньо «пінінгу» верхньою межею діапазону analyzer і перевіркою обох країв, чи комітити `pubspec.lock` (варіант C).
3. **OP8** — чи має watch переживати будь-який виняток (нова межа `on Object`), чи падати голосно.
