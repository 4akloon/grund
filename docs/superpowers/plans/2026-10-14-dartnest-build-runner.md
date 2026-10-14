# dartnest build_runner Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 6 роадмапу: пакет `dartnest_build` — агрегуючий build_runner-builder на `lib/$lib$`, який пише `lib/<package>.dartnest.dart` байт-у-байт таким, як `dartnest_cli gen` (той самий заголовок, ті самі джерела, ті самі конструкти), і звітує проблеми рядками `path:line:col: error: message [code]` як помилки логу build_runner.

**Architecture:** Builder — тонкий драйвер над `dartnest_generator`, як і CLI. `PackageSources` бере з `BuildStep` усі `lib/**.dart`, крім `*.dartnest.dart` (`findAssets`), сортує, перевіряє синтаксис через `resolver.compilationUnitFor` (`SyntaxErrorInAssetException` → `SyntaxProblem`, частини теж) і віддає резолвлені бібліотеки (`resolver.libraryFor`, частини пропускаються). `DartnestBuilder.build` збирає `PackageModel` через `PackageCollector(package, '/$package')` (analyzer build_runner бачить файли пакета `p` під `/p/`, тож шляхи діагностик — відносні до кореня пакета, як у CLI), запускає `DartnestGenerator` і пише рівно один asset; будь-яка проблема — `log.severe` по рядку на проблему, нічого не пишеться. build_runner не повідомляє builder-у ім'я пакета до збірки, тому пакет називає себе опцією `package` у своєму `build.yaml` (`DartnestBuildOptions.builderFor`); без неї чи з неправильною — `ConfigurationErrorBuilder`, що валить збірку з готовим `build.yaml`. Спільне з CLI (`SyntaxProblem`, `PackageModel.isEmpty`, `LibraryWriter.validPackageName`) переїжджає в генератор першою задачею.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors); `build` ^4.0.2, `analyzer` `'>=8.1.1 <15.0.0'` (як генератор і CLI), `glob` ^2.1.0; dev: `build_test` ^3.5.0, `dartnest_cli` (для порівняння байтів), `test` ^1.25.0; у фікстурі `users_app` — `build_runner` ^2.16.0 (`--only-check`). Обидва краї перевірено: `analyzer` 8.1.1 / `build` 4.0.2 / `build_runner` 2.10.5 / `build_test` 3.5.5 і `analyzer` 14.5.0 / `build` 4.0.11 / `build_runner` 2.16.2 / `build_test` 3.5.21.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md`, розділ 6 «Драйвери» (build_runner: `Builder` з `buildExtensions: {r'$lib$': ['<pkg>.dartnest.dart']}`, `findAssets` + `resolver.libraryFor`, той самий `PackageModel`) і таблиця пакетів розділу 3 (`dartnest_build` → `dartnest_generator`, `build`); `docs/superpowers/ROADMAP.md`, рядок 6; план етапу 5 `docs/superpowers/plans/2026-10-14-dartnest-cli.md` (правило «The CLI owns only its output», формат проблем, `GenerationSession`).

## Open decisions

Рішення, які спека не приймає, а план приймає сам; автор може змінити їх до виконання. Для кожного — таблиця компромісів і рекомендація; план написано за рекомендованим варіантом (позначено ✔).

### OD1. Звідки builder знає ім'я пакета

`buildExtensions` мусить назвати вихід до збірки, а `BuilderOptions` (перевірено на build 4.0.2 і 4.0.11) не містить імені пакета: фабрика викликається один раз на ціль, ім'я відоме лише в `build()` (`buildStep.inputId.package`). `build.yaml` дозволяє `build_extensions: {"$lib$": ["<package>.dartnest.dart"]}` лише як опис — фактичні виходи дає сам `Builder`.

| Варіант | Як | Наслідки |
|---|---|---|
| A ✔ обов'язкова опція `package` у `build.yaml` пакета користувача (`targets: $default: builders: dartnest_build: options: package: shop`) | `DartnestBuildOptions.builderFor(options)` | один файл конфігурації; немає опції, невалідне ім'я, невідома опція чи ім'я іншого пакета (скопійований `build.yaml`) — збірка падає з готовим `build.yaml`; нічого не вгадується |
| B якір на `lib/<pkg>.dart`: `{'.dart': ['.dartnest.dart']}` лише для файлу з іменем пакета | нуль конфігурації | без `lib/<pkg>.dart` (поширено в застосунках) builder мовчки нічого не робить; агрегування через другорядний вхід |
| C читати `pubspec.yaml` з поточної теки у фабриці | нуль конфігурації | ламається з `build_runner --workspace` (одна фабрика на багато пакетів, cwd — корінь workspace); `dart:io` у фабриці |

Конфігураційна помилка — окремий builder, а не виняток у фабриці: виняток дає стек build_runner замість повідомлення. Такий builder оголошує вихід `lib/dartnest_build.unconfigured`, який ніколи не пише: build_runner до 2.16 і `build_test` пропускають builder без жодного виходу, і збірка пройшла б мовчки (перевірено на 2.10.5 / 3.5.5). **Варіанти:** A — опція `package`; B — якір `lib/<pkg>.dart`; C — pubspec з cwd. **Рекомендація: A.**

### OD2. Спільний код з CLI

| Варіант | Що | Ціна |
|---|---|---|
| A ✔ перенести в генератор `SyntaxProblem` (з `dartnest_cli`), `PackageModel.isEmpty` (замість приватного `GenerationSession._isEmpty`) і `LibraryWriter.validPackageName` (зараз приватний `_packageName`; `PackageRoot.validName` стає посиланням на нього); CLI реекспортує `SyntaxProblem` — його barrel не змінюється для користувачів | Task 1, окремий рефакторинг | три маленькі публічні члени генератора; поведінка CLI та сама (`+136` без змін) |
| B `dartnest_build` залежить від `dartnest_cli` | — | у build-скрипт користувача тягнуться `vm_service`, `watcher`, `args`; дві реалізації читання файлів в одному процесі |
| C дублювати | — | формат рядка проблеми й правило «порожній пакет» розходяться з часом; conformance-тест ловить пізно |

**Варіанти:** A — винести в генератор; B — залежати від CLI; C — дублювати. **Рекомендація: A.** `dartnest_cli` лишається лише dev-залежністю `dartnest_build` — для тестів порівняння.

### OD3. Правило заголовка й «вихід лишається, поки є проблеми»

build_runner з 2.7 завжди видаляє файли, що конфліктують з виходами, ще до запуску builder-ів (прапорця `--delete-conflicting-outputs` більше немає), і видаляє попередній вихід кроку, який завершився без запису. Перевірено на 2.16.2: синтаксична помилка в `users_app` — `lib/users_app.dartnest.dart` видалено, після виправлення — записано знову.

| Варіант | Чужий файл без заголовка | Попередній вихід при проблемах |
|---|---|---|
| A ✔ прийняти правила build_runner; вихід має той самий заголовок, тож CLI і `dev` приймають файл build_runner і навпаки; README і `CLAUDE.md` описують відмінність | видаляє build_runner | видаляється |
| B builder читає попередній вихід і переписує його при проблемах | — | builder не може прочитати власний оголошений вихід |
| C писати в інший файл (`lib/<pkg>.dartnest.g.dart`) | не конфліктує | ламає «байт-у-байт той самий файл» і імпорти користувача |

**Варіанти:** A — правила build_runner + документація; B — переписувати старий вихід; C — інший файл. **Рекомендація: A.**

### OD4. Версії

| Залежність | Діапазон | Чому |
|---|---|---|
| `build` ✔ | `^4.0.2` | 4.0.2–4.0.7 підтримують `analyzer` ≥ 8 (той самий нижній край, що в генератора); 4.0.8+ вимагають `analyzer` ≥ 13.3 і SDK ^3.11 — pub обере сам |
| `analyzer` ✔ | `'>=8.1.1 <15.0.0'` | як `dartnest_generator`/`dartnest_cli`; `LibraryElement` іде в `PackageCollector` |
| `glob` ✔ | `^2.1.0` | `findAssets(Glob)`; без прямої залежності — `depend_on_referenced_packages` |
| `build_test` (dev) ✔ | `^3.5.0` | `TestReaderWriter`, `loadIsolateSources`, `TestBuilderResult.errors` з'явились у 3.5.0 |
| `build_runner` у `users_app` (dev) ✔ | `^2.16.0` | `--only-check` для інтеграційного тесту; користувачам README радить `^2.10.0` (нижній край перевірено) |

Наслідок: workspace репозиторію резолвиться лише на SDK ≥ 3.11 (build_runner 2.15.2+ вимагає ^3.11); пакети лишаються з `sdk: ^3.8.0`. **Варіанти:** A — як у таблиці; B — `build_runner` у фікстурі `^2.10.0` і інтеграційний тест через `build` + порівняння (пише у фікстуру репозиторію); C — без `build_runner` у фікстурі (інтеграційного тесту немає). **Рекомендація: A.**

### OD5. Конструкт, що генерує власний файл (`FileUnit`)

| Варіант | Поведінка | Ціна |
|---|---|---|
| A ✔ помилка збірки, по рядку на файл: `dartnest_build cannot write openapi.json: ...`; нічого не пишеться | конструкти v1 `FileUnit` не дають; OpenAPI (v1.1) вирішить сам | без мовчазної втрати файлу |
| B оголосити `{r'$lib$': ['<pkg>.dartnest.dart', 'openapi.json']}` | шлях файлу відомий лише після генерації | `buildExtensions` статичні |
| C ігнорувати `FileUnit` | — | мовчки губить вихід (проти «Nothing is guessed silently») |

**Варіанти:** A — помилка; B — оголосити наперед; C — ігнорувати. **Рекомендація: A.**

### OD6. Як тестувати без мережі

| Варіант | Builder | CLI | Справжній build_runner |
|---|---|---|---|
| A ✔ `build_test` у пам'яті: `TestReaderWriter(rootPackage:)` + `testing.loadIsolateSources()` (усі пакети конфігурації тестового ізолята, ~0.4 с, без `pub get`) + `testBuilder(..., flattenOutput: true)` | `TestBuilderResult.errors` — чисті рядки | `GenerationSession` на копії в `TempDir` з `WorkspacePackageConfig` (як тести CLI) | `integration/build_runner_test.dart`: `dart run build_runner build --only-check` у `users_app` (дочірній процес, ~20 с на AOT-компіляцію), `dart test integration` |
| B лише справжній build_runner | — | — | 20 с на кожен сценарій; тести пишуть у робоче дерево |
| C лише `build_test` | — | — | `build.yaml` і фабрика не перевіряються ніколи |

Не друкувати в `onLog` `testBuilder`-а: на build_runner 2.10.x `print` у ньому дає переповнення стеку (рекурсія зон); тести читають `result.errors`. **Варіанти:** A — пам'ять + один інтеграційний; B — лише build_runner; C — лише пам'ять. **Рекомендація: A.**

