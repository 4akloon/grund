# dartnest Hot Reload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 5b роадмапу: `dart run dartnest_cli dev` запускає застосунок з VM service і після кожної зміни `lib/` чи теки точки входу генерує пакет і робить hot reload (`reloadSources`, потім `ext.dartnest.reassemble`: екземпляри провайдерів зберігаються за `(moduleId, key)`, контролери й роути будуються заново, таблиця підміняється атомарно) або hot restart, коли reload не може коректно застосувати зміну; інтеграційний тест роадмапу: PID не змінюється при reload, змінюється при restart.

**Architecture:** Дві половини. **Ядро `dartnest`** (без `dart:io`): `ModuleInjector.instances`/`adopt` і `Container.reassemble(newRoot)` переносять створені екземпляри в новий граф; `ApplicationAssembly.start`/`rebuild` будує пару «контейнер + роутер» (record `Assembly`), а `Application.reassemble()` заново викликає функцію модуля, валідує, перебудовує й підміняє `_assembly` одним присвоєнням, повертаючи `ReassembleReport` (додані й прибрані роути); `HotReloadExtension` через `dart:developer` реєструє `ext.dartnest.reassemble` і `ext.dartnest.close` для всіх відкритих застосунків, лише поза product-режимом. **CLI `dartnest_cli/lib/src/dev/`**: `ShapeTracker` (analyzer `parseString`, без резолву) помічає зміни полів, конструкторів, top-level/static змінних і значень enum — їх reload застосувати коректно не може; `AppProcess` запускає `dart --enable-vm-service=0 --no-dds <target>`, читає з банера URI VM service, пересилає вивід, зупиняє через SIGTERM → SIGKILL; `ReloadClient` (`package:vm_service`) робить `reloadSources`, класифікує відповідь (`Reloaded`/`ReloadFailed`/`ReloadRejected`), викликає reassemble і `ext.dartnest.close`; `DevSession` послідовно виконує `apply`/`reload`/`restart`/`stop`; `DevPrinter` друкує по рядку на подію; `MergedWatcher` об'єднує watcher-и `lib/` і теки точки входу; `TerminalKeys` дає `r`/`R`. `DevCommand` склеює `GenerationSession` етапу 5 з `WatchLoop.custom(afterRun: dev.apply)`.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors); `dart:developer` у ядрі; `vm_service` ^15.2.0 лише в `dartnest_cli` (перевірено 15.2.0 і 15.3.0); `analyzer` `'>=8.1.1 <15.0.0'` (як в етапі 5; API `ShapeTracker` перевірено на 8.1.1 і 14.5.0); `args`, `watcher`, `path` — як в етапі 5; `package:test` ^1.25.0.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md`, розділ 10 (10.1 — вимоги до ядра, 10.2 — інструмент, 10.3 — тестування); `docs/superpowers/ROADMAP.md`, рядок 5b і абзац «Вимоги до ядра заради hot reload»; план етапу 5 `docs/superpowers/plans/2026-10-14-dartnest-cli.md` (OP10: `GenerationSession` для `dev`).

## Open points

Рішення, які план приймає сам, але які автор може змінити до виконання. Для кожного — таблиця компромісів і рекомендація; план написано за рекомендованим варіантом (позначено ✔). Кожна рекомендація відкочується в межах однієї-двох задач.

### OP1. Розкладка пакетів

| Варіант | Де код | Наслідки |
|---|---|---|
| A ✔ хук у ядрі: `Container.reassemble`, `Application.reassemble`, `ReassembleReport`, `HotReloadExtension` у `dartnest` (лише SDK: `dart:developer`); інструмент — `dartnest_cli/lib/src/dev/` + `DevCommand` у `lib/src/cli/` | як у спеці 10.1/10.2 і рядку роадмапу | нових пакетів немає; barrel CLI не змінюється (усе `dev` — внутрішнє) |
| B окремий пакет `dartnest_dev` з командою і `vm_service` | новий член workspace | CLI або залежить від нього, або має другий executable; два місця для генерації |
| C extension реєструє адаптер (`dartnest_io`) | ядро без `dart:developer` | застосунок без адаптера (`shelfHandler`, `TestClient`, власний сервер) не перезавантажується |

**Варіанти:** A — ядро + `dartnest_cli`; B — пакет `dartnest_dev`; C — extension в адаптері. **Рекомендація: A.**

### OP2. Залежність `vm_service`

| Варіант | Протокол між CLI і застосунком | Ціна |
|---|---|---|
| A ✔ `vm_service: ^15.2.0` лише в `dartnest_cli`; ядро відповідає JSON-ом через `registerExtension`; імена `ext.dartnest.reassemble`/`ext.dartnest.close` — константи з обох боків (`HotReloadExtension.reassembleMethod`, `ReloadClient.reassembleMethod`), розбіжність ловлять тести обох сторін (Task 4, Task 7) | VM service JSON-RPC | одна залежність, обидва краї перевірено |
| B спільний пакет протоколу (імена, формат JSON) | той самий | новий пакет заради двох рядків |
| C власний JSON-RPC через WebSocket без `vm_service` | той самий | ~200 рядків протоколу, який уже є в SDK-пакеті |

**Варіанти:** A — `vm_service` у CLI, дубльовані константи; B — пакет протоколу; C — свій клієнт. **Рекомендація: A.**

### OP3. Що зберігається, що перебудовується

| Варіант | Провайдери | Контролери, enhancers, роути | Ризик |
|---|---|---|---|
| A ✔ екземпляри за `(moduleId, key)` (також async і `Provider.value`); новий або перенесений в інший модуль провайдер — створюється; зниклий — відкидається без dispose (lifecycle-хуки — етап 9) | стан зберігається (спека 10.1 п. 2) | заново | змінене значення `Provider.value` (конфіг) видно лише після restart — README |
| B як A, але `Provider.value` завжди нове | конфіг видно | заново | значення-синглтон (клієнт БД, переданий значенням) губиться — «стан зберігається» порушено |
| C зберігати й контролери | — | старі | спека: контролери без стану; нові залежності контролера не підхопились би |

**Варіанти:** A — провайдери за ключем, решта заново; B — `Provider.value` завжди нове; C — і контролери. **Рекомендація: A.**

### OP4. Зміна форми класу

Перевірено на Dart 3.13.5: VM **приймає** reload з новим полем (`shapeChangeMappings`). Поле з ініціалізатором у старих екземплярах ініціалізується ліниво, а поле, яке присвоює конструктор, у старих екземплярах — `null`, і перше читання падає `type 'Null' is not a subtype of type 'String'`. Зміну type parameters VM відхиляє (`ReasonForCancellingReload`, `Limitation: changing type parameters does not work with hot reload.`). Тобто відповіді `reloadSources` (спека 10.2) недостатньо.

| Варіант | Як визначається restart | Хибні restart | Пропущені |
|---|---|---|---|
| A ✔ `ShapeTracker`: `parseString` без резолву, «форма» файлу — вихідний текст полів, конструкторів, top-level змінних і значень enum; змінилась у будь-якому файлі прогону (і в згенерованому) → restart з причиною; плюс відмова VM → restart | статично, ~1 мс на файл | нове поле з ініціалізатором (reload впорався б) | форма, змінена поза `lib/` і текою точки входу |
| B лише відповідь `reloadSources` (спека буквально) | VM | немає | тихо зіпсовані екземпляри (Review Focus 9) |
| C B + `reassemble` перестворює екземпляри змінених класів | — | немає | потребує зв'язку клас → провайдер (генератор/mirrors); складно |

**Варіанти:** A — `ShapeTracker` + відмова VM; B — лише VM; C — перестворення екземплярів. **Рекомендація: A** (відмова від неї — прибрати один виклик у `DevSession._apply`).

### OP5. Невдалий reload і помилки генерації

| Варіант | Проблеми генерації (синтаксис, діагностики) | Reload не компілюється | `reassemble` впав |
|---|---|---|---|
| A ✔ | нічого не робиться: `bin/main.dart keeps running the previous code.` / `... starts when the problems are fixed.` | помилка компілятора в stderr, `Hot reload failed; bin/main.dart keeps running the previous code.`, без restart | помилка з ланцюжком у stderr, старі модулі й роути (спека 10.1 п. 5) |
| B (спека 10.2 буквально: «невдалий reload → restart») | як A | restart: новий процес не скомпілюється, застосунок зникає до виправлення | restart |

**Варіанти:** A — нічого не ламати, друкувати; B — restart на будь-який невдалий reload. **Рекомендація: A** — відхилення від 10.2: restart при помилці компіляції лише прибирає працюючий застосунок; restart лишається для відмов VM (`ReasonForCancellingReload`) і для OP4.

### OP6. Reload чи restart: вибір і клавіші

| Варіант | Автоматично | Вручну |
|---|---|---|
| A ✔ reload за замовчуванням; restart — OP4 і відмова VM; `main` reload не перезапускає (README: зміна налаштування сервера в `main` — через `R`) | так | `r`/`R` у терміналі (`TerminalKeys`, лише коли `stdin.hasTerminal`; без echo й line mode, відновлюються при скасуванні); тести дають клавіші через `DartnestCli(keys:)` |
| B лише автоматично | так | немає (спека 10.2 називає `r`/`R`) |
| C restart на кожну зміну точки входу | так | — | зміна хелпера в `bin/` теж перезапускає; помилка компіляції в `bin/` прибирає застосунок |

**Варіанти:** A — авто + `r`/`R`; B — лише авто; C — restart на зміну точки входу. **Рекомендація: A.**

### OP7. Порт і адаптер при restart

| Варіант | Reload | Restart | Порт |
|---|---|---|---|
| A ✔ нічого не передається | той самий процес і сокет | `ext.dartnest.close` (нові запити 503, поточні до кінця, таймаут 5 с) → SIGTERM → SIGKILL через 2 с → дочекатися виходу → новий процес | фіксований порт вільний, бо старий процес уже завершився; Dart ставить `SO_REUSEADDR` на POSIX, `TIME_WAIT` не заважає (перевірено) |
| B передати слухаючий сокет новому процесу | — | без розриву | `dart:io` не передає сокети між процесами |
| C запустити новий до зупинки старого (`shared: true`) | — | менший простій | `shared` працює лише між ізолятами одного процесу — порт зайнятий |

Порт, зайнятий чужим процесом: застосунок падає на `bind`, `dev` друкує `bin/main.dart exited with code 255; it starts again after the next change.` **Варіанти:** A — закрити, дочекатися, запустити; B — передача сокета; C — перекриття. **Рекомендація: A.**

### OP8. Точка входу

| Варіант | За замовчуванням | Узгодженість |
|---|---|---|
| A ✔ `--target`/`-t` з alias `--entry` (спека 10.2), `bin/main.dart`; аргументи після `--` ідуть у `main`; точка входу має бути в теці пакета (не в корені: watcher над коренем бачив би `.dart_tool/`) — інакше `64`; немає файлу — `66` з підказкою `--target` | `bin/main.dart` | спека 10.2; `init` етапу 5 створює `bin/server.dart` — README `init` називає `dev --target bin/server.dart` |
| B `bin/server.dart` | як `init` | розходиться зі спекою |
| C єдиний файл у `bin/` | вгадування | проти «Nothing is guessed silently» |

**Варіанти:** A — `bin/main.dart` + `--target`; B — `bin/server.dart`; C — вгадати. **Рекомендація: A** (див. «Відкриті питання», п. 1).

### OP9. Дочірній процес і його вивід

| Варіант | Команда | Вивід |
|---|---|---|
| A ✔ `Platform.resolvedExecutable --enable-vm-service=0 --no-dds <target> <args>`, cwd — корінь пакета | `dart <file>` виконує `dartvm` у тому ж PID; VM service на `127.0.0.1` з ефемерним портом і токеном; без DDS — один процес | stdout/stderr рядками як є (UTF-8, `allowMalformed`); банер VM service не пересилається, замість нього `Started bin/main.dart (pid N, VM service URI).` |
| B `dart run --enable-vm-service` (спека 10.2) | неявний `pub get` (мережа, секунди) на кожен restart; DDS — окремий процес `dart development-service`, що переживає батька | як A |
| C як A, але з префіксом `[app]` | — | ламає JSON-логи й кольори |

**Варіанти:** A — `dart --no-dds <target>`; B — `dart run`; C — префікс. **Рекомендація: A** (відхилення від 10.2, README пояснює: після правки `pubspec.yaml` — `dart pub get` і `R`).

### OP10. Сигнали й прибирання

| Варіант | Що зупиняє `dev` | Сироти |
|---|---|---|
| A ✔ `DartnestCli.interrupted()`: перший SIGINT або (не на Windows) SIGTERM, потім обидві підписки скасовуються; `DevCommand` у `finally`: скасувати клавіші → `dev.stop()` (graceful close → SIGTERM → SIGKILL) → `session.close()`; збій дії клавіші завершує `dev` тим самим шляхом | Ctrl+C, SIGTERM (systemd, docker, IDE) | Ctrl+C у терміналі отримують обидва процеси (одна група), застосунок закривається сам, `stop` дочікується; сирота лише після SIGKILL самого `dev` (README) |
| B лише SIGINT (як `gen --watch` етапу 5) | Ctrl+C | supervisor шле SIGTERM → `dev` помирає без `finally`, застосунок лишається |
| C окрема група процесів / job object для дитини | — | `dart:io` не дає `setsid`/job objects |

Windows: SIGTERM не спостерігається (`ProcessSignal.sigterm.watch()` кидає), `Process.kill` — завжди `TerminateProcess`; graceful-частину все одно дає `ext.dartnest.close`. **Варіанти:** A — SIGINT + SIGTERM, `finally`; B — лише SIGINT; C — група процесів. **Рекомендація: A.**

### OP11. Падіння застосунку

| Варіант | Поведінка | Ризик |
|---|---|---|
| A ✔ без автоперезапуску: `bin/main.dart exited with code N; it starts again after the next change.`; наступна зміна без проблем запускає знову | цикл неможливий | після падіння треба зберегти файл (або `r`) |
| B автоперезапуск з backoff | | цикл падінь у логах, CPU |
| C завершити `dev` | | ручний перезапуск і повний холодний старт аналізу |

**Варіанти:** A — чекати зміни; B — backoff; C — вийти. **Рекомендація: A.**

### OP12. Де живуть процесні тести

| Варіант | `dart test` | Повний `dev` |
|---|---|---|
| A ✔ тести `AppProcess`, `ReloadClient`, `DevSession`, `DevCommand` (по 1–3 с, дочірні процеси лише на loopback) — у `test/`; повний `dev` (тест роадмапу з PID, шторм, помилка компіляції в `bin/`, SIGTERM дочірнього CLI) — `packages/dartnest_cli/integration/` (`dart test integration`), як `benchmark/` етапу 5 | +11 с (7 → 18 с) | окрема команда — «окремий таск CI» спеки 10.3 |
| B усе в `test/` | +28 с | — |
| C `@Tags(['integration'])` + `dart_test.yaml` | як A | новий файл конфігурації, та сама окрема команда |

**Варіанти:** A — `integration/`; B — усе в `test/`; C — теги. **Рекомендація: A.**

## Рішення

1. **Ядро переносить екземпляри, а не контейнер.** `ModuleInjector.instances` — створені екземпляри власних провайдерів за ключем, `adopt(instances)` — підставити їх у слоти нового інжектора до `instantiateAll` (слот з екземпляром фабрику не викликає). `Container.create` і `Container.reassemble` йдуть через один приватний `_start(graph, kept)`; `reassemble` будує граф від нового кореня і ніколи не змінює старий контейнер: будь-яка помилка лишає його робочим.
2. **Застосунок тримає одну пару.** `typedef Assembly = ({Container container, Router<Endpoint> router})`; `ApplicationAssembly.start` (валідація, контейнер, роутер; закриття контейнера при збої) і `rebuild` (той самий шлях через `Container.reassemble` + `ReassembleReport.between`). `Application` читає `_assembly.router` один раз на запит, тому запит у польоті доходить старою таблицею; `reassemble()` присвоює `_assembly` одним виразом після успіху. `replaceRoutes` (`@internal`-заготовка етапу 2) прибирається — її роль тепер у `reassemble`.
3. **Звіт.** `RouteTableBuilder.describe(graph)` — відсортовані `METHOD /path`; `ReassembleReport.between(before, after)` → `addedRoutes`, `removedRoutes`, `changedRoutes`, `toJson()`. Експортується з barrel.
4. **Extension.** `HotReloadExtension.attach` викликається з `Application.create`, `detach` — з першого `close()`. Реєстрація — один раз на ізолят (`registerExtension` не можна зняти), лише якщо `isEnabled` (`!bool.fromEnvironment('dart.vm.product')`). `handle(method, params)` — нова межа `on Object`: `ServiceExtensionResponse.error(extensionError, ...)` з текстом помилки (для не-`DartnestError` — і стеком). Відповідь reassemble: `{'applications': n, 'addedRoutes': [...], 'removedRoutes': [...]}`; close: `{'applications': n}`.
5. **Один прогін `dev`:** `WatchLoop` → `GenerationSession.run(changed:)` → `ReportPrinter.report` → `afterRun` = `DevSession.apply(changed, report)`: проблеми → `waiting`; не запущено → запуск; `ShapeTracker.changed(changed + вихід, якщо записаний чи видалений)` не порожній → restart; інакше `ReloadClient.reload()` → `DevPrinter.reloaded` → для `ReloadRejected` — restart. `WatchLoop` чекає `afterRun`, тож прогони й reload не перекриваються.
6. **Послідовність.** Усі операції `DevSession` (`apply`, `reload`, `restart`, `stop`) ланцюжаться через `_tail` і виконуються по одній, також після збою попередньої (збій іде своєму викликачу, а `stop` мусить завершити процес). Вихід процесу, що завершився сам, ігнорується, якщо сесія вже замінила або зупинила його (`identical(_running, running)`).
7. **Повідомлення** (англійською, як `ReportPrinter`): `Started bin/main.dart (pid N, VM service URI).`, `Reloaded N libraries in X ms, M routes changed.` (без застосунку dartnest — без «routes»), `Restarting bin/main.dart: <reason>.`, `bin/main.dart exited with code N; it starts again after the next change.`, `bin/main.dart keeps running the previous code.`, `bin/main.dart starts when the problems are fixed.`, `Hot reload failed; bin/main.dart keeps running the previous code.`, `..., but the application could not be reassembled; it keeps its previous modules and routes.`; watch — `Watching lib/ and bin/ for changes; press Ctrl+C to stop.`
8. **Тести.** Мережі немає: дочірні процеси слухають `127.0.0.1` на ефемерному порту, VM service — `127.0.0.1` з токеном. Тестовий застосунок `hello` (`DevSources`, `HelloApp`) збирається в `TempPackage` етапу 5 і генерується справжньою `GenerationSession`. Очікування — на рядки (`LineSink.next`/`nextWhere`, `until` в інтеграційному тесті), без `sleep`, крім двох перевірок «нічого не сталося» (`LineSink.after`).
9. **Поза планом:** dispose відкинутих провайдерів (етап 9), автоматичний `pub get` і restart на зміну `pubspec.yaml`, стеження поза `lib/` і текою точки входу (конфіги, `.env`), кілька ізолятів із застосунками (reassemble викликається в першому ізоляті з extension), CI-конфігурація (у репозиторії її немає; «окремий таск CI» = команда `dart test integration` у `CLAUDE.md`).

## Global Constraints

- Ядро `dartnest` лишається без `dart:io`, `dart:mirrors`, analyzer і серверів; новий імпорт — лише `dart:developer` (SDK). `vm_service` — лише в `dartnest_cli` (`^15.2.0`). Інші пакети (`dartnest_annotations`, `dartnest_generator`, адаптери) не змінюються.
- Публічний API ядра додається, нічого не ламаючи, крім прибраного `Application.replaceRoutes` (`@internal`-заготовка етапу 2): `Container.reassemble`, `Application.reassemble`, `ReassembleReport` (у barrel). `HotReloadExtension`, `ApplicationAssembly` і все `dev` — не в barrel.
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/` (`application.dart` — 283 після Task 4: Task 2 спершу виносить `ApplicationAssembly`), ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів, ≤ 3 рівні вкладеності; один публічний клас або sealed-сімейство на файл (`ReloadResult` — сімейство; приватні `_Slot`, `_ShapeCollector`, `_Running`, `_Runner` ділять файл); без top-level функцій у `lib/src`; без `!`, `dynamic`, `late`; позиційних `bool` немає; dartdoc на кожному публічному члені.
- `catch` лише з `on`. Нова межа `on Object` одна — `HotReloadExtension.handle` (Task 4); `CLAUDE.md` отримує її в Task 11. `ReloadClient` ловить лише `SocketException`, `WebSocketException`, `RPCError`, `SentinelException`, `TimeoutException`; `ShapeTracker` — `FileSystemException`.
- Тести: мережі немає (лише loopback), temp-файли — через `TempDir`/`TempPackage`; CLI — у процесі (`DartnestCli(out:, err:, untilStopped:, keys:)`), крім одного тесту SIGTERM в `integration/`; дочірні процеси — лише застосунок користувача (`AppProcess`) і цей CLI; кожен дочірній процес зупиняється в `addTearDown`.
- Публічний API, dartdoc, повідомлення CLI, README і повідомлення комітів — англійською.
- Перед кожним комітом: з кореня `dart analyze` — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів; тести змінених пакетів зелені.
- `dart` не завжди в `PATH`: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після зміни `pubspec.yaml` — `dart pub get` з кореня.
- Відхилення від специфікації, зафіксовані планом: `dart --no-dds <target>` замість `dart run` (OP9); невдала компіляція reload — без restart (OP5); restart також за статичним `ShapeTracker` (OP4); стежимо за `lib/` і текою точки входу (за замовчуванням `bin/`); рядок результату — речення з великої літери й крапкою, як `ReportPrinter`.

## Review Focus

1. **Дочірні процеси-сироти** (Ctrl+C, SIGTERM від supervisor-а, `stop` після помилки, дитина ігнорує SIGTERM): після виходу `dev` застосунку немає, його порт відмовляє. Закріплено в Task 9 (`stop ends the application and frees its port`, `// Review Focus 1`), Task 10 (`SIGTERM stops dev and the application with it`, `// Review Focus 1 and 7`; `dev reloads bodies and routes and restarts on a new field`, `// Review Focus 1`) і Task 6 (`stop kills a child that ignores SIGTERM`).
2. **Reload під час запиту в польоті:** запит, що почався, доходить старою таблицею й старим контролером, нові — новою. Закріплено в Task 3 (`a request keeps the table it started with`, `// Review Focus 2`).
3. **Помилка регенерації посеред редагування** (файл, збережений наполовину; помилка компіляції в `bin/`): застосунок працює зі старим кодом, після виправлення reload проходить. Закріплено в Task 9 (`sources with problems keep the previous code running`, `// Review Focus 3`), Task 7 (`a compile error fails the reload and keeps the old code`) і Task 10 (`a compile error in bin/ keeps the previous code running`).
4. **Шторм подій** (редактор пише кілька разів поспіль, `git checkout`): reload-и не перекриваються, у підсумку — остання версія в тому ж процесі. Закріплено в Task 9 (`runs that arrive together are applied one after another`, `// Review Focus 4`) і Task 10 (`a storm of saves ends with the last version in one process`, `// Review Focus 4`).
5. **Цикл падінь дочірнього процесу:** застосунок, що впав, не перезапускається сам; лише наступна зміна запускає його знову. Закріплено в Task 9 (`an application that exits starts again only after a change`, `// Review Focus 5`).
6. **Порт уже зайнятий:** restart на фіксованому порту не падає з `Address already in use`, бо новий процес стартує після виходу старого. Закріплено в Task 10 (`dev reloads bodies and routes and restarts on a new field` — `-- <port>`, `// Review Focus 6`); чужий процес на порту → `exited with code`, як у п. 5.
7. **Відмінності сигналів на Windows:** SIGTERM не спостерігається й не надсилається; `stop` там одразу вбиває після graceful `ext.dartnest.close`. Закріплено в Task 6 (`stop kills a child that ignores SIGTERM`, `// Review Focus 7`, `testOn: '!windows'`) і Task 10 (`SIGTERM stops dev and the application with it`, `testOn: '!windows'`); `DartnestCli.interrupted` не підписується на SIGTERM на Windows (Task 10, код).
8. **Застарілий згенерований файл:** reload іде лише після того, як `lib/<package>.dartnest.dart` записано, тож новий роут видно після першого ж reload. Закріплено в Task 10 (`dev reloads bodies and routes and restarts on a new field`, `// Review Focus 8`) і Task 8 (`afterRun follows the printed report of every run`).
9. **Зіпсований стан після зміни форми класу** (нове поле, змінений конструктор): restart замість reload, жодного `Null` у старих екземплярах. Закріплено в Task 5 (`a new field changes the shape`, `// Review Focus 9`) і Task 9 (`a new field restarts the application in a new process`, `// Review Focus 9`).