### OD7. Співіснування з `dartnest gen --watch` / `dev`

| Варіант | Що | Наслідки |
|---|---|---|
| A ✔ один записувач на пакет; README: `build_runner watch`, коли інші builder-и все одно працюють, або `dartnest_cli dev` для hot reload з `enabled: false` для `dartnest_build`, якщо `build_runner watch` працює поруч | лише документація | обидва пишуть ті самі байти й заголовок, тож навіть два записувачі не дають різних файлів; але build_runner видаляє вихід при помилці, що `dev` побачить як зникнення бібліотеки |
| B `dev` запускає build_runner замість власної генерації | — | секунди на прогін, другий процес; суперечить етапу 5b |
| C builder пропускає збірку, коли працює `dev` | — | прихований стан між процесами |

**Варіанти:** A — документація; B — `dev` над build_runner; C — детекція `dev`. **Рекомендація: A.**

### OD8. Перевірка синтаксису

| Варіант | Як | Наслідки |
|---|---|---|
| A ✔ `resolver.compilationUnitFor(asset)` для кожного джерела, `SyntaxErrorInAssetException.filesWithErrors` → `SyntaxProblem` (позиція з `lineInfo`) | той самий парсер analyzer, що в `getParsedUnit` CLI | рядки збігаються з CLI (перевірено: `cases_app`, синтаксис у бібліотеці й у частині) |
| B `parseString` з `package:analyzer` на вмісті asset | без резолвера | друга реалізація; частини треба читати окремо |
| C покладатися на виняток `libraryFor` | — | повідомлення build_test/build_runner (`1:30: Expected to find ')'.`) без шляху й коду |

**Варіанти:** A — `compilationUnitFor`; B — `parseString`; C — виняток `libraryFor`. **Рекомендація: A.**

### OD9. Пакет без анотацій

| Варіант | Поведінка |
|---|---|
| A ✔ нічого не писати й не логувати; build_runner сам видаляє попередній вихід — як CLI видаляє бібліотеку, коли анотацій більше немає |
| B писати порожню бібліотеку | розходиться з CLI (байт-у-байт) |
| C попередження в лог | шум у кожному пакеті, що залежить від `dartnest_build` без анотацій |

**Варіанти:** A — нічого; B — порожня бібліотека; C — попередження. **Рекомендація: A.**

### OD10. Ім'я builder-а і застосування

| Варіант | Ключ | Застосування |
|---|---|---|
| A ✔ `dartnest_build` (у `build.yaml` користувача — короткий ключ `dartnest_build:`; у логах `dartnest_build on lib/$lib$`), `auto_apply: dependents`, `build_to: source`, фабрика `dartnestBuilder` — top-level у barrel (виняток у `CLAUDE.md`: `build.yaml` вимагає top-level фабрику) | короткий | пакет із залежністю на `dartnest_build` отримує builder без `builders:` |
| B `dartnest_build:dartnest` | довгий | те саме |
| C `auto_apply: none` | — | кожен пакет вмикає явно — плюс другий блок у `build.yaml` |

**Варіанти:** A — `dartnest_build`, dependents; B — `dartnest_build:dartnest`; C — none. **Рекомендація: A.**

## Рішення

1. **Task 1 — рефакторинг без зміни поведінки:** `SyntaxProblem` переїжджає (`git mv`) у `dartnest_generator/lib/src/diagnostic/`, генератор експортує його, CLI реекспортує (`show SyntaxProblem`); `PackageModel.isEmpty`; `LibraryWriter.validPackageName` (публічний) і `PackageRoot.validName = LibraryWriter.validPackageName`. Тести генератора `+163` → `+169`, CLI `+136` без змін.
2. **Джерела:** `PackageSources.find(step)` — `findAssets(Glob('lib/**.dart'))` без `*.dartnest.dart`, відсортовано (як `PackageAnalysis.sourceFiles` CLI); `syntaxProblems()` — по `compilationUnitFor` на кожне джерело (частини теж), відсортовано; `libraries()` — `isLibrary` → `libraryFor`.
3. **Порядок `build()`:** ім'я пакета ≠ опції → помилка; синтаксис → помилки; `PackageCollector(package, '/$package')`; `model.isEmpty` → нічого; діагностики → помилки; `FileUnit` → помилки; інакше `writeAsString(AssetId(package, 'lib/$package.dartnest.dart'), library)`. Помилка — `log.severe('$problem')` по одній на проблему: build_runner валить збірку (код 1), `build_test` повертає їх у `errors`.
4. **Опції:** `DartnestBuildOptions.builderFor(options, {generator})`; єдиний ключ `package`; `buildYaml(package)` — текст для повідомлень; `dartnestBuilder(options)` — top-level фабрика в `lib/dartnest_build.dart`. Власні конструкти — власна фабрика користувача через `builderFor(options, generator: ...)` (README, перевірено справжнім build_runner з `tool/builder.dart`).
5. **Повідомлення** (англійською): `dartnest_build cannot build shop: the option "package" is missing. Name the package in its build.yaml:` + `build.yaml`; `... "Shop-App" is not a package name. ...`; `... unknown option pakage. ...`; `dartnest_build cannot build shop: its build.yaml names the package "users_app". ...`; `dartnest_build cannot write openapi.json: a construct generated it, and a build_runner builder writes only lib/<package>.dartnest.dart. Generate this package with dartnest_cli gen.`
6. **Conformance:** `users_app` — UTF-8 байти builder-а = байти CLI = закомічений golden; `cases_app` — `build.errors == cli.report.problemLines` (61 рядок); синтаксис у бібліотеці й у частині — ті самі рядки, що в CLI.
7. **Поза планом:** `FileUnit` під build_runner (OD5), кілька пакетів одним `build_runner --workspace` (не перевірялось), CI-конфігурація (у репозиторії її немає; інтеграційний тест — команда в `CLAUDE.md`), публікація (етап 7).

## Global Constraints

- `build` — лише в `dartnest_build`; `analyzer` — лише в `dartnest_generator`/`dartnest_cli`/`dartnest_build`. Ядро, анотації й адаптери не змінюються. `dartnest_build` не залежить від `dartnest_cli` (лише dev).
- Вихід builder-а для тих самих джерел байт-у-байт дорівнює виходу `dartnest_cli gen` (той самий заголовок `// GENERATED BY dartnest_generator. DO NOT EDIT.`), проблеми — ті самі рядки `path:line:column: error: message [code]` у тому самому порядку. Детермінізм: джерела відсортовано, генератор той самий.
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/`, ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів, ≤ 3 рівні вкладеності; один публічний клас на файл; без top-level функцій у `lib/src` (фабрика `dartnestBuilder` — у `lib/dartnest_build.dart`, виняток фіксує Task 5); без `!`, `dynamic`, `late`; `catch` лише з `on` (єдиний новий — `on SyntaxErrorInAssetException`); dartdoc на кожному публічному члені.
- Тести: мережі немає, temp-файли — через `TempDir`; `dart test` не запускає build_runner як процес; `integration/` — `dart test integration`.
- Публічний API, dartdoc, повідомлення, README і коміти — англійською.
- Перед кожним комітом: з кореня `dart analyze` — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів; тести змінених пакетів зелені.
- `dart` не завжди в `PATH`: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після зміни `pubspec.yaml` — `dart pub get` з кореня.
- Відхилення від спеки, зафіксовані планом: обов'язкова опція `package` у `build.yaml` (OD1); вихід під build_runner видаляється при проблемах (OD3).

## Review Focus

1. **Застарілий або чужий `*.dartnest.dart` у `lib/`** (вихід іншого пакета, старий файл): не читається як джерело, вихід той самий, що в CLI. Закріплено в Task 2 (`generated libraries in lib/ are not sources`, `// Review Focus 1`).
2. **`build.yaml`, скопійований з іншого члена workspace** (`package: users_app` у пакеті `shop`) або опції немає: збірка падає з готовим `build.yaml`, нічого не пишеться. Закріплено в Task 4 (`the name of another package fails the build`, `// Review Focus 2`; `a missing package option fails the build`).
3. **Частини (`part`)**: синтаксична помилка в частині звітується з шляхом частини, як у CLI; частини не резолвляться як бібліотеки. Закріплено в Task 3 (`a syntax error in a part file is reported at the part`, `// Review Focus 3`).
4. **Частина, яку інший builder (`json_serializable`) ще не записав:** вихід той самий, що з частиною. Закріплено в Task 2 (`a part another builder has not written yet changes nothing`, `// Review Focus 4`).
5. **Анотації прибрано:** збірка успішна, виходу немає (build_runner прибирає старий). Закріплено в Task 2 (`a package without annotations gets no library`).

---
## File Structure

```
CLAUDE.md                                            # commands, analyzer/build rule, header rule under build_runner, factory exception, test rule (T5)
docs/superpowers/ROADMAP.md                          # row 6 links this plan (T5)
pubspec.yaml                                         # workspace + packages/dartnest_build (T2)
packages/dartnest_generator/
  lib/dartnest_generator.dart                        # + syntax_problem.dart (T1)
  lib/src/diagnostic/syntax_problem.dart             # MOVED from dartnest_cli (T1)
  lib/src/model/package_model.dart                   # isEmpty (T1)
  lib/src/emit/library_writer.dart                   # validPackageName (T1)
  test/diagnostic/syntax_problem_test.dart           # NEW (T1)
  test/model/package_model_test.dart                 # NEW (T1)
  test/fixtures/users_app/pubspec.yaml               # dev: build_runner, dartnest_build (T4)
  test/fixtures/users_app/build.yaml                 # NEW: package: users_app (T4)
packages/dartnest_cli/
  lib/dartnest_cli.dart                              # re-exports SyntaxProblem (T1)
  lib/src/generate/generation_session.dart           # model.isEmpty (T1)
  lib/src/generate/{generation_report,package_analysis}.dart  # import from the generator (T1)
  lib/src/package/package_root.dart                  # validName = LibraryWriter.validPackageName (T1)
  README.md                                          # build_runner section (T5)
packages/dartnest_build/                             # NEW package
  pubspec.yaml, analysis_options.yaml (T2), build.yaml (T4), README.md (T5)
  lib/dartnest_build.dart                            # barrel (T2), dartnestBuilder factory (T4)
  lib/src/package_sources.dart                       # PackageSources (T2), syntaxProblems (T3)
  lib/src/dartnest_builder.dart                      # DartnestBuilder (T2), problems (T3), package check (T4)
  lib/src/dartnest_build_options.dart                # DartnestBuildOptions (T4)
  lib/src/configuration_error_builder.dart           # ConfigurationErrorBuilder (T4)
  test/dartnest_builder_test.dart, conformance_test.dart (T2), problems_test.dart (T3), options_test.dart (T4)
  test/helpers/temp_dir.dart, workspace_package_config.dart, fixture_files.dart,
    cli_generation.dart, build_run.dart, shop_sources.dart (T2; shop_sources + broken in T3), file_construct.dart (T3)
  integration/build_runner_test.dart                 # NEW: `dart test integration` (T4)
```