---
## File Structure

```
CLAUDE.md                                            # commands, vm_service/dart:developer rule, dev test rule, new on Object boundary (T11)
docs/superpowers/ROADMAP.md                          # 5b row links this plan (T11)
packages/dartnest/
  README.md                                          # Hot reload section (T11)
  lib/dartnest.dart                                  # barrel + reassemble_report.dart (T3)
  lib/src/di/module_injector.dart                    # instances, adopt (T1)
  lib/src/di/container.dart                          # reassemble, private _start (T1)
  lib/src/app/application_assembly.dart              # NEW: Assembly, ApplicationAssembly.start (T2), rebuild (T3)
  lib/src/app/reassemble_report.dart                 # NEW: ReassembleReport (T3)
  lib/src/app/route_table_builder.dart               # describe(graph) (T3)
  lib/src/app/application.dart                       # uses ApplicationAssembly (T2), reassemble (T3), attach/detach (T4)
  lib/src/app/hot_reload_extension.dart              # NEW: HotReloadExtension (T4)
  test/di/container_reassemble_test.dart             # NEW (T1)
  test/app/application_reassemble_test.dart          # NEW (T3)
  test/app/application_test.dart                     # replaceRoutes test moves to the reassemble tests (T3)
  test/app/hot_reload_extension_test.dart            # NEW (T4)
packages/dartnest_cli/
  pubspec.yaml                                       # vm_service ^15.2.0 (T7), description (T11)
  README.md                                          # dev section, init --target note, exit codes (T11)
  lib/src/dev/shape_tracker.dart                     # NEW: ShapeTracker (T5)
  lib/src/dev/app_process.dart                       # NEW: AppProcess (T6)
  lib/src/dev/reload_result.dart                     # NEW: sealed ReloadResult (T7)
  lib/src/dev/reload_client.dart                     # NEW: ReloadClient (T7)
  lib/src/watch/watch_loop.dart                      # custom(watched:, afterRun:) (T8)
  lib/src/dev/merged_watcher.dart                    # NEW: MergedWatcher (T8)
  lib/src/dev/dev_printer.dart                       # NEW: DevPrinter (T9)
  lib/src/dev/dev_session.dart                       # NEW: DevSession (T9)
  lib/src/dev/terminal_keys.dart                     # NEW: TerminalKeys (T10)
  lib/src/cli/dev_command.dart                       # NEW: DevCommand (T10)
  lib/src/cli/dartnest_cli.dart                      # dev, keys:, interrupted() (T10)
  test/shape_tracker_test.dart (T5), app_process_test.dart (T6), reload_client_test.dart (T7),
  test/merged_watcher_test.dart, watch_loop_runs_test.dart (T8), dev_printer_test.dart, dev_session_test.dart (T9),
  test/dev_command_test.dart (T10)
  test/helpers/dev_sources.dart, hello_app.dart      # NEW: the hello app (T7)
  test/helpers/line_sink.dart                        # nextWhere (T9)
  integration/dev_test.dart                          # NEW: `dart test integration` (T10)
```

Залежності задач: 1 → 2 → 3 → 4 (ядро); 5, 6 і 8 не залежать від ядра й між собою; 4 + 6 → 7; 5 + 7 + 8 → 9 → 10; 1–10 → 11. Кількості тестів у кроках «Expected» — наростаючим підсумком: `cd packages/dartnest && dart test` — T1 `+258`, T2 `+258`, T3 `+264`, T4 `+270`; `cd packages/dartnest_cli && dart test` — T5 `+71`, T6 `+76`, T7 `+81`, T8 `+85`, T9 `+97`, T10 `+102`; `cd packages/dartnest_cli && dart test integration` — T10 `+4`. На початку етапу (`909bf52`): `dartnest` `+251`, `dartnest_cli` `+62`.

### Task 1: `Container.reassemble`: екземпляри за модулем і ключем

Спека 10.1 п. 2. `ModuleInjector` отримує два члени: `instances` (створені екземпляри власних провайдерів за ключем) і `adopt(instances)` (підставити їх у слоти до `instantiateAll`; слот з екземпляром фабрику не викликає, тож залежності нових провайдерів отримують збережені екземпляри). `Container.create` і `Container.reassemble` — один приватний `_start(graph, kept)`. Старий контейнер не змінюється ніколи: помилка графа чи фабрики лишає його робочим (спека 10.1 п. 5). Async-провайдер теж зберігається — його `Future` не викликається вдруге.

**Files:**
- Modify: `packages/dartnest/lib/src/di/module_injector.dart`
- Modify: `packages/dartnest/lib/src/di/container.dart`
- Test: `packages/dartnest/test/di/container_reassemble_test.dart`

**Interfaces:**
- Consumes: `ModuleGraph.build(Module root)`, `ModuleGraph.modules`, `ModuleInjector.wire`/`instantiateAll`, `Container.get`/`maybeGet`/`injectorFor`, `DuplicateProviderError`, `ProviderCreationError` (етап 1).
- Produces:
  - `ModuleInjector`: `Map<Object, Object> get instances` (лише вже створені власні провайдери), `void adopt(Map<Object, Object> instances)` (ключі, яких модуль не оголошує, ігноруються).
  - `Container`: `Future<Container> reassemble(Module newRoot)` — новий контейнер; екземпляри провайдерів, чий модуль (`id`) і ключ лишились, переносяться; кидає ті самі помилки, що `create`.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest/test/di/container_reassemble_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

/// The module `app` with [providers] and the imports [imports].
Module appWith(
  List<ProviderSpec> providers, {
  List<Module> imports = const [],
}) => Module(id: 'app', imports: imports, providers: providers);

void main() {
  group('Container.reassemble', () {
    test(
      'keeps the instance of a provider whose module and key stay',
      () async {
        var clocks = 0;
        ProviderSpec clock() => Provider((i) {
          clocks++;
          return Clock();
        });
        final first = await Container.create(appWith([clock()]));

        final second = await first.reassemble(appWith([clock()]));

        expect(second.root.get<Clock>(), same(first.root.get<Clock>()));
        expect(clocks, 1);
      },
    );

    test('creates new providers with the kept ones as dependencies', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));

      final second = await first.reassemble(
        appWith([Provider((i) => Clock()), Provider((i) => Repo(i.get()))]),
      );

      expect(second.root.get<Repo>().clock, same(first.root.get<Clock>()));
    });

    test('drops providers that are gone', () async {
      final first = await Container.create(
        appWith([Provider((i) => Clock()), Provider((i) => Db())]),
      );

      final second = await first.reassemble(
        appWith([Provider((i) => Clock())]),
      );

      expect(second.root.maybeGet<Db>(), isNull);
      expect(first.root.get<Db>(), isA<Db>());
    });

    test('a provider that moved to another module is created anew', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));
      final time = Module(
        id: 'time',
        providers: [Provider((i) => Clock())],
        exports: [Clock],
      );

      final second = await first.reassemble(appWith(const [], imports: [time]));

      expect(second.root.get<Clock>(), isNot(same(first.root.get<Clock>())));
    });

    test(
      'keeps an async provider without awaiting its factory again',
      () async {
        var connections = 0;
        ProviderSpec db() => Provider.async((i) async {
          connections++;
          return Db();
        });
        final first = await Container.create(appWith([db()]));

        final second = await first.reassemble(appWith([db()]));

        expect(second.root.get<Db>(), same(first.root.get<Db>()));
        expect(connections, 1);
      },
    );

    test('a graph error leaves the previous container working', () async {
      final first = await Container.create(appWith([Provider((i) => Clock())]));
      final broken = appWith([
        Provider((i) => Clock()),
        Provider((i) => Clock()),
      ]);

      await expectLater(
        first.reassemble(broken),
        throwsA(isA<DuplicateProviderError>()),
      );
      expect(first.root.get<Clock>(), isA<Clock>());
    });

    test(
      'a failing new factory leaves the previous container working',
      () async {
        final first = await Container.create(
          appWith([Provider((i) => Clock())]),
        );
        final failing = appWith([
          Provider((i) => Clock()),
          Provider<Db>((i) => throw StateError('no database')),
        ]);

        await expectLater(
          first.reassemble(failing),
          throwsA(isA<ProviderCreationError>()),
        );
        expect(first.root.get<Clock>(), isA<Clock>());
        expect(first.root.maybeGet<Db>(), isNull);
      },
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest && dart test test/di/container_reassemble_test.dart`
Expected: FAIL: `The method 'reassemble' isn't defined for the type 'Container'`

- [ ] **Step 3: Implement `instances` and `adopt`**

Повний файл (нові члени — `instances` і `adopt` після `get`/`maybeGet`):

Файл `packages/dartnest/lib/src/di/module_injector.dart`:

```dart
import 'dart:async';

import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'provider.dart';
import 'resolution_trace.dart';
import 'token.dart';

/// One provider's lifecycle inside a module.
final class _Slot {
  _Slot(this.provider, this.owner);

  final ProviderSpec provider;
  final ModuleInjector owner;
  Object? instance;
  bool creating = false;

  Object get key => provider.key;
}

/// [Injector] implementation for one module. Constructed by `Container`.
final class ModuleInjector implements Injector {
  /// Creates the injector for [module]; call [wire] before resolving.
  ModuleInjector(this.module, this._trace, this._modulesDeclaring) {
    for (final provider in module.providers) {
      _own[provider.key] = _Slot(provider, this);
    }
  }

  /// The module this injector serves.
  final Module module;

  final ResolutionTrace _trace;
  final List<String> Function(Object key) _modulesDeclaring;
  final Map<Object, _Slot> _own = {};
  List<ModuleInjector> _imports = const [];
  List<ModuleInjector> _globals = const [];

  @override
  String get moduleId => module.id;

  /// Connects this injector to the injectors of its imports and to the
  /// global modules (excluding itself).
  void wire({
    required List<ModuleInjector> imports,
    required List<ModuleInjector> globals,
  }) {
    _imports = imports;
    _globals = globals;
  }

  @override
  T get<T extends Object>([Token<T>? token]) {
    final key = _keyFor<T>(token);
    final slot = _resolveSlot(key);
    if (slot == null) {
      throw MissingProviderError(
        key: key,
        moduleId: module.id,
        chain: _trace.snapshot,
        definedIn: _modulesDeclaring(key),
      );
    }
    return slot.owner._createSync(slot) as T;
  }

  @override
  T? maybeGet<T extends Object>([Token<T>? token]) {
    final slot = _resolveSlot(_keyFor<T>(token));
    if (slot == null) return null;
    return slot.owner._createSync(slot) as T;
  }

  Object _keyFor<T extends Object>(Token<T>? token) {
    final key = token ?? T;
    if (key == Object) {
      throw ArgumentError(
        'Type argument for get() could not be inferred; call get<MyType>().',
      );
    }
    return key;
  }

  /// The instances of this module's own providers created so far, by key.
  Map<Object, Object> get instances => {
    for (final MapEntry(:key, value: slot) in _own.entries)
      if (slot.instance case final instance?) key: instance,
  };

  /// Takes over the [instances] whose keys this module still declares, so
  /// that [instantiateAll] does not create them again. Called by
  /// `Container.reassemble` before [wire].
  void adopt(Map<Object, Object> instances) {
    for (final MapEntry(:key, value: slot) in _own.entries) {
      slot.instance = instances[key] ?? slot.instance;
    }
  }

  /// Creates every own provider in declaration order, awaiting async ones.
  /// Called once by `Container.create` and `Container.reassemble`.
  Future<void> instantiateAll() async {
    for (final slot in _own.values) {
      if (slot.instance == null) {
        await _createAsync(slot);
      }
    }
  }

  _Slot? _resolveSlot(Object key) {
    final own = _own[key];
    if (own != null) return own;
    for (final import in _imports) {
      final slot = import._exported(key);
      if (slot != null) return slot;
    }
    for (final global in _globals) {
      final slot = global._exported(key);
      if (slot != null) return slot;
    }
    return null;
  }

  /// The slot for [key] if this module exports it directly or through a
  /// re-exported module.
  _Slot? _exported(Object key) {
    if (module.exportsKey(key)) return _own[key];
    for (final import in _imports) {
      if (module.reexportedModuleIds.contains(import.module.id)) {
        final slot = import._exported(key);
        if (slot != null) return slot;
      }
    }
    return null;
  }

  Object _createSync(_Slot slot) {
    if (slot.instance case final instance?) return instance;
    if (slot.creating) _rejectReentry(slot);
    if (slot.provider.isAsync) throw _notReady(slot);
    final result = _invoke(slot);
    if (result is Future) {
      // The factory was `async` without Provider.async. A sync caller cannot
      // use the future, so it is discarded (startup invokes the factory
      // again); `ignore` keeps a later failure from becoming unhandled.
      result.ignore();
      slot.creating = false;
      throw _notReady(slot);
    }
    _complete(slot, result);
    return result;
  }

  /// A slot that is still being created was asked for again: a cycle when
  /// its key is on the trace, otherwise an access from outside the sequential
  /// startup (for example an unawaited future), which is a not-ready error.
  Never _rejectReentry(_Slot slot) {
    if (_trace.contains(slot.key)) {
      throw CircularDependencyError(_trace.cycleFrom(slot.key));
    }
    throw _notReady(slot);
  }

  AsyncProviderNotReadyError _notReady(_Slot slot) =>
      AsyncProviderNotReadyError(
        key: slot.key,
        moduleId: slot.owner.module.id,
        chain: _trace.snapshot,
      );

  /// Creates [slot], awaiting an async factory. The key stays on the trace
  /// across the await so that a `get` made after it still sees the chain.
  Future<void> _createAsync(_Slot slot) async {
    if (slot.instance != null) return;
    if (slot.creating) _rejectReentry(slot);
    slot.creating = true;
    _trace.push(slot.key);
    try {
      _complete(slot, await slot.provider.create(this));
    } on Object catch (error, stackTrace) {
      slot.creating = false;
      if (error is DartnestError) rethrow;
      _failCreation(slot, error, stackTrace, _trace.snapshot.skip(1).toList());
    } finally {
      _trace.pop();
    }
  }

  /// Runs the factory with the trace pushed; marks the slot as creating.
  /// Returns the raw factory result (value or Future).
  FutureOr<Object> _invoke(_Slot slot) {
    slot.creating = true;
    _trace.push(slot.key);
    // The factory boundary wraps every failure, including `Error`s from user
    // config code, to annotate it with the chain; the cause and stack trace
    // are preserved and nothing is swallowed.
    try {
      return slot.provider.create(this);
    } on Object catch (error, stackTrace) {
      slot.creating = false;
      if (error is DartnestError) rethrow;
      _failCreation(slot, error, stackTrace, _trace.snapshot.skip(1).toList());
    } finally {
      _trace.pop();
    }
  }

  /// Rethrows with the factory's own stack trace so an uncaught crash points
  /// at the user's frame instead of this wrapper.
  Never _failCreation(
    _Slot slot,
    Object error,
    StackTrace stackTrace,
    List<Object> chain,
  ) {
    Error.throwWithStackTrace(
      ProviderCreationError(
        key: slot.key,
        moduleId: module.id,
        chain: chain,
        error: error,
        stackTrace: stackTrace,
      ),
      stackTrace,
    );
  }

  void _complete(_Slot slot, Object instance) {
    slot.instance = instance;
    slot.creating = false;
  }
}
```

- [ ] **Step 4: Implement `Container.reassemble`**

Файл `packages/dartnest/lib/src/di/container.dart`:

````dart
import 'errors.dart';
import 'injector.dart';
import 'module.dart';
import 'module_graph.dart';
import 'module_injector.dart';
import 'resolution_trace.dart';

/// The started dependency graph: one [ModuleInjector] per module, every
/// provider instantiated.
///
/// ```dart
/// final container = await Container.create(appModule);
/// final users = container.root.get<UsersService>();
/// ```
final class Container {
  Container._(this.graph, this._injectors);

  /// The validated module graph.
  final ModuleGraph graph;

  final Map<String, ModuleInjector> _injectors;

  /// Builds, validates and starts the graph rooted at [root].
  ///
  /// Order of work:
  /// 1. [ModuleGraph.build] — structural validation, nothing is created.
  /// 2. One injector per module, wired to its imports and to global modules.
  /// 3. Modules in start order (see below); inside a module, providers in
  ///    declaration order. Async factories are awaited; sync factories may
  ///    pull sync dependencies on demand in any order.
  ///
  /// Modules start in imports-first order with global modules (and their
  /// imports) first, so any module may use a global module's async exports.
  /// The one remaining edge: a module inside a global's import closure that
  /// uses another global's async export may start before it; a sync `get`
  /// then throws `AsyncProviderNotReadyError`. Import that global explicitly.
  ///
  /// Throws an `InjectionError` subtype on the first problem; no partially
  /// started container is ever returned.
  static Future<Container> create(Module root) async =>
      _start(ModuleGraph.build(root), const {});

  /// Builds and starts the graph rooted at [newRoot] like [create], for a
  /// hot reload: a provider whose key is still declared by a module with the
  /// same id keeps the instance this container created for it (its factory
  /// does not run again); new providers are created, providers that are gone
  /// are dropped.
  ///
  /// Returns a new container and leaves this one untouched, so a failure (an
  /// `InjectionError`, like [create]) keeps the previous state usable.
  /// Instances are matched by key only: a kept instance still holds the
  /// dependencies it was created with.
  Future<Container> reassemble(Module newRoot) async =>
      _start(ModuleGraph.build(newRoot), {
        for (final MapEntry(key: id, value: injector) in _injectors.entries)
          id: injector.instances,
      });

  /// Wires one injector per module of [graph], hands each the [kept]
  /// instances of its module id and creates the rest.
  static Future<Container> _start(
    ModuleGraph graph,
    Map<String, Map<Object, Object>> kept,
  ) async {
    final trace = ResolutionTrace();
    final injectors = <String, ModuleInjector>{
      for (final module in graph.ordered)
        module.id: ModuleInjector(module, trace, graph.modulesDeclaring)
          ..adopt(kept[module.id] ?? const {}),
    };
    ModuleInjector of(String id) =>
        injectors[id] ?? (throw UnknownModuleError(id));
    for (final module in graph.ordered) {
      of(module.id).wire(
        imports: [for (final import in module.imports) of(import.id)],
        globals: [
          for (final other in graph.ordered)
            if (other.global && other.id != module.id) of(other.id),
        ],
      );
    }
    for (final module in graph.ordered) {
      await of(module.id).instantiateAll();
    }
    return Container._(graph, injectors);
  }

  /// Injector of the root module.
  Injector get root => injectorFor(graph.root.id);

  /// Injector of the module with [moduleId]; throws `UnknownModuleError`.
  Injector injectorFor(String moduleId) =>
      _injectors[moduleId] ?? (throw UnknownModuleError(moduleId));

  Future<void>? _closing;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Shuts the container down. Idempotent: every call returns the same
  /// future. Providers have no shutdown hooks yet, so nothing else happens;
  /// instances stay readable.
  Future<void> close() => _closing ??= Future<void>.value();
}
````

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest && dart test test/di/container_reassemble_test.dart`
Expected: `+7: All tests passed!`

Run: `cd packages/dartnest && dart test`
Expected: `+258: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest/lib/src/di/module_injector.dart \
  packages/dartnest/lib/src/di/container.dart \
  packages/dartnest/test/di/container_reassemble_test.dart
git commit -m "feat(core): Container.reassemble keeps instances by module and key"
```

### Task 2: Винести `ApplicationAssembly` з `Application`

Рефакторинг без зміни поведінки (окремий коміт, `CLAUDE.md`): `application.dart` має 254 рядки, а Task 3 і Task 4 додають у нього `reassemble` і extension (разом понад 300). Збирання «валідація → контейнер → роутер, закрити контейнер при збої» переїжджає в `ApplicationAssembly.start`, а пара результату — у record `Assembly`, який Task 3 підмінятиме одним присвоєнням. Тести не змінюються.

**Files:**
- Create: `packages/dartnest/lib/src/app/application_assembly.dart`
- Modify: `packages/dartnest/lib/src/app/application.dart`

**Interfaces:**
- Consumes: `ModuleGraph.build`, `RouteTableBuilder.validate`/`build`, `Container.create`, `Enhancers`, `Router<Endpoint>` (етапи 1–2).
- Produces:
  - `typedef Assembly = ({Container container, Router<Endpoint> router})`.
  - `abstract final class ApplicationAssembly { static Future<Assembly> start(Module root, Enhancers enhancers); }` — кидає помилки валідації й контейнера; контейнер, створений до збою роутера, закривається.

- [ ] **Step 1: Create `ApplicationAssembly`**

Файл `packages/dartnest/lib/src/app/application_assembly.dart`:

```dart
import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../routing/router.dart';
import 'route_table_builder.dart';

/// The started container of an application and the route table built from
/// it.
typedef Assembly = ({Container container, Router<Endpoint> router});

/// Builds what an `Application` serves from its root module: validates the
/// routes before any provider is created, starts the container, creates the
/// controllers and the route table.
abstract final class ApplicationAssembly {
  /// Assembles [root] with the application-level [enhancers].
  ///
  /// Fails fast: a `RoutingError` before any provider is created; on any
  /// later failure the container is closed before the error is passed on.
  static Future<Assembly> start(Module root, Enhancers enhancers) async {
    RouteTableBuilder.validate(ModuleGraph.build(root));
    final container = await Container.create(root);
    // Any failure before the return closes the container; the error itself
    // propagates untouched, so no catch is needed.
    var succeeded = false;
    try {
      final router = RouteTableBuilder.build(container, enhancers);
      succeeded = true;
      return (container: container, router: router);
    } finally {
      if (!succeeded) await container.close();
    }
  }
}
```

- [ ] **Step 2: Use it in `Application`**

Файл `packages/dartnest/lib/src/app/application.dart`:

````dart
import 'package:meta/meta.dart';

import '../di/container.dart';
import '../di/module.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/serializer_registry.dart';
import '../routing/router.dart';
import '../pipeline/application_error.dart';
import 'application_assembly.dart';
import 'http_adapter.dart';
import 'in_flight_requests.dart';
import 'middleware.dart';
import 'request_dispatcher.dart';

/// A started dartnest application: the container, the route table and the
/// request pipeline. Works without a server through [handle]; serves HTTP
/// through an [HttpAdapter] and [listen].
///
/// ```dart
/// final app = await Application.create(appModule);
/// final response = await app.handle(
///   HttpRequest(method: 'GET', uri: Uri.parse('/users/1')),
/// );
/// await app.close();
/// ```
final class Application {
  Application._({
    required this.container,
    required Router<Endpoint> router,
    required HttpAdapter? adapter,
    required HttpErrorResponder errors,
  }) : _router = router,
       _adapter = adapter,
       _errors = errors,
       _dispatcher = RequestDispatcher(
         serializer: ResponseSerializer(SerializerRegistry()),
         errors: errors,
       );

  /// Builds the module returned by [root], validates the routes, starts the
  /// container, creates the controllers and builds the route table.
  ///
  /// [root] is a function so that the module graph can be rebuilt after a
  /// hot reload. [enhancers] are the application-level components, resolved
  /// through the root module. [debug] adds error details to 500 responses;
  /// [onError] receives unexpected errors (default: print); it must not
  /// throw, or [handle] fails.
  ///
  /// Fails fast: a `RoutingError` before any provider is created, an
  /// `InjectionError` or `ApplicationError` (or any other failure) before the
  /// application is returned (the container is closed first).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) => fromModule(
    root(),
    adapter: adapter,
    enhancers: enhancers,
    debug: debug,
    onError: onError,
  );

  /// Like [create], for a module value.
  static Future<Application> fromModule(
    Module root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) async {
    final (:container, :router) = await ApplicationAssembly.start(
      root,
      enhancers,
    );
    return Application._(
      container: container,
      router: router,
      adapter: adapter,
      errors: HttpErrorResponder(
        debug: debug,
        log: onError ?? HttpErrorResponder.printError,
      ),
    );
  }

  /// The started dependency container.
  final Container container;

  /// Converters for result types without `toJson()`.
  SerializerRegistry get serializers => _dispatcher.serializer.registry;

  Router<Endpoint> _router;
  final HttpAdapter? _adapter;
  final HttpErrorResponder _errors;
  final RequestDispatcher _dispatcher;
  final List<Middleware> _middleware = [];
  final InFlightRequests _inFlight = InFlightRequests();
  Future<void>? _closing;
  bool _listening = false;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Adds [middleware] after the ones added before (it runs inside them);
  /// fails with [ApplicationStateError] after [close] has started.
  void use(Middleware middleware) {
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'use',
        reason: 'the application is closed',
      );
    }
    _middleware.add(middleware);
  }

  /// Answers [request]; never throws. After [close] it answers 503.
  ///
  /// The route table is read once per request, so a request keeps the table
  /// it started with even if [replaceRoutes] runs meanwhile.
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) return _unavailable();
    final router = _router;
    final chain = List.of(_middleware);
    return _inFlight.track(() => _answer(request, router, chain));
  }

  /// Serves the application through the adapter on [address] and [port]. The
  /// adapter gets an uncounted variant of [handle] (same answers, 503 after
  /// [close]); it counts its own in-flight requests. Fails with
  /// [ApplicationStateError] without an adapter, after [close], or when
  /// already listening. When the adapter fails to start, the error is passed
  /// on and [listen] can be called again, e.g. on another port.
  Future<void> listen({required int port, Object address = 'localhost'}) async {
    final adapter = _adapter;
    if (adapter == null) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'no HttpAdapter was passed to Application.create',
      );
    }
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is closed',
      );
    }
    if (_listening) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is already listening',
      );
    }
    _listening = true;
    // A failed start must not block a retry, e.g. on another port.
    var started = false;
    try {
      await adapter.listen(_handleForAdapter, address: address, port: port);
      started = true;
    } finally {
      if (!started) _listening = false;
    }
  }

  /// Stops the application: the adapter stops accepting requests, new
  /// requests answer 503, in-flight requests finish (unless [force]), then
  /// the container closes. Every call returns the same future; [force] of
  /// later calls is ignored.
  ///
  /// The adapter's `close` waits for the requests it delivered and may give
  /// up on them after a timeout of its own; this method then waits for the
  /// [handle] calls made directly, e.g. by `TestClient`.
  ///
  /// If the adapter's `close` throws, the wait for in-flight requests is
  /// skipped (the container is still closed and the error propagates to
  /// every `close()` caller), so a failing adapter can cut in-flight
  /// requests short.
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// Replaces the route table in one assignment. Requests already running
  /// finish on the table they started with. For hot reload; not public API.
  @internal
  void replaceRoutes(Router<Endpoint> router) => _router = router;

  // Not counted in _inFlight: the adapter's close waits for the requests it
  // delivered and may abandon them after its timeout; counting them here as
  // well would leave close waiting for a handler the adapter gave up on.
  Future<HttpResponse> _handleForAdapter(HttpRequest request) {
    if (isClosed) return _unavailable();
    return _answer(request, _router, List.of(_middleware));
  }

  Future<HttpResponse> _unavailable() => Future.value(
    _errors.respond(
      const ServiceUnavailableException(
        message: 'The application is shutting down.',
      ),
      StackTrace.current,
    ),
  );

  Future<void> _shutdown({required bool force}) async {
    final adapter = _adapter;
    try {
      if (_listening && adapter != null) await adapter.close(force: force);
      if (!force) await _inFlight.idle;
    } finally {
      await container.close();
    }
  }

  Future<HttpResponse> _answer(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
  ) async {
    // Request boundary: a throwing middleware still gets an answer.
    try {
      return await _next(request, router, chain, 0);
    } on Object catch (error, stackTrace) {
      return _errors.respond(error, stackTrace);
    }
  }

  Future<HttpResponse> _next(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
    int index,
  ) {
    if (index == chain.length) return _dispatcher.dispatch(request, router);
    return chain[index](
      request,
      () => _next(request, router, chain, index + 1),
    );
  }
}
````

- [ ] **Step 3: Run the tests**

Run: `cd packages/dartnest && dart test`
Expected: `+258: All tests passed!` (нових тестів немає)

- [ ] **Step 4: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 5: Commit**

```bash
git add \
  packages/dartnest/lib/src/app/application_assembly.dart \
  packages/dartnest/lib/src/app/application.dart
git commit -m "refactor(core): extract ApplicationAssembly from Application.fromModule"
```

### Task 3: `Application.reassemble` і `ReassembleReport`

Спека 10.1 пп. 1–3, 5. `reassemble()` заново викликає функцію модуля з `Application.create`, будує й валідує граф, `Container.reassemble`, новий роутер, і присвоює `_assembly` одним виразом. Запит читає `_assembly.router` один раз, тому запит у польоті доходить старою таблицею (Review Focus 2) — тест переїжджає сюди з `application_test.dart` (там він перевіряв заготовку `replaceRoutes`, яка тепер прибирається). Будь-яка помилка лишає старі контейнер і роути; паралельний `reassemble()` і виклик після `close()` — `ApplicationStateError`. `ReassembleReport` — різниця відсортованих описів роутів `METHOD /path` (`RouteTableBuilder.describe`), для рядка `2 routes changed`.

**Files:**
- Create: `packages/dartnest/lib/src/app/reassemble_report.dart`
- Modify: `packages/dartnest/lib/src/app/route_table_builder.dart`
- Modify: `packages/dartnest/lib/src/app/application_assembly.dart`
- Modify: `packages/dartnest/lib/src/app/application.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/app/application_reassemble_test.dart`
- Test: `packages/dartnest/test/app/application_test.dart`

**Interfaces:**
- Consumes: `Container.reassemble` (Task 1), `Assembly`, `ApplicationAssembly.start` (Task 2), `RoutePattern.join`, `ApplicationStateError` (етап 2).
- Produces:
  - `final class ReassembleReport`: `const ReassembleReport({required List<String> addedRoutes, required List<String> removedRoutes})`, `factory ReassembleReport.between(List<String> before, List<String> after)`, `int get changedRoutes`, `Map<String, Object> toJson()` (`{'addedRoutes': [...], 'removedRoutes': [...]}`); у barrel.
  - `RouteTableBuilder.describe(ModuleGraph graph)` → `List<String>` (відсортовані `GET /users/:id`).
  - `ApplicationAssembly.rebuild(Assembly current, Module root, Enhancers enhancers)` → `Future<(Assembly, ReassembleReport)>`.
  - `Application.reassemble()` → `Future<ReassembleReport>`; `Application.replaceRoutes` прибрано.

- [ ] **Step 1: Write the failing test**

Новий файл:

Файл `packages/dartnest/test/app/application_reassemble_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class Answer {
  Answer(this.clock, this.text);
  final Clock clock;
  final String text;
}

/// The application's module function reads this, the way a module
/// function reads the code a hot reload replaced.
final class Version {
  /// The answer of `GET /answer`.
  static String text = 'old';

  /// The paths of the routes, each answering [text].
  static List<String> paths = ['/answer'];

  /// Holds `GET /answer` until it completes.
  static Completer<void> gate = Completer<void>()..complete();

  /// The module of the current version.
  static Module module() => Module(
    id: 'app',
    providers: [Provider((i) => Clock())],
    controllers: [
      Controller<Answer>(
        create: (i) => Answer(i.get(), text),
        routes: [
          for (final path in paths)
            Route.get(path, (c, ctx) async {
              await gate.future;
              return c.text;
            }),
        ],
      ),
    ],
  );
}

Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void main() {
  setUp(() {
    Version.text = 'old';
    Version.paths = ['/answer'];
    Version.gate = Completer<void>()..complete();
  });

  group('Application.reassemble', () {
    test('serves the routes of the new module function', () async {
      final app = await Application.create(Version.module);
      Version.text = 'new';
      Version.paths = ['/reply'];

      final report = await app.reassemble();

      expect(
        await textOf(await app.handle(requestFor('GET', '/reply'))),
        'new',
      );
      expect((await app.handle(requestFor('GET', '/answer'))).status, 404);
      expect(report.addedRoutes, ['GET /reply']);
      expect(report.removedRoutes, ['GET /answer']);
      expect(report.changedRoutes, 2);
    });

    test('keeps the instances of providers that stay', () async {
      final app = await Application.create(Version.module);
      final clock = app.container.root.get<Clock>();

      await app.reassemble();

      expect(app.container.root.get<Clock>(), same(clock));
    });

    test('a request keeps the table it started with', () async {
      // Review Focus 2: a reload while a request is in flight.
      Version.gate = Completer<void>();
      final app = await Application.create(Version.module);
      app.use((request, next) async {
        await Future<void>.delayed(Duration.zero);
        return next();
      });

      final inFlight = app.handle(requestFor('GET', '/answer'));
      Version.text = 'new';
      await app.reassemble();
      final after = app.handle(requestFor('GET', '/answer'));
      Version.gate.complete();

      expect(await textOf(await inFlight), 'old');
      expect(await textOf(await after), 'new');
    });

    test('a failure keeps the previous routes and container', () async {
      final app = await Application.create(Version.module);
      final container = app.container;
      Version.paths = ['/answer', '/answer'];

      await expectLater(app.reassemble(), throwsA(isA<RoutingError>()));
      expect(app.container, same(container));
      expect(
        await textOf(await app.handle(requestFor('GET', '/answer'))),
        'old',
      );
      Version.paths = ['/answer'];
      expect(await app.reassemble(), isA<ReassembleReport>());
    });

    test('a module function that throws is passed on', () async {
      var calls = 0;
      final app = await Application.create(() {
        if (++calls > 1) throw StateError('broken module');
        return Version.module();
      });

      await expectLater(app.reassemble(), throwsA(isA<StateError>()));
      expect((await app.handle(requestFor('GET', '/answer'))).status, 200);
    });

    test('a module value is reassembled with the same routes', () async {
      final app = await Application.fromModule(Version.module());

      final report = await app.reassemble();

      expect(report.changedRoutes, 0);
    });

    test('fails while another reassemble runs and after close', () async {
      final app = await Application.create(Version.module);

      final first = app.reassemble();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await first;
      await app.close();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
    });
  });
}
```

У `application_test.dart` прибирається тест `a request keeps the table it started with` (і імпорти, які були лише для нього). Повний файл:

Файл `packages/dartnest/test/app/application_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class Answer {
  Answer(this.text);
  final String text;
}

/// A module whose `GET /slow` waits for [gate] and answers [label].
Module slowModule(String label, Completer<void> gate) => Module(
  id: 'slow',
  controllers: [
    Controller<Answer>(
      create: (i) => Answer(label),
      routes: [
        Route.get('/slow', (c, ctx) async {
          await gate.future;
          return c.text;
        }),
      ],
    ),
  ],
);

Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void silent(Object error, StackTrace stackTrace) {}

void main() {
  group('Application.create', () {
    test('takes a module function and answers through handle', () async {
      final app = await Application.create(appModule, onError: silent);

      final response = await app.handle(requestFor('GET', '/users/2'));

      expect(response.status, 200);
      expect(await textOf(response), '{"id":2,"name":"bob"}');
      expect(app.container.injectorFor('users').get<UsersService>(), isNotNull);
    });

    test('fromModule takes a module value', () async {
      final app = await Application.fromModule(appModule(), onError: silent);

      expect((await app.handle(requestFor('GET', '/users'))).status, 200);
    });

    test('a bad route fails before any provider is created', () async {
      var created = false;
      final root = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created = true;
            return Answer('x');
          }),
        ],
        controllers: [
          Controller<Answer>(
            create: (i) => i.get(),
            routes: [Route.get('/*/x', (c, ctx) => c.text)],
          ),
        ],
      );

      await expectLater(
        Application.fromModule(root),
        throwsA(isA<InvalidRoutePatternError>()),
      );
      expect(created, isFalse);
    });

    test('a duplicate route fails before any provider is created', () async {
      var created = false;
      final root = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created = true;
            return Answer('x');
          }),
        ],
        controllers: [
          Controller<Answer>(
            create: (i) => Answer('x'),
            routes: [
              Route.get('/same', (c, ctx) => c.text),
              Route.get('/same', (c, ctx) => c.text),
            ],
          ),
        ],
      );

      await expectLater(
        Application.fromModule(root),
        throwsA(isA<RoutingError>()),
      );
      expect(created, isFalse);
    });

    test('application enhancers resolve through the root module', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          imports: [usersModule()],
          providers: [Provider((i) => AuthGuard())],
        ),
        enhancers: const Enhancers(guards: [Use<AuthGuard>()]),
        onError: silent,
      );

      expect((await app.handle(requestFor('GET', '/users'))).status, 401);
    });

    test('serializers registered on the app are used', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          controllers: [
            Controller<Answer>(
              create: (i) => Answer('x'),
              routes: [Route.get('/', (c, ctx) => c)],
            ),
          ],
        ),
        onError: silent,
      );
      app.serializers.register<Answer>((a) => {'text': a.text});

      expect(
        await textOf(await app.handle(requestFor('GET', '/'))),
        '{"text":"x"}',
      );
    });
  });

  group('Application middleware', () {
    test('runs in registration order around routing', () async {
      final app = await Application.create(appModule, onError: silent);
      final log = <String>[];
      app
        ..use((request, next) async {
          log.add('outer in');
          final response = await next();
          log.add('outer out');
          return response.mergeHeaders(HeaderMap.of({'x-outer': '1'}));
        })
        ..use((request, next) async {
          log.add('inner');
          return next();
        });

      final response = await app.handle(requestFor('GET', '/nope'));

      expect(response.status, 404);
      expect(response.headers['x-outer'], '1');
      expect(log, ['outer in', 'inner', 'outer out']);
    });

    test('can answer without routing, errors become 500', () async {
      final errors = <Object>[];
      final app = await Application.create(
        appModule,
        onError: (error, _) => errors.add(error),
      );
      app.use((request, next) async {
        if (request.uri.path == '/boom') throw StateError('boom');
        return HttpResponse.text('short');
      });

      expect(
        await textOf(await app.handle(requestFor('GET', '/users'))),
        'short',
      );
      expect((await app.handle(requestFor('GET', '/boom'))).status, 500);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('Application route table', () {
    test('middleware added while a request runs does not join it', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => slowModule('old', gate));
      final log = <String>[];
      app.use((request, next) async {
        await gate.future;
        return next();
      });

      final inFlight = app.handle(requestFor('GET', '/slow'));
      app.use((request, next) {
        log.add('late');
        return next();
      });
      gate.complete();
      await inFlight;
      await app.handle(requestFor('GET', '/slow'));

      expect(log, ['late']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest && dart test test/app/application_reassemble_test.dart`
Expected: FAIL: `'ReassembleReport' isn't a type`

- [ ] **Step 3: Implement `ReassembleReport` and `describe`**

Файл `packages/dartnest/lib/src/app/reassemble_report.dart`:

```dart
/// What `Application.reassemble` changed in the routes an application
/// serves, each route as `'GET /users/:id'`.
final class ReassembleReport {
  /// Creates the report.
  const ReassembleReport({
    required this.addedRoutes,
    required this.removedRoutes,
  });

  /// Compares the sorted route lists [before] and [after] a reassemble.
  factory ReassembleReport.between(List<String> before, List<String> after) {
    final old = before.toSet();
    final current = after.toSet();
    return ReassembleReport(
      addedRoutes: [
        for (final route in after)
          if (!old.contains(route)) route,
      ],
      removedRoutes: [
        for (final route in before)
          if (!current.contains(route)) route,
      ],
    );
  }

  /// Routes served now and not before, sorted.
  final List<String> addedRoutes;

  /// Routes served before and not now, sorted.
  final List<String> removedRoutes;

  /// How many routes were added or removed.
  int get changedRoutes => addedRoutes.length + removedRoutes.length;

  /// The report as JSON, for the `ext.dartnest.reassemble` service
  /// extension.
  Map<String, Object> toJson() => {
    'addedRoutes': addedRoutes,
    'removedRoutes': removedRoutes,
  };
}
```

Файл `packages/dartnest/lib/src/app/route_table_builder.dart`:

```dart
import '../controller/controller.dart';
import '../di/container.dart';
import '../di/injector.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/resolved_enhancers.dart';
import '../routing/route_pattern.dart';
import '../routing/router.dart';

/// Turns the controllers of a module graph into a [Router] of [Endpoint]s.
///
/// Modules are visited in `ModuleGraph.ordered` order, controllers and
/// routes in declaration order, so duplicate reports are deterministic.
abstract final class RouteTableBuilder {
  /// Checks every route pattern and rejects duplicate routes without
  /// creating anything, so `Application.create` can fail before any provider
  /// factory runs. Throws a `RoutingError`.
  static void validate(ModuleGraph graph) {
    final dryRun = Router<void>();
    for (final module in graph.ordered) {
      for (final controller in module.controllers) {
        for (final route in controller.routes) {
          dryRun.add(
            route.method,
            RoutePattern.join(controller.path, route.path),
            null,
            source: _source(controller, route.name, module.id),
          );
        }
      }
    }
  }

  /// Every route of [graph] as `'GET /users/:id'`, sorted; nothing is
  /// created.
  static List<String> describe(ModuleGraph graph) => [
    for (final module in graph.ordered)
      for (final controller in module.controllers)
        for (final route in controller.routes)
          '${route.method} ${RoutePattern.join(controller.path, route.path)}',
  ]..sort();

  /// Creates every controller with its module's injector, resolves the
  /// application [enhancers] through the root injector and the controller
  /// and route enhancers through the controller's module injector, and
  /// registers one [Endpoint] per route.
  static Router<Endpoint> build(Container container, Enhancers enhancers) {
    final application = ResolvedEnhancers.resolve(
      enhancers,
      container.root,
      owner: 'Application',
    );
    final router = Router<Endpoint>();
    for (final module in container.graph.ordered) {
      final injector = container.injectorFor(module.id);
      for (final controller in module.controllers) {
        _addController(router, controller, injector, application);
      }
    }
    return router;
  }

  static void _addController(
    Router<Endpoint> router,
    ControllerSpec controller,
    Injector injector,
    ResolvedEnhancers application,
  ) {
    final instance = controller.instantiate(injector);
    final controllerLevel = ResolvedEnhancers.resolve(
      controller.enhancers,
      injector,
      owner: '${controller.type}',
    );
    for (final route in controller.routes) {
      final routeLevel = ResolvedEnhancers.resolve(
        route.enhancers,
        injector,
        owner: '${controller.type}.${route.name}',
      );
      final endpoint = Endpoint(
        controllerType: controller.type,
        handlerName: route.name,
        metadata: [...route.metadata, ...controller.metadata],
        enhancers: ResolvedEnhancers.chain([
          application,
          controllerLevel,
          routeLevel,
        ]),
        invoke: (context) => route.invoke(instance, context),
      );
      router.add(
        route.method,
        RoutePattern.join(controller.path, route.path),
        endpoint,
        source: _source(controller, route.name, injector.moduleId),
      );
    }
  }

  static String _source(
    ControllerSpec controller,
    String handler,
    String moduleId,
  ) => '${controller.type}.$handler (module "$moduleId")';
}
```

Barrel (новий рядок — `reassemble_report.dart`):

Файл `packages/dartnest/lib/dartnest.dart`:

```dart
/// NestJS-style modular backend framework for Dart without `dart:mirrors`.
library;

export 'src/app/application.dart';
export 'src/pipeline/application_error.dart';
export 'src/app/http_adapter.dart';
export 'src/app/middleware.dart';
export 'src/app/reassemble_report.dart';
export 'src/controller/controller.dart';
export 'src/controller/route.dart';
export 'src/di/container.dart';
export 'src/di/errors.dart';
export 'src/di/injector.dart';
export 'src/di/module.dart';
export 'src/di/module_graph.dart';
export 'src/di/provider.dart';
export 'src/di/token.dart';
export 'src/http/connection_info.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
export 'src/http/status_code.dart';
export 'src/pipeline/argument_meta.dart';
export 'src/pipeline/argument_source.dart';
export 'src/pipeline/enhancers.dart';
export 'src/pipeline/enum_pipe.dart';
export 'src/pipeline/exception_filter.dart';
export 'src/pipeline/execution_context.dart';
export 'src/pipeline/guard.dart';
export 'src/pipeline/handler_spec.dart';
export 'src/pipeline/http_error_responder.dart' show ErrorLogger;
export 'src/pipeline/interceptor.dart';
export 'src/pipeline/pipe.dart';
export 'src/pipeline/pipeline_component.dart';
export 'src/pipeline/pipeline_error.dart';
export 'src/pipeline/serializer_registry.dart';
export 'src/pipeline/transport.dart';
export 'src/pipeline/use.dart';
export 'src/routing/routing_error.dart';
```

- [ ] **Step 4: Implement `rebuild` and `Application.reassemble`**

Файл `packages/dartnest/lib/src/app/application_assembly.dart`:

```dart
import '../di/container.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../routing/router.dart';
import 'reassemble_report.dart';
import 'route_table_builder.dart';

/// The started container of an application and the route table built from
/// it.
typedef Assembly = ({Container container, Router<Endpoint> router});

/// Builds what an `Application` serves from its root module: validates the
/// routes before any provider is created, starts the container, creates the
/// controllers and the route table.
abstract final class ApplicationAssembly {
  /// Assembles [root] with the application-level [enhancers].
  ///
  /// Fails fast: a `RoutingError` before any provider is created; on any
  /// later failure the container is closed before the error is passed on.
  static Future<Assembly> start(Module root, Enhancers enhancers) async {
    RouteTableBuilder.validate(ModuleGraph.build(root));
    final container = await Container.create(root);
    // Any failure before the return closes the container; the error itself
    // propagates untouched, so no catch is needed.
    var succeeded = false;
    try {
      final router = RouteTableBuilder.build(container, enhancers);
      succeeded = true;
      return (container: container, router: router);
    } finally {
      if (!succeeded) await container.close();
    }
  }

  /// Assembles [root] again after a hot reload, like [start] but through
  /// `Container.reassemble`, so providers that stay keep their instances;
  /// reports which routes changed against [current].
  ///
  /// [current] is not changed: on a failure it still serves.
  static Future<(Assembly, ReassembleReport)> rebuild(
    Assembly current,
    Module root,
    Enhancers enhancers,
  ) async {
    final graph = ModuleGraph.build(root);
    RouteTableBuilder.validate(graph);
    final container = await current.container.reassemble(root);
    final router = RouteTableBuilder.build(container, enhancers);
    final report = ReassembleReport.between(
      RouteTableBuilder.describe(current.container.graph),
      RouteTableBuilder.describe(graph),
    );
    return ((container: container, router: router), report);
  }
}
```

Файл `packages/dartnest/lib/src/app/application.dart`:

````dart
import '../di/container.dart';
import '../di/module.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/serializer_registry.dart';
import '../routing/router.dart';
import '../pipeline/application_error.dart';
import 'application_assembly.dart';
import 'http_adapter.dart';
import 'in_flight_requests.dart';
import 'middleware.dart';
import 'reassemble_report.dart';
import 'request_dispatcher.dart';

/// A started dartnest application: the container, the route table and the
/// request pipeline. Works without a server through [handle]; serves HTTP
/// through an [HttpAdapter] and [listen].
///
/// ```dart
/// final app = await Application.create(appModule);
/// final response = await app.handle(
///   HttpRequest(method: 'GET', uri: Uri.parse('/users/1')),
/// );
/// await app.close();
/// ```
final class Application {
  Application._({
    required Module Function() root,
    required Enhancers enhancers,
    required Assembly assembly,
    required HttpAdapter? adapter,
    required HttpErrorResponder errors,
  }) : _root = root,
       _enhancers = enhancers,
       _assembly = assembly,
       _adapter = adapter,
       _errors = errors,
       _dispatcher = RequestDispatcher(
         serializer: ResponseSerializer(SerializerRegistry()),
         errors: errors,
       );