Задачі йдуть строго послідовно: 1 → 2 → 3 → 4 → 5. Кількості тестів у кроках «Expected» — наростаючим підсумком: `cd packages/dartnest_generator && dart test` — T1 `+169`; `cd packages/dartnest_build && dart test` — T2 `+7`, T3 `+11`, T4 `+16`; `cd packages/dartnest_build && dart test integration` — T4 `+1`; `cd packages/dartnest_cli && dart test` — `+136` до й після T1. На початку етапу (`387f8a6`): `dartnest_generator` `+163`, `dartnest_cli` `+136`.

### Task 1: Спільне для драйверів — у генератор

`SyntaxProblem` (зараз у `dartnest_cli`), правило «порожній пакет» (приватний `GenerationSession._isEmpty`) і регулярний вираз імені пакета (приватний `LibraryWriter._packageName` і копія в `PackageRoot.validName`) потрібні й builder-у. Вони переїжджають у генератор без зміни поведінки (OD2): CLI реекспортує `SyntaxProblem`, тож імпорти його користувачів не змінюються.

**Files:**
- Move: `packages/dartnest_cli/lib/src/generate/syntax_problem.dart` → `packages/dartnest_generator/lib/src/diagnostic/syntax_problem.dart`
- Modify: `packages/dartnest_generator/lib/dartnest_generator.dart`, `packages/dartnest_generator/lib/src/model/package_model.dart`, `packages/dartnest_generator/lib/src/emit/library_writer.dart`
- Modify: `packages/dartnest_cli/lib/dartnest_cli.dart`, `packages/dartnest_cli/lib/src/generate/generation_report.dart`, `packages/dartnest_cli/lib/src/generate/generation_session.dart`, `packages/dartnest_cli/lib/src/generate/package_analysis.dart`, `packages/dartnest_cli/lib/src/package/package_root.dart`
- Test: `packages/dartnest_generator/test/diagnostic/syntax_problem_test.dart`, `packages/dartnest_generator/test/model/package_model_test.dart`

**Interfaces:**
- Consumes: `SourceLocation(path, line, column)` + `compareTo`/`toString` (генератор), `GraphModels.package/module/controller/type` (тестовий хелпер генератора), `PackageModel({packageName, languageVersion, injectables, ...})`, `InjectableModel`, `ConstructorModel`.
- Produces (barrel `dartnest_generator`):
  - `SyntaxProblem(SourceLocation location, String message)`, `static const code = 'syntax_error'`, `compareTo` (місце, потім текст), `toString()` → `'$location: error: $message [syntax_error]'`.
  - `PackageModel.isEmpty` — `modules`, `injectables` і `controllers` порожні.
  - `LibraryWriter.validPackageName` — `RegExp(r'^[a-z_][a-z0-9_]*$')`.
  - `dartnest_cli` експортує `SyntaxProblem` з генератора (`show SyntaxProblem`); `PackageRoot.validName` — той самий об'єкт `RegExp`.

- [ ] **Step 1: Write the failing tests**

Файл `packages/dartnest_generator/test/diagnostic/syntax_problem_test.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

void main() {
  test('a syntax problem prints like a diagnostic with syntax_error', () {
    const problem = SyntaxProblem(
      SourceLocation('lib/src/clock.dart', 2, 9),
      "Expected to find ';'.",
    );

    expect(
      '$problem',
      "lib/src/clock.dart:2:9: error: Expected to find ';'. [syntax_error]",
    );
  });

  test('syntax problems sort by location, then by message', () {
    const later = SyntaxProblem(SourceLocation('lib/b.dart', 1, 1), 'A.');
    const second = SyntaxProblem(SourceLocation('lib/a.dart', 3, 5), 'B.');
    const first = SyntaxProblem(SourceLocation('lib/a.dart', 3, 5), 'A.');

    expect([later, second, first]..sort(), [first, second, later]);
  });
}
```

Файл `packages/dartnest_generator/test/model/package_model_test.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  test('a package without modules, injectables or controllers is empty', () {
    expect(GraphModels.package([]).isEmpty, isTrue);
  });

  test('a module makes the package non-empty', () {
    expect(GraphModels.package([GraphModels.module('App')]).isEmpty, isFalse);
  });

  test('a controller makes the package non-empty', () {
    final controller = GraphModels.controller('Users', guard: 'Auth');

    expect(GraphModels.package([], [controller]).isEmpty, isFalse);
  });

  test('an injectable makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      injectables: [
        InjectableModel(
          type: GraphModels.type('Clock'),
          isAnnotated: true,
          constructor: const ConstructorModel([]),
          location: const SourceLocation('lib/app.dart', 1, 7),
        ),
      ],
    );

    expect(package.isEmpty, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/dartnest_generator && dart test test/diagnostic/syntax_problem_test.dart test/model/package_model_test.dart`
Expected: FAIL — `Error: Method not found: 'SyntaxProblem'.` (і `isEmpty` не визначено)

- [ ] **Step 3: Move `SyntaxProblem` into the generator**

```bash
git mv packages/dartnest_cli/lib/src/generate/syntax_problem.dart packages/dartnest_generator/lib/src/diagnostic/syntax_problem.dart
```

Файл `packages/dartnest_generator/lib/src/diagnostic/syntax_problem.dart` (імпорт і dartdoc класу змінюються, члени — ні):

```dart
import 'source_location.dart';

/// A syntax error in a source file of `lib/`; a driver does not run the
/// generator while one exists.
///
/// Printed like a `Diagnostic`:
/// `path:line:column: error: message [syntax_error]`. The CLI and the
/// build_runner builder both report syntax errors with it, so they print
/// them the same way.
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

Замінити в `packages/dartnest_generator/lib/dartnest_generator.dart`:

```dart
export 'src/diagnostic/source_location.dart';
```

на:

```dart
export 'src/diagnostic/source_location.dart';
export 'src/diagnostic/syntax_problem.dart';
```

- [ ] **Step 4: `PackageModel.isEmpty` and `LibraryWriter.validPackageName`**

Замінити в `packages/dartnest_generator/lib/src/model/package_model.dart`:

```dart
  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;
}
```

на:

```dart
  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;

  /// Whether the package has no modules, injectables or controllers: there
  /// is nothing to generate, and a driver removes a library it generated
  /// before.
  bool get isEmpty =>
      modules.isEmpty && injectables.isEmpty && controllers.isEmpty;
}
```

Замінити в `packages/dartnest_generator/lib/src/emit/library_writer.dart`:

```dart
  static final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');
```

на:

```dart
  /// A valid Dart package name; drivers check names against it too.
  static final validPackageName = RegExp(r'^[a-z_][a-z0-9_]*$');
```

Замінити в `packages/dartnest_generator/lib/src/emit/library_writer.dart`:

```dart
    if (!_packageName.hasMatch(packageName)) {
```

на:

```dart
    if (!validPackageName.hasMatch(packageName)) {
```

Замінити в `packages/dartnest_generator/lib/src/emit/library_writer.dart`:

```dart
        'must match ${_packageName.pattern}',
```

на:

```dart
        'must match ${validPackageName.pattern}',
```

- [ ] **Step 5: Use them in the CLI**

Замінити в `packages/dartnest_cli/lib/dartnest_cli.dart`:

```dart
library;

export 'src/cli/cli_exit_code.dart';
```

на:

```dart
library;

export 'package:dartnest_generator/dartnest_generator.dart' show SyntaxProblem;

export 'src/cli/cli_exit_code.dart';
```

Замінити в `packages/dartnest_cli/lib/dartnest_cli.dart`:

```dart
export 'src/generate/generation_session.dart';
export 'src/generate/syntax_problem.dart';
export 'src/generate/write_outcome.dart';
```

на:

```dart
export 'src/generate/generation_session.dart';
export 'src/generate/write_outcome.dart';
```

Замінити в `packages/dartnest_cli/lib/src/generate/generation_report.dart`:

```dart
import 'syntax_problem.dart';
import 'write_outcome.dart';
```

на:

```dart
import 'write_outcome.dart';
```

Замінити в `packages/dartnest_cli/lib/src/generate/package_analysis.dart`:

```dart
import '../package/package_root.dart';
import 'syntax_problem.dart';
```

на:

```dart
import '../package/package_root.dart';
```

Замінити в `packages/dartnest_cli/lib/src/generate/generation_session.dart`:

```dart
import 'package_analysis.dart';
import 'syntax_problem.dart';
```

на:

```dart
import 'package_analysis.dart';
```

Замінити в `packages/dartnest_cli/lib/src/generate/generation_session.dart`:

```dart
    if (_isEmpty(model)) {
```

на:

```dart
    if (model.isEmpty) {
```

Замінити в `packages/dartnest_cli/lib/src/generate/generation_session.dart`:

```dart
    diagnostics: diagnostics,
  );

  static bool _isEmpty(PackageModel model) =>
      model.modules.isEmpty &&
      model.injectables.isEmpty &&
      model.controllers.isEmpty;
}
```

на:

```dart
    diagnostics: diagnostics,
  );
}
```

Замінити в `packages/dartnest_cli/lib/src/package/package_root.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
```

на:

```dart
import 'dart:io';

import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:path/path.dart' as p;
```

Замінити в `packages/dartnest_cli/lib/src/package/package_root.dart`:

```dart
  static final validName = RegExp(r'^[a-z_][a-z0-9_]*$');
```

на:

```dart
  static final validName = LibraryWriter.validPackageName;
```

- [ ] **Step 6: Run the tests**

Run: `cd packages/dartnest_generator && dart test`
Expected: `+169: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+136: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `Formatted ... (0 changed)`, exit 0

- [ ] **Step 8: Commit**

```bash
git add packages/dartnest_generator packages/dartnest_cli
git commit -m "refactor(generator): share SyntaxProblem, PackageModel.isEmpty and the package name rule with drivers"
```

### Task 2: Пакет `dartnest_build` і `DartnestBuilder`

Новий член workspace. `DartnestBuilder(packageName, {generator})` оголошує `{r'$lib$': ['<packageName>.dartnest.dart']}`, читає джерела через `PackageSources` і пише вихід, коли модель не порожня й діагностик немає. Тести порівнюють з CLI: `CliGeneration` збирає ті самі файли в `TempDir` і запускає справжню `GenerationSession` (без `pub get`, `WorkspacePackageConfig`); `BuildRun` запускає builder у пам'яті (`build_test`). Conformance: `users_app` (байти = CLI = golden) і `cases_app` (ті самі рядки проблем).