  /// Builds the module returned by [root], validates the routes, starts the
  /// container, creates the controllers and builds the route table.
  ///
  /// [root] is a function so that the module graph can be rebuilt after a
  /// hot reload. [enhancers] are the application-level components, resolved
  /// through the root module. [debug] adds error details to 500 responses;
  /// [onError] receives unexpected errors (default: print); it must not
  /// throw, or [handle] fails.
  ///
  /// Fails fast: a `RoutingError` before any provider is created, an
  /// `InjectionError` or `ApplicationError` (or any other failure) before the
  /// application is returned (the container is closed first).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) async => Application._(
    root: root,
    enhancers: enhancers,
    assembly: await ApplicationAssembly.start(root(), enhancers),
    adapter: adapter,
    errors: HttpErrorResponder(
      debug: debug,
      log: onError ?? HttpErrorResponder.printError,
    ),
  );

  /// Like [create], for a module value; [reassemble] reuses that value.
  static Future<Application> fromModule(
    Module root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) => create(
    () => root,
    adapter: adapter,
    enhancers: enhancers,
    debug: debug,
    onError: onError,
  );

  /// The started dependency container; [reassemble] replaces it.
  Container get container => _assembly.container;

  /// Converters for result types without `toJson()`.
  SerializerRegistry get serializers => _dispatcher.serializer.registry;

  final Module Function() _root;
  final Enhancers _enhancers;
  Assembly _assembly;
  final HttpAdapter? _adapter;
  final HttpErrorResponder _errors;
  final RequestDispatcher _dispatcher;
  final List<Middleware> _middleware = [];
  final InFlightRequests _inFlight = InFlightRequests();
  Future<void>? _closing;
  bool _listening = false;
  bool _reassembling = false;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Adds [middleware] after the ones added before (it runs inside them);
  /// fails with [ApplicationStateError] after [close] has started.
  void use(Middleware middleware) {
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'use',
        reason: 'the application is closed',
      );
    }
    _middleware.add(middleware);
  }

  /// Answers [request]; never throws. After [close] it answers 503.
  ///
  /// The route table is read once per request, so a request keeps the table
  /// it started with even if [reassemble] replaces it meanwhile.
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) return _unavailable();
    final router = _assembly.router;
    final chain = List.of(_middleware);
    return _inFlight.track(() => _answer(request, router, chain));
  }

  /// Serves the application through the adapter on [address] and [port]. The
  /// adapter gets an uncounted variant of [handle] (same answers, 503 after
  /// [close]); it counts its own in-flight requests. Fails with
  /// [ApplicationStateError] without an adapter, after [close], or when
  /// already listening. When the adapter fails to start, the error is passed
  /// on and [listen] can be called again, e.g. on another port.
  Future<void> listen({required int port, Object address = 'localhost'}) async {
    final adapter = _adapter;
    if (adapter == null) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'no HttpAdapter was passed to Application.create',
      );
    }
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is closed',
      );
    }
    if (_listening) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is already listening',
      );
    }
    _listening = true;
    // A failed start must not block a retry, e.g. on another port.
    var started = false;
    try {
      await adapter.listen(_handleForAdapter, address: address, port: port);
      started = true;
    } finally {
      if (!started) _listening = false;
    }
  }

  /// Stops the application: the adapter stops accepting requests, new
  /// requests answer 503, in-flight requests finish (unless [force]), then
  /// the container closes. Every call returns the same future; [force] of
  /// later calls is ignored.
  ///
  /// The adapter's `close` waits for the requests it delivered and may give
  /// up on them after a timeout of its own; this method then waits for the
  /// [handle] calls made directly, e.g. by `TestClient`.
  ///
  /// If the adapter's `close` throws, the wait for in-flight requests is
  /// skipped (the container is still closed and the error propagates to
  /// every `close()` caller), so a failing adapter can cut in-flight
  /// requests short.
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// Rebuilds the application from its module function after a hot reload:
  /// the new graph is validated, `Container.reassemble` keeps the instances
  /// of providers that stay, controllers and the route table are created
  /// anew, and both replace the old ones in one assignment. Requests
  /// already running finish on the table they started with.
  ///
  /// Any failure (those of [create], or of the module function) leaves the
  /// previous container and routes serving and is passed on. Fails with
  /// [ApplicationStateError] after [close] and while another reassemble
  /// runs.
  Future<ReassembleReport> reassemble() async {
    if (isClosed || _reassembling) {
      throw ApplicationStateError(
        operation: 'reassemble',
        reason: isClosed
            ? 'the application is closed'
            : 'a reassemble is already running',
      );
    }
    _reassembling = true;
    try {
      final (assembly, report) = await ApplicationAssembly.rebuild(
        _assembly,
        _root(),
        _enhancers,
      );
      _assembly = assembly;
      return report;
    } finally {
      _reassembling = false;
    }
  }

  // Not counted in _inFlight: the adapter's close waits for the requests it
  // delivered and may abandon them after its timeout; counting them here as
  // well would leave close waiting for a handler the adapter gave up on.
  Future<HttpResponse> _handleForAdapter(HttpRequest request) {
    if (isClosed) return _unavailable();
    return _answer(request, _assembly.router, List.of(_middleware));
  }

  Future<HttpResponse> _unavailable() => Future.value(
    _errors.respond(
      const ServiceUnavailableException(
        message: 'The application is shutting down.',
      ),
      StackTrace.current,
    ),
  );

  Future<void> _shutdown({required bool force}) async {
    final adapter = _adapter;
    try {
      if (_listening && adapter != null) await adapter.close(force: force);
      if (!force) await _inFlight.idle;
    } finally {
      await container.close();
    }
  }

  Future<HttpResponse> _answer(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
  ) async {
    // Request boundary: a throwing middleware still gets an answer.
    try {
      return await _next(request, router, chain, 0);
    } on Object catch (error, stackTrace) {
      return _errors.respond(error, stackTrace);
    }
  }

  Future<HttpResponse> _next(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
    int index,
  ) {
    if (index == chain.length) return _dispatcher.dispatch(request, router);
    return chain[index](
      request,
      () => _next(request, router, chain, index + 1),
    );
  }
}
````

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest && dart test test/app/application_reassemble_test.dart`
Expected: `+7: All tests passed!`

Run: `cd packages/dartnest && dart test`
Expected: `+264: All tests passed!`

Run: `cd packages/dartnest_io && dart test`
Expected: `+46: All tests passed!`

Run: `cd packages/dartnest_shelf && dart test`
Expected: `+67: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest/lib/src/app/reassemble_report.dart \
  packages/dartnest/lib/src/app/route_table_builder.dart \
  packages/dartnest/lib/src/app/application_assembly.dart \
  packages/dartnest/lib/src/app/application.dart \
  packages/dartnest/lib/dartnest.dart \
  packages/dartnest/test/app/application_reassemble_test.dart \
  packages/dartnest/test/app/application_test.dart
git commit -m "feat(core): Application.reassemble rebuilds the graph and swaps the routes"
```

### Task 4: Service extensions `ext.dartnest.reassemble` і `ext.dartnest.close`

Спека 10, 10.2 п. 2. `HotReloadExtension` тримає множину відкритих застосунків ізоляту: `Application.create` додає (`attach`), перший `close()` прибирає (`detach`). Обидві extension реєструються один раз на ізолят і лише поза product-режимом (`isEnabled`; у AOT нуль накладних витрат, спека 10). `handle` — нова межа `on Object` (Рішення 4): збій `reassemble` чи `close` (там виконуються функції модулів і фабрики користувача) стає `ServiceExtensionResponse.error` з текстом помилки (`DartnestError` уже містить ланцюжок; для решти — ще й стек), застосунок працює далі. `handle` позначено `@visibleForTesting`, щоб тест викликав його без VM service; справжній виклик через VM service перевіряє Task 7.

**Files:**
- Create: `packages/dartnest/lib/src/app/hot_reload_extension.dart`
- Modify: `packages/dartnest/lib/src/app/application.dart`
- Test: `packages/dartnest/test/app/hot_reload_extension_test.dart`

**Interfaces:**
- Consumes: `Application.reassemble`, `ReassembleReport.addedRoutes`/`removedRoutes` (Task 3), `Application.close`, `DartnestError`; `dart:developer` (`registerExtension`, `ServiceExtensionResponse`), `package:meta` (`visibleForTesting`).
- Produces:
  - `abstract final class HotReloadExtension`: `static const reassembleMethod = 'ext.dartnest.reassemble'`, `static const closeMethod = 'ext.dartnest.close'`, `static const isEnabled`, `static void attach(Application)`, `static void detach(Application)`, `@visibleForTesting static Future<ServiceExtensionResponse> handle(String method, Map<String, String> parameters)`.
  - Відповідь reassemble: `{"applications": n, "addedRoutes": [...], "removedRoutes": [...]}` (відсортовано, по всіх застосунках); close: `{"applications": n}`; помилка — `ServiceExtensionResponse.extensionError`, `errorDetail` = текст помилки. Не в barrel.

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest/test/app/hot_reload_extension_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/hot_reload_extension.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

/// The module of the application; a test changes it to "reload" the code.
final class Code {
  /// The path of the one route.
  static String path = '/a';

  /// Whether the module function throws a non-dartnest error.
  static bool isBroken = false;

  /// The module of the current code.
  static Module module() {
    if (isBroken) throw StateError('broken module');
    return Module(
      id: 'app',
      providers: [Provider((i) => Clock())],
      controllers: [
        Controller<Clock>(
          create: (i) => i.get(),
          routes: [Route.get(path, (c, ctx) => 'ok')],
        ),
      ],
    );
  }
}

/// An application of [Code.module] closed when the test ends.
Future<Application> started() async {
  final application = await Application.create(Code.module);
  addTearDown(application.close);
  return application;
}

/// The JSON result of calling [method], or a failure with its error.
Future<Map<String, Object?>> callExtension(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  final result =
      response.result ??
      fail('error ${response.errorCode}: ${response.errorDetail}');
  return jsonDecode(result) as Map<String, Object?>;
}

void main() {
  setUp(() {
    Code.path = '/a';
    Code.isBroken = false;
  });

  test('the extensions exist outside product builds', () {
    expect(HotReloadExtension.isEnabled, isTrue);
  });

  test(
    'reassemble rebuilds every open application and reports routes',
    () async {
      final first = await started();
      await started();
      Code.path = '/b';

      final result = await callExtension(HotReloadExtension.reassembleMethod);

      expect(result, {
        'applications': 2,
        'addedRoutes': ['GET /b', 'GET /b'],
        'removedRoutes': ['GET /a', 'GET /a'],
      });
      expect(first.container.graph.root.controllers, hasLength(1));
    },
  );

  test('a closed application is not reassembled', () async {
    final application = await started();
    await application.close();

    expect(await callExtension(HotReloadExtension.reassembleMethod), {
      'applications': 0,
      'addedRoutes': <String>[],
      'removedRoutes': <String>[],
    });
  });

  test('a dartnest error is answered with its message', () async {
    await started();
    Code.path = 'a/:x/:x';

    final response = await HotReloadExtension.handle(
      HotReloadExtension.reassembleMethod,
      const {},
    );

    expect(response.errorCode, -32000);
    expect(response.errorDetail, startsWith('InvalidRoutePatternError: '));
    expect(response.errorDetail, isNot(contains('#0')));
  });

  test('any other error is answered with its stack trace', () async {
    await started();
    Code.isBroken = true;

    final response = await HotReloadExtension.handle(
      HotReloadExtension.reassembleMethod,
      const {},
    );

    expect(response.errorDetail, startsWith('Bad state: broken module\n#0'));
  });

  test('close closes every open application', () async {
    final application = await started();

    expect(await callExtension(HotReloadExtension.closeMethod), {
      'applications': 1,
    });
    expect(application.isClosed, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest && dart test test/app/hot_reload_extension_test.dart`
Expected: FAIL: `Undefined name 'HotReloadExtension'`

- [ ] **Step 3: Implement the extension**

Файл `packages/dartnest/lib/src/app/hot_reload_extension.dart`:

```dart
import 'dart:convert';
import 'dart:developer';

import 'package:meta/meta.dart';

import '../di/errors.dart';
import 'application.dart';
import 'reassemble_report.dart';

/// The VM service extensions through which `dartnest_cli dev` drives the
/// applications of the process it runs: [reassembleMethod] after a hot
/// reload, [closeMethod] before a hot restart.
///
/// Every `Application` is attached when it is created and detached when it
/// starts closing. The extensions are registered with the VM once, on the
/// first attach, and only when [isEnabled]: a product (AOT) build neither
/// registers them nor keeps any application.
abstract final class HotReloadExtension {
  /// Calls `Application.reassemble` on every attached application and
  /// answers `{"applications": n, "addedRoutes": [...], "removedRoutes":
  /// [...]}`.
  static const reassembleMethod = 'ext.dartnest.reassemble';

  /// Closes every attached application and answers `{"applications": n}`.
  static const closeMethod = 'ext.dartnest.close';

  /// Whether the extensions exist: the process is not a product build.
  static const isEnabled = !bool.fromEnvironment('dart.vm.product');

  static final _applications = <Application>{};
  static var _registered = false;

  /// Makes [application] reachable from the extensions.
  static void attach(Application application) {
    if (!isEnabled) return;
    _applications.add(application);
    if (_registered) return;
    _registered = true;
    registerExtension(reassembleMethod, handle);
    registerExtension(closeMethod, handle);
  }

  /// Makes [application] unreachable from the extensions.
  static void detach(Application application) =>
      _applications.remove(application);

  /// Answers one call of [method]; the handler registered with the VM.
  @visibleForTesting
  static Future<ServiceExtensionResponse> handle(
    String method,
    Map<String, String> parameters,
  ) async {
    final applications = List.of(_applications);
    // Extension boundary: the module functions and provider factories of
    // the user run inside reassemble, and adapters inside close. A failure
    // becomes an extension error with its message (a DartnestError carries
    // its dependency chain; anything else gets its stack trace), the
    // previous application state keeps serving and `dev` prints the error.
    try {
      return method == closeMethod
          ? await _close(applications)
          : await _reassemble(applications);
    } on Object catch (error, stackTrace) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        error is DartnestError ? '$error' : '$error\n$stackTrace',
      );
    }
  }

  static Future<ServiceExtensionResponse> _reassemble(
    List<Application> applications,
  ) async {
    final added = <String>[];
    final removed = <String>[];
    for (final application in applications) {
      final report = await application.reassemble();
      added.addAll(report.addedRoutes);
      removed.addAll(report.removedRoutes);
    }
    final report = ReassembleReport(
      addedRoutes: added..sort(),
      removedRoutes: removed..sort(),
    );
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': applications.length, ...report.toJson()}),
    );
  }

  static Future<ServiceExtensionResponse> _close(
    List<Application> applications,
  ) async {
    await Future.wait([
      for (final application in applications) application.close(),
    ]);
    return ServiceExtensionResponse.result(
      jsonEncode({'applications': applications.length}),
    );
  }
}
```

- [ ] **Step 4: Attach in `create`, detach in `close`**

Файл `packages/dartnest/lib/src/app/application.dart`:

````dart
import '../di/container.dart';
import '../di/module.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/serializer_registry.dart';
import '../routing/router.dart';
import '../pipeline/application_error.dart';
import 'application_assembly.dart';
import 'hot_reload_extension.dart';
import 'http_adapter.dart';
import 'in_flight_requests.dart';
import 'middleware.dart';
import 'reassemble_report.dart';
import 'request_dispatcher.dart';

/// A started dartnest application: the container, the route table and the
/// request pipeline. Works without a server through [handle]; serves HTTP
/// through an [HttpAdapter] and [listen].
///
/// ```dart
/// final app = await Application.create(appModule);
/// final response = await app.handle(
///   HttpRequest(method: 'GET', uri: Uri.parse('/users/1')),
/// );
/// await app.close();
/// ```
final class Application {
  Application._({
    required Module Function() root,
    required Enhancers enhancers,
    required Assembly assembly,
    required HttpAdapter? adapter,
    required HttpErrorResponder errors,
  }) : _root = root,
       _enhancers = enhancers,
       _assembly = assembly,
       _adapter = adapter,
       _errors = errors,
       _dispatcher = RequestDispatcher(
         serializer: ResponseSerializer(SerializerRegistry()),
         errors: errors,
       );

  /// Builds the module returned by [root], validates the routes, starts the
  /// container, creates the controllers and builds the route table. Outside
  /// product (AOT) builds the application is then reachable from the VM
  /// service extensions of `dartnest_cli dev` until it starts closing.
  ///
  /// [root] is a function so that the module graph can be rebuilt after a
  /// hot reload. [enhancers] are the application-level components, resolved
  /// through the root module. [debug] adds error details to 500 responses;
  /// [onError] receives unexpected errors (default: print); it must not
  /// throw, or [handle] fails.
  ///
  /// Fails fast: a `RoutingError` before any provider is created, an
  /// `InjectionError` or `ApplicationError` (or any other failure) before the
  /// application is returned (the container is closed first).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) async {
    final application = Application._(
      root: root,
      enhancers: enhancers,
      assembly: await ApplicationAssembly.start(root(), enhancers),
      adapter: adapter,
      errors: HttpErrorResponder(
        debug: debug,
        log: onError ?? HttpErrorResponder.printError,
      ),
    );
    HotReloadExtension.attach(application);
    return application;
  }

  /// Like [create], for a module value; [reassemble] reuses that value.
  static Future<Application> fromModule(
    Module root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) => create(
    () => root,
    adapter: adapter,
    enhancers: enhancers,
    debug: debug,
    onError: onError,
  );

  /// The started dependency container; [reassemble] replaces it.
  Container get container => _assembly.container;

  /// Converters for result types without `toJson()`.
  SerializerRegistry get serializers => _dispatcher.serializer.registry;

  final Module Function() _root;
  final Enhancers _enhancers;
  Assembly _assembly;
  final HttpAdapter? _adapter;
  final HttpErrorResponder _errors;
  final RequestDispatcher _dispatcher;
  final List<Middleware> _middleware = [];
  final InFlightRequests _inFlight = InFlightRequests();
  Future<void>? _closing;
  bool _listening = false;
  bool _reassembling = false;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Adds [middleware] after the ones added before (it runs inside them);
  /// fails with [ApplicationStateError] after [close] has started.
  void use(Middleware middleware) {
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'use',
        reason: 'the application is closed',
      );
    }
    _middleware.add(middleware);
  }

  /// Answers [request]; never throws. After [close] it answers 503.
  ///
  /// The route table is read once per request, so a request keeps the table
  /// it started with even if [reassemble] replaces it meanwhile.
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) return _unavailable();
    final router = _assembly.router;
    final chain = List.of(_middleware);
    return _inFlight.track(() => _answer(request, router, chain));
  }

  /// Serves the application through the adapter on [address] and [port]. The
  /// adapter gets an uncounted variant of [handle] (same answers, 503 after
  /// [close]); it counts its own in-flight requests. Fails with
  /// [ApplicationStateError] without an adapter, after [close], or when
  /// already listening. When the adapter fails to start, the error is passed
  /// on and [listen] can be called again, e.g. on another port.
  Future<void> listen({required int port, Object address = 'localhost'}) async {
    final adapter = _adapter;
    if (adapter == null) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'no HttpAdapter was passed to Application.create',
      );
    }
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is closed',
      );
    }
    if (_listening) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is already listening',
      );
    }
    _listening = true;
    // A failed start must not block a retry, e.g. on another port.
    var started = false;
    try {
      await adapter.listen(_handleForAdapter, address: address, port: port);
      started = true;
    } finally {
      if (!started) _listening = false;
    }
  }

  /// Stops the application: the adapter stops accepting requests, new
  /// requests answer 503, in-flight requests finish (unless [force]), then
  /// the container closes. Every call returns the same future; [force] of
  /// later calls is ignored.
  ///
  /// The adapter's `close` waits for the requests it delivered and may give
  /// up on them after a timeout of its own; this method then waits for the
  /// [handle] calls made directly, e.g. by `TestClient`.
  ///
  /// If the adapter's `close` throws, the wait for in-flight requests is
  /// skipped (the container is still closed and the error propagates to
  /// every `close()` caller), so a failing adapter can cut in-flight
  /// requests short.
  Future<void> close({bool force = false}) {
    HotReloadExtension.detach(this);
    return _closing ??= _shutdown(force: force);
  }

  /// Rebuilds the application from its module function after a hot reload:
  /// the new graph is validated, `Container.reassemble` keeps the instances
  /// of providers that stay, controllers and the route table are created
  /// anew, and both replace the old ones in one assignment. Requests
  /// already running finish on the table they started with.
  ///
  /// Any failure (those of [create], or of the module function) leaves the
  /// previous container and routes serving and is passed on. Fails with
  /// [ApplicationStateError] after [close] and while another reassemble
  /// runs.
  Future<ReassembleReport> reassemble() async {
    if (isClosed || _reassembling) {
      throw ApplicationStateError(
        operation: 'reassemble',
        reason: isClosed
            ? 'the application is closed'
            : 'a reassemble is already running',
      );
    }
    _reassembling = true;
    try {
      final (assembly, report) = await ApplicationAssembly.rebuild(
        _assembly,
        _root(),
        _enhancers,
      );
      _assembly = assembly;
      return report;
    } finally {
      _reassembling = false;
    }
  }

  // Not counted in _inFlight: the adapter's close waits for the requests it
  // delivered and may abandon them after its timeout; counting them here as
  // well would leave close waiting for a handler the adapter gave up on.
  Future<HttpResponse> _handleForAdapter(HttpRequest request) {
    if (isClosed) return _unavailable();
    return _answer(request, _assembly.router, List.of(_middleware));
  }

  Future<HttpResponse> _unavailable() => Future.value(
    _errors.respond(
      const ServiceUnavailableException(
        message: 'The application is shutting down.',
      ),
      StackTrace.current,
    ),
  );

  Future<void> _shutdown({required bool force}) async {
    final adapter = _adapter;
    try {
      if (_listening && adapter != null) await adapter.close(force: force);
      if (!force) await _inFlight.idle;
    } finally {
      await container.close();
    }
  }

  Future<HttpResponse> _answer(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
  ) async {
    // Request boundary: a throwing middleware still gets an answer.
    try {
      return await _next(request, router, chain, 0);
    } on Object catch (error, stackTrace) {
      return _errors.respond(error, stackTrace);
    }
  }

  Future<HttpResponse> _next(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
    int index,
  ) {
    if (index == chain.length) return _dispatcher.dispatch(request, router);
    return chain[index](
      request,
      () => _next(request, router, chain, index + 1),
    );
  }
}
````

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest && dart test test/app/hot_reload_extension_test.dart`
Expected: `+6: All tests passed!`

Run: `cd packages/dartnest && dart test`
Expected: `+270: All tests passed!`

Run: `cd packages/dartnest_io && dart test`
Expected: `+46: All tests passed!`

Run: `cd packages/dartnest_shelf && dart test`
Expected: `+67: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest/lib/src/app/hot_reload_extension.dart \
  packages/dartnest/lib/src/app/application.dart \
  packages/dartnest/test/app/hot_reload_extension_test.dart
git commit -m "feat(core): ext.dartnest.reassemble and ext.dartnest.close service extensions"
```

### Task 5: `ShapeTracker`

OP4. «Форма» файлу — вихідний текст (`toSource()`, тож коментарі й форматування не рахуються) його полів (зокрема static), конструкторів, top-level змінних і значень enum; `parseString(throwIfDiagnostics: false)` без резолву, тож файл із синтаксичними помилками теж має форму. `remember(paths)` запам'ятовує базу (на кожному запуску процесу), `changed(paths)` повертає файли, форма яких змінилась, і оновлює базу. Новий і видалений файли — не зміна форми (новий клас не має старих екземплярів; видалений клас перестає використовуватись — reload або VM-відмова розберуться). Нечитабельний файл — `FileSystemException` → немає форми.

**Files:**
- Create: `packages/dartnest_cli/lib/src/dev/shape_tracker.dart`
- Test: `packages/dartnest_cli/test/shape_tracker_test.dart`

**Interfaces:**
- Consumes: `package:analyzer` (`parseString`, `RecursiveAstVisitor`, `TopLevelVariableDeclaration`, `FieldDeclaration`, `ConstructorDeclaration`, `EnumConstantDeclaration` — однакові в 8.1.1 і 14.5.0).
- Produces: `final class ShapeTracker`: `static String shapeOf(String source)`, `void remember(Iterable<String> paths)`, `List<String> changed(Iterable<String> paths)` (абсолютні шляхи в порядку `paths`).

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/shape_tracker_test.dart`:

```dart
import 'package:dartnest_cli/src/dev/shape_tracker.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

const _service = '''
final greeting = 'hi';

final class Service {
  Service(this.name);

  final String name;

  String greet() => 'hello \$name';
}
''';

/// Whether replacing [from] by [to] in `_service` changes its shape.
bool changesShape(String from, String to) {
  expect(_service, contains(from));
  return ShapeTracker.shapeOf(_service) !=
      ShapeTracker.shapeOf(_service.replaceFirst(from, to));
}

void main() {
  group('ShapeTracker.shapeOf', () {
    test('a method body is not part of the shape', () {
      expect(changesShape("'hello \$name'", "'bye \$name'"), isFalse);
    });

    test('comments and formatting are not part of the shape', () {
      expect(
        changesShape(
          '  final String name;',
          '  // why\n  final String  name ;',
        ),
        isFalse,
      );
    });

    test('a new field changes the shape', () {
      // Review Focus 9: a reload keeps instances without the new field.
      expect(
        changesShape(
          '  final String name;',
          '  final String name;\n  int count = 0;',
        ),
        isTrue,
      );
    });

    test('a changed constructor changes the shape', () {
      expect(
        changesShape('Service(this.name);', 'Service([this.name = "x"]);'),
        isTrue,
      );
    });

    test('a changed top-level initializer changes the shape', () {
      expect(changesShape("greeting = 'hi'", "greeting = 'hello'"), isTrue);
    });

    test('a new enum value changes the shape', () {
      const before = 'enum Level { low }';
      expect(
        ShapeTracker.shapeOf(before),
        isNot(ShapeTracker.shapeOf('enum Level { low, high }')),
      );
    });

    test('a file with syntax errors still has a shape', () {
      expect(
        ShapeTracker.shapeOf('final class { int x = 1; '),
        contains('int x = 1;'),
      );
    });
  });

  group('ShapeTracker.changed', () {
    test('reports the files whose shape changed since remembered', () {
      final dir = TempDir.create();
      final service = dir.write('lib/service.dart', _service);
      final body = dir.write('lib/body.dart', _service);
      final tracker = ShapeTracker()..remember([service, body]);
      dir.write(
        'lib/service.dart',
        _service.replaceFirst(
          'final String name;',
          'final String name;\n  int count = 0;',
        ),
      );
      dir.write('lib/body.dart', _service.replaceFirst('hello', 'bye'));

      expect(tracker.changed([service, body]), [service]);
      expect(tracker.changed([service, body]), isEmpty);
    });

    test('new and deleted files are not shape changes', () {
      final dir = TempDir.create();
      final tracker = ShapeTracker();
      final added = dir.write('lib/added.dart', _service);

      expect(tracker.changed([added, dir.resolve('lib/gone.dart')]), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/shape_tracker_test.dart`
Expected: FAIL: `Undefined name 'ShapeTracker'`

- [ ] **Step 3: Implement `ShapeTracker`**

Файл `packages/dartnest_cli/lib/src/dev/shape_tracker.dart`:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Remembers the shape of Dart files: the declarations a hot reload cannot
/// apply to state that already exists.
///
/// The shape of a file is the source (without comments and formatting) of
/// its top-level variables, fields, constructors and enum values. A
/// changed field or constructor would leave instances created before the
/// reload (the providers kept by `Container.reassemble`) with fields that
/// were never initialized; a changed initializer of a top-level or static
/// variable, or a changed `const`, is not applied by a reload at all. A
/// change of anything else (method bodies, functions, annotations of
/// classes and methods) is reloadable.
final class ShapeTracker {
  final _shapes = <String, String>{};

  /// The shape of the Dart [source]; syntax errors are tolerated.
  static String shapeOf(String source) {
    final collector = _ShapeCollector();
    parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.accept(collector);
    return collector.parts.join('\n');
  }

  /// Remembers the shapes of the files at [paths]; missing files are
  /// skipped.
  void remember(Iterable<String> paths) {
    for (final path in paths) {
      final source = _read(path);
      if (source != null) _shapes[path] = shapeOf(source);
    }
  }

  /// The [paths] whose shape differs from the one remembered, in the
  /// order given; remembers the new shapes. A file seen for the first time
  /// or deleted is not a change of shape.
  List<String> changed(Iterable<String> paths) {
    final changed = <String>[];
    for (final path in paths) {
      final source = _read(path);
      if (source == null) {
        _shapes.remove(path);
        continue;
      }
      final shape = shapeOf(source);
      final previous = _shapes[path];
      _shapes[path] = shape;
      if (previous != null && previous != shape) changed.add(path);
    }
    return changed;
  }

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      // Deleted or unreadable since the event: nothing to compare.
      return null;
    }
  }
}

/// Collects the source of every shape declaration of a unit.
final class _ShapeCollector extends RecursiveAstVisitor<void> {
  final parts = <String>[];

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitFieldDeclaration(FieldDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) =>
      parts.add(node.toSource());
}
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/shape_tracker_test.dart`
Expected: `+9: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+71: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/lib/src/dev/shape_tracker.dart \
  packages/dartnest_cli/test/shape_tracker_test.dart
git commit -m "feat(cli): ShapeTracker finds changes a hot reload cannot apply"
```

### Task 6: `AppProcess`

OP9, OP10. Дочірній процес — `Platform.resolvedExecutable` з `AppProcess.vmFlags` (`--enable-vm-service=0 --no-dds`), точкою входу й аргументами, у корені пакета. `dart <file>` виконує VM у тому ж процесі, тож `pid` — PID застосунку (тест порівнює з `pid`, який друкує сам застосунок). Рядок банера `The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/` завершує `serviceUri` і не пересилається; решта stdout/stderr — у `out`/`err` рядками як є. Без банера (точка входу не існує) `serviceUri` завершується `null`, коли stdout закрився. `exitCode` — після закриття обох потоків (увесь вивід уже переслано). `stop` — SIGTERM, через `killGrace` — SIGKILL; на Windows `kill` одразу завершує процес (Review Focus 7). Тести запускають маленькі Dart-програми з `TempDir`, без мережі.

**Files:**
- Create: `packages/dartnest_cli/lib/src/dev/app_process.dart`
- Test: `packages/dartnest_cli/test/app_process_test.dart`

**Interfaces:**
- Consumes: `dart:io` `Process`, `Platform.resolvedExecutable`; тестові `TempDir`, `LineSink` (етап 5).
- Produces: `final class AppProcess`: `static const vmFlags`, `static Future<AppProcess> start({required String target, required List<String> arguments, required String workingDirectory, required StringSink out, required StringSink err})`, `int get pid`, `Future<Uri?> serviceUri`, `Future<int> exitCode`, `Future<int> stop({Duration killGrace = const Duration(seconds: 2)})` (код виходу).

- [ ] **Step 1: Write the failing test**

Файл `packages/dartnest_cli/test/app_process_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:dartnest_cli/src/dev/app_process.dart';
import 'package:test/test.dart';

import 'helpers/line_sink.dart';
import 'helpers/temp_dir.dart';

/// Starts the Dart program [source] as an [AppProcess] in a [TempDir].
Future<(AppProcess, LineSink, LineSink)> startProgram(String source) async {
  final dir = TempDir.create();
  dir.write('bin/main.dart', source);
  final out = LineSink();
  final err = LineSink();
  final app = await AppProcess.start(
    target: 'bin/main.dart',
    arguments: ['an argument'],
    workingDirectory: dir.path,
    out: out,
    err: err,
  );
  addTearDown(() => app.stop(killGrace: Duration.zero));
  return (app, out, err);
}

void main() {
  test(
    'forwards the output of the child without the VM service banner',
    () async {
      final (app, out, err) = await startProgram('''
import 'dart:io';

void main(List<String> arguments) {
  print('started with \$arguments');
  stderr.writeln('a warning');
  exitCode = 3;
}
''');

      final uri = await app.serviceUri;
      expect(await app.exitCode, 3);
      expect(uri, isNotNull);
      expect(uri?.host, '127.0.0.1');
      expect(out.lines, ['started with [an argument]']);
      expect(err.lines, ['a warning']);
    },
  );

  test('the pid is the pid of the application', () async {
    final (app, out, _) = await startProgram('''
import 'dart:io';

void main() => print(pid);
''');

    await app.exitCode;
    expect(out.lines, ['${app.pid}']);
  });

  test('a child that cannot start has no VM service', () async {
    final dir = TempDir.create();
    final err = LineSink();
    final app = await AppProcess.start(
      target: 'bin/missing.dart',
      arguments: const [],
      workingDirectory: dir.path,
      out: LineSink(),
      err: err,
    );

    expect(await app.serviceUri, isNull);
    expect(await app.exitCode, isNot(0));
    expect(err.lines.join('\n'), contains('bin/missing.dart'));
  });

  test('stop ends a child that keeps running', () async {
    final (app, out, _) = await startProgram('''
Future<void> main() async {
  print('ready');
  await Future<void>.delayed(const Duration(hours: 1));
}
''');
    expect(await out.next(), 'ready');

    expect(await app.stop(), isNot(0));
  });

  test('stop kills a child that ignores SIGTERM', () async {
    // Review Focus 7: Windows has no SIGTERM; there stop only kills.
    final (app, out, _) = await startProgram('''
import 'dart:io';

void main() {
  ProcessSignal.sigterm.watch().listen((_) => print('ignored'));
  print('ready');
}
''');
    expect(await out.next(), 'ready');

    final code = await app.stop(killGrace: const Duration(milliseconds: 500));

    expect(code, -ProcessSignal.sigkill.signalNumber);
  }, testOn: '!windows');
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/app_process_test.dart`
Expected: FAIL: `Type 'AppProcess' not found`

- [ ] **Step 3: Implement `AppProcess`**

Файл `packages/dartnest_cli/lib/src/dev/app_process.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The user's application, running in a child Dart VM with the VM service
/// on an ephemeral loopback port.
///
/// The child is one process (no development service), so [pid] is the
/// application's own `pid`. Its stdout and stderr are forwarded line by
/// line, except the VM service banner, which gives [serviceUri].
final class AppProcess {
  AppProcess._(this._process, this.serviceUri, this.exitCode);

  /// The flags of the child VM: the VM service on an ephemeral port of
  /// 127.0.0.1 with an authentication code in its URI, and no development
  /// service (DDS), which would run as a separate process.
  static const vmFlags = ['--enable-vm-service=0', '--no-dds'];

  static final _banner = RegExp(
    r'^The Dart VM service is listening on (http://\S+)$',
  );

  /// Starts `dart <vmFlags> <target> <arguments>` in [workingDirectory],
  /// forwarding the child's stdout lines to [out] and stderr lines to
  /// [err].
  static Future<AppProcess> start({
    required String target,
    required List<String> arguments,
    required String workingDirectory,
    required StringSink out,
    required StringSink err,
  }) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      ...vmFlags,
      target,
      ...arguments,
    ], workingDirectory: workingDirectory);
    final serviceUri = Completer<Uri?>();
    final stdoutDone = _lines(process.stdout).listen((line) {
      final banner = serviceUri.isCompleted ? null : _banner.firstMatch(line);
      if (banner == null) {
        out.writeln(line);
      } else {
        serviceUri.complete(Uri.parse(banner[1] ?? ''));
      }
    }).asFuture<void>();
    final stderrDone = _lines(
      process.stderr,
    ).listen(err.writeln).asFuture<void>();
    final exitCode = Future.wait([stdoutDone, stderrDone]).then((_) async {
      if (!serviceUri.isCompleted) serviceUri.complete(null);
      return process.exitCode;
    });
    return AppProcess._(process, serviceUri.future, exitCode);
  }

  final Process _process;

  /// The URI of the child's VM service; `null` when the child exited
  /// without starting it.
  final Future<Uri?> serviceUri;

  /// The child's exit code, completed after its last output line was
  /// forwarded.
  final Future<int> exitCode;

  /// The process id of the child, the application's `pid`.
  int get pid => _process.pid;

  /// Ends the child and completes with its exit code: sends it `SIGTERM`
  /// (on Windows the process is terminated at once) and, when it is still
  /// running after [killGrace], `SIGKILL`.
  Future<int> stop({Duration killGrace = const Duration(seconds: 2)}) {
    _process.kill();
    return exitCode.timeout(
      killGrace,
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return exitCode;
      },
    );
  }

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
}
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/app_process_test.dart`
Expected: `+5: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+76: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/lib/src/dev/app_process.dart \
  packages/dartnest_cli/test/app_process_test.dart
git commit -m "feat(cli): AppProcess runs the application with the VM service"
```

### Task 7: `ReloadClient` і `vm_service`

OP2, OP4, OP5. `connect` відкриває WebSocket до `<serviceUri>ws` (`null`, якщо VM service недоступний). `reload()` викликає `reloadSources` для першого ізоляту й класифікує `ReloadReport`: успіх → `Reloaded(libraries: loadedLibraryCount)` і reassemble; повідомлення типу `ReasonForCancellingReload` (обмеження VM, наприклад зміна type parameters) → `ReloadRejected(reason)` — `DevSession` перезапустить; інше (помилка компіляції, `ReasonForCancelling` з текстом компілятора) → `ReloadFailed(message)`. Reassemble шукає ізолят, у `extensionRPCs` якого є `ext.dartnest.reassemble`; немає (застосунок без dartnest) → `changedRoutes: null`; `RPCError` extension → `reassembleError` з `details` (текст помилки з ядра). `closeApplications` — `ext.dartnest.close` з таймаутом 5 с; збої (`RPCError`, `SentinelException`, `TimeoutException`) ковтаються, бо далі йде SIGTERM.

Тут з'являється тестовий застосунок `hello` (`DevSources`): `bin/main.dart` слухає `127.0.0.1` на порту з першого аргументу (без нього — ефемерному) і друкує `listening on <port>`; `GET /hello` відповідає `{"text": "hello v1", "pid": <pid>}`. `HelloApp.create` кладе його в `TempPackage` і генерує одним прогоном `GenerationSession`.

**Files:**
- Modify: `packages/dartnest_cli/pubspec.yaml`
- Create: `packages/dartnest_cli/lib/src/dev/reload_result.dart`
- Create: `packages/dartnest_cli/lib/src/dev/reload_client.dart`
- Test: `packages/dartnest_cli/test/helpers/dev_sources.dart`
- Test: `packages/dartnest_cli/test/helpers/hello_app.dart`
- Test: `packages/dartnest_cli/test/reload_client_test.dart`

**Interfaces:**
- Consumes: `AppProcess` (Task 6), extension ядра (Task 4: імена, JSON відповіді, `errorDetail`), `GenerationSession`, `TempPackage`, `LineSink` (етап 5); `package:vm_service` (`vmServiceConnectUri`, `VmService.getVM`/`getIsolate`/`reloadSources`/`callServiceExtension`/`dispose`, `ReloadReport`, `RPCError`, `SentinelException`).
- Produces:
  - `sealed class ReloadResult` з `Reloaded({required int libraries, required Duration elapsed, int? changedRoutes, String? reassembleError})`, `ReloadFailed(String message)`, `ReloadRejected(String reason)`.
  - `final class ReloadClient`: `static Future<ReloadClient?> connect(Uri serviceUri)`, `Future<ReloadResult> reload()`, `Future<void> closeApplications({Duration timeout = const Duration(seconds: 5)})`, `Future<void> dispose()`, константи `reassembleMethod`, `closeMethod`.
  - Тестові `DevSources.main/greeter/controller/module/files`, `HelloApp.create()`, `HelloApp.package`, `edit(relative, from, to)`, `static int? portIn(String line)`, `static Future<Object?> get(int port, String path)` (JSON або код статусу).

- [ ] **Step 1: Add the dependency**

Повний `packages/dartnest_cli/pubspec.yaml` (новий рядок — `vm_service`):

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
  vm_service: ^15.2.0
  watcher: ^1.2.1
  yaml: ^3.1.3
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

Run: `dart pub get`
Expected: `Got dependencies!`

- [ ] **Step 2: Write the test application and the failing test**

Файл `packages/dartnest_cli/test/helpers/dev_sources.dart`:

```dart
/// Sources of a small annotated application `hello` with a `bin/main.dart`
/// that serves it on a loopback port (its first argument, an ephemeral
/// port without one) and prints
/// `listening on <port>`; `GET /hello` answers the greeting and the pid.
abstract final class DevSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:hello/hello.dartnest.dart';

Future<void> main(List<String> arguments) async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  final port = arguments.isEmpty ? 0 : int.parse(arguments.first);
  await app.listen(port: port, address: InternetAddress.loopbackIPv4);
  print('listening on \${adapter.port}');
}
''';

  /// `lib/src/greeter.dart`.
  static const greeter = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Greeter {
  String greet() => 'hello v1';
}
''';

  /// `lib/src/hello_controller.dart`.
  static const controller = '''
import 'dart:io';

import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'greeter.dart';

@Controller('/hello')
final class HelloController {
  HelloController(this.greeter);

  final Greeter greeter;

  @Get()
  Map<String, Object> hello() => {'text': greeter.greet(), 'pid': pid};
}
''';

  /// `lib/src/app_module.dart`.
  static const module = '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'greeter.dart';
import 'hello_controller.dart';

@Module(id: 'app', providers: [Greeter], controllers: [HelloController])
final class AppModule {}
''';

  /// The files of the application.
  static const files = {
    'bin/main.dart': main,
    'lib/src/greeter.dart': greeter,
    'lib/src/hello_controller.dart': controller,
    'lib/src/app_module.dart': module,
  };
}
```

Файл `packages/dartnest_cli/test/helpers/hello_app.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';

import 'dev_sources.dart';
import 'temp_package.dart';

/// The generated `hello` application ([DevSources]) in a [TempPackage].
final class HelloApp {
  HelloApp._(this.package);

  /// Creates the package and generates its library.
  static Future<HelloApp> create() async {
    final package = await TempPackage.create('hello', DevSources.files);
    final session = GenerationSession(package.root);
    try {
      final report = await session.run();
      if (report.hasProblems) throw StateError('${report.problemLines}');
    } finally {
      await session.close();
    }
    return HelloApp._(package);
  }

  /// The package.
  final TempPackage package;

  /// Replaces [from] by [to] in the package file [relative].
  void edit(String relative, String from, String to) {
    final source = package.dir.read(relative);
    if (!source.contains(from)) throw StateError('No "$from" in $relative.');
    package.dir.write(relative, source.replaceFirst(from, to));
  }

  /// The port in a `listening on <port>` line, or `null`.
  static int? portIn(String line) => switch (line.split(' ')) {
    ['listening', 'on', final port] => int.tryParse(port),
    _ => null,
  };

  /// The JSON answer of `GET <path>` on 127.0.0.1:[port], or the status
  /// code when it is not 200.
  static Future<Object?> get(int port, String path) async {
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, path);
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      return response.statusCode == 200
          ? jsonDecode(body)
          : response.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}
```

Файл `packages/dartnest_cli/test/reload_client_test.dart`:

```dart
import 'package:dartnest_cli/src/dev/app_process.dart';
import 'package:dartnest_cli/src/dev/reload_client.dart';
import 'package:dartnest_cli/src/dev/reload_result.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:test/test.dart';

import 'helpers/hello_app.dart';
import 'helpers/line_sink.dart';

/// The running `hello` application with a connected [ReloadClient].
final class Running {
  Running._(this.app, this.process, this.client, this.port, this.err);

  /// Starts the application and waits until it listens.
  static Future<Running> start() async {
    final app = await HelloApp.create();
    final out = LineSink();
    final err = LineSink();
    final process = await AppProcess.start(
      target: 'bin/main.dart',
      arguments: const [],
      workingDirectory: app.package.dir.path,
      out: out,
      err: err,
    );
    addTearDown(() => process.stop(killGrace: Duration.zero));
    final uri = await process.serviceUri;
    final client = uri == null ? null : await ReloadClient.connect(uri);
    if (client == null) throw StateError('No VM service: ${err.lines}');
    addTearDown(client.dispose);
    final port = HelloApp.portIn(await out.next());
    if (port == null) throw StateError('Not listening: ${out.lines}');
    return Running._(app, process, client, port, err);
  }

  final HelloApp app;
  final AppProcess process;
  final ReloadClient client;
  final int port;
  final LineSink err;

  /// Generates the package again, as `dev` does before a reload.
  Future<void> regenerate() async {
    final session = GenerationSession(app.package.root);
    try {
      await session.run();
    } finally {
      await session.close();
    }
  }
}

void main() {
  test('a changed method body is reloaded and reassembled', () async {
    final running = await Running.start();
    running.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');

    final result = await running.client.reload();

    expect(result, isA<Reloaded>());
    final reloaded = result as Reloaded;
    expect(reloaded.libraries, greaterThan(0));
    expect(reloaded.changedRoutes, 0);
    expect(reloaded.reassembleError, isNull);
    expect(await HelloApp.get(running.port, '/hello'), {
      'text': 'hello v2',
      'pid': running.process.pid,
    });
  });

  test('a compile error fails the reload and keeps the old code', () async {
    final running = await Running.start();
    running.app.edit('lib/src/greeter.dart', "'hello v1'", "'hello v1' +");

    final result = await running.client.reload();

    expect(result, isA<ReloadFailed>());
    expect((result as ReloadFailed).message, contains('Error:'));
    expect(
      await HelloApp.get(running.port, '/hello'),
      containsPair('text', 'hello v1'),
    );
  });

  test('a change hot reload cannot apply is rejected', () async {
    final running = await Running.start();
    running.app.edit(
      'lib/src/greeter.dart',
      'class Greeter {',
      'class Greeter<T> {',
    );

    final result = await running.client.reload();

    expect(result, isA<ReloadRejected>());
    expect((result as ReloadRejected).reason, contains('type parameters'));
  });

  test('a failing reassemble is reported and the old state serves', () async {
    final running = await Running.start();
    running.app.package.dir.write('lib/src/broken.dart', '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Broken {
  Broken() {
    throw StateError('broken provider');
  }
}
''');
    running.app.edit(
      'lib/src/app_module.dart',
      '[Greeter]',
      '[Greeter, Broken]',
    );
    running.app.edit(
      'lib/src/app_module.dart',
      "import 'greeter.dart';",
      "import 'broken.dart';\nimport 'greeter.dart';",
    );
    await running.regenerate();

    final result = await running.client.reload();

    expect(result, isA<Reloaded>());
    expect((result as Reloaded).reassembleError, contains('broken provider'));
    expect(
      await HelloApp.get(running.port, '/hello'),
      containsPair('text', 'hello v1'),
    );
  });

  test('closing the applications lets the process exit', () async {
    final running = await Running.start();

    await running.client.closeApplications();

    expect(await running.process.exitCode, 0);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/reload_client_test.dart`
Expected: FAIL: `Error when reading 'lib/src/dev/reload_client.dart'`

- [ ] **Step 4: Implement `ReloadResult` and `ReloadClient`**

Файл `packages/dartnest_cli/lib/src/dev/reload_result.dart`:

```dart
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
    this.changedRoutes,
    this.reassembleError,
  });

  /// How many libraries the VM loaded.
  final int libraries;

  /// How long the reload and the reassemble took.
  final Duration elapsed;

  /// How many routes were added or removed; `null` when no dartnest
  /// application was reassembled.
  final int? changedRoutes;

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