**Files:**
- Modify: `pubspec.yaml` (workspace)
- Create: `packages/dartnest_build/pubspec.yaml`, `packages/dartnest_build/analysis_options.yaml`
- Create: `packages/dartnest_build/lib/dartnest_build.dart`, `packages/dartnest_build/lib/src/package_sources.dart`, `packages/dartnest_build/lib/src/dartnest_builder.dart`
- Create: `packages/dartnest_build/test/helpers/temp_dir.dart`, `workspace_package_config.dart`, `fixture_files.dart`, `cli_generation.dart`, `build_run.dart`, `shop_sources.dart`
- Test: `packages/dartnest_build/test/dartnest_builder_test.dart`, `packages/dartnest_build/test/conformance_test.dart`

**Interfaces:**
- Consumes: Task 1 (`PackageModel.isEmpty`); генератор: `PackageCollector(packageName, packageRoot).collect(List<LibraryElement>)`, `DartnestGenerator.core()`/`generate(model)` → `GenerationResult.library`/`diagnostics`/`files`; CLI (dev): `GenerationSession(PackageRoot.open(path)).run()`/`close()`, `GenerationReport.problemLines`/`diagnostics`/`syntaxProblems`; `build`: `Builder`, `BuildStep.inputId`/`findAssets`/`resolver`/`writeAsString`, `AssetId`, `log`; `build_test`: `TestReaderWriter(rootPackage:)`, `testing.loadIsolateSources()`/`exists`/`delete`/`readString`, `testBuilder(..., rootPackage:, readerWriter:, flattenOutput: true)` → `TestBuilderResult.succeeded`/`outputs`/`errors`.
- Produces:
  - `DartnestBuilder(String packageName, {DartnestGenerator generator = const DartnestGenerator.core()})`, `packageName`, `generator`, `buildExtensions`, `build(BuildStep)`.
  - `PackageSources.find(BuildStep)` → `Future<PackageSources>`, `assets` (`List<AssetId>`), `libraries()` → `Future<List<LibraryElement>>` (не в barrel).
  - Хелпери: `TempDir.create/path/resolve/write/read/exists`, `WorkspacePackageConfig.write(root, name)`, `FixtureFiles.of(package)`/`golden(package)`, `CliResult = ({GenerationReport report, String? library})`, `CliGeneration.run(name, files)`, `BuildRun.run(builder, package, [files])` + `succeeded`/`errors`/`library`, `ShopSources.package/clock/controller/module/files/user/userPart/users`.

- [ ] **Step 1: Add the package to the workspace**

Замінити в `pubspec.yaml`:

```yaml
  - packages/dartnest_annotations
```

на:

```yaml
  - packages/dartnest_annotations
  - packages/dartnest_build
```

Файл `packages/dartnest_build/pubspec.yaml`:

```yaml
name: dartnest_build
description: >-
  The build_runner builder of dartnest: writes lib/<package>.dartnest.dart
  from the annotations of a package, byte for byte what dartnest_cli gen
  writes.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  build: ^4.0.2
  dartnest_generator: ^0.1.0-dev
  glob: ^2.1.0
dev_dependencies:
  build_test: ^3.5.0
  dartnest_cli: ^0.1.0-dev
  lints: ^5.1.0
  path: ^1.9.0
  test: ^1.25.0
```

Файл `packages/dartnest_build/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

Run: `dart pub get`
Expected: `Got dependencies!` (або `Changed N dependencies!`)

- [ ] **Step 2: Write the test helpers**

`TempDir` і `WorkspacePackageConfig` — копії хелперів `dartnest_cli` (тести пакетів не діляться кодом), `TempDir` з префіксом `dartnest_build_`.

Файл `packages/dartnest_build/test/helpers/temp_dir.dart`:

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
    final directory = Directory.systemTemp.createTempSync('dartnest_build_');
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

Файл `packages/dartnest_build/test/helpers/workspace_package_config.dart`:

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

Файл `packages/dartnest_build/test/helpers/fixture_files.dart`:

```dart
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The files of `lib/` of a package of this workspace (the generator's
/// fixtures `users_app` and `cases_app`), read from this checkout.
abstract final class FixtureFiles {
  /// The files of [package]'s `lib/` except its own generated library
  /// `lib/<package>.dartnest.dart`, keyed by path relative to the package
  /// root with `/` separators (`lib/src/users.dart`).
  static Future<Map<String, String>> of(String package) async {
    final uri = await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
    if (uri == null) {
      throw StateError('$package is not in the test package config.');
    }
    final lib = Directory.fromUri(uri);
    final output = 'lib/$package.dartnest.dart';
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path when path != output)
          path: file.readAsStringSync(),
    };
  }

  /// The committed `lib/<package>.dartnest.dart` of [package].
  static Future<String> golden(String package) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:$package/$package.dartnest.dart'),
    );
    if (uri == null) {
      throw StateError('$package is not in the test package config.');
    }
    return File.fromUri(uri).readAsStringSync();
  }

  static String _path(Directory lib, File file) => p.posix.joinAll([
    'lib',
    ...p.split(p.relative(file.path, from: lib.path)),
  ]);
}
```

Файл `packages/dartnest_build/test/helpers/cli_generation.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';

import 'temp_dir.dart';
import 'workspace_package_config.dart';

/// What `dartnest_cli gen` does with a package: its report and the
/// generated library it left on disk.
typedef CliResult = ({GenerationReport report, String? library});

/// Runs the CLI's generation once over a fresh package outside the
/// workspace, resolved against this checkout without `pub get`.
abstract final class CliGeneration {
  /// Generates package [name] made of [files] (path relative to the
  /// package root → content).
  static Future<CliResult> run(String name, Map<String, String> files) async {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: $name\nenvironment:\n  sdk: ^3.8.0\n');
    Directory(dir.resolve('lib')).createSync();
    files.forEach(dir.write);
    await WorkspacePackageConfig.write(dir.path, name);
    final session = GenerationSession(PackageRoot.open(dir.path));
    try {
      final report = await session.run();
      final output = 'lib/$name.dartnest.dart';
      return (
        report: report,
        library: dir.exists(output) ? dir.read(output) : null,
      );
    } finally {
      await session.close();
    }
  }
}
```

Файл `packages/dartnest_build/test/helpers/build_run.dart`:

```dart
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';

/// One build of a package with build_test, in memory: the sources of every
/// package of the test's package config (so `package:dartnest_annotations`
/// and the workspace fixtures resolve without `pub get`), plus the given
/// files.
final class BuildRun {
  BuildRun._(this._output, this._result);

  /// Builds [package] with [builder]; [files] (path relative to the package
  /// root → content) are added to or replace its sources.
  ///
  /// A generated library the package already has is removed first, so
  /// [library] is always the builder's own output.
  static Future<BuildRun> run(
    Builder builder,
    String package, [
    Map<String, String> files = const {},
  ]) async {
    final readerWriter = TestReaderWriter(rootPackage: package);
    await readerWriter.testing.loadIsolateSources();
    final output = AssetId(package, 'lib/$package.dartnest.dart');
    if (readerWriter.testing.exists(output)) {
      readerWriter.testing.delete(output);
    }
    final result = await testBuilder(
      builder,
      {
        for (final MapEntry(:key, :value) in files.entries)
          '$package|$key': value,
      },
      rootPackage: package,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    return BuildRun._(output, result);
  }

  final AssetId _output;
  final TestBuilderResult _result;

  /// Whether the build succeeded.
  bool get succeeded => _result.succeeded;

  /// The errors the build logged, in order.
  List<String> get errors => [..._result.errors];

  /// The generated library, or `null` when the build did not write it.
  String? get library => _result.outputs.contains(_output)
      ? _result.readerWriter.testing.readString(_output)
      : null;
}
```

Файл `packages/dartnest_build/test/helpers/shop_sources.dart`:

```dart
/// Sources of a small annotated package `shop`: a clock service, a
/// controller that uses it, the root module, and the variants the builder
/// tests need.
abstract final class ShopSources {
  /// The package name.
  static const package = 'shop';

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

  /// The files of the valid package.
  static const files = {
    'lib/src/clock.dart': clock,
    'lib/src/time_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };

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

  /// `lib/src/users.dart`: a controller and module that take a [user].
  static const users = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'user.dart';

@Controller('/users')
final class UsersController {
  @Post()
  User create(@Body() User user) => user;
}

@Module(id: 'users', controllers: [UsersController])
final class UsersModule {}
''';
}
```

- [ ] **Step 3: Write the failing tests**

Файл `packages/dartnest_build/test/dartnest_builder_test.dart`:

```dart
import 'package:dartnest_build/dartnest_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(Map<String, String> files) => BuildRun.run(
  DartnestBuilder(ShopSources.package),
  ShopSources.package,
  files,
);

void main() {
  test('the library is the one the CLI writes', () async {
    final build = await _build(ShopSources.files);
    final cli = await CliGeneration.run(ShopSources.package, ShopSources.files);

    expect(build.succeeded, isTrue);
    expect(build.library, cli.library);
  });

  test('a package without annotations gets no library', () async {
    final build = await _build({
      'lib/src/plain.dart': 'final class Plain {}\n',
    });

    expect(build.succeeded, isTrue);
    expect(build.library, isNull);
  });

  // Review Focus 1: a stale or foreign *.dartnest.dart in lib/ is not read.
  test('generated libraries in lib/ are not sources', () async {
    final files = {
      ...ShopSources.files,
      'lib/src/old.dartnest.dart': 'this is not Dart',
    };

    final build = await _build(files);

    expect(build.succeeded, isTrue);
    expect(build.library, (await CliGeneration.run('shop', files)).library);
  });

  // Review Focus 4: build_runner may run before json_serializable.
  test('a part another builder has not written yet changes nothing', () async {
    final withPart = await _build({
      'lib/src/user.dart': ShopSources.user,
      'lib/src/user.g.dart': ShopSources.userPart,
      'lib/src/users.dart': ShopSources.users,
    });
    final withoutPart = await _build({
      'lib/src/user.dart': ShopSources.user,
      'lib/src/users.dart': ShopSources.users,
    });

    expect(withPart.library, isNotNull);
    expect(withoutPart.library, withPart.library);
  });
}
```

Файл `packages/dartnest_build/test/conformance_test.dart`:

```dart
// The builder and `dartnest_cli gen` over the generator's fixtures: the same
// bytes for users_app (the golden package), the same problems for
// cases_app (one scenario per library, most of them invalid).
import 'dart:convert';

import 'package:dartnest_build/dartnest_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/fixture_files.dart';

void main() {
  test('users_app: the builder writes the bytes the CLI writes', () async {
    final build = await BuildRun.run(DartnestBuilder('users_app'), 'users_app');
    final cli = await CliGeneration.run(
      'users_app',
      await FixtureFiles.of('users_app'),
    );

    final library = cli.library ?? fail('the CLI wrote no library');
    expect(utf8.encode(build.library ?? ''), utf8.encode(library));
  });

  test('users_app: the builder writes the committed golden library', () async {
    final build = await BuildRun.run(DartnestBuilder('users_app'), 'users_app');
    final golden = await FixtureFiles.golden('users_app');

    expect(build.library, golden);
  });

  test('cases_app: the builder reports the problems the CLI reports', () async {
    final build = await BuildRun.run(DartnestBuilder('cases_app'), 'cases_app');
    final cli = await CliGeneration.run(
      'cases_app',
      await FixtureFiles.of('cases_app'),
    );

    expect(cli.report.diagnostics, isNotEmpty);
    expect(build.errors, cli.report.problemLines);
  });
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd packages/dartnest_build && dart test`
Expected: FAIL — `Error: Error when reading 'lib/dartnest_build.dart': No such file or directory`

- [ ] **Step 5: Implement `PackageSources` and `DartnestBuilder`**

Файл `packages/dartnest_build/lib/dartnest_build.dart`:

```dart
/// The build_runner builder of dartnest: writes
/// `lib/<package>.dartnest.dart` from the annotations of a package, byte
/// for byte what `dartnest_cli gen` writes for the same sources.
///
/// [DartnestBuilder] is the builder; `build.yaml` of this package applies
/// it to every package that depends on `dartnest_build`.
library;

export 'src/dartnest_builder.dart';
```

Файл `packages/dartnest_build/lib/src/package_sources.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// The Dart sources of a package's `lib/` as one build step sees them:
/// every `*.dart` asset except generated `*.dartnest.dart` files, sorted by
/// path, the files `dartnest_cli gen` reads.
final class PackageSources {
  PackageSources._(this._step, this.assets);

  /// Finds the sources of the package [step] builds.
  static Future<PackageSources> find(BuildStep step) async {
    final assets = await step
        .findAssets(_dartFiles)
        .where((asset) => !asset.path.endsWith('.dartnest.dart'))
        .toList();
    return PackageSources._(step, assets..sort());
  }

  static final _dartFiles = Glob('lib/**.dart');

  final BuildStep _step;

  /// The sources, sorted by path.
  final List<AssetId> assets;

  /// The resolved libraries among [assets]; part files are skipped.
  Future<List<LibraryElement>> libraries() async {
    final resolver = _step.resolver;
    return [
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ];
  }
}
```

Файл `packages/dartnest_build/lib/src/dartnest_builder.dart`:

```dart
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'package_sources.dart';

/// Writes `lib/<package>.dartnest.dart` of package [packageName] from the
/// annotations of its `lib/`, as `dartnest_cli gen` does: the same files
/// are read, the same constructs run and the same bytes are written.
///
/// An aggregating builder on `lib/$lib$`: one build step reads every
/// source of `lib/`. Problems are logged as errors, one per line, in the
/// CLI's `path:line:column: error: message [code]` form, and fail the
/// build; nothing is written then.
final class DartnestBuilder implements Builder {
  /// Creates the builder of package [packageName], generating with
  /// [generator].
  DartnestBuilder(
    this.packageName, {
    this.generator = const DartnestGenerator.core(),
  });

  /// The package whose library this builder writes.
  final String packageName;

  /// The constructs that run.
  final DartnestGenerator generator;

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['$packageName.dartnest.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final sources = await PackageSources.find(buildStep);
    // Diagnostic paths are relative to this root: build_runner's analyzer
    // sees the files of package p under /p/.
    final model = PackageCollector(
      package,
      '/$package',
    ).collect(await sources.libraries());
    if (model.isEmpty) return;
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) {
      result.diagnostics.map((diagnostic) => '$diagnostic').forEach(log.severe);
      return;
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/$package.dartnest.dart'),
      library,
    );
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `cd packages/dartnest_build && dart test`
Expected: `+7: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: 0 changed, exit 0

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml packages/dartnest_build
git commit -m "feat(build): DartnestBuilder writes the library the CLI writes"
```

### Task 3: Синтаксичні помилки й файли конструктів

Без перевірки синтаксису `libraryFor` кидає `SyntaxErrorInAssetException`, і build_runner друкує `1:30: Expected to find ')'.` без шляху й коду. `PackageSources.syntaxProblems()` перевіряє кожне джерело (частини теж) через `compilationUnitFor` і перетворює помилки на `SyntaxProblem` — ті самі рядки, що в CLI (OD8). `FileUnit` конструкта валить збірку (OD5). Тестовий `FileConstruct` дає `openapi.json`, як майбутній OpenAPI-конструкт.

**Files:**
- Modify: `packages/dartnest_build/lib/src/package_sources.dart`, `packages/dartnest_build/lib/src/dartnest_builder.dart`
- Modify: `packages/dartnest_build/test/helpers/shop_sources.dart`
- Create: `packages/dartnest_build/test/helpers/file_construct.dart`
- Test: `packages/dartnest_build/test/problems_test.dart`

**Interfaces:**
- Consumes: Task 1 (`SyntaxProblem`), Task 2 (`PackageSources`, `DartnestBuilder`, хелпери); `build`: `Resolver.compilationUnitFor(AssetId)`, `SyntaxErrorInAssetException.filesWithErrors` (`AnalysisResultWithDiagnostics`: `lineInfo`, `diagnostics` з `offset`/`message`); генератор: `Construct` (`validate`, `generate`), `FileUnit(path:, contentType:, content:)`, `ContentType.json`, `DartnestGenerator(constructs)`.
- Produces: `PackageSources.syntaxProblems()` → `Future<List<SyntaxProblem>>` (відсортовано); `ShopSources.broken`; `FileConstruct()`.

- [ ] **Step 1: Write the failing tests**

Замінити в `packages/dartnest_build/test/helpers/shop_sources.dart`:

```dart
  /// `lib/src/user.dart`: a request body whose `fromJson` lives in a part
```

на:

```dart
  /// `lib/src/broken.dart`: two syntax errors on one line.
  static const broken = 'final class Broken { void f( }\n';

  /// `lib/src/user.dart`: a request body whose `fromJson` lives in a part
```

Файл `packages/dartnest_build/test/helpers/file_construct.dart`:

```dart
import 'package:dartnest_generator/dartnest_generator.dart';

/// A [Construct] that generates one file of its own, `openapi.json`, like
/// the OpenAPI construct of v1.1 will.
final class FileConstruct implements Construct {
  /// Creates the construct.
  const FileConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => const [];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [
    FileUnit(
      path: 'openapi.json',
      contentType: ContentType.json,
      content: '{}',
    ),
  ];
}
```

Файл `packages/dartnest_build/test/problems_test.dart`:

```dart
import 'package:dartnest_build/dartnest_build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/file_construct.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(
  Map<String, String> files, {
  DartnestGenerator generator = const DartnestGenerator.core(),
}) => BuildRun.run(
  DartnestBuilder(ShopSources.package, generator: generator),
  ShopSources.package,
  files,
);

void main() {
  test('syntax errors are reported as the CLI reports them', () async {
    final files = {
      ...ShopSources.files,
      'lib/src/broken.dart': ShopSources.broken,
    };

    final build = await _build(files);
    final cli = await CliGeneration.run(ShopSources.package, files);

    expect(cli.report.syntaxProblems, hasLength(2));
    expect(build.errors, cli.report.problemLines);
  });

  test('syntax errors fail the build and write nothing', () async {
    final build = await _build({
      ...ShopSources.files,
      'lib/src/broken.dart': ShopSources.broken,
    });

    expect(build.succeeded, isFalse);
    expect(build.library, isNull);
  });

  // Review Focus 3: a part file is checked, not resolved as a library.
  test('a syntax error in a part file is reported at the part', () async {
    final files = {
      'lib/src/user.dart': ShopSources.user,
      'lib/src/user.g.dart': 'part of \'user.dart\';\n\nvoid f( {}\n',
      'lib/src/users.dart': ShopSources.users,
    };

    final build = await _build(files);
    final cli = await CliGeneration.run(ShopSources.package, files);

    expect(build.errors, everyElement(startsWith('lib/src/user.g.dart:')));
    expect(build.errors, cli.report.problemLines);
  });

  test('a file generated by a construct fails the build', () async {
    final generator = DartnestGenerator([
      ...const DartnestGenerator.core().constructs,
      const FileConstruct(),
    ]);

    final build = await _build(ShopSources.files, generator: generator);

    expect(build.errors, [
      'dartnest_build cannot write openapi.json: a construct generated it, '
          'and a build_runner builder writes only lib/<package>.dartnest.dart. '
          'Generate this package with dartnest_cli gen.',
    ]);
    expect(build.library, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/dartnest_build && dart test test/problems_test.dart`
Expected: FAIL — `+1 -3: Some tests failed.`; у `syntax errors are reported as the CLI reports them` — `Actual: ['1:30: Expected to find \')\'.' ...]`; у `a file generated by a construct fails the build` — `Actual: []`

- [ ] **Step 3: Check the syntax of every source**

Файл `packages/dartnest_build/lib/src/package_sources.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:glob/glob.dart';

/// The Dart sources of a package's `lib/` as one build step sees them:
/// every `*.dart` asset except generated `*.dartnest.dart` files, sorted by
/// path, the files `dartnest_cli gen` reads.
final class PackageSources {
  PackageSources._(this._step, this.assets);

  /// Finds the sources of the package [step] builds.
  static Future<PackageSources> find(BuildStep step) async {
    final assets = await step
        .findAssets(_dartFiles)
        .where((asset) => !asset.path.endsWith('.dartnest.dart'))
        .toList();
    return PackageSources._(step, assets..sort());
  }

  static final _dartFiles = Glob('lib/**.dart');

  final BuildStep _step;

  /// The sources, sorted by path.
  final List<AssetId> assets;

  /// The syntax errors of [assets], part files included, sorted by
  /// location: what the parser reports, as the CLI reports it.
  Future<List<SyntaxProblem>> syntaxProblems() async {
    final problems = [
      for (final asset in assets) ...await _syntaxProblemsOf(asset),
    ];
    return problems..sort();
  }

  /// The resolved libraries among [assets]; part files are skipped.
  Future<List<LibraryElement>> libraries() async {
    final resolver = _step.resolver;
    return [
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ];
  }

  Future<List<SyntaxProblem>> _syntaxProblemsOf(AssetId asset) async {
    try {
      await _step.resolver.compilationUnitFor(asset);
      return const [];
    } on SyntaxErrorInAssetException catch (error) {
      return [
        for (final file in error.filesWithErrors)
          for (final diagnostic in file.diagnostics)
            SyntaxProblem(
              _location(asset, file.lineInfo, diagnostic.offset),
              diagnostic.message,
            ),
      ];
    }
  }

  static SourceLocation _location(AssetId asset, LineInfo lines, int offset) {
    final position = lines.getLocation(offset);
    return SourceLocation(
      asset.path,
      position.lineNumber,
      position.columnNumber,
    );
  }
}
```

- [ ] **Step 4: Report syntax errors and generated files**

Файл `packages/dartnest_build/lib/src/dartnest_builder.dart`:

```dart
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'package_sources.dart';

/// Writes `lib/<package>.dartnest.dart` of package [packageName] from the
/// annotations of its `lib/`, as `dartnest_cli gen` does: the same files
/// are read, the same constructs run and the same bytes are written.
///
/// An aggregating builder on `lib/$lib$`: one build step reads every
/// source of `lib/`. Problems are logged as errors, one per line, in the
/// CLI's `path:line:column: error: message [code]` form, and fail the
/// build; nothing is written then.
final class DartnestBuilder implements Builder {
  /// Creates the builder of package [packageName], generating with
  /// [generator].
  DartnestBuilder(
    this.packageName, {
    this.generator = const DartnestGenerator.core(),
  });

  /// The package whose library this builder writes.
  final String packageName;

  /// The constructs that run.
  final DartnestGenerator generator;

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['$packageName.dartnest.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final sources = await PackageSources.find(buildStep);
    final syntaxProblems = await sources.syntaxProblems();
    if (syntaxProblems.isNotEmpty) return _fail(syntaxProblems);
    // Diagnostic paths are relative to this root: build_runner's analyzer
    // sees the files of package p under /p/.
    final model = PackageCollector(
      package,
      '/$package',
    ).collect(await sources.libraries());
    if (model.isEmpty) return;
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) return _fail(result.diagnostics);
    if (result.files.isNotEmpty) {
      return _fail([for (final file in result.files) _unwritable(file)]);
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/$package.dartnest.dart'),
      library,
    );
  }

  static void _fail(Iterable<Object> problems) {
    for (final problem in problems) {
      log.severe('$problem');
    }
  }

  static String _unwritable(FileUnit file) =>
      'dartnest_build cannot write ${file.path}: a construct generated it, '
      'and a build_runner builder writes only lib/<package>.dartnest.dart. '
      'Generate this package with dartnest_cli gen.';
}
```

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest_build && dart test`
Expected: `+11: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: 0 changed, exit 0

- [ ] **Step 7: Commit**

```bash
git add packages/dartnest_build
git commit -m "feat(build): syntax errors and generated files fail the build"
```

### Task 4: `build.yaml`, опція `package` і справжній build_runner

Фабрика `dartnestBuilder` для `build.yaml`, `DartnestBuildOptions` (OD1), `ConfigurationErrorBuilder` і перевірка «опція називає інший пакет» у `DartnestBuilder` (Review Focus 2). `build.yaml` пакета оголошує builder `dartnest_build` (OD10). Фікстура `users_app` отримує `build.yaml` і dev-залежності, а `integration/build_runner_test.dart` запускає `dart run build_runner build --only-check` у ній: код 0 означає, що builder пише рівно закомічений golden.

**Files:**
- Create: `packages/dartnest_build/lib/src/dartnest_build_options.dart`, `packages/dartnest_build/lib/src/configuration_error_builder.dart`, `packages/dartnest_build/build.yaml`
- Modify: `packages/dartnest_build/lib/dartnest_build.dart`, `packages/dartnest_build/lib/src/dartnest_builder.dart`
- Modify: `packages/dartnest_generator/test/fixtures/users_app/pubspec.yaml`; Create: `packages/dartnest_generator/test/fixtures/users_app/build.yaml`
- Test: `packages/dartnest_build/test/options_test.dart`, `packages/dartnest_build/integration/build_runner_test.dart`

**Interfaces:**
- Consumes: Task 1 (`LibraryWriter.validPackageName`), Task 2–3 (`DartnestBuilder`, `BuildRun`, `ShopSources`); `build`: `BuilderOptions(config)`.
- Produces (barrel `dartnest_build`):
  - `Builder dartnestBuilder(BuilderOptions options)` — top-level фабрика.
  - `DartnestBuildOptions.packageKey` (`'package'`), `builderFor(BuilderOptions, {DartnestGenerator generator})` → `Builder`, `buildYaml(String package)` → `String`.
  - `ConfigurationErrorBuilder(String problem)` — не в barrel; оголошує `{r'$lib$': ['dartnest_build.unconfigured']}`, нічого не пише.
  - `build.yaml`: builder `dartnest_build`, `builder_factories: [dartnestBuilder]`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_build/test/options_test.dart`:

```dart
import 'package:build/build.dart';
import 'package:dartnest_build/dartnest_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(Map<String, Object?> config) => BuildRun.run(
  dartnestBuilder(BuilderOptions(config)),
  ShopSources.package,
  ShopSources.files,
);

String _error(String problem) =>
    'dartnest_build cannot build shop: $problem. '
    'Name the package in its build.yaml:\n\n'
    'targets:\n'
    '  \$default:\n'
    '    builders:\n'
    '      dartnest_build:\n'
    '        options:\n'
    '          package: shop\n';

void main() {
  test('the package option names the library', () async {
    final builder = dartnestBuilder(const BuilderOptions({'package': 'shop'}));

    expect(builder.buildExtensions, {
      r'$lib$': ['shop.dartnest.dart'],
    });
    expect((await _build({'package': 'shop'})).library, isNotNull);
  });

  test('a missing package option fails the build', () async {
    final build = await _build({});

    expect(build.succeeded, isFalse);
    expect(build.errors, [_error('the option "package" is missing')]);
    expect(build.library, isNull);
  });

  test('an invalid package name fails the build', () async {
    final build = await _build({'package': 'Shop-App'});

    expect(build.errors, [_error('"Shop-App" is not a package name')]);
  });

  test('an unknown option fails the build', () async {
    final build = await _build({'package': 'shop', 'pakage': 'shop'});

    expect(build.errors, [_error('unknown option pakage')]);
  });

  // Review Focus 2: build.yaml copied from another workspace member.
  test('the name of another package fails the build', () async {
    final build = await _build({'package': 'users_app'});

    expect(build.succeeded, isFalse);
    expect(build.errors, [
      'dartnest_build cannot build shop: its build.yaml names the package '
          '"users_app". Name the package in its build.yaml:\n\n'
          '${DartnestBuildOptions.buildYaml('shop')}',
    ]);
    expect(build.library, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest_build && dart test test/options_test.dart`
Expected: FAIL — `Error: Method not found: 'dartnestBuilder'.`

- [ ] **Step 3: Implement the options and the error builder**

Файл `packages/dartnest_build/lib/src/configuration_error_builder.dart`:

```dart
import 'package:build/build.dart';

import 'dartnest_build_options.dart';

/// The builder that stands in for `dartnest_build` when its options in
/// `build.yaml` are missing or wrong: it writes nothing and fails the build
/// with [problem] and the `build.yaml` to write.
final class ConfigurationErrorBuilder implements Builder {
  /// Creates the builder that reports [problem].
  const ConfigurationErrorBuilder(this.problem);

  /// What is wrong with the options.
  final String problem;

  /// An output that is never written: build_runner before 2.16 and
  /// build_test skip a builder that declares none, and the build would
  /// pass silently.
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$lib$': ['dartnest_build.unconfigured'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    log.severe(
      'dartnest_build cannot build $package: $problem. '
      'Name the package in its build.yaml:\n\n'
      '${DartnestBuildOptions.buildYaml(package)}',
    );
  }
}
```

Файл `packages/dartnest_build/lib/src/dartnest_build_options.dart`:

```dart
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'configuration_error_builder.dart';
import 'dartnest_builder.dart';

/// The options of `dartnest_build` in a package's `build.yaml`: the only
/// one, `package`, names the package, which build_runner does not tell a
/// builder before it builds; its output, `lib/<package>.dartnest.dart`,
/// must be declared before.
abstract final class DartnestBuildOptions {
  /// The option that names the package.
  static const packageKey = 'package';

  /// The builder [options] configure: a [DartnestBuilder] generating with
  /// [generator], or, when the options are missing or wrong, a builder that
  /// writes nothing and fails the build with what to put in `build.yaml`.
  static Builder builderFor(
    BuilderOptions options, {
    DartnestGenerator generator = const DartnestGenerator.core(),
  }) {
    final config = options.config;
    final unknown = [
      for (final key in config.keys)
        if (key != packageKey) key,
    ]..sort();
    if (unknown.isNotEmpty) {
      return ConfigurationErrorBuilder('unknown option ${unknown.join(', ')}');
    }
    return switch (config[packageKey]) {
      final String name when LibraryWriter.validPackageName.hasMatch(name) =>
        DartnestBuilder(name, generator: generator),
      null => const ConfigurationErrorBuilder(
        'the option "package" is missing',
      ),
      final Object name => ConfigurationErrorBuilder(
        '"$name" is not a package name',
      ),
    };
  }

  /// The `build.yaml` that configures `dartnest_build` for [package].
  static String buildYaml(String package) =>
      'targets:\n'
      '  \$default:\n'
      '    builders:\n'
      '      dartnest_build:\n'
      '        options:\n'
      '          $packageKey: $package\n';
}
```

Файл `packages/dartnest_build/lib/dartnest_build.dart`:

```dart
/// The build_runner builder of dartnest: writes
/// `lib/<package>.dartnest.dart` from the annotations of a package, byte
/// for byte what `dartnest_cli gen` writes for the same sources.
///
/// `build.yaml` of this package applies [dartnestBuilder] to every package
/// that depends on `dartnest_build`; the package names itself in its own
/// `build.yaml` ([DartnestBuildOptions]).
library;

import 'package:build/build.dart';

import 'src/dartnest_build_options.dart';

export 'src/dartnest_build_options.dart';
export 'src/dartnest_builder.dart';

/// The builder factory `build.yaml` names: the [Builder] that
/// [DartnestBuildOptions.builderFor] makes from [options].
Builder dartnestBuilder(BuilderOptions options) =>
    DartnestBuildOptions.builderFor(options);
```

- [ ] **Step 4: Check the package name in the builder**

Файл `packages/dartnest_build/lib/src/dartnest_builder.dart`:

```dart
import 'package:build/build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import 'dartnest_build_options.dart';
import 'package_sources.dart';

/// Writes `lib/<package>.dartnest.dart` of package [packageName] from the
/// annotations of its `lib/`, as `dartnest_cli gen` does: the same files
/// are read, the same constructs run and the same bytes are written.
///
/// An aggregating builder on `lib/$lib$`: one build step reads every
/// source of `lib/`. Problems are logged as errors, one per line, in the
/// CLI's `path:line:column: error: message [code]` form, and fail the
/// build; nothing is written then.
final class DartnestBuilder implements Builder {
  /// Creates the builder of package [packageName], generating with
  /// [generator].
  DartnestBuilder(
    this.packageName, {
    this.generator = const DartnestGenerator.core(),
  });

  /// The package whose library this builder writes.
  final String packageName;

  /// The constructs that run.
  final DartnestGenerator generator;

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['$packageName.dartnest.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    if (package != packageName) return _fail([_misnamed(package)]);
    final sources = await PackageSources.find(buildStep);
    final syntaxProblems = await sources.syntaxProblems();
    if (syntaxProblems.isNotEmpty) return _fail(syntaxProblems);
    // Diagnostic paths are relative to this root: build_runner's analyzer
    // sees the files of package p under /p/.
    final model = PackageCollector(
      package,
      '/$package',
    ).collect(await sources.libraries());
    if (model.isEmpty) return;
    final result = generator.generate(model);
    final library = result.library;
    if (library == null) return _fail(result.diagnostics);
    if (result.files.isNotEmpty) {
      return _fail([for (final file in result.files) _unwritable(file)]);
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/$package.dartnest.dart'),
      library,
    );
  }

  static void _fail(Iterable<Object> problems) {
    for (final problem in problems) {
      log.severe('$problem');
    }
  }

  String _misnamed(String package) =>
      'dartnest_build cannot build $package: its build.yaml names the '
      'package "$packageName". Name the package in its build.yaml:\n\n'
      '${DartnestBuildOptions.buildYaml(package)}';

  static String _unwritable(FileUnit file) =>
      'dartnest_build cannot write ${file.path}: a construct generated it, '
      'and a build_runner builder writes only lib/<package>.dartnest.dart. '
      'Generate this package with dartnest_cli gen.';
}
```

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest_build && dart test`
Expected: `+16: All tests passed!`

- [ ] **Step 6: Declare the builder and configure `users_app`**

Файл `packages/dartnest_build/build.yaml`:

```yaml
builders:
  dartnest_build:
    import: package:dartnest_build/dartnest_build.dart
    builder_factories: [dartnestBuilder]
    build_extensions: {"$lib$": ["<package>.dartnest.dart"]}
    auto_apply: dependents
    build_to: source
```

Файл `packages/dartnest_generator/test/fixtures/users_app/build.yaml`:

```yaml
# dartnest_build writes lib/users_app.dartnest.dart; build_runner does not
# tell a builder the package name before it builds, so it is named here.
targets:
  $default:
    builders:
      dartnest_build:
        options:
          package: users_app
```

Замінити в `packages/dartnest_generator/test/fixtures/users_app/pubspec.yaml`:

```yaml
dependencies:
  dartnest: ^0.1.0-dev
  dartnest_annotations: ^0.1.0-dev
```

на:

```yaml
dependencies:
  dartnest: ^0.1.0-dev
  dartnest_annotations: ^0.1.0-dev

# The build_runner way of generating lib/users_app.dartnest.dart; the
# integration test of dartnest_build checks the golden with it.
dev_dependencies:
  build_runner: ^2.16.0
  dartnest_build: ^0.1.0-dev
```

Run: `dart pub get`
Expected: `Changed N dependencies!` (build_runner і його залежності)

- [ ] **Step 7: Write the integration test**

Файл `packages/dartnest_build/integration/build_runner_test.dart`:

```dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// The root of the generator's golden fixture `users_app`, whose
/// `build.yaml` configures `dartnest_build`.
Future<Directory> usersApp() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:users_app/'));
  if (lib == null) throw StateError('users_app is not in the package config.');
  return Directory.fromUri(lib.resolve('..'));
}

void main() {
  // The real build_runner, as a child process: it compiles the build
  // script (about 20 s the first time) and checks, writing nothing, that
  // the outputs it would write are the committed ones.
  test('build_runner generates the committed golden library', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'build',
      '--only-check',
    ], workingDirectory: (await usersApp()).path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
```

Run: `cd packages/dartnest_build && dart test integration`
Expected: `+1: All tests passed!` (~25 с: AOT-компіляція build-скрипта). Перевірка, що тест справді ловить розбіжність (вручну, не комітити): дописати рядок у `lib/users_app.dartnest.dart` фікстури → `dart run build_runner build --only-check` у `users_app` друкує `Verify failed due to Incorrect|Missing|Unexpected:` і `I lib/users_app.dartnest.dart`, код 1, файл не змінено; повернути файл (`git checkout -- packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dartnest.dart`).

- [ ] **Step 8: Run the other suites, analyze and format**

Run: `cd packages/dartnest_generator && dart test`
Expected: `+169: All tests passed!`

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: 0 changed, exit 0

Run: `git status --short`
Expected: лише файли цієї задачі (`.dart_tool/` фікстури ігнорується)

- [ ] **Step 9: Commit**

```bash
git add packages/dartnest_build packages/dartnest_generator/test/fixtures/users_app
git commit -m "feat(build): build.yaml, the package option and the build_runner check of users_app"
```

### Task 5: README, `CLAUDE.md`, роадмап

README `dartnest_build` (налаштування, команди, `--only-check`, відмінності від CLI — OD3, співіснування з `gen --watch`/`dev` — OD7, власні конструкти, версії — OD4, тести). `CLAUDE.md`: команда інтеграційного тесту, правило `analyzer`/`build`, правило виходу під build_runner, виняток для фабрики, правило тестів. Роадмап: рядок 6 посилається на план. README CLI — розділ `build_runner`.

**Files:**
- Create: `packages/dartnest_build/README.md`
- Modify: `CLAUDE.md`, `docs/superpowers/ROADMAP.md`, `packages/dartnest_cli/README.md`

**Interfaces:**
- Consumes: імена з Task 2–4 (`DartnestBuildOptions.builderFor`, `dartnestBuilder`, опція `package`, `integration/build_runner_test.dart`).
- Produces: документацію; коду немає.

- [ ] **Step 1: Write the README**

Файл `packages/dartnest_build/README.md`:

````markdown
# dartnest_build

The build_runner builder of dartnest. It writes `lib/<package>.dartnest.dart`
from the annotations of a package: the same files are read, the same
constructs run and the same bytes are written as by `dartnest_cli gen`.
Use it when a package already generates code with build_runner (for example
`json_serializable`); otherwise `dartnest_cli gen --watch` and `dev` are
faster and need no configuration.

```yaml
# pubspec.yaml
dev_dependencies:
  build_runner: ^2.10.0
  dartnest_build: ^0.1.0
```

```yaml
# build.yaml, next to pubspec.yaml
targets:
  $default:
    builders:
      dartnest_build:
        options:
          package: shop # the name in pubspec.yaml
```

```sh
dart run build_runner build                 # generate once
dart run build_runner watch                 # regenerate on every change
dart run build_runner build --only-check    # build_runner 2.16+: fail if a generated file is out of date, write nothing
```

## The package option

build_runner does not tell a builder which package it builds before the
build, and the builder must declare its output, `lib/<package>.dartnest.dart`,
before. So the package names itself in its `build.yaml`. A missing option,
a name that is not a valid package name, an unknown option or the name of
another package (a `build.yaml` copied from another package) fails the build
with the `build.yaml` to write; nothing is written.

## What it does

- Reads every Dart file of `lib/` except generated `*.dartnest.dart` files
  and runs the core constructs of `dartnest_generator`
  (`DartnestGenerator.core()`), as `dartnest_cli gen` does.
- Problems are build errors, one per line, as
  `path:line:column: error: message [code]`, the lines `dartnest_cli gen`
  prints for the same sources. Syntax errors (in part files too) have the
  code `syntax_error`; the generator's codes are listed in the
  `dartnest_generator` README. Any problem fails the build and nothing is
  written.
- A part another builder has not written yet (`user.g.dart` of
  `json_serializable`) does not change the output: the generator reads
  annotations and declarations, not generated members.
- When `lib/` has no annotations, nothing is written; build_runner deletes
  a library it generated before.
- A construct that generates a file of its own (`FileUnit`) fails the
  build: this builder writes only `lib/<package>.dartnest.dart`. Generate
  such a package with `dartnest_cli gen`.

## Differences from dartnest_cli gen

- **The output belongs to build_runner.** `dartnest_cli gen` never
  overwrites a file without the generated header; build_runner deletes a
  file in the way of an output (since build_runner 2.7, conflicting
  outputs are always deleted) before any builder runs. Do not keep a
  hand-written `lib/<package>.dartnest.dart`.
- **Problems delete the library.** `dartnest_cli gen` leaves the library
  as it was while the sources have problems; build_runner deletes the
  previous output of a failed build step, so code that imports the library
  stops compiling until the problems are fixed.
- The generated header is the same, so `dartnest_cli gen` and `dev` accept
  a library build_runner wrote, and the other way round.

## build_runner and dartnest_cli in one package

Both write the same bytes and the same header, so they never fight over
the library, but give it one writer per package:

- `dart run build_runner watch`, when other builders (`json_serializable`)
  run anyway; restart the application yourself.
- `dartnest_cli dev` (or `gen --watch`) for hot reload. If other builders
  need `dart run build_runner watch` beside it, disable `dartnest_build`
  in the package's `build.yaml` (`enabled: false` under
  `dartnest_build:`), so build_runner does not rewrite or delete the
  library `dev` reloads.

## Own constructs

Dart cannot load constructs at run time, so a package with constructs of
its own declares its own builder. With `build`, `dartnest_build` and
`dartnest_generator` in its dev dependencies:

```dart
// tool/builder.dart
import 'package:build/build.dart';
import 'package:dartnest_build/dartnest_build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

Builder shopBuilder(BuilderOptions options) => DartnestBuildOptions.builderFor(
  options,
  generator: DartnestGenerator([
    ...const DartnestGenerator.core().constructs,
    // MyConstruct(),
  ]),
);
```

```yaml
# build.yaml
builders:
  dartnest:
    import: tool/builder.dart
    builder_factories: [shopBuilder]
    build_extensions: {"$lib$": ["<package>.dartnest.dart"]}
    build_to: source
    auto_apply: root_package
targets:
  $default:
    builders:
      dartnest_build:
        enabled: false
      shop:dartnest:
        options:
          package: shop
```

## Versions

`build` `^4.0.2` and `analyzer` `>=8.1.1 <15.0.0`, the range of
`dartnest_generator`; with build_runner 2.10.5 to 2.16.2 the builder was
checked on both edges. `--only-check` needs build_runner 2.16.

## Tests

`dart test` builds packages in memory with `build_test`. The real
build_runner runs only in the integration test, which is not part of
`dart test` (it compiles the build script, about 20 s the first time):

```sh
cd packages/dartnest_build && dart test integration
```

It runs `dart run build_runner build --only-check` in the generator's golden
fixture `users_app` and passes when the committed
`lib/users_app.dartnest.dart` is what the builder writes.
````

Приклад «Own constructs» перевірено справжнім build_runner 2.16.2 у копії `users_app` (`tool/builder.dart`, `enabled: false` для `dartnest_build`, `--only-check` — код 0).

- [ ] **Step 2: Add a build_runner section to the CLI README**

Замінити в `packages/dartnest_cli/README.md`:

```markdown
analysis kept in memory, for tools that decide themselves when to run.
```

на:

```markdown
analysis kept in memory, for tools that decide themselves when to run.

## build_runner

`dartnest_build` runs the same generation as a build_runner builder and
writes the bytes `gen` writes, so a package that already uses build_runner
can generate with it instead. Its README says when to use which and how the
two share a package.
```

- [ ] **Step 3: Update `CLAUDE.md`**

Замінити в `CLAUDE.md`:

```markdown
# packages/dartnest_cli: the dev integration tests (not part of `dart test`):
dart test integration
```

на:

```markdown
# packages/dartnest_cli: the dev integration tests (not part of `dart test`):
dart test integration
# packages/dartnest_build: the real build_runner over the golden fixture
# users_app (not part of `dart test`; about 20 s the first time):
dart test integration
```

Замінити в `CLAUDE.md`:

```markdown
  `analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`, and
  `vm_service` only in `dartnest_cli`. `dart:developer` (SDK) is allowed in
  the core for the hot reload service extensions, which register only
  outside product mode.
```

на:

```markdown
  `analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`/
  `dartnest_build`, `vm_service` only in `dartnest_cli`, and `build` only
  in `dartnest_build`. `dart:developer` (SDK) is allowed in the core for
  the hot reload service extensions, which register only outside product
  mode.
```

Замінити в `CLAUDE.md`:

```markdown
  leaves it as it was while the sources have problems.
```

на:

```markdown
  leaves it as it was while the sources have problems. Under build_runner
  (`dartnest_build`) the output belongs to build_runner, which deletes a
  conflicting file and the output of a failed step; the builder writes the
  same bytes and header as the CLI, so either accepts the other's file.
```

Замінити в `CLAUDE.md`:

```markdown
  `Module databaseModule({...})`, `env(...)`, `describeKey`) and `main`.
```

на:

```markdown
  `Module databaseModule({...})`, `env(...)`, `describeKey`), builder
  factories that `build.yaml` names (`dartnestBuilder`, in the
  `dartnest_build` library) and `main`.
```

Замінити в `CLAUDE.md`:

```markdown
  of `dart test`) also runs the real `dartnest dev` as a child process.
```

на:

```markdown
  of `dart test`) also runs the real `dartnest dev` as a child process.
  `dartnest_build` tests build in memory with `build_test`
  (`TestReaderWriter` + `loadIsolateSources()`, no `pub get`), and compare
  with the CLI through `GenerationSession` on a `TempDir` package;
  `integration/build_runner_test.dart` (run with `dart test integration`)
  runs the real build_runner as a child process.
```

- [ ] **Step 4: Link the plan from the roadmap**

Замінити в `docs/superpowers/ROADMAP.md`:

```markdown
| 6 | **build_runner-драйвер** | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
```

на:

```markdown
| 6 | **build_runner-драйвер** (план `2026-10-14-dartnest-build-runner.md`) | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
```

- [ ] **Step 5: Analyze, format and run everything once more**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: 0 changed, exit 0

Run: `cd packages/dartnest_build && dart test && dart test integration`
Expected: `+16: All tests passed!`, потім `+1: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/superpowers/ROADMAP.md packages/dartnest_build/README.md packages/dartnest_cli/README.md
git commit -m "docs: dartnest_build README, CLAUDE.md rules and roadmap row 6"
```

## Самоперевірка

**Покриття спеки й завдання.**

| Вимога | Задача |
|---|---|
| Спека 6 «Драйвери»: `Builder` з `buildExtensions: {r'$lib$': ['<pkg>.dartnest.dart']}` | 2 (`DartnestBuilder.buildExtensions`), 4 (`build.yaml`, опція `package` — OD1) |
| Спека 6: `findAssets` + `resolver.libraryFor` будують той самий `PackageModel` | 2 (`PackageSources`, `PackageCollector`) |
| Спека 3: `dartnest_build` залежить від `dartnest_generator` і `build` | 2 (`pubspec.yaml`), 5 (`CLAUDE.md`) |
| Роадмап 6: «байт-у-байт той самий файл, що CLI» | 2 (`conformance_test.dart`: `users_app` байти = CLI = golden), 4 (справжній build_runner `--only-check` = golden) |
| Правило заголовка («The CLI owns only its output») | OD3; той самий заголовок — 2 (golden); документація — 5 |
| Діагностики `path:line:col ... [code]` як помилки логу | 2 (`cases_app`), 3 (синтаксис, частини, `FileUnit`), 4 (конфігурація) |
| Детермінований вихід | 2 (сортування джерел; golden), Global Constraints |
| `build.yaml`, README | 4, 5 |
| Спільний код з CLI мінімальною окремою задачею | 1 (OD2) |
| Версії analyzer/build | OD4; обидва краї — «Перевірка» |
| Тести без мережі | OD6; 2–4 (`loadIsolateSources`, `WorkspacePackageConfig`) |
| Workspace | 2 (член workspace), OD1 (C ламається з `--workspace`), Review Focus 2 |
| Взаємодія з `dartnest dev`/watch | OD7, 5 (README) |

**Плейсхолдери.** Пошук `TBD`, `TODO`, «similar to Task», «add error handling», «implement later» — нічого. Кожен крок з кодом містить повний файл; файли, які змінюються кількома задачами, наведено повністю в кожній: `lib/dartnest_build.dart` (2, 4), `lib/src/package_sources.dart` (2, 3), `lib/src/dartnest_builder.dart` (2, 3, 4). Зміни існуючих файлів (Task 1, `shop_sources.dart` у Task 3, `users_app/pubspec.yaml`, `CLAUDE.md`, роадмап, README CLI) дано точним «було → стало»; кожен фрагмент «було» трапляється у файлі рівно раз.

**Узгодженість типів.** Імена між задачами взято з коду, що пройшов перевірку нижче: `SyntaxProblem(location, message)` + `.code`, `PackageModel.isEmpty`, `LibraryWriter.validPackageName`, `PackageRoot.validName`; `PackageSources.find/assets/syntaxProblems/libraries`; `DartnestBuilder(packageName, {generator})` + `.packageName/.generator/.buildExtensions/.build`; `DartnestBuildOptions.packageKey/builderFor/buildYaml`; `ConfigurationErrorBuilder(problem)`; `dartnestBuilder(options)`; хелпери `TempDir.create/path/resolve/write/read/exists`, `WorkspacePackageConfig.write`, `FixtureFiles.of/golden`, `CliResult`, `CliGeneration.run`, `BuildRun.run/succeeded/errors/library`, `ShopSources.package/clock/controller/module/files/broken/user/userPart/users`, `FileConstruct`. З CLI (dev) — лише barrel: `GenerationSession`, `PackageRoot.open`, `GenerationReport.problemLines/diagnostics/syntaxProblems`.

**Перевірка.** Задачі виконано механічно, одна за одною, у копії репозиторію (`cp -r` з `master` `387f8a6` у `/tmp`, гілка поза репозиторієм), і кожен блок коду цього плану згенеровано з файлів тих комітів; окремий скрипт застосував план (файли, «було → стало», `git mv`) до чистої копії `387f8a6` і після кожної задачі порівняв дерево з відповідним комітом копії — збіг для всіх 5 задач. Результати на кожному кроці: `dart analyze` — «No issues found!», `dart format` — 0 змінених файлів; `dartnest_generator` `+169` (було `+163`), `dartnest_cli` `+136` до й після Task 1; `dartnest_build` `+7`, `+11`, `+16`; `dart test integration` — `+1` (~24 с); `dartnest` `+274`, `dartnest_io` `+46`, `dartnest_shelf` `+67`, `dartnest_annotations` `+6` не змінились. Кроки «verify it fails» дають наведені помилки (Task 3 — `+1 -3`: тест «syntax errors fail the build and write nothing» проходить і до реалізації, бо `libraryFor` кидає сам). SDK: Dart 3.13.5 (fvm Flutter 3.47.6) з мовною версією 3.8. Верхній край: `analyzer` 14.5.0, `build` 4.0.11, `build_runner` 2.16.2, `build_test` 3.5.21, `glob` 2.2.0, `test` 1.33.0. Нижній край — окрема копія з `dependency_overrides` (`analyzer` 8.1.1, `build` 4.0.2, `build_runner` 2.10.5, `build_test` 3.5.5, `code_builder` 4.11.1, `dart_style` 3.1.2, `test` 1.26.3): `dartnest_build` `+16`, `dartnest_generator` `+169`, `dartnest_cli` `+136`, `dart analyze lib test` у `dartnest_build` — «No issues found!»; справжній `dart run build_runner build` у `users_app` пише рівно golden. Саме нижній край показав, що builder без жодного виходу build_runner 2.10.5 і `build_test` 3.5.5 мовчки пропускають (звідси `dartnest_build.unconfigured`, OD1); з ним неправильна опція дає `E dartnest_build on lib/$lib$: ...` і код 1 на обох краях. Вручну: модифікований golden + `--only-check` — код 1, файл не змінено; синтаксична помилка в `users_app` під `build_runner build` — `lib/broken.dart:2:1: error: Expected to find ')'. [syntax_error]`, вихід видалено, після виправлення — записано знову (OD3); приклад «Own constructs» з README — код 0. Розміри: найбільший файл у `lib/` — `dartnest_builder.dart` (75 рядків), у тестах — `shop_sources.dart` (94), `problems_test.dart` (73); найдовший метод — `DartnestBuilder.build` (24 рядки).

**Не перевірено.** Шляхи Windows (корінь `'/$package'` для `PackageCollector`, який рахує відносні шляхи через `package:path`; на Windows analyzer build_runner може бачити інші шляхи); `build_runner build --workspace` з кількома пакетами, кожен зі своїм `build.yaml`; версії build_runner між 2.10.5 і 2.16.2, крім країв; інтеграційний тест — лише на верхньому краї (`--only-check` з'явився в 2.16); порядок з `json_serializable` змодельовано відсутньою частиною (Review Focus 4), а не справжнім другим builder-ом.

**Review Focus.** Кожен пункт закріплено тестом з коментарем `// Review Focus N`: 1, 4 і 5 → Task 2; 3 → Task 3; 2 → Task 4.

## Відкриті питання для автора

Усі рішення винесено в «Open decisions» (OD1–OD10) з рекомендаціями; план написано за ними. Найбільше на подальші етапи впливають:

1. **OD1** — обов'язкова опція `package` у `build.yaml` (явно, але один зайвий файл на пакет) проти якоря на `lib/<pkg>.dart` (нуль конфігурації, мовчить без цього файлу).
2. **OD3** — чи прийнятно, що під build_runner бібліотека зникає, поки в джерелах є проблеми (CLI її лишає).
3. **OD4** — `build_runner: ^2.16.0` у фікстурі піднімає мінімальний SDK для роботи з репозиторієм до 3.11 (пакети лишаються на ^3.8).