Файл `packages/dartnest_cli/lib/src/dev/reload_client.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'reload_result.dart';

/// Drives the application process through its VM service: hot reload
/// followed by the `ext.dartnest.reassemble` extension, and the
/// `ext.dartnest.close` extension before a restart.
final class ReloadClient {
  ReloadClient._(this._service);

  /// The extension `Application` registers to reassemble after a reload.
  static const reassembleMethod = 'ext.dartnest.reassemble';

  /// The extension `Application` registers to close before a restart.
  static const closeMethod = 'ext.dartnest.close';

  final VmService _service;

  /// Connects to the VM service at [serviceUri] (the `http://` URI the
  /// child printed); `null` when the child is already gone.
  static Future<ReloadClient?> connect(Uri serviceUri) async {
    final webSocket = serviceUri.resolve('ws').replace(scheme: 'ws');
    try {
      return ReloadClient._(await vmServiceConnectUri('$webSocket'));
    } on SocketException {
      return null;
    } on WebSocketException {
      return null;
    }
  }

  /// Reloads the changed sources of the process, then reassembles its
  /// dartnest applications.
  Future<ReloadResult> reload() async {
    final stopwatch = Stopwatch()..start();
    try {
      final isolates = await _isolateIds();
      if (isolates.isEmpty) return const ReloadFailed('No isolate to reload.');
      final report = await _service.reloadSources(isolates.first);
      if (report.success != true) return _failure(report);
      final (changedRoutes, error) = await _reassemble(isolates);
      return Reloaded(
        libraries: _loadedLibraries(report),
        elapsed: stopwatch.elapsed,
        changedRoutes: changedRoutes,
        reassembleError: error,
      );
    } on RPCError catch (error) {
      return ReloadFailed('The VM service failed: ${error.message}.');
    } on SentinelException catch (error) {
      return ReloadFailed('The VM service failed: $error.');
    }
  }

  /// Closes the dartnest applications of the process (they finish their
  /// requests in flight), waiting up to [timeout]; any failure is left to
  /// the restart, which ends the process anyway.
  Future<void> closeApplications({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final isolate = await _isolateWith(closeMethod, await _isolateIds());
      if (isolate == null) return;
      await _service
          .callServiceExtension(closeMethod, isolateId: isolate)
          .timeout(timeout);
    } on RPCError {
      return;
    } on SentinelException {
      return;
    } on TimeoutException {
      return;
    }
  }

  /// Closes the connection.
  Future<void> dispose() => _service.dispose();

  Future<List<String>> _isolateIds() async => [
    for (final isolate in (await _service.getVM()).isolates ?? <IsolateRef>[])
      if (isolate.id case final id?) id,
  ];

  Future<String?> _isolateWith(String method, List<String> isolates) async {
    for (final id in isolates) {
      final isolate = await _service.getIsolate(id);
      if (isolate.extensionRPCs?.contains(method) ?? false) return id;
    }
    return null;
  }

  /// The changed routes, or the error, of the reassemble; `(null, null)`
  /// when no isolate has a dartnest application.
  Future<(int?, String?)> _reassemble(List<String> isolates) async {
    final isolate = await _isolateWith(reassembleMethod, isolates);
    if (isolate == null) return (null, null);
    try {
      final response = await _service.callServiceExtension(
        reassembleMethod,
        isolateId: isolate,
      );
      return switch (response.json) {
        {
          'addedRoutes': final List<Object?> added,
          'removedRoutes': final List<Object?> removed,
        } =>
          (added.length + removed.length, null),
        _ => (0, null),
      };
    } on RPCError catch (error) {
      return (null, error.details ?? error.message);
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

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/reload_client_test.dart`
Expected: `+5: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+81: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest_cli/pubspec.yaml \
  packages/dartnest_cli/lib/src/dev/reload_result.dart \
  packages/dartnest_cli/lib/src/dev/reload_client.dart \
  packages/dartnest_cli/test/helpers/dev_sources.dart \
  packages/dartnest_cli/test/helpers/hello_app.dart \
  packages/dartnest_cli/test/reload_client_test.dart
git commit -m "feat(cli): ReloadClient reloads and reassembles through the VM service"
```

### Task 8: `WatchLoop.custom(watched:, afterRun:)` і `MergedWatcher`

Рішення 5. `WatchLoop.custom` отримує `watched` (що друкувати в `Watching ... for changes`, замість обчислення з сесії) і необов'язковий `afterRun(changed, report)`, який цикл чекає після друку кожного прогону, тож наступний прогін не почнеться, поки `dev` не закінчив reload (Review Focus 4, 8). Прогін, що впав з `CliFailure` (вихід не записався), `afterRun` не викликає. Звичайний конструктор поводиться як раніше. `MergedWatcher` — один `Watcher` над кількома (`lib/` і `bin/`); `events` при кожному читанні — новий single-subscription потік, як у `package:watcher`.

**Files:**
- Modify: `packages/dartnest_cli/lib/src/watch/watch_loop.dart`
- Create: `packages/dartnest_cli/lib/src/dev/merged_watcher.dart`
- Test: `packages/dartnest_cli/test/watch_loop_runs_test.dart`
- Test: `packages/dartnest_cli/test/merged_watcher_test.dart`

**Interfaces:**
- Consumes: `WatchLoop`, `GenerationReport`, `ReportPrinter`, `CliFailure`, `FakeWatcher` (етап 5); `package:watcher` (`Watcher`, `WatchEvent`).
- Produces:
  - `WatchLoop.custom({required Future<GenerationReport> Function(List<String> changed) generate, required String watched, required ReportPrinter printer, Future<void> Function(List<String> changed, GenerationReport report)? afterRun, Duration debounce = defaultDebounce})`; поля `watched`, `afterRun`.
  - `final class MergedWatcher implements Watcher`: `MergedWatcher(String path, List<Watcher> watchers)`.

- [ ] **Step 1: Write the failing tests**

Тестова обв'язка `watch_loop_runs_test.dart` передає `watched: 'lib'` і `afterRun`, що записує `'<changed> after <останній надрукований рядок>'`; два нові тести внизу. Повний файл:

Файл `packages/dartnest_cli/test/watch_loop_runs_test.dart`:

```dart
import 'dart:async';

import 'package:dartnest_cli/src/cli/cli_exit_code.dart';
import 'package:dartnest_cli/src/cli/cli_failure.dart';
import 'package:dartnest_cli/src/cli/report_printer.dart';
import 'package:dartnest_cli/src/generate/generation_report.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:dartnest_cli/src/watch/watch_loop.dart';
import 'package:test/test.dart';

import 'helpers/fake_watcher.dart';
import 'helpers/line_sink.dart';

const _debounce = Duration(milliseconds: 20);
const _gap = Duration(milliseconds: 60);

final _report = GenerationReport(
  output: 'lib/x.dartnest.dart',
  outcome: WriteOutcome.written,
  elapsed: Duration.zero,
);

/// A loop whose runs the test releases one by one.
final class _Harness {
  _Harness() {
    loop = WatchLoop.custom(
      generate: _generate,
      watched: 'lib',
      printer: ReportPrinter(lines, lines),
      afterRun: _afterRun,
      debounce: _debounce,
    );
    stop = Completer<void>();
    addTearDown(() {
      if (!stop.isCompleted) stop.complete();
    });
  }

  final lines = LineSink();
  final watcher = FakeWatcher('/pkg/lib');
  final calls = <List<String>>[];
  final _gates = <Completer<void>>[];
  Object? failWith;
  // Both are set in the constructor body, before any method reads them.
  late final WatchLoop loop;
  late final Completer<void> stop;

  /// Every run waits for [release] when [blocking] is set.
  bool blocking = false;

  Future<GenerationReport> _generate(List<String> changed) async {
    calls.add(changed);
    if (blocking) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    final failure = failWith;
    if (failure != null) throw failure;
    return _report;
  }

  /// Each call of `afterRun`: the changed paths and the last line printed
  /// before it.
  final afterRuns = <String>[];

  Future<void> _afterRun(List<String> changed, GenerationReport report) async {
    afterRuns.add('${changed.join(',')} after ${lines.lines.last}');
  }

  Future<void> start() => loop.run(watcher, stop.future);

  Future<void> release() async {
    while (_gates.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    _gates.removeAt(0).complete();
  }

  Future<void> changed(String file) async {
    watcher.modify(file);
    await Future<void>.delayed(_gap);
  }
}

void main() {
  test('paths changed while a run is in flight share one follow-up', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;

    await h.changed('/pkg/lib/a.dart');
    await h.changed('/pkg/lib/c.dart');
    await h.changed('/pkg/lib/b.dart');
    await h.changed('/pkg/lib/c.dart');
    h.blocking = false;
    await h.release();
    expect(await h.lines.next(), startsWith('Generated'));
    expect(await h.lines.next(), startsWith('Generated'));

    expect(await h.lines.after(_gap), isEmpty);
    expect(h.calls, [
      <String>[],
      ['/pkg/lib/a.dart'],
      ['/pkg/lib/b.dart', '/pkg/lib/c.dart'],
    ]);
    h.stop.complete();
    await done;
  });

  test('afterRun follows the printed report of every run', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();

    await h.changed('/pkg/lib/a.dart');
    await h.lines.next();
    h.stop.complete();
    await done;

    expect(h.afterRuns, [
      ' after Generated lib/x.dartnest.dart in 0 ms.',
      '/pkg/lib/a.dart after Generated lib/x.dartnest.dart in 0 ms.',
    ]);
  });

  test('afterRun is not called for a run that failed to write', () async {
    final h = _Harness()
      ..failWith = const CliFailure(CliExitCode.cannotCreate, 'No write.');
    final done = h.start();

    expect(await h.lines.next(), 'No write.');
    h.stop.complete();
    await done;
    expect(h.afterRuns, isEmpty);
  });

  test('a failure of a run ends run() without waiting for stop', () async {
    final h = _Harness()..failWith = StateError('boom');

    await expectLater(h.start(), throwsA(isA<StateError>()));
  });

  test('stop waits for the run in flight', () async {
    final h = _Harness();
    final done = h.start();
    var finished = false;
    unawaited(done.then((_) => finished = true));
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;
    await h.changed('/pkg/lib/a.dart');

    h.stop.complete();
    await Future<void>.delayed(_gap);
    expect(finished, isFalse);

    await h.release();
    await done;
    expect(await h.lines.next(), startsWith('Generated'));
    expect(h.calls.length, 2);
  });

  test('stop drops a change that is still debouncing', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();

    h.watcher.modify('/pkg/lib/a.dart');
    h.stop.complete();
    await done;

    expect(await h.lines.after(_gap), isEmpty);
    expect(h.calls.length, 1);
  });

  test('a failure of a run after stop is still thrown', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.blocking = true;
    await h.changed('/pkg/lib/a.dart');

    h.stop.complete();
    h.failWith = StateError('late');
    await h.release();

    await expectLater(done, throwsA(isA<StateError>()));
  });

  test('a failure of an event-triggered run ends run()', () async {
    final h = _Harness();
    final done = h.start();
    await h.lines.next();
    await h.lines.next();
    h.failWith = StateError('boom');

    h.watcher.modify('/pkg/lib/a.dart');

    await expectLater(done, throwsA(isA<StateError>()));
  });
}
```

Файл `packages/dartnest_cli/test/merged_watcher_test.dart`:

```dart
import 'package:dartnest_cli/src/dev/merged_watcher.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import 'helpers/fake_watcher.dart';

void main() {
  test('delivers the events of every watcher', () async {
    final lib = FakeWatcher('/pkg/lib');
    final bin = FakeWatcher('/pkg/bin');
    final merged = MergedWatcher('/pkg', [lib, bin]);
    final events = <String>[];
    final subscription = merged.events.listen(
      (event) => events.add(event.path),
    );
    await merged.ready;

    lib.modify('/pkg/lib/a.dart');
    bin.modify('/pkg/bin/main.dart');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(events, ['/pkg/lib/a.dart', '/pkg/bin/main.dart']);
    expect(merged.isReady, isTrue);
  });

  test('cancelling stops listening to every watcher', () async {
    final lib = FakeWatcher('/pkg/lib');
    final merged = MergedWatcher('/pkg', <Watcher>[lib]);
    final events = <WatchEvent>[];
    final subscription = merged.events.listen(events.add);

    await subscription.cancel();
    lib.modify('/pkg/lib/a.dart');
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/dartnest_cli && dart test test/watch_loop_runs_test.dart test/merged_watcher_test.dart`
Expected: FAIL: `No named parameter with the name 'watched'`

- [ ] **Step 3: Implement**

Файл `packages/dartnest_cli/lib/src/watch/watch_loop.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../cli/cli_failure.dart';
import '../cli/report_printer.dart';
import '../generate/generation_report.dart';
import '../generate/generation_session.dart';

/// Regenerates a package whenever its `lib/` changes, until stopped.
///
/// Events are debounced: a burst (an editor saving through a temporary
/// file, a branch switch) gives one run with every changed path. Runs never
/// overlap; paths that change during a run are collected into exactly one
/// follow-up run. Generated `*.dartnest.dart` files (the session's own
/// output) and non-Dart files are ignored. A [CliFailure] of a run is
/// printed and watching goes on; any other failure of a run ends [run] with
/// it at once. Errors of the watcher's event stream are not handled and end
/// the process (OP8).
final class WatchLoop {
  /// Creates the loop over [session], printing through [printer].
  WatchLoop(
    GenerationSession session,
    ReportPrinter printer, {
    Duration debounce = defaultDebounce,
  }) : this.custom(
         generate: (changed) => session.run(changed: changed),
         watched: session.package.display(session.package.libPath),
         printer: printer,
         debounce: debounce,
       );

  /// Creates the loop over any [generate] (the run of a session), printing
  /// [watched] as the watched directories and calling [afterRun] after
  /// each printed run; for `dev` and for tests that control the runs.
  WatchLoop.custom({
    required this.generate,
    required this.watched,
    required this.printer,
    this.afterRun,
    this.debounce = defaultDebounce,
  });

  /// How long the loop waits after the last event before it runs.
  static const defaultDebounce = Duration(milliseconds: 100);

  /// Runs the generation for the changed absolute paths.
  final Future<GenerationReport> Function(List<String> changed) generate;

  /// The watched directories as printed after the first run, without the
  /// trailing `/` (`lib`).
  final String watched;

  /// Called with the changed paths and the report of every run, after the
  /// report is printed and before the next run starts; not called when a
  /// run fails with a [CliFailure]. A failure ends [run] like a failure of
  /// [generate].
  final Future<void> Function(List<String> changed, GenerationReport report)?
  afterRun;

  /// Prints every run.
  final ReportPrinter printer;

  /// The quiet time after the last event that starts a run.
  final Duration debounce;

  final _pending = SplayTreeSet<String>();
  final _failure = Completer<void>();
  Timer? _timer;
  Future<void>? _active;
  var _stopped = false;

  /// Generates once, then once per batch of [watcher] events, until [stop]
  /// completes; returns when the run in flight has finished.
  ///
  /// Completes with the error of a run that failed with anything but a
  /// [CliFailure], without waiting for [stop]. Changes still waiting for
  /// their debounce or their turn when [stop] completes are dropped.
  Future<void> run(Watcher watcher, Future<void> stop) async {
    final subscription = watcher.events.where(_isSource).listen(_add);
    try {
      await watcher.ready;
      _start(() => _first(watcher));
      await Future.any([stop, _failure.future]);
    } finally {
      _stopped = true;
      _timer?.cancel();
      await subscription.cancel();
      await _active;
    }
    if (_failure.isCompleted) await _failure.future;
  }

  void _add(WatchEvent event) {
    _pending.add(p.normalize(p.absolute(event.path)));
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    if (_active == null) _start(_drain);
  }

  void _start(Future<void> Function() work) {
    _active = work().then<void>(
      (_) => _active = null,
      onError: (Object error, StackTrace trace) {
        _active = null;
        if (!_failure.isCompleted) _failure.completeError(error, trace);
      },
    );
  }

  Future<void> _first(Watcher watcher) async {
    await _generate(const []);
    printer.watching(watched);
    await _drain();
  }

  Future<void> _drain() async {
    while (!_stopped && _pending.isNotEmpty) {
      final changed = _pending.toList();
      _pending.clear();
      await _generate(changed);
    }
  }

  Future<void> _generate(List<String> changed) async {
    final GenerationReport report;
    try {
      report = await generate(changed);
    } on CliFailure catch (failure) {
      printer.err.writeln(failure.message);
      return;
    }
    printer.report(report);
    await afterRun?.call(changed, report);
  }

  static bool _isSource(WatchEvent event) =>
      event.path.endsWith('.dart') && !event.path.endsWith('.dartnest.dart');
}
```

Файл `packages/dartnest_cli/lib/src/dev/merged_watcher.dart`:

```dart
import 'dart:async';

import 'package:watcher/watcher.dart';

/// One [Watcher] over the directories of several watchers: `dev` watches
/// `lib/` and the directory of its entry point.
final class MergedWatcher implements Watcher {
  /// Merges [watchers]; [path] is the directory they belong to (the
  /// package root).
  MergedWatcher(this.path, this.watchers);

  @override
  final String path;

  /// The merged watchers.
  final List<Watcher> watchers;

  /// The events of every watcher. Each read gives a new single-subscription
  /// stream; listening to it starts the watchers, cancelling it stops them.
  @override
  Stream<WatchEvent> get events {
    final subscriptions = <StreamSubscription<WatchEvent>>[];
    final controller = StreamController<WatchEvent>();
    controller
      ..onListen = () {
        for (final watcher in watchers) {
          subscriptions.add(
            watcher.events.listen(controller.add, onError: controller.addError),
          );
        }
      }
      ..onCancel = () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]);
    return controller.stream;
  }

  @override
  bool get isReady => watchers.every((watcher) => watcher.isReady);

  @override
  Future<void> get ready =>
      Future.wait([for (final watcher in watchers) watcher.ready]);
}
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/watch_loop_runs_test.dart test/merged_watcher_test.dart`
Expected: `+10: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+85: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_cli/lib/src/watch/watch_loop.dart \
  packages/dartnest_cli/lib/src/dev/merged_watcher.dart \
  packages/dartnest_cli/test/watch_loop_runs_test.dart \
  packages/dartnest_cli/test/merged_watcher_test.dart
git commit -m "refactor(cli): WatchLoop takes a watched label and an afterRun hook; MergedWatcher"
```

### Task 9: `DevPrinter` і `DevSession`

Рішення 5–7, OP5, OP7, OP11. `DevSession` — уся логіка «що робити з прогоном»: проблеми → `waiting`; не запущено → запуск; зміна форми (`ShapeTracker`, база — на кожному запуску, по `lib/` і теці точки входу) → restart з причиною `<file> changed a field, a constructor or a top-level variable`; інакше reload, а для `ReloadRejected` — restart. Restart = `closeApplications` → `stop` → `dispose` → запуск; новий процес стартує лише після виходу старого (Review Focus 6). Застосунок, що завершився сам, друкує `exited` і не перезапускається (Review Focus 5). `DevPrinter` — рядки Рішення 7: стан застосунку — у `out`, збої — у `err`. Тести `DevSession` запускають справжній `hello` (Task 7) і живлять сесію справжньою `GenerationSession`, як це робитиме `dev`.

**Files:**
- Create: `packages/dartnest_cli/lib/src/dev/dev_printer.dart`
- Create: `packages/dartnest_cli/lib/src/dev/dev_session.dart`
- Modify: `packages/dartnest_cli/test/helpers/line_sink.dart`
- Test: `packages/dartnest_cli/test/dev_printer_test.dart`
- Test: `packages/dartnest_cli/test/dev_session_test.dart`

**Interfaces:**
- Consumes: `ShapeTracker` (Task 5), `AppProcess` (Task 6), `ReloadClient`, `ReloadResult`, `HelloApp`, `DevSources` (Task 7), `PackageRoot`, `GenerationReport`, `WriteOutcome`, `GenerationSession`, `LineSink` (етап 5).
- Produces:
  - `final class DevPrinter`: `DevPrinter(String target, StringSink out, StringSink err)`, `started(int pid, Uri serviceUri)`, `restarting(String reason)`, `exited(int code)`, `waiting({required bool isRunning})`, `reloaded(ReloadResult result)`.
  - `final class DevSession`: `DevSession(PackageRoot package, {required String target, required List<String> arguments, required DevPrinter printer, required StringSink out})` (`target` — абсолютний; stderr застосунку — `printer.err`), `Future<void> apply(List<String> changed, GenerationReport report)`, `reload()`, `restart()`, `stop()`.
  - `LineSink.nextWhere(bool Function(String line) test, {Duration timeout})`.

- [ ] **Step 1: Write the failing tests**

`LineSink` отримує `nextWhere` (повний файл):

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

  /// The next line not returned before that satisfies [test], skipping
  /// the lines before it, waiting up to [timeout] in all.
  Future<String> nextWhere(
    bool Function(String line) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final line = await next(timeout: timeout - stopwatch.elapsed);
      if (test(line)) return line;
    }
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

Файл `packages/dartnest_cli/test/dev_printer_test.dart`:

```dart
import 'package:dartnest_cli/src/dev/dev_printer.dart';
import 'package:dartnest_cli/src/dev/reload_result.dart';
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
  test('a reload with a reassemble prints one line with the routes', () {
    expect(
      printed(
        (printer) => printer.reloaded(
          const Reloaded(libraries: 3, elapsed: _elapsed, changedRoutes: 2),
        ),
      ),
      ('Reloaded 3 libraries in 180 ms, 2 routes changed.\n', ''),
    );
  });

  test('a reload without a dartnest application has no route count', () {
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
      'reassembled; it keeps its previous modules and routes.\n',
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
}
```

Файл `packages/dartnest_cli/test/dev_session_test.dart`:

```dart
import 'dart:io';

import 'package:dartnest_cli/src/dev/dev_printer.dart';
import 'package:dartnest_cli/src/dev/dev_session.dart';
import 'package:dartnest_cli/src/generate/generation_session.dart';
import 'package:test/test.dart';

import 'helpers/hello_app.dart';
import 'helpers/line_sink.dart';

/// A [DevSession] of the `hello` application, fed by a real
/// [GenerationSession] as `dev` feeds it; the application's output and
/// what the session prints go to [lines].
final class Dev {
  Dev._(this.app, this.lines, this.generation, this.session);

  /// Creates the application and starts it through the first run.
  static Future<Dev> start() async {
    final app = await HelloApp.create();
    final lines = LineSink();
    final generation = GenerationSession(app.package.root);
    addTearDown(generation.close);
    final session = DevSession(
      app.package.root,
      target: app.package.dir.resolve('bin/main.dart'),
      arguments: const [],
      printer: DevPrinter('bin/main.dart', lines, lines),
      out: lines,
    );
    addTearDown(session.stop);
    final dev = Dev._(app, lines, generation, session);
    await dev.change(const []);
    return dev;
  }

  final HelloApp app;
  final LineSink lines;
  final GenerationSession generation;
  final DevSession session;

  /// Generates after a change of the package files [relative] and applies
  /// the run, as the watch loop of `dev` does.
  Future<void> change(List<String> relative) async {
    final changed = [
      for (final path in relative) app.package.dir.resolve(path),
    ];
    final report = await generation.run(changed: changed);
    await session.apply(changed, report);
  }

  /// Waits for the next `listening on <port>` line of the application.
  Future<int> listening() async {
    final line = await lines.nextWhere((line) => HelloApp.portIn(line) != null);
    return HelloApp.portIn(line) ?? 0;
  }

  /// The answer of `GET /hello` on [port].
  static Future<Map<String, Object?>> hello(int port) async =>
      await HelloApp.get(port, '/hello') as Map<String, Object?>;
}

void main() {
  test('a body change is reloaded in the same process', () async {
    final dev = await Dev.start();
    final port = await dev.listening();
    final before = await Dev.hello(port);

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await dev.change(['lib/src/greeter.dart']);

    expect(dev.lines.lines.last, startsWith('Reloaded '));
    final after = await Dev.hello(port);
    expect(after, {'text': 'hello v2', 'pid': before['pid']});
  });

  test('a new field restarts the application in a new process', () async {
    // Review Focus 9: the old instances would keep a field they never
    // initialized; a restart builds them again.
    final dev = await Dev.start();
    final before = await Dev.hello(await dev.listening());

    dev.app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n  String greet',
    );
    await dev.change(['lib/src/greeter.dart']);

    expect(
      dev.lines.lines,
      contains(
        'Restarting bin/main.dart: lib/src/greeter.dart changed a field, '
        'a constructor or a top-level variable.',
      ),
    );
    final after = await Dev.hello(await dev.listening());
    expect(after['pid'], isNot(before['pid']));
  });

  test('sources with problems keep the previous code running', () async {
    // Review Focus 3: a half-typed edit must not reach the application.
    final dev = await Dev.start();
    final port = await dev.listening();

    dev.app.edit('lib/src/greeter.dart', "'hello v1';", "'hello v2'");
    await dev.change(['lib/src/greeter.dart']);

    expect(
      dev.lines.lines.last,
      'bin/main.dart keeps running the previous code.',
    );
    expect((await Dev.hello(port))['text'], 'hello v1');

    dev.app.edit('lib/src/greeter.dart', "'hello v2'", "'hello v2';");
    await dev.change(['lib/src/greeter.dart']);
    expect((await Dev.hello(port))['text'], 'hello v2');
  });

  test('runs that arrive together are applied one after another', () async {
    // Review Focus 4: a storm of changes must not overlap two reloads.
    final dev = await Dev.start();
    final port = await dev.listening();
    final before = await Dev.hello(port);
    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    final changed = [dev.app.package.dir.resolve('lib/src/greeter.dart')];
    final report = await dev.generation.run(changed: changed);

    await Future.wait([
      for (var run = 0; run < 3; run++) dev.session.apply(changed, report),
    ]);

    final reloads = dev.lines.lines.where(
      (line) => line.startsWith('Reloaded'),
    );
    expect(reloads, hasLength(3));
    expect(await Dev.hello(port), {'text': 'hello v2', 'pid': before['pid']});
  });

  test('an application that exits starts again only after a change', () async {
    // Review Focus 5: a crashing application must not restart in a loop.
    final dev = await Dev.start();
    final pid = (await Dev.hello(await dev.listening()))['pid'] as int;

    Process.killPid(pid, ProcessSignal.sigkill);
    await dev.lines.nextWhere((line) => line.contains('exited with code'));
    expect(
      await dev.lines.after(const Duration(milliseconds: 500)),
      isNot(contains(startsWith('Started '))),
    );

    await dev.change(['lib/src/greeter.dart']);
    final again = await Dev.hello(await dev.listening());
    expect(again['pid'], isNot(pid));
  });

  test('stop ends the application and frees its port', () async {
    // Review Focus 1: no application process outlives dev.
    final dev = await Dev.start();
    final port = await dev.listening();

    await dev.session.stop();

    await expectLater(Dev.hello(port), throwsA(isA<SocketException>()));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/dartnest_cli && dart test test/dev_printer_test.dart test/dev_session_test.dart`
Expected: FAIL: `Type 'DevPrinter' not found`

- [ ] **Step 3: Implement `DevPrinter`**

Файл `packages/dartnest_cli/lib/src/dev/dev_printer.dart`:

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
            'reassembled; it keeps its previous modules and routes.',
          );
      case Reloaded(changedRoutes: final routes?):
        out.writeln('${_summary(result)}, ${_count(routes, 'route')} changed.');
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

- [ ] **Step 4: Implement `DevSession`**

Файл `packages/dartnest_cli/lib/src/dev/dev_session.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../generate/generation_report.dart';
import '../generate/write_outcome.dart';
import '../package/package_root.dart';
import 'app_process.dart';
import 'dev_printer.dart';
import 'reload_client.dart';
import 'reload_result.dart';
import 'shape_tracker.dart';

/// Runs the application of a package for `dev` and applies every
/// generation run to it: a hot reload when the change allows it, a hot
/// restart when it does not, nothing while the sources have problems.
///
/// The application never restarts on its own: when it exits, it starts
/// again after the next change. Operations run one at a time, in the order
/// they were asked for.
final class DevSession {
  /// Creates the session for [target] (absolute) of [package], started
  /// with [arguments], printing through [printer] and forwarding the
  /// application's output to [out] and [err].
  DevSession(
    this.package, {
    required this.target,
    required this.arguments,
    required this.printer,
    required this.out,
  }) : err = printer.err;

  /// The package of the application.
  final PackageRoot package;

  /// The absolute path of the entry point.
  final String target;

  /// The arguments of the application's `main`.
  final List<String> arguments;

  /// Prints what happens to the application.
  final DevPrinter printer;

  /// Where the application's stdout goes.
  final StringSink out;

  /// Where the application's stderr goes.
  final StringSink err;

  final _shapes = ShapeTracker();
  Future<void> _tail = Future<void>.value();
  _Running? _running;

  /// Applies the generation run [report] for the [changed] paths: starts
  /// the application when it is not running, restarts it when a file
  /// changed its shape (see [ShapeTracker]), reloads it otherwise.
  Future<void> apply(List<String> changed, GenerationReport report) =>
      _serially(() => _apply(changed, report));

  /// Reloads the application now (the `r` key); starts it when it is not
  /// running.
  Future<void> reload() => _serially(() async {
    final running = _running;
    if (running == null) return _launch();
    await _reload(running);
  });

  /// Restarts the application now (the `R` key).
  Future<void> restart() => _serially(() => _restart('restart requested'));

  /// Stops the application: its dartnest applications close (requests in
  /// flight finish), then the process ends.
  Future<void> stop() => _serially(_shutdown);

  // Every operation runs after the previous one, also after one that
  // failed: its failure went to its own caller, and stop() must still end
  // the process.
  Future<void> _serially(Future<void> Function() operation) => _tail = _tail
      .then((_) => operation(), onError: (Object _) => operation());

  Future<void> _apply(List<String> changed, GenerationReport report) async {
    final running = _running;
    if (report.hasProblems) {
      printer.waiting(isRunning: running != null);
      return;
    }
    final reshaped = _shapes.changed([
      ...changed,
      if (report.outcome == WriteOutcome.written ||
          report.outcome == WriteOutcome.deleted)
        package.outputPath,
    ]);
    if (running == null) return _launch();
    if (reshaped.isEmpty) return _reload(running);
    await _restart(
      '${package.display(reshaped.first)} changed a field, a constructor '
      'or a top-level variable',
    );
  }

  Future<void> _reload(_Running running) async {
    final result = await running.client.reload();
    printer.reloaded(result);
    if (result is ReloadRejected) await _replace();
  }

  Future<void> _restart(String reason) async {
    printer.restarting(reason);
    await _replace();
  }

  Future<void> _replace() async {
    await _shutdown();
    await _launch();
  }

  Future<void> _launch() async {
    _shapes.remember(_sources());
    final process = await AppProcess.start(
      target: target,
      arguments: arguments,
      workingDirectory: package.path,
      out: out,
      err: err,
    );
    final uri = await process.serviceUri;
    final client = uri == null ? null : await ReloadClient.connect(uri);
    if (uri == null || client == null) {
      printer.exited(await process.stop());
      return;
    }
    final running = _Running(process, client);
    _running = running;
    printer.started(process.pid, uri);
    unawaited(process.exitCode.then((code) => _exited(running, code)));
  }

  void _exited(_Running running, int code) {
    if (!identical(_running, running)) return;
    _running = null;
    unawaited(running.client.dispose());
    printer.exited(code);
  }

  Future<void> _shutdown() async {
    final running = _running;
    if (running == null) return;
    _running = null;
    await running.client.closeApplications();
    await running.process.stop();
    await running.client.dispose();
  }

  /// The Dart files the application is built from, as far as `dev`
  /// watches them: `lib/` and the directory of the entry point.
  List<String> _sources() => [
    for (final directory in {package.libPath, p.dirname(target)})
      ..._dartFiles(directory),
  ];

  static Iterable<String> _dartFiles(String directory) =>
      Directory(directory).existsSync()
      ? Directory(directory)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('.dart'))
      : const <String>[];
}

/// The application process with its VM service connection.
final class _Running {
  _Running(this.process, this.client);

  final AppProcess process;
  final ReloadClient client;
}
```

- [ ] **Step 5: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/dev_printer_test.dart test/dev_session_test.dart`
Expected: `+12: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+97: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest_cli/lib/src/dev/dev_printer.dart \
  packages/dartnest_cli/lib/src/dev/dev_session.dart \
  packages/dartnest_cli/test/helpers/line_sink.dart \
  packages/dartnest_cli/test/dev_printer_test.dart \
  packages/dartnest_cli/test/dev_session_test.dart
git commit -m "feat(cli): DevSession reloads, restarts and stops the application"
```

### Task 10: Команда `dev`, клавіші, сигнали, інтеграційний тест

OP6, OP8, OP10, OP12. `DevCommand`: `--directory`/`-C`, `--target`/`-t` (alias `--entry`, за замовчуванням `bin/main.dart`), аргументи після `--`; точка входу поза текою пакета — `64`, немає файлу — `66`. Watcher — `lib/` або `MergedWatcher` над `lib/` і текою точки входу (`Watching lib/ and bin/ for changes; ...`). `WatchLoop.custom(afterRun: dev.apply)` зупиняється на `untilStopped()` або на збої дії клавіші; у `finally` — скасування клавіш, `dev.stop()`, `session.close()`. `DartnestCli` отримує команду `dev`, параметр `keys` (за замовчуванням `TerminalKeys.read`; без термінала — порожній потік) і `interrupted()`: SIGINT або, крім Windows, SIGTERM. Інтеграційний тест роадмапу (`integration/dev_test.dart`, `dart test integration`) запускає `dev` у процесі на фіксованому порту: зміна тіла → `Reloaded`, той самий PID; новий роут → `1 route changed`, він відповідає; нове поле → `Restarting`, інший PID на тому самому порту; `R` → ще один PID; зупинка → код 0 і порт відмовляє. Ще три тести: шторм збережень, помилка компіляції в `bin/`, SIGTERM дочірнього `dartnest_cli dev` (без сиріт).

**Files:**
- Create: `packages/dartnest_cli/lib/src/dev/terminal_keys.dart`
- Create: `packages/dartnest_cli/lib/src/cli/dev_command.dart`
- Modify: `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart`
- Test: `packages/dartnest_cli/test/dev_command_test.dart`
- Test: `packages/dartnest_cli/integration/dev_test.dart`

**Interfaces:**
- Consumes: `DevSession`, `DevPrinter` (Task 9), `MergedWatcher`, `WatchLoop.custom` (Task 8), `GenerationSession`, `PackageRoot`, `ReportPrinter`, `CliFailure`, `CliExitCode`, `CliRun`, `TempPackage` (етап 5), `HelloApp`, `DevSources` (Task 7), `LineSink` (Task 9).
- Produces:
  - `final class DevCommand extends Command<int>`: `DevCommand(DartnestCli cli)`, `static const defaultTarget = 'bin/main.dart'`.
  - `abstract final class TerminalKeys { static Stream<String> read(); }`.
  - `DartnestCli({StringSink? out, StringSink? err, DartnestGenerator generator, Future<void> Function()? untilStopped, Stream<String> Function()? keys})`, поле `keys`, `static Future<void> interrupted()`.

- [ ] **Step 1: Write the failing tests**

Файл `packages/dartnest_cli/test/dev_command_test.dart`:

```dart
import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/dev_sources.dart';
import 'helpers/temp_package.dart';

void main() {
  test('dev --help shows the target option', () async {
    final run = await CliRun.run(['dev', '--help']);

    expect(run.exitCode, CliExitCode.success.code);
    expect(run.out, contains('--target'));
    expect(run.out, contains('(defaults to "bin/main.dart")'));
  });

  test('dev without the entry point fails before starting', () async {
    final package = await TempPackage.create(
      'hello',
      Map.of(DevSources.files)..remove('bin/main.dart'),
    );

    final run = await CliRun.run(['dev', '-C', package.dir.path]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, contains('No bin/main.dart in '));
    expect(run.err, contains('pass the entry point with --target.'));
  });

  test('--entry is the --target of the design', () async {
    final package = await TempPackage.create('hello', DevSources.files);

    final run = await CliRun.run([
      'dev',
      '-C',
      package.dir.path,
      '--entry',
      'bin/server.dart',
    ]);

    expect(run.exitCode, CliExitCode.noInput.code);
    expect(run.err, contains('No bin/server.dart in '));
  });

  test(
    'an entry point outside a directory of the package is refused',
    () async {
      final package = await TempPackage.create('hello', DevSources.files);

      for (final target in ['main.dart', '../main.dart']) {
        final run = await CliRun.run([
          'dev',
          '-C',
          package.dir.path,
          '-t',
          target,
        ]);

        expect(run.exitCode, CliExitCode.usage.code, reason: target);
        expect(run.err, contains('such as bin/; $target is not.'));
      }
    },
  );

  test('an unknown option is a usage error', () async {
    final run = await CliRun.run(['dev', '--port', '1']);

    expect(run.exitCode, CliExitCode.usage.code);
    expect(run.err, contains('Could not find an option named "--port"'));
  });
}
```

Файл `packages/dartnest_cli/integration/dev_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test/helpers/hello_app.dart';
import '../test/helpers/line_sink.dart';

/// Waits until [lines] has [count] lines that satisfy [test], in any order
/// with the other lines (the application prints while dev does).
Future<void> until(
  LineSink lines,
  bool Function(String line) test, {
  int count = 1,
}) async {
  while (lines.lines.where(test).length < count) {
    await lines.next();
  }
}

bool isListening(String line) => HelloApp.portIn(line) != null;

/// A loopback port that was free a moment ago.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// The answer of `GET /hello` on [port].
Future<Map<String, Object?>> hello(int port) async =>
    await HelloApp.get(port, '/hello') as Map<String, Object?>;

/// `dev` of the `hello` application on [port], run in-process.
final class DevRun {
  DevRun._(this.app, this.port, this.lines, this.keys, this._stop, this.exit);

  /// Starts `dev` and waits until the application listens.
  static Future<DevRun> start() async {
    final app = await HelloApp.create();
    final port = await freePort();
    final lines = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final exit = DartnestCli(
      out: lines,
      err: lines,
      untilStopped: () => stop.future,
      keys: () => keys.stream,
    ).run(['dev', '-C', app.package.dir.path, '--', '$port']);
    final run = DevRun._(app, port, lines, keys, stop, exit);
    addTearDown(run.stop);
    await until(lines, (line) => line.startsWith('Watching lib/ and bin/'));
    await until(lines, isListening);
    return run;
  }

  final HelloApp app;
  final int port;
  final LineSink lines;
  final StreamController<String> keys;
  final Completer<void> _stop;

  /// The exit code of `dev`.
  final Future<int> exit;

  /// Stops `dev` as Ctrl+C does and returns its exit code.
  Future<int> stop() {
    if (!_stop.isCompleted) _stop.complete();
    return exit;
  }
}

void main() {
  // The roadmap's dev test: a body change keeps the process, a new route
  // appears, a new field restarts the application in a new process.
  test('dev reloads bodies and routes and restarts on a new field', () async {
    final dev = await DevRun.start();
    final first = (await hello(dev.port))['pid'];

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await until(dev.lines, (line) => line.startsWith('Reloaded '));
    expect(await hello(dev.port), {'text': 'hello v2', 'pid': first});

    // Review Focus 8: the route reaches the application only through the
    // generated file, which is written before the reload.
    dev.app.edit(
      'lib/src/hello_controller.dart',
      '  @Get()',
      "  @Get('/bye')\n  Map<String, Object> bye() => {'text': 'bye'};\n\n"
          '  @Get()',
    );
    await until(dev.lines, (line) => line.endsWith(', 1 route changed.'));
    expect(await HelloApp.get(dev.port, '/hello/bye'), {'text': 'bye'});
    expect((await hello(dev.port))['pid'], first);

    // Review Focus 6: the new process binds the port the old one held.
    dev.app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n\n  String greet',
    );
    await until(dev.lines, (line) => line.startsWith('Restarting '));
    await until(dev.lines, isListening, count: 2);
    final second = (await hello(dev.port))['pid'];
    expect(second, isNot(first));

    dev.keys.add('R');
    await until(dev.lines, (line) => line.endsWith(': restart requested.'));
    await until(dev.lines, isListening, count: 3);
    expect((await hello(dev.port))['pid'], allOf(isNot(first), isNot(second)));

    expect(await dev.stop(), CliExitCode.success.code);
    // Review Focus 1: the application ended with dev.
    await expectLater(hello(dev.port), throwsA(isA<SocketException>()));
  });

  test('a storm of saves ends with the last version in one process', () async {
    // Review Focus 4.
    final dev = await DevRun.start();
    final first = (await hello(dev.port))['pid'];

    for (var version = 2; version <= 6; version++) {
      dev.app.edit(
        'lib/src/greeter.dart',
        'hello v${version - 1}',
        'hello v$version',
      );
    }
    final stopwatch = Stopwatch()..start();
    while ((await hello(dev.port))['text'] != 'hello v6') {
      if (stopwatch.elapsed > const Duration(seconds: 30)) fail('No v6.');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect((await hello(dev.port))['pid'], first);
    expect(dev.lines.lines, isNot(contains(startsWith('Restarting '))));
    expect(dev.lines.lines, isNot(contains(contains('failed'))));
  });

  test('a compile error in bin/ keeps the previous code running', () async {
    final dev = await DevRun.start();

    dev.app.edit('bin/main.dart', 'final adapter', 'final adapter = 1;\n  var');
    await until(dev.lines, (line) => line.startsWith('Hot reload failed; '));
    expect((await hello(dev.port))['text'], 'hello v1');
  });

  test('SIGTERM stops dev and the application with it', () async {
    // Review Focus 1 and 7: a supervisor stops dev with SIGTERM outside
    // Windows; the application must not outlive it.
    final app = await HelloApp.create();
    final port = await freePort();
    final cli = await Isolate.resolvePackageUri(
      Uri.parse('package:dartnest_cli/'),
    );
    final script = p.join(
      p.dirname(p.fromUri(cli ?? Uri())),
      'bin',
      'dartnest_cli.dart',
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      script,
      'dev',
      '-C',
      app.package.dir.path,
      '--',
      '$port',
    ]);
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final lines = LineSink();
    process.stdout.transform(utf8.decoder).listen(lines.write);
    process.stderr.transform(utf8.decoder).listen(lines.write);
    await until(lines, isListening);
    expect((await hello(port))['text'], 'hello v1');

    process.kill(ProcessSignal.sigterm);

    expect(
      await process.exitCode.timeout(const Duration(seconds: 30)),
      CliExitCode.success.code,
    );
    await expectLater(hello(port), throwsA(isA<SocketException>()));
  }, testOn: '!windows');
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartnest_cli && dart test test/dev_command_test.dart`
Expected: FAIL: `Some tests failed.` — `dev` ще не зареєстровано (падають 4 з 5 тестів; `an unknown option is a usage error` проходить і без команди)

- [ ] **Step 3: Implement `TerminalKeys`**

Файл `packages/dartnest_cli/lib/src/dev/terminal_keys.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The keys typed in the terminal, for the `r` and `R` of `dev`.
abstract final class TerminalKeys {
  /// Every key typed on stdin when it is a terminal; an empty stream
  /// otherwise. While the stream is listened to, stdin reads key by key
  /// without echo (Ctrl+C still interrupts); cancelling restores it.
  static Stream<String> read() {
    if (!stdin.hasTerminal) return const Stream<String>.empty();
    StreamSubscription<String>? subscription;
    final controller = StreamController<String>();
    controller
      ..onListen = () {
        stdin
          ..echoMode = false
          ..lineMode = false;
        subscription = stdin
            .transform(const Utf8Decoder(allowMalformed: true))
            .expand((chunk) => chunk.split(''))
            .listen(controller.add);
      }
      ..onCancel = () async {
        await subscription?.cancel();
        stdin
          ..lineMode = true
          ..echoMode = true;
      };
    return controller.stream;
  }
}
```

- [ ] **Step 4: Implement `DevCommand`**

Файл `packages/dartnest_cli/lib/src/cli/dev_command.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../dev/dev_printer.dart';
import '../dev/dev_session.dart';
import '../dev/merged_watcher.dart';
import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'dartnest_cli.dart';
import 'report_printer.dart';

/// `dev`: runs the application and, on every change of `lib/` or of the
/// directory of its entry point, generates the package and hot reloads the
/// application, or hot restarts it when a reload cannot apply the change.
final class DevCommand extends Command<int> {
  /// Creates the command of [cli].
  DevCommand(this.cli) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'The package of the application.',
      )
      ..addOption(
        'target',
        abbr: 't',
        aliases: ['entry'],
        defaultsTo: defaultTarget,
        valueHelp: 'path',
        help: 'The entry point, relative to the package.',
      );
  }

  /// The entry point when no `--target` is given.
  static const defaultTarget = 'bin/main.dart';

  /// The command line this command belongs to.
  final DartnestCli cli;

  @override
  String get name => 'dev';

  @override
  String get description =>
      'Runs the application and hot reloads it on every change.';

  @override
  String get invocation =>
      'dartnest_cli dev [options] [-- <arguments of main>]';

  @override
  void printUsage() => cli.out.writeln(usage);

  @override
  Future<int> run() async {
    final options = argResults ?? (throw StateError('dev was not parsed.'));
    final package = PackageRoot.open(options.option('directory') ?? '.');
    final target = _target(package, options.option('target') ?? '');
    final session = GenerationSession(package, generator: cli.generator);
    final dev = DevSession(
      package,
      target: target,
      arguments: options.rest,
      printer: DevPrinter(package.display(target), cli.out, cli.err),
      out: cli.out,
    );
    final failure = Completer<void>();
    final keys = cli.keys().listen((key) => _press(dev, key, failure));
    try {
      final (watcher, watched) = _watch(package, target);
      await WatchLoop.custom(
        generate: (changed) => session.run(changed: changed),
        watched: watched,
        printer: ReportPrinter(cli.out, cli.err),
        afterRun: dev.apply,
      ).run(watcher, Future.any([cli.untilStopped(), failure.future]));
    } finally {
      await keys.cancel();
      await dev.stop();
      await session.close();
    }
    return CliExitCode.success.code;
  }

  static String _target(PackageRoot package, String relative) {
    final target = p.normalize(p.join(package.path, relative));
    if (!p.isWithin(package.path, p.dirname(target))) {
      throw CliFailure(
        CliExitCode.usage,
        'The entry point must be in a directory of the package, such as '
        'bin/; $relative is not.',
      );
    }
    if (File(target).existsSync()) return target;
    throw CliFailure(
      CliExitCode.noInput,
      'No $relative in ${package.path}; pass the entry point with --target.',
    );
  }

  /// The watcher of `lib/` and of the directory of [target], and how the
  /// watched directories are printed.
  static (Watcher, String) _watch(PackageRoot package, String target) {
    final lib = DirectoryWatcher(package.libPath);
    if (p.isWithin(package.libPath, target)) return (lib, 'lib');
    final directory = p.dirname(target);
    return (
      MergedWatcher(package.path, [lib, DirectoryWatcher(directory)]),
      'lib/ and ${package.display(directory)}',
    );
  }

  /// Runs the operation of [key]; a failure of it ends `dev` through
  /// [failure].
  static void _press(DevSession dev, String key, Completer<void> failure) {
    final operation = switch (key) {
      'r' => dev.reload,
      'R' => dev.restart,
      _ => null,
    };
    unawaited(
      operation?.call().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!failure.isCompleted) failure.completeError(error, stackTrace);
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Register `dev`, `keys` and `interrupted` in `DartnestCli`**

Файл `packages/dartnest_cli/lib/src/cli/dartnest_cli.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import '../dev/terminal_keys.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'dev_command.dart';
import 'gen_command.dart';
import 'init_command.dart';

/// The `dartnest_cli` command line.
///
/// `bin/dartnest_cli.dart` runs it with the core constructs; a package
/// with constructs of its own runs it from `tool/dartnest.dart`:
/// `DartnestCli(generator: DartnestGenerator([...])).run(arguments)`.
final class DartnestCli {
  /// Creates the command line; output goes to [out] and [err] (stdout and
  /// stderr by default), `gen` runs [generator], `gen --watch` and `dev`
  /// stop when [untilStopped] completes (the first Ctrl+C, or `SIGTERM`
  /// outside Windows, by default) and `dev` reads its `r` and `R` from
  /// [keys] (the terminal by default).
  DartnestCli({
    StringSink? out,
    StringSink? err,
    this.generator = const DartnestGenerator.core(),
    Future<void> Function()? untilStopped,
    Stream<String> Function()? keys,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       untilStopped = untilStopped ?? interrupted,
       keys = keys ?? TerminalKeys.read;

  /// Where results and usage go.
  final StringSink out;

  /// Where problems and failures go.
  final StringSink err;

  /// The constructs `gen` runs.
  final DartnestGenerator generator;

  /// Called when `gen --watch` or `dev` starts; watching ends when the
  /// future completes.
  final Future<void> Function() untilStopped;

  /// Called when `dev` starts: the keys pressed while it runs.
  final Stream<String> Function() keys;

  /// Runs the command in [arguments] and returns the process exit code
  /// (see [CliExitCode]).
  Future<int> run(List<String> arguments) async {
    final runner = _Runner(out)
      ..addCommand(DevCommand(this))
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

  /// Completes on the first `SIGINT` (Ctrl+C) or, outside Windows, where
  /// it cannot be watched, `SIGTERM`; then stops watching both.
  static Future<void> interrupted() {
    final stopped = Completer<void>();
    final subscriptions = [
      for (final signal in [
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ])
        signal.watch().listen((_) {
          if (!stopped.isCompleted) stopped.complete();
        }),
    ];
    return stopped.future.whenComplete(
      () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]),
    );
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

- [ ] **Step 6: Run the tests**

Run: `cd packages/dartnest_cli && dart test test/dev_command_test.dart`
Expected: `+5: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+102: All tests passed!`

Run: `cd packages/dartnest_cli && dart test integration`
Expected: `+4: All tests passed!` (близько 20 с)

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_cli/lib/src/dev/terminal_keys.dart \
  packages/dartnest_cli/lib/src/cli/dev_command.dart \
  packages/dartnest_cli/lib/src/cli/dartnest_cli.dart \
  packages/dartnest_cli/test/dev_command_test.dart \
  packages/dartnest_cli/integration/dev_test.dart
git commit -m "feat(cli): dev runs the application with hot reload and hot restart"
```

### Task 11: Документація

README обох пакетів (англійською): у `dartnest_cli` — розділ `dev` (команда дочірнього процесу, рядки виводу, reload/restart і чому, проблеми й помилки компіляції, падіння, клавіші й сигнали, сироти після SIGKILL, `dart` замість `dart run`), `--target bin/server.dart` для каркаса `init` (OP8), коди виходу `dev`; у `dartnest` — розділ «Hot reload» (`reassemble`, що зберігається, помилки, `Provider.value`, extensions лише поза product). `CLAUDE.md`: команда `dart test integration`, правило залежностей (`vm_service` лише в CLI, `dart:developer` у ядрі), виняток для процесних тестів `dev`, нова межа `on Object` (`HotReloadExtension.handle`). Роадмап: рядок 5b посилається на план. Опис пакета CLI згадує `dev`.

**Files:**
- Modify: `packages/dartnest_cli/README.md`
- Modify: `packages/dartnest/README.md`
- Modify: `packages/dartnest_cli/pubspec.yaml`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/ROADMAP.md`

**Interfaces:**
- Consumes: усі команди, повідомлення й публічні типи Tasks 1–10 (README описує їх як є).
- Produces: документацію; коду немає.

- [ ] **Step 1: Write the `dartnest_cli` README**

Повний файл:

Файл `packages/dartnest_cli/README.md`:

````markdown
# dartnest_cli

The command line tool of dartnest. `gen` writes `lib/<package>.dartnest.dart`
from the annotations of a package, `gen --watch` keeps it up to date while
you edit, `dev` runs the application and hot reloads it on every change, and
`init` scaffolds a new application.

```sh
dart run dartnest_cli gen                    # in the package directory
dart run dartnest_cli gen --watch            # regenerate on every change, Ctrl+C stops
dart run dartnest_cli gen --directory packages/shop
dart run dartnest_cli dev                    # run bin/main.dart, hot reload on every change
dart run dartnest_cli dev -t bin/server.dart -- --port 8080
dart run dartnest_cli init my_app            # a new package in ./my_app
```

`--directory` is `-C` and `--watch` is `-w`. Installed as an executable (the
package declares `dartnest`, for example
`dart pub global activate --source path packages/dartnest_cli`), the same
commands are `dartnest gen` and `dartnest init`. Without a command the tool
prints its usage and exits with 0.

## gen

- Reads every Dart file of `lib/` except generated `*.dartnest.dart` files
  and runs the core constructs of `dartnest_generator`
  (`DartnestGenerator.core()`).
- Problems go to stderr, one per line, as
  `path:line:column: error: message [code]`, with the path relative to the
  package root and `/` separators on every platform; the last line counts
  them. Syntax errors have the code `syntax_error`; the generator's codes
  are listed in the `dartnest_generator` README. While there are problems,
  the generated library is left as it was.
- Only syntax errors stop the analysis early. Other analyzer errors do not:
  on the first run the generated library does not exist yet, so code
  importing it does not compile.
- The library is written only when its content changed, through
  `<file>.tmp` and a rename, so a running analyzer or `dev` never reads
  half a file. A file at that path that does not start with
  `// GENERATED BY dartnest_generator. DO NOT EDIT.` is never overwritten or
  deleted: `gen` fails with exit code 73 instead.
- When `lib/` has no annotations any more, the generated library is
  deleted.
- The success line ends with the time the run took, for example
  `lib/shop.dartnest.dart is up to date (35 ms).`
- One package per run. A `@Module` class of another package is imported
  from that package's own generated library, so generate dependencies
  first. The generator cannot see into such a module (or into a module
  built by a function): it stays opaque, and `missing_provider` and
  `circular_dependency` are left to `Application.create` for the whole
  package that references it.

## gen --watch

- Generates once, then after every change of a Dart file in `lib/`, with
  the analysis kept in memory: only changed files are read again.
- Events are debounced (100 ms): an editor's save or a branch switch gives
  one run. Runs never overlap; changes made during a run go into the next.
  A burst that spans the end of a run can therefore give two runs.
- Problems are printed and watching goes on; so does a failure to write the
  output (a `CliFailure`). Any other exception of a run ends the process,
  and so does an error of the file watcher's stream.
- Known limitation: a non-syntax error that leaves the model empty while you
  edit (for example a broken `package:dartnest_annotations` import, so no
  annotation is recognised) makes the run see "no annotations" and delete the
  generated library. The next successful run writes it again.
- The generation benchmark is not part of `dart test`:
  `cd packages/dartnest_cli && dart test benchmark`. On 200 files it took
  about 2.5 s cold and 0.35 s for an incremental run when this was written;
  the test fails above 10 s and 1 s.

## dev

`dev` generates like `gen --watch` and runs the application next to it:
`dart --enable-vm-service=0 --no-dds <target> <arguments>` in the package
directory, where the target is `bin/main.dart` or `--target` (`-t`, also
`--entry`) and the arguments are the ones after `--`. The application's
output is passed through unchanged; `dev` adds one line per event:

```text
Started bin/main.dart (pid 4242, VM service http://127.0.0.1:40107/abc=/).
Reloaded 3 libraries in 180 ms, 2 routes changed.
Restarting bin/main.dart: lib/src/greeter.dart changed a field, a constructor or a top-level variable.
```

- `lib/` and the directory of the target are watched; the target must be
  in a directory of the package (`bin/main.dart`, not `main.dart`).
- After every run without problems, the application is hot reloaded (the
  VM's `reloadSources`) and then reassembled (`ext.dartnest.reassemble`, see
  the `dartnest` README): provider instances keep their state, controllers
  and routes are rebuilt, the process and its port stay.
- It is hot restarted instead (the dartnest applications close, requests in
  flight finish, the process ends, then a new one starts, free to bind
  the same port) when
  a file changed a field, a constructor, a top-level or static variable or
  an enum value: a reload would keep instances without the new field. It is
  also restarted when the VM refuses the reload (for example a changed type
  parameter).
- A reload does not run `main` again: a change of the server setup in
  `main` itself takes effect after a restart (`R`).
- While the sources have problems, nothing is reloaded: the application
  keeps running the previous code. A reload that does not compile (an error
  outside `lib/`) is printed and changes nothing either. A reassemble that
  fails keeps the previous modules and routes and prints the error.
- An application that exits (or does not start) is started again after the
  next change, never in a loop.
- In a terminal, `r` reloads and `R` restarts. Ctrl+C (or `SIGTERM` outside
  Windows) stops `dev`: the application closes and ends first. If `dev`
  itself is killed (`SIGKILL`), the application keeps running.
- `dev` runs the target with `dart <target>`, not `dart run`: no implicit
  `pub get` on every restart. Run `dart pub get` after editing
  `pubspec.yaml`, then restart with `R`.

## init

`init <directory>` writes a new package into a new or empty directory; the
directory name is the package name (lowercase_with_underscores, not a Dart
reserved word, and not one of the packages the template depends on):
`pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `lib/src/hello.dart`
(a service, a controller and the root `AppModule`) and `bin/server.dart`.
If writing fails, the files `init` created are removed again. Then:

```sh
cd my_app
dart pub get
dart run dartnest_cli gen
dart run bin/server.dart    # GET http://localhost:8080/hello?name=you
```

The scaffold's entry point is `bin/server.dart`, so its `dev` is
`dart run dartnest_cli dev --target bin/server.dart`.

The scaffold depends on `dartnest`, `dartnest_annotations`, `dartnest_io`
and `dartnest_cli` at `^0.1.0`. The workspace packages are `0.1.0-dev`, so
`dart pub get` resolves them only once 0.1.0 is published.

## Exit codes

| Code | When |
| --- | --- |
| 0 | done (also when there is nothing to generate, when no command is given, and after `--watch` or `dev` stops) |
| 1 | problems in the sources: diagnostics or syntax errors |
| 64 | wrong command line (unknown command or option, `init` without exactly one directory, or with a name that is not a valid package name, a `dev` target outside a directory of the package) |
| 66 | no `pubspec.yaml` with a valid `name`, no `lib/`, or no `dev` target |
| 73 | a file cannot be written, a foreign file is in the way of the output, or `init` into a directory that is not empty |

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

- [ ] **Step 2: Add the hot reload section to the `dartnest` README**

У `packages/dartnest/README.md` замінити:

```markdown
  number of times: new requests get 503, running ones finish, then the
  container closes.
```

на:

```markdown
  number of times: new requests get 503, running ones finish, then the
  container closes.

## Hot reload

`dart run dartnest_cli dev` (see the `dartnest_cli` README) hot reloads a
running application; this package provides the hooks it uses.

- `app.reassemble()` calls the module function given to `Application.create`
  again, validates the new graph and builds a new container with
  `Container.reassemble`: provider instances are kept by module id and key,
  providers that are new (or moved to another module) are created, and
  providers that are gone are dropped. Controllers, enhancers and the route
  table are always built anew. The new container and routes replace the old
  ones in one step; a request already running finishes on the table it
  started with. It returns a `ReassembleReport` with the added and removed
  routes (`GET /users/:id`).
- A failure (an invalid graph, a factory that throws, a module function
  that throws) leaves the previous container and routes serving and is
  passed on. `reassemble()` fails with `ApplicationStateError` after
  `close()` and while another reassemble runs.
- A kept instance keeps its state, also when its class changed: a hot
  reload that changes fields or constructors is followed by a restart in
  `dev`, not by `reassemble()`. A `Provider.value` keeps its old value; a
  changed configuration value needs a restart.
- Outside product mode (`dart.vm.product`), `Application.create` registers
  the VM service extensions `ext.dartnest.reassemble` (reassembles every
  open application; the result lists the added and removed routes, an error
  carries the failure with its causes) and `ext.dartnest.close` (closes
  every open application). AOT and `--define=dart.vm.product=true` builds
  register nothing.
```

- [ ] **Step 3: Update the package description**

У `packages/dartnest_cli/pubspec.yaml` замінити:

```yaml
  Command line tool of dartnest: generates the code of annotated packages
  (gen, gen --watch) and scaffolds new applications (init).
```

на:

```yaml
  Command line tool of dartnest: generates the code of annotated packages
  (gen, gen --watch), runs them with hot reload (dev) and scaffolds new
  applications (init).
```

- [ ] **Step 4: Update `CLAUDE.md`**

У `CLAUDE.md` замінити:

```markdown
# packages/dartnest_cli: the generation benchmark (not part of `dart test`):
dart test benchmark
```

на:

```markdown
# packages/dartnest_cli: the generation benchmark (not part of `dart test`):
dart test benchmark
# packages/dartnest_cli: the dev integration tests (not part of `dart test`):
dart test integration
```

У `CLAUDE.md` замінити:

```markdown
  `analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`.
```

на:

```markdown
  `analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`, and
  `vm_service` only in `dartnest_cli`. `dart:developer` (SDK) is allowed in
  the core for the hot reload service extensions, which register only
  outside product mode.
```

У `CLAUDE.md` замінити:

```markdown
  run the command line in-process (`CliRun`, `DartnestCli(out:, err:,
  untilStopped:)`), never as a child process.
```

на:

```markdown
  run the command line in-process (`CliRun`, `DartnestCli(out:, err:,
  untilStopped:, keys:)`), never as a child process. The exceptions are
  `dev`'s: its tests start the user's application as a child process with
  the VM service on loopback (`AppProcess`, `DevSession`), and
  `integration/dev_test.dart` (run with `dart test integration`) also runs
  the command line as a child process to stop it with `SIGTERM`.
```

У `CLAUDE.md` замінити:

```markdown
  trace, so reporting never
  stops the 500 or the server.
```

на:

```markdown
  trace, so reporting never
  stops the 500 or the server;
- the hot reload boundary (added by the hot reload work):
  `HotReloadExtension.handle` turns any failure of `reassemble`/`close`
  (user module functions and factories run there) into a
  `ServiceExtensionResponse.error` with the error and, for a failure that
  is not a `DartnestError`, its stack trace, so `dev` prints it and the
  application keeps serving.
```

- [ ] **Step 5: Update the roadmap**

У `docs/superpowers/ROADMAP.md` замінити:

```markdown
| 5b | **Hot reload / hot restart** | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
```

на:

```markdown
| 5b | **Hot reload / hot restart** (план `2026-10-14-dartnest-hot-reload.md`) | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
```

- [ ] **Step 6: Verify the whole stage**

Run: `cd packages/dartnest && dart test`
Expected: `+270: All tests passed!`

Run: `cd packages/dartnest_cli && dart test`
Expected: `+102: All tests passed!`

Run: `cd packages/dartnest_cli && dart test integration`
Expected: `+4: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+163: All tests passed!` (генератор не змінено)

Run: `cd packages/dartnest_io && dart test`
Expected: `+46: All tests passed!`

Run: `cd packages/dartnest_shelf && dart test`
Expected: `+67: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_cli/README.md \
  packages/dartnest/README.md \
  packages/dartnest_cli/pubspec.yaml \
  CLAUDE.md \
  docs/superpowers/ROADMAP.md
git commit -m "docs: document dev and hot reload"
```

## Самоперевірка

**Покриття специфікації.**

| Вимога | Задача |
|---|---|
| 10: лише JIT і debug (`!bool.fromEnvironment('dart.vm.product')`), у production нуль накладних витрат | 4 (`HotReloadExtension.isEnabled`, реєстрація лише за нього) |
| 10: hot restart — `app.close()` (graceful, in-flight до таймауту), запуск заново | 4 (`ext.dartnest.close`), 7 (`closeApplications`, 5 с), 6 (SIGTERM → SIGKILL), 9 (`_replace`) (OP7) |
| 10: hot reload — `reloadSources`, потім `app.reassemble()`; стан провайдерів зберігається | 1, 3, 7, 9 (OP3) |
| 10: зміни полів, конструкторів, `const`, top-level ініціалізаторів → restart | 5 (`ShapeTracker`), 9 (OP4) |
| 10.1 п. 1: `Application.create` приймає `Module Function()`; `reassemble` будує граф заново | 3 (`_root` викликається в `reassemble`) |
| 10.1 п. 2: `Container.reassemble(Module newRoot)`, екземпляри за `(moduleId, key)`, нові створюються, зниклі відкидаються; контролери й роути заново | 1, 3 |
| 10.1 п. 3: атомарна підміна таблиці, запит у польоті — старою | 3 (Review Focus 2) |
| 10.1 п. 4: `close()` коректний і повторюваний | етап 2; 4 (`detach` у першому `close`, тест `a closed application is not reassembled`) |
| 10.1 п. 5: помилка `reassemble` лишає попередній стан, друкується з ланцюжком | 1, 3, 4 (`DartnestError` з ланцюжком у `errorDetail`), 7, 9 (`DevPrinter`) |
| 10.2: `dart run dartnest_cli dev [--entry bin/main.dart]` | 10 (`--target` з alias `--entry`) (OP8) |
| 10.2 п. 1: дочірній процес з VM service | 6 (`dart --enable-vm-service=0 --no-dds`, відхилення OP9) |
| 10.2 п. 2: стежити за `lib/` і `bin/`, генератор у тому ж процесі, потім reload; `r`/`R`; невдалий або неможливий reload → restart | 8, 9, 10 (OP5, OP6; невдала компіляція — без restart) |
| 10.2 п. 3: результат одним рядком | 9 (`DevPrinter`, Рішення 7) |
| 10.3 юніт: ідентичність збережених, нові, зниклі, помилка графа, атомарна підміна | 1 (7 тестів), 3 (`a request keeps the table it started with`) |
| 10.3 інтеграційний: тіло → той самий PID; новий роут з'являється; поле → restart, інший PID; окремий таск | 10 (`integration/dev_test.dart`, `dart test integration`) (OP12) |
| Роадмап 5b «Готово, коли» | 1–10; посилання на план — 11 |

**Плейсхолдери.** Пошук `TBD`, `TODO`, «similar to Task», «add error handling», «implement later» — нічого. Кожен крок з кодом містить повний файл; файли, які змінюються кількома задачами, наведено повністю в кожній: `lib/src/app/application.dart` (2, 3, 4), `lib/src/app/application_assembly.dart` (2, 3), `packages/dartnest_cli/pubspec.yaml` (7 — повністю, 11 — «було → стало»). Зміни `CLAUDE.md`, роадмапу й README ядра (Task 11) дано точним «було → стало».

**Узгодженість типів.** Імена між задачами взято з того самого коду, що пройшов перевірку нижче: `ModuleInjector.instances/adopt`, `Container.reassemble`, `Assembly` (`container`, `router`), `ApplicationAssembly.start/rebuild`, `ReassembleReport({addedRoutes, removedRoutes}).between/changedRoutes/toJson`, `RouteTableBuilder.describe`, `Application.reassemble`, `HotReloadExtension.reassembleMethod/closeMethod/isEnabled/attach/detach/handle`, `ShapeTracker.shapeOf/remember/changed`, `AppProcess.vmFlags/start({target, arguments, workingDirectory, out, err})/pid/serviceUri/exitCode/stop({killGrace})`, `ReloadResult` → `Reloaded({libraries, elapsed, changedRoutes, reassembleError})`/`ReloadFailed(message)`/`ReloadRejected(reason)`, `ReloadClient.connect/reload/closeApplications({timeout})/dispose/reassembleMethod/closeMethod`, `WatchLoop.custom({generate, watched, printer, afterRun, debounce})`, `MergedWatcher(path, watchers)`, `DevPrinter(target, out, err).started/restarting/exited/waiting({isRunning})/reloaded`, `DevSession(package, {target, arguments, printer, out}).apply/reload/restart/stop`, `TerminalKeys.read`, `DevCommand(cli)` + `defaultTarget`, `DartnestCli({out, err, generator, untilStopped, keys}).keys/interrupted`; хелпери `DevSources.main/greeter/controller/module/files`, `HelloApp.create/package/edit/portIn/get`, `LineSink.next/nextWhere/after/lines`, `Dev` (у `dev_session_test.dart`), `DevRun`/`until`/`freePort`/`hello` (у `integration/dev_test.dart`). Константи extension в ядрі й CLI однакові: `ext.dartnest.reassemble`, `ext.dartnest.close`.

**Перевірка.** План перевірено скриптом, який читає цей markdown і застосовує його задача за задачею до чистого клону `master` (`909bf52`) у `/tmp`: записує кожен файл з блоку коду, застосовує «було → стало» (кожен фрагмент «було» трапляється рівно раз), виконує кожен рядок `Run:` (`dart pub get` — з `--offline`, `TMPDIR` у `/tmp`) і порівнює з `Expected:` (кроки «verify it fails» мусять завершитися з помилкою, що містить наведений текст; кроки з `+N` — дати рівно `+N: All tests passed!`), виконує блок коміту як є й перевіряє, що після нього `git status` чистий, а дерево збігається з еталонною гілкою, на якій код писався. Результат: усі 11 задач, усі кількості (`dartnest` `+258`, `+258`, `+264`, `+270`; `dartnest_cli` `+71`, `+76`, `+81`, `+85`, `+97`, `+102`; `integration` `+4`), `dart analyze` — «No issues found!» і `dart format` — 0 змінених файлів після кожної задачі; `dartnest_io` `+46`, `dartnest_shelf` `+67`, `dartnest_generator` `+163` не змінились. SDK: Dart 3.13.5 (fvm Flutter 3.47.6) з мовною версією 3.8. Нижні краї: `vm_service` 15.2.0 (`reload_client.dart`, `reload_result.dart`) і `analyzer` 8.1.1 (`shape_tracker.dart`) — окрема копія, `dart analyze` чистий, `ShapeTracker.shapeOf` дає ту саму форму. Стабільність процесних тестів: `dart test integration` — 6 прогонів поспіль зелені (~17 с кожен), ще 2 — паралельно з `dart test` і з окремим прогоном `dev_session_test.dart` + `reload_client_test.dart` (навантаження на CPU) — зелені. Факти, на яких стоять OP, перевірено окремими пробами: `dart <file>` і `--no-dds` — один процес із PID застосунку; `dart run` робить неявний `pub get`; VM приймає reload з новим полем, а поле, присвоєне конструктором, у старих екземплярах дає `type 'Null' is not a subtype of type 'String'`; зміна type parameters — `ReasonForCancellingReload`; помилка компіляції — `ReasonForCancelling` з `Error:`; після `ext.dartnest.close` процес виходить з кодом 0 за ~20 мс при підключеному VM service; повторний `bind` фіксованого порту одразу після SIGKILL сервера проходить (`SO_REUSEADDR`). Розміри: найбільший файл у `lib/` — `application.dart` (283 рядки), далі `module_injector.dart` (232), `dev_session.dart` (179); у тестах — `application_test.dart` (208), `watch_loop_runs_test.dart` (207), `integration/dev_test.dart` (190); найдовші нові методи — `AppProcess.start` (30 рядків) і `DevCommand.run` (29).

**Review Focus.** Кожен пункт закріплено тестом з коментарем `// Review Focus N`: 2 → Task 3; 9 → Task 5 і Task 9; 7 → Task 6 і Task 10; 1, 3, 4, 5 → Task 9; 1, 4, 6, 8 → Task 10.

## Відкриті питання для автора

Усі рішення, які варто переглянути до виконання, винесено в «Open points» (OP1–OP12) з рекомендаціями; план написано за ними. Рішення автора справді потрібне в одному місці, і ще два варто підтвердити:

1. **OP8 — точка входу за замовчуванням.** Спека 10.2 і план: `bin/main.dart`; але `init` етапу 5 створює `bin/server.dart`, тож для свіжого каркаса `dev` без `--target` завершиться кодом `66` (README називає `--target bin/server.dart`). Варіанти: (a) як у плані; (b) окремим малим комітом перейменувати файл каркаса `init` на `bin/main.dart` (`ProjectTemplate`, README `init`, тест `init`); (c) зробити `bin/server.dart` за замовчуванням `dev`. Рекомендація — (b) після цього етапу.
2. **OP5 і OP9 — відхилення від спеки 10.2** (без restart при помилці компіляції; `dart --no-dds <target>` замість `dart run`). Чи оновити текст спеки разом з етапом, чи лишити відхилення зафіксованими лише в плані.
3. **OP4 — статичний `ShapeTracker`.** Він дає зайвий restart для нового поля з ініціалізатором (reload впорався б). Якщо це заважає, варіант B (лише відповідь VM) вимикається прибиранням одного виклику, ціною ризику Review Focus 9.
