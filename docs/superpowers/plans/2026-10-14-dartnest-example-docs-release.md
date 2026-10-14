# dartnest — приклад, документація й готовність до випуску 0.1.0: план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Зробити репозиторій готовим до випуску `0.1.0` семи пакетів. Додати
приклад-застосунок `example/` в обох стилях і документацію (кореневий
README, `docs/*.md`). Кожен публікований пакет має проходити
`dart pub publish --dry-run` з нулем попереджень. Публікацію, теги, push і
створення GitHub-репозиторію план не виконує: це ручні кроки мейнтейнера
за `docs/RELEASING.md`.

**Architecture:** Чотири незалежні шари змін.

1. **Метадані випуску (Task 1).** Lockstep-версія `0.1.0` у всіх членах
   workspace. LICENSE у корені й у кожному пакеті. `repository` /
   `issue_tracker` / `topics`. Самодостатні `analysis_options.yaml` з
   `public_member_api_docs`. `false_secrets` для тестового TLS-ключа.
2. **Приклад `example/` (Tasks 2–3).** Пакет `tasks_api` є членом workspace
   і не публікується. Це API задач, де є кожна частина фреймворку.
   Анотаційний граф генерує `dart run dartnest_cli gen` у закомічений
   `lib/tasks_api.dartnest.dart`. Явний граф пише вручну `lib/explicit.dart`
   з тих самих класів. Один e2e-набір проганяє обидва графи на обох
   адаптерах через loopback з ефемерним портом. Golden-тест порівнює
   закомічений згенерований файл з виходом `GenerationSession`.
3. **pub.dev-готовність пакетів (Tasks 4–5).** У кожному пакеті є приклад
   під ім'ям, яке впізнає pana: `example/README.md` або
   `example/<package>_example.dart`. Виконувані приклади покриті тестом.
   Кожен пакет має `CHANGELOG.md` з `## 0.1.0`. README ядра більше не
   застарілий.
4. **Документація й процес (Tasks 6–8).** Кореневий `README.md` з quick
   start для обох стилів, таблицею пакетів і мапою NestJS→dartnest. Дев'ять
   сторінок `docs/`, серед них FAQ з відомими обмеженнями. CI-workflow, що
   набуде чинності лише після push. `docs/RELEASING.md`. Фінальний прохід
   узгодженості ROADMAP, спеки й `CLAUDE.md`.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і
primary constructors); pub workspace; `package:test` ^1.25.0; `lints`
^5.1.0. Залежності прикладу: `dartnest`, `dartnest_annotations`,
`dartnest_io`, `dartnest_shelf`, dev — `dartnest_cli`, `path`. Перевірено
на Dart 3.13.5 (Flutter 3.47.6 через fvm).

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (розділи
1 «Поза межами v1», 2, 8, 10); ROADMAP, рядок 7.

---

## Відкриті рішення

Кожне рішення має рекомендований варіант (✔), і план написано під нього.
Відмова від рекомендації змінює вказані задачі.

### OD1. Версія в репозиторії

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ `0.1.0` уже зараз, у всіх членах workspace (lockstep) | dry-run перевіряє рівно те, що піде на pub.dev; шаблон `init` (`^0.1.0`) і README узгоджені з версіями; CHANGELOG згадує поточну версію | до публікації `dartnest init` поза репозиторієм не резолвиться (те саме й сьогодні); потрібен `dependency_overrides`-сніпет |
| B лишити `0.1.0-dev`, підняти в момент публікації | версія чесно каже «не випущено» | dry-run попереджає, що CHANGELOG не згадує `0.1.0-dev`; `^0.1.0-dev` у документації; підняття версії стає частиною ручного релізу |
| C `0.0.1` | «ранній» сигнал | ламає `^0.1.0` у шаблоні `init` (CLI довелося б міняти) |

### OD2. Назва пакетів

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ лишити `dartnest*` | 2026-10-14 усі сім імен вільні (`https://pub.dev/api/packages/<name>` → 404); нуль змін коду | спека називала її «робочою»; ім'я фіксується назавжди першою публікацією |
| B перейменувати зараз | — | зачіпає кожен pubspec, import, README і план; немає кращого кандидата |

`docs/RELEASING.md` нагадує перевірити ім'я ще раз безпосередньо перед
публікацією й дає команду для перейменування.

### OD3. `repository` / `homepage` / `issue_tracker` без remote

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ заглушка `https://github.com/4akLoon/dartnest` (гілка `master`, `tree/master/packages/<p>`) + `issue_tracker` | dry-run без попереджень; той самий власник, що в `typed_openapi`; одна заміна `git grep`, якщо назва репозиторію інша | URL не існує, доки мейнтейнер не створить репозиторій; pana перевіряє його доступність |
| B без полів | нічого вигаданого | dry-run: «Your pubspec.yaml does not have a repository/homepage entry» → exit 65 |
| C лише `homepage` | — | та сама заглушка, без посилань на сирці пакета |

### OD4. Ліцензія

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ MIT, `Copyright (c) 2026 Yevhenii Aleksiuk` (як `typed_openapi`) | коротка, впізнавана pana; узгоджена з іншим OSS автора | — |
| B BSD-3-Clause | як у Dart SDK і більшості `dart-lang/*` | розходиться з іншими репозиторіями автора |
| C Apache-2.0 | патентний пункт | довша; NOTICE-конвенції |

### OD5. Приклад: член workspace чи окремий пакет

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ член workspace (`example/` у кореневому `workspace:`), `publish_to: none` | один `dart pub get`; `dart analyze` і CI бачать його; `dart run dartnest_cli gen` працює як у користувача; тести без мережі | приклад резолвиться проти локальних пакетів, не проти pub.dev (перевірку «як у користувача» дає `init` у RELEASING) |
| B окремий пакет з `dependency_overrides` на `../packages/*` | ближче до користувача | окремий `pub get`, окремий lock; analyzer кореня його не бачить; дублювання |

### OD6. Неопубліковані dev-залежності публікованих пакетів

`dartnest_io` і `dartnest_shelf` мають dev-залежність `dartnest_conformance`,
`dartnest_generator` — fixture-пакети `cases_app` і `users_app`.

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ лишити як є | pub.dev перевіряє існування лише `dependencies`, не `dev_dependencies` (сирці pub-dev, `PackageBackend`, перевірено 2026-10-14); pana знімає dev-залежності перед `outdated`/downgrade; dry-run — 0 попереджень | тести з архіву пакета поза репозиторієм не запускаються (так і в більшості пакетів) |
| B опублікувати `dartnest_conformance` | тести адаптерів запускаються з архіву | ще один публічний API, який треба підтримувати; `package:test` у `lib/` |
| C винести тести, що його використовують, з пакетів | — | ламає структуру етапу 3 |

### OD7. `analysis_options.yaml` публікованих пакетів

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ самодостатній файл (`include: package:lints/recommended.yaml` + strict-режими кореня) + `public_member_api_docs` | pana аналізує архів без батьківської теки: `include: ../../analysis_options.yaml` там би не знайшовся; lint закріплює правило «`///` на кожному public» (зараз 0 порушень) | дублювання з коренем (CLAUDE.md вимагає синхронізувати) |
| B `include: ../../analysis_options.yaml` | одне джерело | у архіві include вказує в нікуди → pana аналізує з іншими налаштуваннями |

### OD8. Версіонування пакетів

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ lockstep: усі сім з однією версією, кожен реліз піднімає всі | `^x.y.z` між пакетами ніколи не змішує версії; один тег-набір; простий RELEASING | пакет без змін отримує порожній реліз |
| B незалежні версії | точніші changelog-и | матриця сумісності (генератор ↔ ядро ↔ анотації) стає проблемою користувача |

### OD9. CI-workflow

| Варіант | Плюси | Мінуси |
|---|---|---|
| A ✔ додати `.github/workflows/ci.yaml` (Ubuntu; Dart 3.8.0 і stable; format/analyze на stable; усі тести, integration, benchmark; окремий job dry-run) | спека §8 вимагає e2e у CI; перша можливість перевірити SDK-нижню межу 3.8; файл нічого не робить до push | не перевірено запуском (немає remote) |
| B не додавати | нічого неперевіреного | §8 лишається невиконаним; 3.8 не перевіряється ніде |

Автоматична публікація (`publish.yml` через OIDC) не додається: перший
випуск кожного пакета все одно ручний, а саме налаштування — рішення
мейнтейнера; `docs/RELEASING.md` описує його як наступний крок.

---

## Global Constraints

- SDK: `sdk: ^3.8.0` у кожному pubspec, також у прикладі; жодних можливостей
  Dart 3.10+ (dot shorthands, null-aware elements), жодних primary
  constructors.
- Жодних кроків назовні: ні `dart pub publish` (лише `--dry-run`), ні
  `git push`, ні `git tag`, ні `git remote add`, ні створення репозиторію.
- Версія всіх членів workspace — `0.1.0`; кожне обмеження між ними —
  `^0.1.0`.
- `dart pub publish --dry-run` кожного з семи пакетів: `Package has 0
  warnings.` і код виходу 0 (будь-яке попередження дає 65).
- Код, doc-коментарі, README і `docs/*.md` — англійською; плани, спека,
  ROADMAP — українською.
- `CLAUDE.md`: ≤300 рядків на файл `lib/`, ≤500 на тест, ≤40 рядків на
  метод, один публічний клас на файл, `///` на кожному public, без `!`,
  `dynamic`, `late` без коментаря, `catch` лише з `on`.
- Тести без мережі; HTTP — ефемерний порт на loopback; тимчасові файли лише
  через `TempDir`.
- `lib/tasks_api.dartnest.dart` не редагується руками: лише
  `dart run dartnest_cli gen` у `example/`.
- `dart format packages example` змінює 0 файлів; `dart analyze` у корені
  друкує `No issues found!`.

## Review Focus

1. **Застарілий згенерований файл прикладу.** Хтось змінює анотацію в
   `example/lib/src/**` і не перегенеровує файл. Очікувано: `dart test`
   падає. Закріплено `example/test/generated_library_test.dart` (Task 2,
   крок «golden падає на застарілому файлі»).
2. **Документація, що бреше.** Сніпет у README не компілюється або
   описує поведінку, якої немає. Очікувано: кожен повний сніпет справді
   запускається. Task 6 витягує quick start і `getting-started` у
   тимчасовий пакет і запускає їх. Task 7 перевіряє обмеження FAQ
   відтворенням (див. «Самоперевірка»).
3. **Архів пакета містить зайве або «секрет».** Очікувано: dry-run без
   помилок; тестовий self-signed ключ позначено `false_secrets`, не
   видалено (Task 1, Task 8).
4. **Порт зайнятий або тест іде в мережу.** e2e слухає
   `InternetAddress.loopbackIPv4` на порту 0 і бере порт з адаптера.
   Очікувано: тести паралельно з іншим сервером на 8080 не падають
   (`example/test/helpers/loopback_server.dart`, Task 3).
5. **Користувач іде за README до публікації.** `dart pub get` не
   знайде `^0.1.0` на pub.dev. Очікувано: README CLI дає
   `dependency_overrides`-сніпет (Task 1), а RELEASING — перевірку
   `init` проти pub.dev після випуску (Task 8).

---

## File Structure

```text
LICENSE                                         # NEW (T1) MIT
packages/<7 published>/LICENSE                  # NEW (T1) копії кореневого
packages/<7 published>/analysis_options.yaml    # MOD (T1) самодостатні + public_member_api_docs
packages/<7 published>/pubspec.yaml             # MOD (T1) 0.1.0, repository, issue_tracker, topics
packages/dartnest_conformance/pubspec.yaml      # MOD (T1) 0.1.0
packages/dartnest_generator/test/fixtures/*/pubspec.yaml  # MOD (T1) 0.1.0
packages/dartnest_cli/README.md                 # MOD (T1) dependency_overrides замість «0.1.0-dev»
packages/dartnest_build/README.md               # MOD (T1) ^0.1.0
pubspec.yaml                                    # MOD (T2) workspace: + example
example/                                        # NEW (T2, T3) tasks_api
  pubspec.yaml, analysis_options.yaml, README.md
  bin/main.dart                                 # T3: --explicit, --shelf, PORT
  lib/tasks_api.dart                            # бар'єр
  lib/tasks_api.dartnest.dart                   # згенеровано `dartnest_cli gen`, закомічено
  lib/explicit.dart                             # T3: той самий граф явним API
  lib/src/{config,auth,tasks,health,common,server}/*.dart
  test/{generated_library,in_process,tasks_service,e2e,server_options}_test.dart
  test/helpers/{temp_dir,workspace_package_config,example_sources,loopback_server,api_response}.dart
packages/dartnest/example/dartnest_example.dart # MOV+MOD (T4) з di_example.dart, + HTTP
packages/dartnest/test/example_test.dart        # MOV+MOD (T4) з test/di/example_test.dart
packages/dartnest/README.md                     # MOD (T4) таблиця пакетів, без «planned»
packages/dartnest_io/example/dartnest_io_example.dart        # NEW (T4)
packages/dartnest_shelf/example/dartnest_shelf_example.dart  # NEW (T4)
packages/dartnest_{io,shelf}/test/example_test.dart          # NEW (T4)
packages/dartnest_annotations/example/README.md # NEW (T4)
packages/dartnest_generator/example/dartnest_generator_example.dart  # NEW (T5)
packages/dartnest_generator/test/example_test.dart           # NEW (T5)
packages/dartnest_{cli,build}/example/README.md # NEW (T5)
packages/<7 published>/CHANGELOG.md             # NEW (T4, T5)
packages/dartnest_cli/lib/src/cli/interruption.dart  # MOD (T5) dartdoc-посилання
README.md                                       # NEW (T6)
docs/{getting-started,modules-and-di,controllers-and-pipeline,annotations-and-codegen,adapters}.md  # NEW (T6)
docs/{dev-mode,build-runner,testing,faq}.md     # NEW (T7)
docs/RELEASING.md                               # NEW (T8)
.github/workflows/ci.yaml                       # NEW (T8)
CLAUDE.md, docs/superpowers/ROADMAP.md, docs/superpowers/specs/2026-10-13-dartnest-design.md  # MOD (T8)
```

Очікувані кількості тестів після плану (база в дужках): `dartnest` +276
(274), `dartnest_annotations` +6, `dartnest_io` +47 (46), `dartnest_shelf`
+68 (67), `dartnest_conformance` +14, `dartnest_generator` +172 (171),
`dartnest_cli` +136, `dartnest_build` +18, `example` +54 (новий);
integration: `dartnest_cli` +5, `dartnest_build` +1; benchmark +1.

Команди нижче — з кореня репозиторію, якщо не сказано інше. Спершу
`export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`.

---

### Task 1: Метадані випуску 0.1.0

**Files:**
- Create: `LICENSE`, `packages/{dartnest,dartnest_annotations,dartnest_io,dartnest_shelf,dartnest_generator,dartnest_cli,dartnest_build}/LICENSE`
- Modify: `pubspec.yaml` сімох публікованих пакетів, `packages/dartnest_conformance/pubspec.yaml`, `packages/dartnest_generator/test/fixtures/{cases_app,users_app}/pubspec.yaml`
- Modify: `analysis_options.yaml` сімох публікованих пакетів
- Modify: `packages/dartnest_cli/README.md`, `packages/dartnest_build/README.md`

**Interfaces:**
- Consumes: —
- Produces: версія `0.1.0` і `^0.1.0` між членами workspace (Tasks 2–8
  пишуть `^0.1.0`); URL `https://github.com/4akLoon/dartnest` (Task 8 —
  RELEASING); `public_member_api_docs` у публікованих пакетах (кожен новий
  public-член у Tasks 4–5 має `///`).

- [ ] **Step 1: Зафіксувати, що dry-run зараз не проходить**

Run: `cd packages/dartnest_io && dart pub publish --dry-run; echo "exit=$?"`
Expected: exit 65. Серед проблем:
- відсутній `LICENSE`;
- `test/fixtures/localhost_key.pem` схожий на приватний ключ;
- немає `homepage`/`repository`;
- немає `CHANGELOG.md`.

У `dartnest_generator` ще 21 попередження: файли
`test/fixtures/**` імпортують `dartnest_annotations`, якої немає в
залежностях пакета.

- [ ] **Step 2: Підняти версію всіх членів workspace**

**Виконати з кореня репозиторію:**

```sh
sed -i 's/0\.1\.0-dev/0.1.0/g' packages/*/pubspec.yaml packages/dartnest_generator/test/fixtures/*/pubspec.yaml
```

- [ ] **Step 3: Метадані публікованих пакетів**

`publish_to: none` прибирається. Додаються `repository` (тека пакета),
`issue_tracker` і `topics` (≤5, лише `[a-z0-9-]`). Опис `dartnest_io`
подовжено до 60–180 символів (діапазон pana). `false_secrets` позначає
тестовий ключ. `dartnest_generator` отримує dev-залежність
`dartnest_annotations` для своїх fixture-файлів.

**Замінити повністю `packages/dartnest/pubspec.yaml`:**

```yaml
name: dartnest
description: NestJS-style modular backend framework for Dart without dart:mirrors.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [server, backend, framework, dependency-injection, http]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  meta: ^1.16.0
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

**Замінити повністю `packages/dartnest_annotations/pubspec.yaml`:**

```yaml
name: dartnest_annotations
description: >-
  Annotations for dartnest applications; dartnest_generator turns them into
  the explicit dartnest API. No dependencies.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_annotations
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [server, framework, annotations, codegen]
environment:
  sdk: ^3.8.0
resolution: workspace
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

**Замінити повністю `packages/dartnest_io/pubspec.yaml`:**

```yaml
name: dartnest_io
description: >-
  dart:io HttpServer adapter for dartnest applications: streaming bodies both
  ways, graceful close with a timeout, HTTPS through a SecurityContext.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_io
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [server, http, framework]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0
dev_dependencies:
  dartnest_conformance: ^0.1.0
  lints: ^5.1.0
  test: ^1.25.0
# A self-signed certificate for the HTTPS test, not a secret.
false_secrets:
  - /test/fixtures/localhost_key.pem
```

**Замінити повністю `packages/dartnest_shelf/pubspec.yaml`:**

```yaml
name: dartnest_shelf
description: shelf adapter for dartnest applications, and a shelf Handler to embed one in an existing shelf pipeline.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_shelf
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [server, http, shelf, framework]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0
  shelf: ^1.4.2
dev_dependencies:
  dartnest_conformance: ^0.1.0
  lints: ^5.1.0
  test: ^1.25.0
```

**Замінити повністю `packages/dartnest_generator/pubspec.yaml`:**

```yaml
name: dartnest_generator
description: >-
  Turns dartnest annotations into ordinary code on the explicit dartnest API,
  with static validation of the module graph.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_generator
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [codegen, analyzer, server, framework]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  code_builder: ^4.11.1
  dart_style: ^3.1.2
  path: ^1.9.0
  pub_semver: ^2.1.4
dev_dependencies:
  cases_app: ^0.1.0
  dartnest: ^0.1.0
  # The fixture packages under test/fixtures import the annotations.
  dartnest_annotations: ^0.1.0
  lints: ^5.1.0
  test: ^1.25.0
  users_app: ^0.1.0
```

**Замінити повністю `packages/dartnest_cli/pubspec.yaml`:**

```yaml
name: dartnest_cli
description: >-
  Command line tool of dartnest: generates the code of annotated packages
  (gen, gen --watch), runs them with hot reload (dev) and scaffolds new
  applications (init).
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_cli
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [cli, codegen, hot-reload, server]
environment:
  sdk: ^3.8.0
resolution: workspace
executables:
  dartnest: dartnest_cli
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  args: ^2.7.0
  dartnest_generator: ^0.1.0
  path: ^1.9.0
  vm_service: ^15.2.0
  watcher: ^1.2.1
  yaml: ^3.1.3
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

**Замінити повністю `packages/dartnest_build/pubspec.yaml`:**

```yaml
name: dartnest_build
description: >-
  The build_runner builder of dartnest: writes lib/<package>.dartnest.dart
  from the annotations of a package, byte for byte what dartnest_cli gen
  writes.
version: 0.1.0
repository: https://github.com/4akLoon/dartnest/tree/master/packages/dartnest_build
issue_tracker: https://github.com/4akLoon/dartnest/issues
topics: [build-runner, codegen, server]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  build: ^4.0.2
  dartnest_generator: ^0.1.0
  glob: ^2.1.0
dev_dependencies:
  build_test: ^3.5.0
  dartnest_cli: ^0.1.0
  lints: ^5.1.0
  path: ^1.9.0
  test: ^1.25.0
  yaml: ^3.1.0
```

- [ ] **Step 4: LICENSE**

**Створити `LICENSE`:**

```text
MIT License

Copyright (c) 2026 Yevhenii Aleksiuk

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Виконати з кореня репозиторію:**

```sh
for p in dartnest dartnest_annotations dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do cp LICENSE "packages/$p/LICENSE"; done
```

- [ ] **Step 5: Самодостатні `analysis_options.yaml`**

**Замінити повністю `packages/dartnest/analysis_options.yaml`:**

```yaml
# Self-contained, not `include: ../../analysis_options.yaml`: the published
# package has no parent directory, and pub.dev analyzes it with this file.
include: package:lints/recommended.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
linter:
  rules:
    - public_member_api_docs
```

**Виконати з кореня репозиторію:**

```sh
for p in dartnest_annotations dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do cp packages/dartnest/analysis_options.yaml "packages/$p/analysis_options.yaml"; done
```

- [ ] **Step 6: README, що згадують `0.1.0-dev`**

**Замінити в `packages/dartnest_cli/README.md`:**

```markdown

The scaffold depends on `dartnest`, `dartnest_annotations`, `dartnest_io`
and `dartnest_cli` at `^0.1.0`. The workspace packages are `0.1.0-dev`, so
`dart pub get` resolves them only once 0.1.0 is published.

## Exit codes
```

**на:**

~~~~markdown

The scaffold depends on `dartnest`, `dartnest_annotations`, `dartnest_io`
and `dartnest_cli` at `^0.1.0`. To try it against a checkout of the
repository instead of pub.dev, add to its `pubspec.yaml` (with your path):

```yaml
dependency_overrides:
  dartnest: {path: ../dartnest/packages/dartnest}
  dartnest_annotations: {path: ../dartnest/packages/dartnest_annotations}
  dartnest_cli: {path: ../dartnest/packages/dartnest_cli}
  dartnest_generator: {path: ../dartnest/packages/dartnest_generator}
  dartnest_io: {path: ../dartnest/packages/dartnest_io}
```

## Exit codes
~~~~

**Замінити в `packages/dartnest_build/README.md`:**

~~~~markdown
dev_dependencies:
  build_runner: ^2.10.5
  dartnest_build: ^0.1.0-dev
```

~~~~

**на:**

~~~~markdown
dev_dependencies:
  build_runner: ^2.10.5
  dartnest_build: ^0.1.0
```

~~~~

- [ ] **Step 7: Перевірити**

Run: `dart pub get && dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`. Новий lint
`public_member_api_docs` не дає жодного повідомлення.

Run: `for d in packages/*/; do (cd "$d" && dart test 2>&1 | tail -1); done`
Expected: кількості як у базі (`dartnest` +274, `dartnest_annotations` +6,
`dartnest_io` +46, `dartnest_shelf` +67, `dartnest_conformance` +14,
`dartnest_generator` +171, `dartnest_cli` +136, `dartnest_build` +18), усі
`All tests passed!`.

- [ ] **Step 8: Commit**

```bash
git add LICENSE packages
git commit -m "chore: release metadata for 0.1.0"
```

Run (після commit, бо dry-run попереджає про незакомічені файли):
`for p in dartnest_annotations dartnest dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do (cd packages/$p && dart pub publish --dry-run 2>&1 | grep -E '^\* |Package has'); done`
Expected: у кожного пакета рівно одне попередження «Please add a
`CHANGELOG.md` to your package» (`CHANGELOG.md` додають Tasks 4–5).

---

### Task 2: Приклад — API задач на анотаціях, згенерований CLI

**Files:**
- Modify: `pubspec.yaml` (кореневий `workspace:`)
- Create: `example/pubspec.yaml`, `example/analysis_options.yaml`
- Create: `example/test/helpers/temp_dir.dart`, `example/test/helpers/workspace_package_config.dart`, `example/test/helpers/example_sources.dart`
- Create: `example/test/generated_library_test.dart`, `example/test/in_process_test.dart`, `example/test/tasks_service_test.dart`
- Create: `example/lib/tasks_api.dart`, `example/lib/src/**` (24 файли, список у Step 4)
- Create (генерується): `example/lib/tasks_api.dartnest.dart`

**Interfaces:**
- Consumes: `^0.1.0` (Task 1); `GenerationSession`, `PackageRoot`,
  `DartnestGenerator.core()` з `package:dartnest_cli/...` (етап 5);
  `TestClient` (`package:dartnest/testing.dart`).
- Produces (Task 3 і документація використовують ці імена):
  - `appName` (`Token<String>`), `apiKeys` (`Token<Map<String, Role>>`),
    `demoApiKeys`; ключі `reader-key`/`editor-key`.
  - `enum Role { reader, editor }`; `Roles extends RouteMetadata`
    (`allowed`).
  - `ApiKeys`, `ApiKeyGuard` (`roleItem = #role`), `RolesGuard`.
  - `Task`, `CreateTaskDto`, `UpdateTaskDto`, `TaskStore`,
    `InMemoryTaskStore`, `TaskNotFound`, `TaskNotFoundFilter`,
    `TasksService`, `TasksController`.
  - `HealthController(String name)`, `TrimStringsPipe`,
    `TimingInterceptor`, `RequestIdMiddleware`.
  - `abstract final class TasksApp` з
    `static Future<Application> create(Module Function() root, {HttpAdapter? adapter, ErrorLogger? onError})`.
  - Модулі `ConfigModule` (`config`, global), `AuthModule` (`auth`),
    `TasksModule` (`tasks`), `HealthModule` (`health`), `AppModule`
    (`app`). Згенеровано `Module appModule()`.
  - Тестові хелпери `TempDir`, `WorkspacePackageConfig`,
    `ExampleSources`.

Приклад показує кожну частину фреймворку:
- глобальний модуль з токенами й `Value`;
- модулі з imports/exports;
- `Bind<TaskStore, InMemoryTaskStore>`;
- `@Inject(token)`;
- контролер з `@Param`/`@Query`/`@Body` і DTO;
- ланцюжок guards з метаданими маршруту;
- pipe, interceptor на рівні застосунку, exception filter, middleware.

`TempDir` і `WorkspacePackageConfig` — копії хелперів `dartnest_build`:
тест прикладу не може імпортувати `test/` іншого пакета.

- [ ] **Step 1: Додати приклад у workspace**

**Замінити в `pubspec.yaml`:**

```yaml
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
```

**на:**

```yaml
  sdk: ^3.8.0
workspace:
  - example
  - packages/dartnest
  - packages/dartnest_annotations
```

**Створити `example/pubspec.yaml`:**

```yaml
name: tasks_api
description: The dartnest example application, a small tasks API; see README.md.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0

dev_dependencies:
  dartnest_cli: ^0.1.0
  lints: ^5.1.0
  path: ^1.9.0
  test: ^1.25.0
```

**Створити `example/analysis_options.yaml`:**

```yaml
include: ../analysis_options.yaml
```

- [ ] **Step 2: Тести (спершу)**

**Створити `example/test/helpers/temp_dir.dart`:**

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
    final directory = Directory.systemTemp.createTempSync('tasks_api_');
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

**Створити `example/test/helpers/workspace_package_config.dart`:**

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

**Створити `example/test/helpers/example_sources.dart`:**

```dart
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The `lib/` of this example package, read from the checkout.
abstract final class ExampleSources {
  /// The generated library the CLI writes, relative to the package root.
  static const generatedLibrary = 'lib/tasks_api.dartnest.dart';

  /// Every file of `lib/` except [generatedLibrary], by path relative to
  /// the package root with `/` separators (`lib/src/tasks/task.dart`).
  static Future<Map<String, String>> files() async {
    final lib = await _lib();
    return {
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (_path(lib, file) case final path when path != generatedLibrary)
          path: file.readAsStringSync(),
    };
  }

  /// The committed [generatedLibrary].
  static Future<String> committedLibrary() async {
    final lib = await _lib();
    return File(p.join(lib.parent.path, generatedLibrary)).readAsStringSync();
  }

  static Future<Directory> _lib() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:tasks_api/'),
    );
    if (uri == null) {
      throw StateError('tasks_api is not in the package config.');
    }
    return Directory.fromUri(uri);
  }

  static String _path(Directory lib, File file) => p.posix.joinAll([
    'lib',
    ...p.split(p.relative(file.path, from: lib.path)),
  ]);
}
```

**Створити `example/test/generated_library_test.dart`:**

```dart
// The committed lib/tasks_api.dartnest.dart is what `dartnest gen` writes
// for the current sources. After changing an annotated class, regenerate:
//   dart run dartnest_cli gen
import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:test/test.dart';

import 'helpers/example_sources.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

void main() {
  test('the committed generated library is up to date', () async {
    final copy = TempDir.create();
    copy.write(
      'pubspec.yaml',
      'name: tasks_api\nenvironment:\n  sdk: ^3.8.0\n',
    );
    (await ExampleSources.files()).forEach(copy.write);
    await WorkspacePackageConfig.write(copy.path, 'tasks_api');
    final session = GenerationSession(PackageRoot.open(copy.path));
    addTearDown(session.close);

    final report = await session.run();

    expect(report.problemLines, isEmpty);
    expect(
      File(copy.resolve(ExampleSources.generatedLibrary)).readAsStringSync(),
      await ExampleSources.committedLibrary(),
      reason: 'Run `dart run dartnest_cli gen` in example/ and commit.',
    );
  });
}
```

**Створити `example/test/in_process_test.dart`:**

```dart
// Without a server: TestClient sends requests straight to app.handle, the
// fastest way to test routes, guards and filters.
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.dartnest.dart';
import 'package:test/test.dart';

void main() {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set together with app.

  setUp(() async {
    app = await TasksApp.create(appModule);
    client = TestClient(app);
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

  test(
    'providers are singletons: a delete is seen by the next request',
    () async {
      await client.delete('/tasks/1', headers: {'x-api-key': 'editor-key'});

      final list = await client.get(
        '/tasks',
        headers: {'x-api-key': 'reader-key'},
      );
      expect(list.json, [
        {'id': 2, 'title': 'Run dartnest dev', 'done': true},
      ]);
    },
  );
}
```

**Створити `example/test/tasks_service_test.dart`:**

```dart
// Unit tests: the service is a plain class, and a test module written with
// the explicit API swaps the store for a fake, even though the application
// itself is wired with annotations.
import 'package:dartnest/dartnest.dart';
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

void main() {
  test('list filters by state', () {
    final service = TasksService(InMemoryTaskStore());

    expect(service.list(done: false).map((task) => task.id), [1]);
    expect(service.list().map((task) => task.id), [1, 2]);
  });

  test('update changes only the given fields', () {
    final service = TasksService(InMemoryTaskStore());

    final task = service.update(2, const UpdateTaskDto(title: 'Run it again'));

    expect(task.toJson(), {'id': 2, 'title': 'Run it again', 'done': true});
  });

  test('a test module provides a fake store through DI', () async {
    final container = await Container.create(
      Module(
        id: 'test',
        providers: [
          Provider<TaskStore>((i) => _EmptyStore()),
          Provider((i) => TasksService(i.get())),
        ],
      ),
    );
    addTearDown(container.close);
    final service = container.root.get<TasksService>();

    expect(service.list(), isEmpty);
    expect(() => service.find(1), throwsA(isA<TaskNotFound>()));
    expect(() => service.delete(1), throwsA(isA<TaskNotFound>()));
  });
}
```

- [ ] **Step 3: Переконатися, що тести падають**

Run: `dart pub get && cd example && dart test`
Expected: FAIL під час компіляції: `package:tasks_api/tasks_api.dart` не
існує.

- [ ] **Step 4: Застосунок**

**Створити `example/lib/tasks_api.dart`:**

```dart
/// The tasks API of the dartnest example, written with annotations; the
/// module graph is `appModule` in `tasks_api.dartnest.dart`, generated by
/// `dart run dartnest_cli gen`.
library;

export 'src/app_module.dart';
export 'src/auth/api_key_guard.dart';
export 'src/auth/api_keys.dart';
export 'src/auth/auth_module.dart';
export 'src/auth/role.dart';
export 'src/auth/roles.dart';
export 'src/auth/roles_guard.dart';
export 'src/common/request_id_middleware.dart';
export 'src/common/timing_interceptor.dart';
export 'src/common/trim_strings_pipe.dart';
export 'src/config/config_module.dart';
export 'src/health/health_controller.dart';
export 'src/health/health_module.dart';
export 'src/server/tasks_app.dart';
export 'src/tasks/create_task_dto.dart';
export 'src/tasks/in_memory_task_store.dart';
export 'src/tasks/task.dart';
export 'src/tasks/task_not_found.dart';
export 'src/tasks/task_not_found_filter.dart';
export 'src/tasks/task_store.dart';
export 'src/tasks/tasks_controller.dart';
export 'src/tasks/tasks_module.dart';
export 'src/tasks/tasks_service.dart';
export 'src/tasks/update_task_dto.dart';
```

**Створити `example/lib/src/config/config_module.dart`:**

```dart
// Configuration every module sees: the application name and the API keys.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../auth/role.dart';

/// The name the health check reports.
const appName = Token<String>('config.app_name');

/// The API keys and the role each one grants.
const apiKeys = Token<Map<String, Role>>('config.api_keys');

/// The keys of the example; a real application reads them from a secret
/// store.
const demoApiKeys = {'reader-key': Role.reader, 'editor-key': Role.editor};

/// Configuration values, visible in every module (`global: true`).
@Module(
  id: 'config',
  providers: [
    Value('tasks_api', token: appName),
    Value(demoApiKeys, token: apiKeys),
  ],
  exports: [appName, apiKeys],
  global: true,
)
final class ConfigModule {}
```

**Створити `example/lib/src/auth/role.dart`:**

```dart
/// What a caller may do.
enum Role {
  /// Reads tasks.
  reader,

  /// Reads, creates, changes and deletes tasks.
  editor,
}
```

**Створити `example/lib/src/auth/roles.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'role.dart';

/// Route metadata: the roles allowed to call a handler. `RolesGuard` reads
/// it.
final class Roles extends RouteMetadata {
  /// Allows [allowed].
  const Roles(this.allowed);

  /// The allowed roles.
  final List<Role> allowed;
}
```

**Створити `example/lib/src/auth/api_keys.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../config/config_module.dart';
import 'role.dart';

/// Looks up the role an API key grants.
@Injectable()
final class ApiKeys {
  /// Reads the keys from the [apiKeys] configuration value.
  ApiKeys(@Inject(apiKeys) this._roles);

  final Map<String, Role> _roles;

  /// The role [key] grants, or `null` for an unknown key.
  Role? roleOf(String key) => _roles[key];
}
```

**Створити `example/lib/src/auth/api_key_guard.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'api_keys.dart';
import 'role.dart';

/// Lets a request through when its `x-api-key` header is a known key, and
/// stores the key's role for the guards after it.
@Injectable()
final class ApiKeyGuard implements Guard {
  /// Checks keys with [keys].
  ApiKeyGuard(this.keys);

  /// The known keys.
  final ApiKeys keys;

  /// The `ExecutionContext.items` key of the caller's [Role].
  static const roleItem = #role;

  @override
  bool canActivate(ExecutionContext context) {
    final key = context.header('x-api-key');
    final role = key == null ? null : keys.roleOf(key);
    if (role == null) {
      throw const UnauthorizedException(message: 'Send a valid x-api-key.');
    }
    context.items[roleItem] = role;
    return true;
  }
}
```

**Створити `example/lib/src/auth/roles_guard.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'api_key_guard.dart';
import 'roles.dart';

/// Allows a handler only for the roles in its [Roles] metadata; runs after
/// [ApiKeyGuard], which stores the caller's role. A handler without
/// [Roles] is allowed for every caller.
@Injectable()
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null ||
        roles.allowed.contains(context.items[ApiKeyGuard.roleItem]);
  }
}
```

**Створити `example/lib/src/auth/auth_module.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'api_key_guard.dart';
import 'api_keys.dart';
import 'roles_guard.dart';

/// API keys and the guards that check them; modules that protect routes
/// import it.
@Module(
  id: 'auth',
  providers: [ApiKeys, ApiKeyGuard, RolesGuard],
  exports: [ApiKeyGuard, RolesGuard],
)
final class AuthModule {}
```

**Створити `example/lib/src/tasks/task.dart`:**

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

  /// The JSON form; dartnest serializes results through `toJson()`.
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};
}
```

**Створити `example/lib/src/tasks/create_task_dto.dart`:**

```dart
/// The body of `POST /tasks`.
final class CreateTaskDto {
  /// Creates the body.
  const CreateTaskDto(this.title);

  /// Reads the body; a missing, empty or too long title is a
  /// [FormatException], which dartnest answers with 400.
  factory CreateTaskDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'title': final String title}
        when title.isNotEmpty && title.length <= maxTitleLength =>
      CreateTaskDto(title),
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

**Створити `example/lib/src/tasks/update_task_dto.dart`:**

```dart
import 'create_task_dto.dart';

/// The body of `PATCH /tasks/:id`: the fields to change.
final class UpdateTaskDto {
  /// Creates the body.
  const UpdateTaskDto({this.title, this.done});

  /// Reads the body; a field of the wrong type is a [FormatException]
  /// (400).
  factory UpdateTaskDto.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final done = json['done'];
    final validTitle =
        title == null ||
        title is String &&
            title.isNotEmpty &&
            title.length <= CreateTaskDto.maxTitleLength;
    if (!validTitle || (done != null && done is! bool)) {
      throw const FormatException(
        '"title" must be a non-empty string and "done" a boolean',
      );
    }
    return UpdateTaskDto(title: title as String?, done: done as bool?);
  }

  /// The new title, or `null` to keep it.
  final String? title;

  /// The new state, or `null` to keep it.
  final bool? done;
}
```

**Створити `example/lib/src/tasks/task_store.dart`:**

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

**Створити `example/lib/src/tasks/in_memory_task_store.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'task.dart';
import 'task_store.dart';

/// A [TaskStore] in memory, starting with two tasks. Its state survives a
/// hot reload, because dartnest keeps provider instances.
@Injectable()
final class InMemoryTaskStore implements TaskStore {
  final Map<int, Task> _tasks = {
    1: const Task(id: 1, title: 'Read the dartnest README'),
    2: const Task(id: 2, title: 'Run dartnest dev', done: true),
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

**Створити `example/lib/src/tasks/task_not_found.dart`:**

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

**Створити `example/lib/src/tasks/task_not_found_filter.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'task_not_found.dart';

/// Answers [TaskNotFound] with 404, so the service stays free of HTTP.
@Injectable()
final class TaskNotFoundFilter extends ExceptionFilter<TaskNotFound> {
  @override
  Object? handle(TaskNotFound error, ExecutionContext context) =>
      throw NotFoundException(message: 'No task ${error.id}.');
}
```

**Створити `example/lib/src/tasks/tasks_service.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'create_task_dto.dart';
import 'task.dart';
import 'task_not_found.dart';
import 'task_store.dart';
import 'update_task_dto.dart';

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
  Task create(CreateTaskDto dto) => store.add(dto.title);

  /// Changes the fields of task [id] that [dto] gives; throws
  /// [TaskNotFound].
  Task update(int id, UpdateTaskDto dto) {
    final task = find(id).copyWith(title: dto.title, done: dto.done);
    store.replace(task);
    return task;
  }

  /// Deletes task [id]; throws [TaskNotFound].
  void delete(int id) {
    if (!store.remove(id)) throw TaskNotFound(id);
  }
}
```

**Створити `example/lib/src/tasks/tasks_controller.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../auth/api_key_guard.dart';
import '../auth/role.dart';
import '../auth/roles.dart';
import '../auth/roles_guard.dart';
import '../common/trim_strings_pipe.dart';
import 'create_task_dto.dart';
import 'task.dart';
import 'task_not_found_filter.dart';
import 'tasks_service.dart';
import 'update_task_dto.dart';

/// `/tasks`: every route needs an API key; changes need the editor role.
@Controller('/tasks')
@UseGuards([ApiKeyGuard])
@UsePipes([TrimStringsPipe])
@UseFilters([TaskNotFoundFilter])
final class TasksController {
  /// Serves [service].
  TasksController(this.service);

  /// The use cases.
  final TasksService service;

  /// `GET /tasks`, optionally `?done=true` or `?done=false`.
  @Get()
  List<Task> list(@Query('done') bool? done) => service.list(done: done);

  /// `GET /tasks/:id`.
  @Get('/:id')
  Task find(@Param('id') int id) => service.find(id);

  /// `POST /tasks`: 201 with the new task and its `location`.
  @Post()
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task create(@Body() CreateTaskDto dto, ExecutionContext context) {
    final task = service.create(dto);
    context.switchToHttp().response
      ..status = StatusCode.created
      ..headers.set('location', '/tasks/${task.id}');
    return task;
  }

  /// `PATCH /tasks/:id`: changes the title or the state.
  @Patch('/:id')
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task update(@Param('id') int id, @Body() UpdateTaskDto dto) =>
      service.update(id, dto);

  /// `DELETE /tasks/:id`: 204.
  @Delete('/:id')
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  void delete(@Param('id') int id) => service.delete(id);
}
```

**Створити `example/lib/src/tasks/tasks_module.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../auth/auth_module.dart';
import '../common/trim_strings_pipe.dart';
import 'in_memory_task_store.dart';
import 'task_not_found_filter.dart';
import 'task_store.dart';
import 'tasks_controller.dart';
import 'tasks_service.dart';

/// Tasks: the store, the service, the controller and its components.
@Module(
  id: 'tasks',
  imports: [AuthModule],
  providers: [
    Bind<TaskStore, InMemoryTaskStore>(),
    TasksService,
    TrimStringsPipe,
    TaskNotFoundFilter,
  ],
  controllers: [TasksController],
)
final class TasksModule {}
```

**Створити `example/lib/src/health/health_controller.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../config/config_module.dart';

/// `GET /health`, public: whether the application answers.
@Controller('/health')
final class HealthController {
  /// Reports [name].
  HealthController(@Inject(appName) this.name);

  /// The application name from the configuration.
  final String name;

  /// The status and the application name.
  @Get()
  Map<String, String> check() => {'status': 'ok', 'name': name};
}
```

**Створити `example/lib/src/health/health_module.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'health_controller.dart';

/// The health check; its `appName` comes from the global `ConfigModule`.
@Module(id: 'health', controllers: [HealthController])
final class HealthModule {}
```

**Створити `example/lib/src/common/trim_strings_pipe.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Trims surrounding whitespace from string arguments and from the string
/// fields of a JSON object body, before they are converted or decoded.
///
/// Pipes in `Enhancers` (or `@UsePipes`) see every argument of every
/// handler they apply to, so this one passes other values through.
@Injectable()
final class TrimStringsPipe implements Pipe<Object?, Object?> {
  @override
  Object? transform(Object? value, ArgumentMeta meta) => switch (value) {
    final String text => text.trim(),
    final Map<String, Object?> json => {
      for (final MapEntry(:key, :value) in json.entries)
        key: value is String ? value.trim() : value,
    },
    _ => value,
  };
}
```

**Створити `example/lib/src/common/timing_interceptor.dart`:**

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Adds `server-timing: handler;dur=<ms>` to every routed response: the
/// time the pipes and the handler took (guards run before interceptors).
/// Registered for the whole application in `TasksApp.enhancers`.
@Injectable()
final class TimingInterceptor implements Interceptor {
  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await next();
    } finally {
      final milliseconds = stopwatch.elapsedMicroseconds / 1000;
      context.switchToHttp().response.headers.set(
        'server-timing',
        'handler;dur=${milliseconds.toStringAsFixed(1)}',
      );
    }
  }
}
```

**Створити `example/lib/src/common/request_id_middleware.dart`:**

```dart
import 'package:dartnest/dartnest.dart';

/// HTTP middleware: answers every request, routed or not, with an
/// `x-request-id` header, the caller's own or `req-<n>`.
final class RequestIdMiddleware {
  int _count = 0;

  /// Runs [next] and adds the id to its response; pass the tear-off to
  /// `Application.use`.
  Future<HttpResponse> call(
    HttpRequest request,
    Next<HttpResponse> next,
  ) async {
    final id = request.headers['x-request-id'] ?? 'req-${++_count}';
    final response = await next();
    return response.mergeHeaders(HeaderMap.of({'x-request-id': id}));
  }
}
```

**Створити `example/lib/src/server/tasks_app.dart`:**

```dart
import 'package:dartnest/dartnest.dart';

import '../common/request_id_middleware.dart';
import '../common/timing_interceptor.dart';

/// Creates the tasks application the same way for both styles, every
/// adapter and the tests.
abstract final class TasksApp {
  /// The application-level components; resolved from the root module.
  static const enhancers = Enhancers(interceptors: [Use<TimingInterceptor>()]);

  /// Creates the application for [root] (`appModule` from the generated
  /// library or `explicitAppModule`), served by [adapter] if given.
  /// [onError] receives unexpected errors (default: print).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    ErrorLogger? onError,
  }) async {
    final app = await Application.create(
      root,
      adapter: adapter,
      enhancers: enhancers,
      onError: onError,
    );
    app.use(RequestIdMiddleware().call);
    return app;
  }
}
```

**Створити `example/lib/src/app_module.dart`:**

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'common/timing_interceptor.dart';
import 'config/config_module.dart';
import 'health/health_module.dart';
import 'tasks/tasks_module.dart';

/// The application root. [TimingInterceptor] is provided here because
/// application-level components resolve from the root module.
@Module(
  id: 'app',
  imports: [ConfigModule, TasksModule, HealthModule],
  providers: [TimingInterceptor],
)
final class AppModule {}
```

- [ ] **Step 5: Згенерувати бібліотеку CLI**

**Виконати з кореня репозиторію:**

```sh
cd example && dart run dartnest_cli gen
```

Expected: `Generated lib/tasks_api.dartnest.dart in N ms.` Файл має 167
рядків і починається з `// GENERATED BY dartnest_generator. DO NOT EDIT.`.
Руками його не правити.

- [ ] **Step 6: Тести проходять**

Run: `cd example && dart test`
Expected: `+6: All tests passed!`

Run: `dart analyze && dart format --output=none --set-exit-if-changed example packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 7: Golden падає на застарілому файлі (Review Focus 1)**

Run: `cd example && sed -i "s#@Controller('/health')#@Controller('/status')#" lib/src/health/health_controller.dart && dart test test/generated_library_test.dart; git checkout lib/src/health/health_controller.dart && dart test test/generated_library_test.dart`
Expected: перший запуск FAIL: `Expected: '// GENERATED BY dartnest_generator. DO NOT EDIT.\n' ...`,
рядки закоміченого файлу проти згенерованого. Після `git checkout` —
`+1: All tests passed!`. Зміна, через яку генератор видає діагностику
(наприклад, `@Get('/:taskId')` при `@Param('id')`), теж валить тест:
`Expected: empty`, у `Actual` діагностика `[unknown_path_parameter]`.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml example
git commit -m "feat(example): the tasks API in annotations, generated by the CLI"
```

---

### Task 3: Приклад — явний двійник, обидва адаптери, `bin/main.dart`

**Files:**
- Modify: `example/pubspec.yaml` (+ `dartnest_io`, `dartnest_shelf`), `example/lib/tasks_api.dart` (+ експорти server)
- Create: `example/lib/explicit.dart`, `example/lib/src/server/{module_style,adapter_kind,server_options}.dart`, `example/bin/main.dart`
- Create: `example/test/helpers/{loopback_server,api_response}.dart`, `example/test/e2e_test.dart`, `example/test/server_options_test.dart`
- Create: `example/README.md`

**Interfaces:**
- Consumes: усе з Task 2; `IoAdapter` (`dartnest_io`), `ShelfAdapter`
  (`dartnest_shelf`).
- Produces (документація посилається):
  - `Module explicitAppModule()` у `package:tasks_api/explicit.dart`.
  - `enum ModuleStyle { annotations, explicit }`,
    `enum AdapterKind { io, shelf }`.
  - `ServerOptions.parse(List<String> arguments, Map<String, String> environment)`
    → `style`, `adapter`, `port`; кидає `FormatException`.
    `ServerOptions.usage`.
  - `LoopbackServer.start(Module Function() root, AdapterKind kind)` з
    `send(method, target, {headers, json})` → `ApiResponse`; `errors`.
  - `bin/main.dart`: прапорці `--explicit`, `--shelf`, змінна `PORT`
    (1..65535, за замовчуванням 8080), код виходу 64 на помилку
    аргументів.

e2e-набір має 11 тестів. Він прогоняється для 2 графів × 2 адаптерів, тобто
44 тести. `tearDown` перевіряє, що `onError` адаптера не отримав жодної
помилки.

- [ ] **Step 1: Тести (спершу)**

**Створити `example/test/helpers/api_response.dart`:**

```dart
import 'dart:convert';

/// A response read whole by `LoopbackServer.send`.
final class ApiResponse {
  /// Creates the response.
  ApiResponse(this.status, this.headers, this.body);

  /// The status code.
  final int status;

  /// The first value of every header, by lowercase name.
  final Map<String, String> headers;

  /// The body as text.
  final String body;

  /// The body decoded as JSON.
  Object? get json => jsonDecode(body);

  @override
  String toString() => 'ApiResponse($status, $body)';
}
```

**Створити `example/test/helpers/loopback_server.dart`:**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:tasks_api/tasks_api.dart';

import 'api_response.dart';

/// The tasks application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the errors reported on the way.
final class LoopbackServer {
  LoopbackServer._(this.app, this.port, this.errors);

  /// Serves [root] with the adapter [kind] names.
  static Future<LoopbackServer> start(
    Module Function() root,
    AdapterKind kind,
  ) async {
    final errors = <Object>[];
    void record(Object error, StackTrace _) => errors.add(error);
    final HttpAdapter adapter;
    final int Function() boundPort;
    switch (kind) {
      case AdapterKind.io:
        final io = IoAdapter(onError: record);
        (adapter, boundPort) = (io, () => io.port);
      case AdapterKind.shelf:
        final shelf = ShelfAdapter(onError: record);
        (adapter, boundPort) = (shelf, () => shelf.port);
    }
    final app = await TasksApp.create(root, adapter: adapter, onError: record);
    await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
    return LoopbackServer._(app, boundPort(), errors);
  }

  /// The served application.
  final Application app;

  /// The port the adapter bound.
  final int port;

  /// What the application and the adapter reported to `onError`.
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
    await app.close(force: true);
  }
}
```

**Створити `example/test/e2e_test.dart`:**

```dart
// One suite, four servers: the generated and the hand-written module graph,
// each served by dart:io and by shelf on a loopback port.
import 'package:dartnest/dartnest.dart';
import 'package:tasks_api/explicit.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.dartnest.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';

const _reader = {'x-api-key': 'reader-key'};
const _editor = {'x-api-key': 'editor-key'};

void main() {
  final graphs = <String, Module Function()>{
    'annotations': appModule,
    'explicit': explicitAppModule,
  };
  graphs.forEach((style, root) {
    for (final kind in AdapterKind.values) {
      group('$style on ${kind.name}', () => _suite(root, kind));
    }
  });
}

void _suite(Module Function() root, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.

  setUp(() async => server = await LoopbackServer.start(root, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  _public(() => server);
  _reading(() => server);
  _writing(() => server);
}

/// What needs no API key: the health check and the middleware.
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
    expect(unrouted.headers['x-request-id'], startsWith('req-'));
  });

  test('the interceptor times routed requests', () async {
    final response = await server().send('GET', '/health');

    expect(
      response.headers['server-timing'],
      matches(RegExp(r'^handler;dur=\d+\.\d$')),
    );
  });
}

/// Reading tasks: the key guard, query and path parameters, the filter.
void _reading(LoopbackServer Function() server) {
  test('a missing or unknown key is 401', () async {
    final missing = await server().send('GET', '/tasks');
    final unknown = await server().send(
      'GET',
      '/tasks',
      headers: {'x-api-key': 'nope'},
    );

    expect(missing.status, 401);
    expect((missing.json as Map)['message'], 'Send a valid x-api-key.');
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
      {'id': 2, 'title': 'Run dartnest dev', 'done': true},
    ]);
    expect(invalid.status, 400);
  });

  test('GET /tasks/:id finds a task; the filter maps a miss to 404', () async {
    final found = await server().send('GET', '/tasks/1', headers: _reader);
    final missing = await server().send('GET', '/tasks/99', headers: _reader);
    final invalid = await server().send('GET', '/tasks/one', headers: _reader);

    expect((found.json as Map)['title'], 'Read the dartnest README');
    expect(missing.status, 404);
    expect((missing.json as Map)['message'], 'No task 99.');
    expect(invalid.status, 400);
  });
}

/// Changing tasks: the roles guard, the body DTOs and the pipe.
void _writing(LoopbackServer Function() server) {
  test('a reader cannot create a task: 403', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _reader,
      json: {'title': 'Nope'},
    );

    expect(response.status, 403);
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
      'title': 'Read the dartnest README',
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

**Створити `example/test/server_options_test.dart`:**

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

**Замінити повністю `example/pubspec.yaml`:**

```yaml
name: tasks_api
description: The dartnest example application, a small tasks API; see README.md.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0
  dartnest_io: ^0.1.0
  dartnest_shelf: ^0.1.0

dev_dependencies:
  dartnest_cli: ^0.1.0
  lints: ^5.1.0
  path: ^1.9.0
  test: ^1.25.0
```

- [ ] **Step 2: Переконатися, що тести падають**

Run: `dart pub get && cd example && dart test test/e2e_test.dart test/server_options_test.dart`
Expected: FAIL під час компіляції: `explicitAppModule`, `AdapterKind`,
`ServerOptions` не визначені.

- [ ] **Step 3: Реалізація**

**Створити `example/lib/src/server/module_style.dart`:**

```dart
/// Which module graph `bin/main.dart` serves.
enum ModuleStyle {
  /// `appModule` from the library generated from the annotations.
  annotations,

  /// `explicitAppModule`, written by hand with the explicit API.
  explicit,
}
```

**Створити `example/lib/src/server/adapter_kind.dart`:**

```dart
/// Which adapter `bin/main.dart` serves with.
enum AdapterKind {
  /// `IoAdapter` from `dartnest_io`.
  io,

  /// `ShelfAdapter` from `dartnest_shelf`.
  shelf,
}
```

**Створити `example/lib/src/server/server_options.dart`:**

```dart
import 'adapter_kind.dart';
import 'module_style.dart';

/// The command line of `bin/main.dart`: `[--explicit] [--shelf]`, and the
/// port from the `PORT` environment variable (8080 by default).
final class ServerOptions {
  /// Creates the options.
  const ServerOptions({
    this.style = ModuleStyle.annotations,
    this.adapter = AdapterKind.io,
    this.port = defaultPort,
  });

  /// Reads [arguments] and [environment]; throws a [FormatException] for
  /// an unknown argument or a `PORT` outside 1 to 65535.
  factory ServerOptions.parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    final unknown = arguments.where((a) => !_flags.contains(a)).toList();
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
      'Usage: dart run bin/main.dart [--explicit] [--shelf]\n'
      '  --explicit  serve the module graph written with the explicit API\n'
      '  --shelf     serve with ShelfAdapter instead of IoAdapter\n'
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

**Замінити повністю `example/lib/tasks_api.dart`:**

```dart
/// The tasks API of the dartnest example: the classes both module graphs
/// share. The graphs themselves are `appModule` in
/// `tasks_api.dartnest.dart` (generated from the annotations) and
/// `explicitAppModule` in `explicit.dart` (written by hand).
library;

export 'src/app_module.dart';
export 'src/auth/api_key_guard.dart';
export 'src/auth/api_keys.dart';
export 'src/auth/auth_module.dart';
export 'src/auth/role.dart';
export 'src/auth/roles.dart';
export 'src/auth/roles_guard.dart';
export 'src/common/request_id_middleware.dart';
export 'src/common/timing_interceptor.dart';
export 'src/common/trim_strings_pipe.dart';
export 'src/config/config_module.dart';
export 'src/health/health_controller.dart';
export 'src/health/health_module.dart';
export 'src/server/adapter_kind.dart';
export 'src/server/module_style.dart';
export 'src/server/server_options.dart';
export 'src/server/tasks_app.dart';
export 'src/tasks/create_task_dto.dart';
export 'src/tasks/in_memory_task_store.dart';
export 'src/tasks/task.dart';
export 'src/tasks/task_not_found.dart';
export 'src/tasks/task_not_found_filter.dart';
export 'src/tasks/task_store.dart';
export 'src/tasks/tasks_controller.dart';
export 'src/tasks/tasks_module.dart';
export 'src/tasks/tasks_service.dart';
export 'src/tasks/update_task_dto.dart';
```

**Створити `example/lib/explicit.dart`:**

```dart
/// The tasks API wired by hand with the explicit API: the same classes and
/// the same module graph as the generated `appModule`, without code
/// generation.
library;

import 'package:dartnest/dartnest.dart';

import 'tasks_api.dart';

/// The application root.
Module explicitAppModule() => Module(
  id: 'app',
  imports: [_configModule(), _tasksModule(), _healthModule()],
  providers: [Provider((i) => TimingInterceptor())],
);

Module _configModule() => Module(
  id: 'config',
  providers: [
    Provider<String>.value('tasks_api', token: appName),
    Provider<Map<String, Role>>.value(demoApiKeys, token: apiKeys),
  ],
  exports: [appName, apiKeys],
  global: true,
);

Module _authModule() => Module(
  id: 'auth',
  providers: [
    Provider((i) => ApiKeys(i.get(apiKeys))),
    Provider((i) => ApiKeyGuard(i.get())),
    Provider((i) => RolesGuard()),
  ],
  exports: [ApiKeyGuard, RolesGuard],
);

Module _tasksModule() => Module(
  id: 'tasks',
  imports: [_authModule()],
  providers: [
    Provider<TaskStore>((i) => InMemoryTaskStore()),
    Provider((i) => TasksService(i.get())),
    Provider((i) => TrimStringsPipe()),
    Provider((i) => TaskNotFoundFilter()),
  ],
  controllers: [_tasksController()],
);

const _editorsOnly = Enhancers(guards: [Use<RolesGuard>()]);

Controller<TasksController> _tasksController() => Controller<TasksController>(
  path: '/tasks',
  create: (i) => TasksController(i.get()),
  enhancers: const Enhancers(
    guards: [Use<ApiKeyGuard>()],
    pipes: [Use<TrimStringsPipe>()],
    filters: [Use<TaskNotFoundFilter>()],
  ),
  routes: [
    Route.get('', (c, ctx) async => c.list(await ctx.query<bool?>('done'))),
    Route.get('/:id', (c, ctx) async => c.find(await ctx.param<int>('id'))),
    Route.post(
      '',
      (c, ctx) async => c.create(await ctx.bodyAs(CreateTaskDto.fromJson), ctx),
      enhancers: _editorsOnly,
      metadata: const [
        Roles([Role.editor]),
      ],
    ),
    Route.patch(
      '/:id',
      (c, ctx) async => c.update(
        await ctx.param<int>('id'),
        await ctx.bodyAs(UpdateTaskDto.fromJson),
      ),
      enhancers: _editorsOnly,
      metadata: const [
        Roles([Role.editor]),
      ],
    ),
    Route.delete(
      '/:id',
      (c, ctx) async {
        c.delete(await ctx.param<int>('id'));
        return null;
      },
      enhancers: _editorsOnly,
      metadata: const [
        Roles([Role.editor]),
      ],
    ),
  ],
);

Module _healthModule() => Module(
  id: 'health',
  controllers: [
    Controller<HealthController>(
      path: '/health',
      create: (i) => HealthController(i.get(appName)),
      routes: [Route.get('', (c, _) => c.check())],
    ),
  ],
);
```

**Створити `example/bin/main.dart`:**

```dart
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:tasks_api/explicit.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.dartnest.dart';

/// Serves the tasks API until Ctrl+C; see [ServerOptions.usage].
Future<void> main(List<String> arguments) async {
  final ServerOptions options;
  try {
    options = ServerOptions.parse(arguments, Platform.environment);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final app = await TasksApp.create(switch (options.style) {
    ModuleStyle.annotations => appModule,
    ModuleStyle.explicit => explicitAppModule,
  }, adapter: _adapter(options.adapter));
  await app.listen(port: options.port);
  print(
    'Serving the ${options.style.name} module graph with '
    '${options.adapter.name} on http://localhost:${options.port}',
  );
  // Ctrl+C closes gracefully: requests in flight finish, then main returns.
  await ProcessSignal.sigint.watch().first;
  await app.close();
}

HttpAdapter _adapter(AdapterKind kind) => switch (kind) {
  AdapterKind.io => IoAdapter(),
  AdapterKind.shelf => ShelfAdapter(),
};
```

- [ ] **Step 4: README прикладу**

**Створити `example/README.md`:**

~~~~markdown
# tasks_api — the dartnest example

A small tasks API that uses every part of dartnest: modules with imports,
exports and a global module, typed tokens, an interface bound to an
implementation, controllers, a guard chain with route metadata, a pipe, an
interceptor, an exception filter, middleware, both adapters and hot reload.

The same application is wired twice:

- with **annotations** (`lib/src/**`), turned by `dartnest_cli gen` into the
  committed `lib/tasks_api.dartnest.dart`, which exports `appModule`;
- with the **explicit API** by hand in `lib/explicit.dart`, which exports
  `explicitAppModule` and reuses the same classes.

`test/e2e_test.dart` runs one suite against both graphs, each served by
`dart:io` and by shelf on a loopback port.

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

| Request | Answer |
| --- | --- |
| `GET /health` | `{"status": "ok", "name": "tasks_api"}`, no key needed |
| `/tasks` without `x-api-key`, or an unknown key | 401 |
| `GET /tasks`, `GET /tasks/:id` with `reader-key` or `editor-key` | the tasks; `?done=maybe` or `/tasks/one` is 400, an unknown id 404 |
| `POST`, `PATCH`, `DELETE` with `reader-key` | 403 |
| `POST /tasks` with `editor-key` | 201, `location: /tasks/3`, the title trimmed |
| every response | `x-request-id` (middleware); routed ones also `server-timing` (interceptor) |

## Where each feature is

| Feature | File |
| --- | --- |
| Global module, tokens, `Value` | `lib/src/config/config_module.dart` |
| Module with imports and exports | `lib/src/tasks/tasks_module.dart`, `lib/src/auth/auth_module.dart` |
| Interface bound to an implementation (`Bind`) | `lib/src/tasks/tasks_module.dart` (`TaskStore` → `InMemoryTaskStore`) |
| Injection by type and by token (`@Inject`) | `lib/src/tasks/tasks_service.dart`, `lib/src/auth/api_keys.dart` |
| Controller, routes, parameters, body DTOs | `lib/src/tasks/tasks_controller.dart`, `create_task_dto.dart`, `update_task_dto.dart` |
| Guards and route metadata | `lib/src/auth/api_key_guard.dart`, `roles_guard.dart`, `roles.dart` |
| Pipe | `lib/src/common/trim_strings_pipe.dart` |
| Exception filter | `lib/src/tasks/task_not_found_filter.dart` |
| Application-level interceptor | `lib/src/common/timing_interceptor.dart`, `lib/src/server/tasks_app.dart` |
| Middleware | `lib/src/common/request_id_middleware.dart` |
| Adapter choice | `bin/main.dart` |
| The explicit-API twin | `lib/explicit.dart` |

## Change the annotations

After editing an annotated class, regenerate and commit the library:

```sh
dart run dartnest_cli gen
```

`test/generated_library_test.dart` fails while the committed file is out
of date.

## Hot reload

```sh
dart run dartnest_cli dev                   # or: dart run dartnest_cli dev -- --shelf
```

`dev` generates, starts `bin/main.dart` and watches `lib/` and `bin/`:

- Change the body of `HealthController.check` and save: the next
  `GET /health` answers with the new code, the process id stays and the
  tasks you created are still there (`Reloaded 7 libraries in 82 ms, 0
  routes changed.`).
- Add a route (`@Get('/live')` on `HealthController`): the library is
  regenerated and reloaded (`1 route changed`).
- Add a field to a class: `dev` restarts the process instead (`Restarting
  bin/main.dart: ... changed a field, a constructor or a top-level
  variable.`) and the in-memory tasks start over.

Press `r` to reload and `R` to restart by hand; Ctrl+C stops.

## Tests

```sh
dart test
```

- `test/e2e_test.dart`: both graphs on both adapters, over loopback.
- `test/in_process_test.dart`: `TestClient`, no server.
- `test/tasks_service_test.dart`: the service alone, and a test module
  with a fake store.
- `test/generated_library_test.dart`: the committed generated library is
  what `dartnest_cli gen` writes.
~~~~

- [ ] **Step 5: Тести проходять, згенерований файл не змінився**

Run: `cd example && dart run dartnest_cli gen && dart test`
Expected: `lib/tasks_api.dartnest.dart is up to date (N ms).`, далі
`+54: All tests passed!`.

Run: `dart analyze && dart format --output=none --set-exit-if-changed example packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 6: Ручна перевірка hot reload (раз, не в CI)**

Run: `cd example && PORT=8091 dart run dartnest_cli dev`. Перевірити три
випадки:
- Змінити тіло `HealthController.check` і зберегти. Очікувано:
  `Reloaded N libraries in M ms, 0 routes changed.` Наступний
  `curl localhost:8091/health` віддає нову відповідь з тим самим pid, а
  створені раніше задачі на місці.
- Додати `@Get('/live')` у `HealthController`. Очікувано: `1 route changed`.
- Додати поле в `HealthController`. Очікувано: `Restarting bin/main.dart:
  lib/src/health/health_controller.dart changed a field, a constructor or a
  top-level variable.`

Ctrl+C. Відкотити зміни: `git checkout example/lib` і
`cd example && dart run dartnest_cli gen`.

- [ ] **Step 7: Commit**

```bash
git add example
git commit -m "feat(example): the explicit twin, both adapters and bin/main.dart"
```

---

### Task 4: Пакети рантайму — приклади, CHANGELOG, оновлений README ядра

**Files:**
- Move: `packages/dartnest/example/di_example.dart` → `packages/dartnest/example/dartnest_example.dart`; `packages/dartnest/test/di/example_test.dart` → `packages/dartnest/test/example_test.dart`
- Modify: `packages/dartnest/README.md`
- Create: `packages/dartnest_io/example/dartnest_io_example.dart`, `packages/dartnest_io/test/example_test.dart`
- Create: `packages/dartnest_shelf/example/dartnest_shelf_example.dart`, `packages/dartnest_shelf/test/example_test.dart`
- Create: `packages/dartnest_annotations/example/README.md`
- Create: `packages/{dartnest,dartnest_annotations,dartnest_io,dartnest_shelf}/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 1 (`public_member_api_docs`).
- Produces:
  - `package:dartnest`: `example/dartnest_example.dart` (`appModule`,
    `httpModule()`, `helloController`, `Greeter`, `Db`, `dbUrl`).
  - `dartnest_io` / `dartnest_shelf`: приклади з
    `Future<String> run()` (сервер на loopback, один запит, close) і
    `appModule()`.

pana шукає приклад за фіксованими іменами (`exampleFileCandidates`):
`example/README.md`, потім `example/<package>_example.dart` тощо. Наявний
`example/di_example.dart` не підходить, тому його перейменовано й
доповнено HTTP-частиною через `TestClient`. Приклади адаптерів слухають
порт 0 на loopback і завершуються самі, тож тест їх запускає.
`dartnest_annotations` без кодогенерації не запускається, тому його
приклад — `example/README.md` з тим самим застосунком, що створює `init`.

- [ ] **Step 1: Перейменувати приклад ядра**

**Виконати з кореня репозиторію:**

```sh
git mv packages/dartnest/example/di_example.dart packages/dartnest/example/dartnest_example.dart
git mv packages/dartnest/test/di/example_test.dart packages/dartnest/test/example_test.dart
```

- [ ] **Step 2: Тести прикладів (спершу)**

**Замінити повністю `packages/dartnest/test/example_test.dart`:**

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:test/test.dart';

import '../example/dartnest_example.dart' as example;

void main() {
  test('README example starts and resolves the greeting service', () async {
    final container = await Container.create(example.appModule);
    final greeter = container.root.get<example.Greeter>();
    expect(greeter.greet('dartnest'), 'Hello, dartnest! (via pg://localhost)');
  });

  test('the HTTP example answers through the injected greeter', () async {
    final app = await Application.create(example.httpModule);
    addTearDown(app.close);
    final response = await TestClient(app).get('/hello?name=you');
    expect(response.status, 200);
    expect(response.json, {'message': 'Hello, you! (via pg://localhost)'});
  });

  test('the HTTP example rejects a missing name with 400', () async {
    final app = await Application.create(example.httpModule);
    addTearDown(app.close);
    final response = await TestClient(app).get('/hello');
    expect(response.status, 400);
  });
}
```

**Створити `packages/dartnest_io/test/example_test.dart`:**

```dart
import 'package:test/test.dart';

import '../example/dartnest_io_example.dart' as example;

void main() {
  test('the README example serves a streamed body over loopback', () async {
    expect(await example.run(), '1\n2\n3\n');
  });
}
```

**Створити `packages/dartnest_shelf/test/example_test.dart`:**

```dart
import 'package:test/test.dart';

import '../example/dartnest_shelf_example.dart' as example;

void main() {
  test('the README example serves a streamed body over loopback', () async {
    expect(await example.run(), '1\n2\n3\n');
  });
}
```

Run: `cd packages/dartnest && dart test test/example_test.dart`
Expected: FAIL під час компіляції: `httpModule` не визначено (і так само
`run` у `dartnest_io`/`dartnest_shelf`).

- [ ] **Step 3: Приклади**

**Замінити повністю `packages/dartnest/example/dartnest_example.dart`:**

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';

/// A typed token for a primitive value.
const dbUrl = Token<String>('db.url');

/// A dynamic module: a plain function returning a Module.
Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);

/// A fake database connection.
class Db {
  Db._(this.url);

  /// The URL this connection was opened with.
  final String url;

  /// Opens a connection to [url].
  static Future<Db> connect(String url) async => Db._(url);
}

/// A service that depends on [Db].
class Greeter {
  /// Creates a greeter backed by [db].
  Greeter(this.db);

  /// The database this greeter reports in its greeting.
  final Db db;

  /// Returns a greeting for [name] that mentions the database URL.
  String greet(String name) => 'Hello, $name! (via ${db.url})';
}

/// Provides [Greeter] and imports the database.
final greetingModule = Module(
  id: 'greeting',
  imports: [databaseModule(url: 'pg://localhost')],
  providers: [Provider((i) => Greeter(i.get()))],
  exports: [Greeter],
);

/// The root module of the dependency injection example.
final appModule = Module(id: 'app', imports: [greetingModule]);

/// Serves `GET /hello?name=...` with a [Greeter].
final helloController = Controller<Greeter>(
  path: '/hello',
  create: (i) => i.get(),
  routes: [
    Route.get(
      '/',
      (greeter, ctx) async => {
        'message': greeter.greet(await ctx.query<String>('name')),
      },
    ),
  ],
);

/// The root module of the HTTP example: [greetingModule] plus a controller.
Module httpModule() => Module(
  id: 'http',
  imports: [greetingModule],
  controllers: [helloController],
);

/// Resolves a service from a container, then answers one request in memory.
///
/// To serve over a socket, pass `IoAdapter()` from `dartnest_io` or
/// `ShelfAdapter()` from `dartnest_shelf` to `Application.create` and call
/// `app.listen(port: 8080)`.
Future<void> main() async {
  final container = await Container.create(appModule);
  print(container.root.get<Greeter>().greet('dartnest'));
  await container.close();

  final app = await Application.create(httpModule);
  final response = await TestClient(app).get('/hello?name=you');
  print('${response.status} ${response.text}');
  await app.close();
}
```

**Створити `packages/dartnest_io/example/dartnest_io_example.dart`:**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingController {
  /// Returns `pong`, sent as `text/plain`.
  String ping() => 'pong';

  /// Streams `1\n2\n3\n`, one chunk per line, without buffering.
  Stream<List<int>> count() =>
      Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n'));
}

/// The root module: one controller, no providers.
Module appModule() => Module(
  id: 'app',
  controllers: [
    Controller<PingController>(
      path: '/',
      create: (i) => PingController(),
      routes: [
        Route.get('/ping', (c, ctx) async => c.ping()),
        Route.get('/count', (c, ctx) async => c.count()),
      ],
    ),
  ],
);

/// Serves [appModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server calls `app.listen(port: 8080)` and closes the application
/// on a signal instead.
Future<String> run() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
  final client = HttpClient();
  try {
    final uri = Uri.http('127.0.0.1:${adapter.port}', '/count');
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

**Створити `packages/dartnest_shelf/example/dartnest_shelf_example.dart`:**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingController {
  /// Returns `pong`, sent as `text/plain`.
  String ping() => 'pong';

  /// Streams `1\n2\n3\n`, one chunk per line, without buffering.
  Stream<List<int>> count() =>
      Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n'));
}

/// The root module: one controller, no providers.
Module appModule() => Module(
  id: 'app',
  controllers: [
    Controller<PingController>(
      path: '/',
      create: (i) => PingController(),
      routes: [
        Route.get('/ping', (c, ctx) async => c.ping()),
        Route.get('/count', (c, ctx) async => c.count()),
      ],
    ),
  ],
);

/// Serves [appModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server calls `app.listen(port: 8080)` and closes the application
/// on a signal instead. To keep your own shelf server and middleware, create
/// the application without an adapter and mount `shelfHandler(app)`.
Future<String> run() async {
  final adapter = ShelfAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
  final client = HttpClient();
  try {
    final uri = Uri.http('127.0.0.1:${adapter.port}', '/count');
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

**Створити `packages/dartnest_annotations/example/README.md`:**

~~~~markdown
# dartnest_annotations example

A complete application in two files. The annotations describe it;
`dartnest_cli gen` (or `dartnest_build`) writes `lib/my_app.dartnest.dart`
with the explicit `package:dartnest` code.

```yaml
# pubspec.yaml
name: my_app
environment:
  sdk: ^3.8.0
dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0
  dartnest_io: ^0.1.0
dev_dependencies:
  dartnest_cli: ^0.1.0
```

```dart
// lib/src/hello.dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Builds greetings.
@Injectable()
final class HelloService {
  /// A greeting for [name].
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
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
```

```dart
// bin/main.dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:my_app/my_app.dartnest.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:${adapter.port}/hello');
}
```

```sh
dart pub get
dart run dartnest_cli gen     # writes lib/my_app.dartnest.dart
dart run bin/main.dart
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
```

`dart run dartnest_cli init my_app` creates exactly this package. The
repository's `example/` directory has a larger application (guards, pipes,
filters, interceptors, middleware, tokens, `Bind`) written in both styles.
~~~~

Run: `for p in dartnest dartnest_io dartnest_shelf; do (cd packages/$p && dart test test/example_test.dart 2>&1 | tail -1 && dart run example/${p}_example.dart); done`
Expected:
- `dartnest`: +3 і два рядки виводу: `Hello, dartnest! (via pg://localhost)`,
  `200 {"message":"Hello, you! (via pg://localhost)"}`.
- `dartnest_io`, `dartnest_shelf`: +1 і `1`, `2`, `3` по рядку.

- [ ] **Step 4: README ядра**

README ядра досі каже, що анотації й генератор «coming in later
milestones», а статична валідація «planned».

**Замінити в `packages/dartnest/README.md`:**

~~~~markdown
is validated before any provider is created; missing or circular dependencies
fail fast during startup, and `Container.create` never returns a partially
started container. Static validation of the full graph is planned for the
generator in a later milestone. Annotations and code generation are an
optional layer on top (coming in later milestones); everything works without
them.

## Dependency injection

Excerpt; the full runnable version is `example/di_example.dart`:

```dart
~~~~

**на:**

~~~~markdown
is validated before any provider is created; missing or circular dependencies
fail fast during startup, and `Container.create` never returns a partially
started container. Annotations (`dartnest_annotations`) and an analyzer-based
generator (`dartnest_generator`, run by `dartnest_cli` or `dartnest_build`)
are an optional layer on top that also validates the graph at build time;
everything works without them, and both styles produce the same values.

| Package | What it adds |
| --- | --- |
| `dartnest` | This package: modules, DI, controllers, the request pipeline, `TestClient` |
| `dartnest_io` | `IoAdapter`, a `dart:io` `HttpServer` adapter |
| `dartnest_shelf` | `ShelfAdapter` and `shelfHandler` for shelf |
| `dartnest_annotations` | `@Module`, `@Controller`, `@Get`, `@Injectable`, ... |
| `dartnest_generator` | The analyzer-based generator behind the annotations |
| `dartnest_cli` | `dartnest gen`, `dartnest dev` (hot reload), `dartnest init` |
| `dartnest_build` | The same generator as a `build_runner` builder |

## Dependency injection

Excerpt; the full runnable version is `example/dartnest_example.dart`:

```dart
~~~~

**Замінити в `packages/dartnest/README.md`:**

```markdown
`dartnest_io` (a `dart:io` `HttpServer`) or `ShelfAdapter` from
`dartnest_shelf`; `shelfHandler(app)` from `dartnest_shelf` embeds an
application in an existing shelf pipeline. Annotations and an
analyzer-based generator are planned in later milestones; see the
repository's `docs/` directory for the roadmap.
```

**на:**

```markdown
`dartnest_io` (a `dart:io` `HttpServer`) or `ShelfAdapter` from
`dartnest_shelf`; `shelfHandler(app)` from `dartnest_shelf` embeds an
application in an existing shelf pipeline. The repository's `docs/`
directory has the guides, and its `example/` directory a complete
application written in both styles.
```

- [ ] **Step 5: CHANGELOG**

**Створити `packages/dartnest/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- Modules as values, typed providers (`Provider`, `Provider.value`,
  `Provider.async`, tokens) and a container that validates the module graph
  before any provider is created; every failure is a typed `InjectionError`.
- Controllers and routes as values; the request pipeline (middleware,
  guards, interceptors, pipes, exception filters) with `Enhancers` and
  `Use<T>()`; JSON results and `HttpException` error responses.
- `HttpAdapter`, the contract the server adapters implement, and
  `TestClient` for tests without a socket.
- `Application.reassemble()` and the `ext.dartnest.*` VM service extensions
  that `dartnest_cli dev` uses for hot reload.
```

**Створити `packages/dartnest_annotations/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- `@Module`, `@Injectable`, `@Inject`, `Bind`, `Value`, `@Controller`, the
  route annotations, the parameter annotations and `@UseGuards`,
  `@UseInterceptors`, `@UsePipes`, `@UseFilters`. No dependencies.
```

**Створити `packages/dartnest_io/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- `IoAdapter`: serves an application on a `dart:io` `HttpServer`, streams
  bodies both ways, closes gracefully with a timeout and serves HTTPS with a
  `SecurityContext`.
```

**Створити `packages/dartnest_shelf/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- `ShelfAdapter`: serves an application through `shelf_io`.
- `shelfHandler(app)`: embeds an application in an existing shelf pipeline.
```

- [ ] **Step 6: Перевірити й закомітити**

Run: `dart analyze && dart format --output=none --set-exit-if-changed packages example && for p in dartnest dartnest_annotations dartnest_io dartnest_shelf; do (cd packages/$p && dart test 2>&1 | tail -1); done`
Expected: `No issues found!`, `0 changed`, `+276`, `+6`, `+47`, `+68`.

```bash
git add packages/dartnest packages/dartnest_annotations packages/dartnest_io packages/dartnest_shelf
git commit -m "docs: examples, changelogs and README refresh for the runtime packages"
```

Run: `for p in dartnest_annotations dartnest dartnest_io dartnest_shelf; do (cd packages/$p && dart pub publish --dry-run 2>&1 | tail -1); done`
Expected: чотири рядки `Package has 0 warnings.`

---

### Task 5: Пакети інструментів — приклади, CHANGELOG, dartdoc

**Files:**
- Create: `packages/dartnest_generator/example/dartnest_generator_example.dart`, `packages/dartnest_generator/test/example_test.dart`
- Create: `packages/dartnest_cli/example/README.md`, `packages/dartnest_build/example/README.md`
- Create: `packages/{dartnest_generator,dartnest_cli,dartnest_build}/CHANGELOG.md`
- Modify: `packages/dartnest_cli/lib/src/cli/interruption.dart` (doc-коментар)

**Interfaces:**
- Consumes: `PackageCollector`, `DartnestGenerator.core()`,
  `GenerationResult.library`/`diagnostics` (етап 4); fixture `users_app` і
  його golden `lib/users_app.dartnest.dart`.
- Produces: `Future<String> generatePackage(String name, String root)` у
  прикладі генератора (кидає `StateError` зі списком діагностик).

Приклад генератора робить те саме, що `dartnest_cli gen`, без запису,
watch і інкрементального аналізу: резолвить `lib/` через
`AnalysisContextCollection` і запускає ядрові конструкти. Тест проганяє
його на `users_app` і порівнює з golden-файлом, тож приклад не застаріє
мовчки. Приклади CLI й build — `example/README.md`. Сценарій
`dartnest_build` (shop, `build.yaml`, `build_runner build`) перевірено
окремим пакетом з `dependency_overrides`: `build_runner` і
`dartnest_cli gen` дали байт-у-байт однаковий `lib/shop.dartnest.dart`, а
`GET /products` → `200 ["tea","coffee"]`.

`dart doc --dry-run` у `dartnest_cli` дає 2 попередження: doc-коментар
посилається на поля record-у `[stopped]`/`[subscription]`, які dartdoc не
резолвить. На pub.dev це мінус у балі документації, тому їх замінено
кодом у зворотних лапках.

- [ ] **Step 1: Тест прикладу генератора (спершу)**

**Створити `packages/dartnest_generator/test/example_test.dart`:**

```dart
import 'dart:io';

import 'package:test/test.dart';

import '../example/dartnest_generator_example.dart' as example;

void main() {
  test('the example generates the committed users_app library', () async {
    final generated = await example.generatePackage(
      'users_app',
      'test/fixtures/users_app',
    );
    final committed = File(
      'test/fixtures/users_app/lib/users_app.dartnest.dart',
    ).readAsStringSync();
    expect(generated, committed);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
```

Run: `cd packages/dartnest_generator && dart test test/example_test.dart`
Expected: FAIL під час компіляції: `example/dartnest_generator_example.dart`
не існує.

- [ ] **Step 2: Приклад генератора**

**Створити `packages/dartnest_generator/example/dartnest_generator_example.dart`:**

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:path/path.dart' as p;

/// Generates the dartnest library of the package at [root] (a directory
/// with a `pubspec.yaml` named [name], after `dart pub get`) and returns
/// its source; throws a [StateError] listing the diagnostics on problems.
///
/// This is what `dartnest_cli gen` does, without the writing, the watching
/// and the incremental analysis.
Future<String> generatePackage(String name, String root) async {
  final lib = p.join(p.normalize(p.absolute(root)), 'lib');
  final collection = AnalysisContextCollection(includedPaths: [lib]);
  try {
    final libraries = <LibraryElement>[
      for (final file in _sourceFiles(lib)) await _resolve(collection, file),
    ];
    final model = PackageCollector(name, p.dirname(lib)).collect(libraries);
    final result = const DartnestGenerator.core().generate(model);
    return switch (result.library) {
      final library? => library,
      null => throw StateError(result.diagnostics.join('\n')),
    };
  } finally {
    await collection.dispose();
  }
}

List<String> _sourceFiles(String lib) {
  final files = Directory(lib)
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => path.endsWith('.dart'))
      .where((path) => !path.endsWith('.dartnest.dart'))
      .toList();
  return files..sort();
}

Future<LibraryElement> _resolve(
  AnalysisContextCollection collection,
  String file,
) async {
  final session = collection.contextFor(file).currentSession;
  return switch (await session.getResolvedLibrary(file)) {
    final ResolvedLibraryResult result => result.element,
    final other => throw StateError('Cannot resolve $file: $other'),
  };
}

/// Prints the library generated for `<name> <directory>`, for example
/// `dart run example/dartnest_generator_example.dart users_app
/// test/fixtures/users_app`.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: dartnest_generator_example.dart <name> <directory>');
    exitCode = 64;
    return;
  }
  stdout.write(await generatePackage(arguments[0], arguments[1]));
}
```

Run: `cd packages/dartnest_generator && dart test test/example_test.dart && dart run example/dartnest_generator_example.dart users_app test/fixtures/users_app | head -3`
Expected: `+1: All tests passed!`, далі заголовок
`// GENERATED BY dartnest_generator. DO NOT EDIT.`.

- [ ] **Step 3: Приклади CLI і build_runner**

**Створити `packages/dartnest_cli/example/README.md`:**

~~~~markdown
# dartnest_cli example

Create an application, generate its code and run it with hot reload:

```sh
dart run dartnest_cli init my_app     # or `dartnest init my_app` when activated
cd my_app
dart pub get
dart run dartnest_cli gen             # writes lib/my_app.dartnest.dart
dart run dartnest_cli dev             # runs bin/main.dart, reloads on every save
```

`dev` prints one line per change:

```text
Reloaded 7 libraries in 82 ms, 0 routes changed.
Reloaded 7 libraries in 95 ms, 1 route changed.
Restarting bin/main.dart: lib/src/hello.dart changed a field, a constructor or a top-level variable.
```

- A changed method body or a new route is a hot reload: the providers keep
  their state and the route table is rebuilt.
- A changed field, constructor or top-level variable restarts the process;
  `dev` tells you which file caused it.
- A problem in the annotations is printed as
  `lib/src/hello.dart:12:3: error: ... [code]`; the application keeps
  running the previous code until the problem is fixed.

Check in CI that the committed library matches the sources:

```sh
dart run dartnest_cli gen && git diff --exit-code lib/my_app.dartnest.dart
```

The repository's `example/` directory is an application developed this
way; its README walks through a hot reload session.
~~~~

**Створити `packages/dartnest_build/example/README.md`:**

~~~~markdown
# dartnest_build example

Generate the dartnest library with build_runner, next to other builders
such as `json_serializable`.

```yaml
# pubspec.yaml
name: shop
environment:
  sdk: ^3.8.0
dependencies:
  dartnest: ^0.1.0
  dartnest_annotations: ^0.1.0
dev_dependencies:
  build_runner: ^2.10.5
  dartnest_build: ^0.1.0
```

```yaml
# build.yaml
targets:
  $default:
    builders:
      dartnest_build:
        options:
          package: shop
```

```dart
// lib/src/catalog.dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The products on sale.
@Injectable()
final class Catalog {
  /// The product names.
  List<String> names() => const ['tea', 'coffee'];
}

/// `GET /products`.
@Controller('/products')
final class ProductsController {
  /// Creates the controller.
  ProductsController(this.catalog);

  /// The catalog.
  final Catalog catalog;

  /// Lists the products.
  @Get()
  List<String> list() => catalog.names();
}

/// The root module.
@Module(id: 'shop', providers: [Catalog], controllers: [ProductsController])
final class ShopModule {}
```

```sh
dart run build_runner build    # writes lib/shop.dartnest.dart with shopModule()
```

`Application.create(shopModule)` then starts the application. The output
is byte-identical to `dart run dartnest_cli gen`, so a package can switch
between the two without a diff.
~~~~

- [ ] **Step 4: CHANGELOG**

**Створити `packages/dartnest_generator/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- `PackageCollector` and `DartnestGenerator.core()`: turn the annotations of
  a package into `lib/<package>.dartnest.dart` on the explicit API, with
  static validation of the module graph and diagnostics with a location and
  a code.
- Deterministic, formatted output; custom `Construct`s.
```

**Створити `packages/dartnest_cli/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- `dartnest gen` and `gen --watch`: write `lib/<package>.dartnest.dart`.
- `dartnest dev`: runs the application and hot reloads it on every change,
  restarting it when a change of shape needs it.
- `dartnest init`: scaffolds a new application.
```

**Створити `packages/dartnest_build/CHANGELOG.md`:**

```markdown
## 0.1.0

Initial release.

- The `dartnest_build` builder for build_runner: the same output as
  `dartnest_cli gen`, configured with the `package` option in `build.yaml`.
```

- [ ] **Step 5: dartdoc без попереджень**

**Замінити в `packages/dartnest_cli/lib/src/cli/interruption.dart`:**

```dart
  final void Function(int code) forceExit;

  /// Listens to [signals]: [stopped] completes on the first interrupt (or
  /// when [untilStopped] completes) and [onSignal] gets the number of every
  /// interrupt, the first included. The caller cancels [subscription] when
  /// its command ends, whatever way it ends.
  ({Future<void> stopped, StreamSubscription<void> subscription}) listen(
```

**на:**

```dart
  final void Function(int code) forceExit;

  /// Listens to [signals]: `stopped` completes on the first interrupt (or
  /// when [untilStopped] completes) and [onSignal] gets the number of every
  /// interrupt, the first included. The caller cancels `subscription` when
  /// its command ends, whatever way it ends.
  ({Future<void> stopped, StreamSubscription<void> subscription}) listen(
```

Run: `for p in dartnest_annotations dartnest dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do (cd packages/$p && dart doc --dry-run 2>&1 | tail -1); done`
Expected: сім рядків `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Перевірити й закомітити**

Run: `dart analyze && dart format --output=none --set-exit-if-changed packages example && for p in dartnest_generator dartnest_cli dartnest_build; do (cd packages/$p && dart test 2>&1 | tail -1); done`
Expected: `No issues found!`, `0 changed`, `+172`, `+136`, `+18`.

```bash
git add packages
git commit -m "docs: examples and changelogs for the tooling packages"
```

Run: `for p in dartnest_annotations dartnest dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do (cd packages/$p && dart pub publish --dry-run > /dev/null 2>&1; echo "$p $?"); done`
Expected: усі сім з кодом 0.

---

### Task 6: Кореневий README і основні посібники

**Files:**
- Create: `README.md`
- Create: `docs/getting-started.md`, `docs/modules-and-di.md`, `docs/controllers-and-pipeline.md`, `docs/annotations-and-codegen.md`, `docs/adapters.md`

**Interfaces:**
- Consumes: імена прикладу (Tasks 2–3); README пакетів (повні правила
  лишаються там, посібники посилаються на них, а не дублюють).
- Produces: якорі, на які посилаються Task 7 і README:
  `../README.md#without-code-generation`,
  `testing.md#a-test-module`, `faq.md#known-limitations`.

Кожен повний сніпет запускався, кожне твердження про поведінку
відтворено. Повідомлення про помилки скопійовано з реального виводу.
Окремі відтворення:
- 404-тіло;
- `missing_provider` з позицією `19:24` у `getting-started`;
- `MissingProviderError` без контролера в ланцюжку;
- поведінка CR/LF в обох адаптерах.

Таблиця відповідностей NestJS→dartnest називає лише наявні API.
`ConflictException` і `overrideProvider` у dartnest немає, і документи
кажуть це прямо.

- [ ] **Step 1: README**

**Створити `README.md`:**

~~~~markdown
# dartnest

A NestJS-style modular backend framework for Dart, without `dart:mirrors`.

Modules, providers, controllers, guards, interceptors, pipes and exception
filters work the way they do in NestJS, but they are plain Dart values: a
module is a `Module(...)`, a provider is a typed factory, a route is a
closure. The container checks the whole module graph before it creates
anything, so a missing or circular dependency fails at startup with the
chain that led to it, never in the middle of a request. Annotations are an
optional layer on top: a generator turns them into the same values, checks
the graph at build time and writes one ordinary Dart file per package.

- **No reflection, no magic at runtime.** The explicit API works in tests,
  scripts and AOT builds without any code generation.
- **Errors before the first request.** Typed `InjectionError`s with the
  resolution chain; with annotations, `path:line:column` diagnostics.
- **Typed tokens** (`Token<String>('db.url')`) instead of strings.
- **Hot reload that keeps state.** `dartnest dev` reloads code changes into
  the running server; providers keep their instances, routes are rebuilt.
- **Two servers, one contract.** `dart:io` or shelf, both checked by the
  same conformance suite on real sockets.

## Quick start

### With annotations

```sh
dart pub global activate dartnest_cli
dartnest init my_app
cd my_app
dart pub get
dartnest gen          # writes lib/my_app.dartnest.dart
dartnest dev          # runs bin/main.dart and hot reloads it
curl 'http://localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
```

`init` writes this controller (`lib/src/hello.dart`):

```dart
@Controller('/hello')
final class HelloController {
  HelloController(this.service);
  final HelloService service;

  @Get()
  Map<String, String> hello(@Query('name') String? name) =>
      service.greet(name ?? 'world');
}

@Module(id: 'app', providers: [HelloService], controllers: [HelloController])
final class AppModule {}
```

and the generator turns `AppModule` into `Module appModule()`, which
`bin/main.dart` passes to `Application.create`.

### Without code generation

```yaml
# pubspec.yaml
dependencies:
  dartnest: ^0.1.0
  dartnest_io: ^0.1.0
```

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';

final class Greeter {
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
}

final class HelloController {
  HelloController(this.greeter);
  final Greeter greeter;

  Map<String, String> hello(String? name) => greeter.greet(name ?? 'world');
}

Module appModule() => Module(
  id: 'app',
  providers: [Provider((i) => Greeter())],
  controllers: [
    Controller<HelloController>(
      path: '/hello',
      create: (i) => HelloController(i.get()),
      routes: [
        Route.get(
          '',
          (c, ctx) async => c.hello(await ctx.query<String?>('name')),
        ),
      ],
    ),
  ],
);

Future<void> main() async {
  final app = await Application.create(appModule, adapter: IoAdapter());
  await app.listen(port: 8080);
  print('Listening on http://localhost:8080/hello');
}
```

The two styles mix freely: a generated module can import a hand-written one
and the other way round.

## Packages

| Package | What it is |
| --- | --- |
| [`dartnest`](packages/dartnest) | The core: modules, DI, controllers, the request pipeline, `TestClient`, the hot reload hooks. No `dart:io`. |
| [`dartnest_io`](packages/dartnest_io) | `IoAdapter`: serves an application on a `dart:io` `HttpServer`. |
| [`dartnest_shelf`](packages/dartnest_shelf) | `ShelfAdapter`, and `shelfHandler(app)` to mount an application in a shelf pipeline. |
| [`dartnest_annotations`](packages/dartnest_annotations) | `@Module`, `@Injectable`, `@Controller`, `@Get`, ... No dependencies. |
| [`dartnest_generator`](packages/dartnest_generator) | Turns the annotations into code and validates the module graph. A library for the drivers below. |
| [`dartnest_cli`](packages/dartnest_cli) | The `dartnest` command: `gen`, `gen --watch`, `dev` (hot reload), `init`. |
| [`dartnest_build`](packages/dartnest_build) | The same generator as a build_runner builder. |

Every package README lists the exact rules of that package.

## Coming from NestJS

| NestJS | dartnest (explicit API) | dartnest (annotations) |
| --- | --- | --- |
| `@Module({imports, providers, controllers, exports})` | `Module(id: ..., imports: ..., ...)` | `@Module(id: ..., ...)` on a class |
| `@Global()` | `Module(global: true)` | `@Module(global: true)` |
| `@Injectable()` class | `Provider((i) => Service(i.get()))` | `@Injectable()` |
| `{provide: TOKEN, useValue: v}` | `Provider.value(v, token: Token<T>('name'))` | `Value(v, token: ...)` |
| `{provide: Abstract, useClass: Impl}` | `Provider<Abstract>((i) => Impl())` | `Bind<Abstract, Impl>()` |
| `useFactory` with `async`, `forRootAsync` | `Provider.async((i) async => ...)` | a function returning a `Module`, in `imports` |
| `@Inject(TOKEN)` | `i.get(token)` | `@Inject(token)` |
| `@Controller('users')`, `@Get(':id')` | `Controller<T>(path: '/users', routes: [Route.get('/:id', ...)])` | `@Controller('/users')`, `@Get('/:id')` |
| `@Param`, `@Query`, `@Body`, `@Headers` | `ctx.param<T>`, `ctx.query<T>`, `ctx.bodyAs`, `ctx.header` | `@Param`, `@Query`, `@Body`, `@Header` |
| `CanActivate`, `@UseGuards` | `Guard`, `Enhancers(guards: [...])` | `@UseGuards([...])` |
| `NestInterceptor`, `PipeTransform` | `Interceptor`, `Pipe<I, O>` | `@UseInterceptors`, `@UsePipes` |
| `ExceptionFilter`, `@Catch(E)` | `ExceptionFilter<E>` | `@UseFilters([...])` |
| `SetMetadata` + `Reflector` | a `RouteMetadata` subclass + `ctx.metadata<T>()` | the same class as an annotation |
| `NestMiddleware`, `app.use` | `app.use(middleware)` | the same |
| `NotFoundException`, `HttpException` | the same names | the same |
| `NestFactory.create(AppModule)` | `Application.create(appModule, adapter: IoAdapter())` | the same, with the generated `appModule` |
| platform-express / platform-fastify | `dartnest_io` / `dartnest_shelf` | the same |
| `Test.createTestingModule`, supertest | `Container.create(testModule)`, `TestClient(app)` | the same |
| `nest start --watch` | `dartnest dev` (reload, not restart) | the same |
| `nest new` | `dartnest init` | the same |

Not in 0.1.0: request-scoped providers, lifecycle hooks (`OnModuleInit`),
WebSockets, SSE, GraphQL, microservice transports, OpenAPI generation. See
[docs/faq.md](docs/faq.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Modules and dependency injection](docs/modules-and-di.md)
- [Controllers and the request pipeline](docs/controllers-and-pipeline.md)
- [Annotations and code generation](docs/annotations-and-codegen.md)
- [Adapters: dart:io and shelf](docs/adapters.md)
- [Dev mode and hot reload](docs/dev-mode.md)
- [build_runner](docs/build-runner.md)
- [Testing](docs/testing.md)
- [FAQ and known limitations](docs/faq.md)

[`example/`](example) is one application, a small tasks API, written in
both styles and tested end to end on both adapters.

## Requirements

Dart SDK 3.8 or later. Developed and tested on Linux; see
[docs/faq.md](docs/faq.md) for macOS and Windows.

## Development

This repository is a pub workspace: `dart pub get` at the root resolves
every package and the example. `CLAUDE.md` lists the commands that CI runs;
`docs/RELEASING.md` describes a release.

## License

MIT, see [LICENSE](LICENSE).
~~~~

- [ ] **Step 2: Перевірити quick start без кодогенерації (Review Focus 2)**

Run (тимчасовий пакет поза репозиторієм, `$R` — абсолютний шлях до `packages`):

```sh
R=$PWD/packages; Q=$(mktemp -d); mkdir -p $Q/bin; cd $Q
printf 'name: qs\nenvironment:\n  sdk: ^3.8.0\ndependencies:\n  dartnest: ^0.1.0\n  dartnest_io: ^0.1.0\ndependency_overrides:\n  dartnest: {path: %s/dartnest}\n  dartnest_io: {path: %s/dartnest_io}\n' $R $R > pubspec.yaml
awk '/^### Without code generation/{s=1} s&&/^```dart/{f=1;next} f&&/^```/{exit} f' $R/../README.md > bin/main.dart
dart pub get && dart analyze bin && dart format --output=none --set-exit-if-changed bin
dart run bin/main.dart & sleep 6; curl -s 'localhost:8080/hello?name=you'; curl -s localhost:8080/hello; kill %1
```

Expected: `No issues found!`, `0 changed`,
`{"message":"Hello, you!"}{"message":"Hello, world!"}`.

- [ ] **Step 3: Посібники**

**Створити `docs/getting-started.md`:**

~~~~markdown
# Getting started

dartnest needs the Dart SDK 3.8 or later (`dart --version`).

## Create an application

```sh
dart pub global activate dartnest_cli   # installs the `dartnest` command
dartnest init my_app
cd my_app
dart pub get
dartnest gen
dart run bin/main.dart
```

Without a global activation every command also works as
`dart run dartnest_cli <command>` inside a package that has `dartnest_cli`
in its `dev_dependencies` (the scaffold has).

`init` writes a package that uses annotations:

```text
my_app/
  pubspec.yaml            dartnest, dartnest_annotations, dartnest_io; dev: dartnest_cli
  analysis_options.yaml
  bin/main.dart           creates the application and listens on port 8080
  lib/src/hello.dart      HelloService, HelloController, AppModule
```

`dartnest gen` reads `lib/` and writes `lib/my_app.dartnest.dart`. That
file is ordinary Dart on the explicit API: `Module appModule()` for
`AppModule` and `Controller<HelloController> helloController()` for the
controller. Commit it; it changes only when the annotations do.

```sh
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
curl 'http://localhost:8080/hello'            # {"message":"Hello, world!"}
curl 'http://localhost:8080/nothing'          # 404: {"statusCode":404,"error":"Not Found",...}
```

## Develop with hot reload

```sh
dartnest dev
```

`dev` runs `bin/main.dart`, regenerates the library on every save and hot
reloads the running process: change the greeting in `HelloService`, save,
and the next request answers with the new text, on the same port and with
the same provider instances. Add a route and it is served after the save.
See [dev-mode.md](dev-mode.md).

## Add a feature

A feature is a module with its providers and controllers. Create
`lib/src/todos.dart`:

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Keeps the todo items in memory.
@Injectable()
final class TodoList {
  final List<String> _items = [];

  /// The items, oldest first.
  List<String> all() => List.unmodifiable(_items);

  /// Adds [item].
  void add(String item) => _items.add(item);
}

/// `GET /todos` and `POST /todos`.
@Controller('/todos')
final class TodosController {
  /// Creates the controller.
  TodosController(this.list);

  /// The items.
  final TodoList list;

  /// Lists the items.
  @Get()
  List<String> all() => list.all();

  /// Adds the `item` field of the JSON body.
  @Post()
  List<String> add(@Body() Map<String, Object?> body) {
    list.add('${body['item']}');
    return list.all();
  }
}

/// The todos feature.
@Module(id: 'todos', providers: [TodoList], controllers: [TodosController])
final class TodosModule {}
```

Import it from the root module in `lib/src/hello.dart`
(`import 'todos.dart';`):

```dart
@Module(
  id: 'app',
  imports: [TodosModule],
  providers: [HelloService],
  controllers: [HelloController],
)
final class AppModule {}
```

```sh
curl -X POST -H 'content-type: application/json' -d '{"item": "milk"}' \
  localhost:8080/todos                        # ["milk"]
```

A mistake is reported before anything runs. Remove `TodoList` from
`providers` and `dartnest gen` prints, exits with 1 and leaves the
generated library as it was:

```text
lib/src/todos.dart:19:24: error: No provider for TodoList in module "todos" (resolving: TodosController). [missing_provider]
1 problem; lib/my_app.dartnest.dart was not changed.
```

## Without annotations

Everything the generator writes can be written by hand; the README's
[quick start](../README.md#without-code-generation) shows the same
application on the explicit API, and
[modules-and-di.md](modules-and-di.md) explains it.

## Next

- [Modules and dependency injection](modules-and-di.md)
- [Controllers and the request pipeline](controllers-and-pipeline.md)
- [The example application](../example/README.md): guards, pipes,
  interceptors, filters and middleware in a real API.
~~~~

**Створити `docs/modules-and-di.md`:**

~~~~markdown
# Modules and dependency injection

A module groups providers (services, repositories, guards, ...) and
controllers, and decides which of its providers other modules may use. The
container builds every provider once, at startup, after it has checked the
whole graph.

## Providers

```dart
import 'package:dartnest/dartnest.dart';

/// A typed token for a value that is not a class of its own.
const dbUrl = Token<String>('db.url');

final class Db {
  Db._(this.url);
  final String url;
  static Future<Db> connect(String url) async => Db._(url);
}

abstract interface class UserStore {
  List<String> names();
}

final class DbUserStore implements UserStore {
  DbUserStore(this.db);
  final Db db;
  @override
  List<String> names() => ['ada', 'linus'];
}

final class UsersService {
  UsersService(this.store, this.url);
  final UserStore store;
  final String url;
}

Module usersModule() => Module(
  id: 'users',
  providers: [
    Provider.value('postgres://localhost/app', token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
    Provider<UserStore>((i) => DbUserStore(i.get())),
    Provider((i) => UsersService(i.get(), i.get(dbUrl))),
  ],
  exports: [UsersService],
);

Future<void> main() async {
  final container = await Container.create(usersModule());
  final users = container.root.get<UsersService>();
  print('${users.store.names()} from ${users.url}');
  await container.close();
}
```

- `Provider((i) => X(...))` provides `X`; the type is inferred from the
  factory. `i.get()` infers the type it returns from the parameter it
  fills, so constructor arguments need no type arguments.
- `Provider<UserStore>((i) => DbUserStore(...))` provides an interface by
  an implementation: consumers ask for `UserStore`.
- `Provider.value(v, token: t)` provides a constant; `Token<T>` gives it a
  name and a type. `i.get(dbUrl)` returns a `String`.
- `Provider.async` awaits its factory during `Container.create`; every
  other provider can then `get` the result synchronously. Declare an async
  provider before the providers that use it, or put it in an imported
  module.

There are no lazy providers: when `Container.create` (or
`Application.create`) returns, every provider exists. A factory that
throws stops the startup with a `ProviderCreationError` that wraps it.

## Visibility

```dart
Module appModule() => Module(
  id: 'app',
  imports: [configModule(), usersModule()],
  controllers: [/* may use UsersService, not UserStore */],
);
```

- A provider is visible in its own module and, if it is in `exports`, in
  every module that imports that module. `UserStore` above is private to
  `users`.
- `exports` may also list tokens (`exports: [dbUrl]`) and imported modules
  (re-export).
- `global: true` makes a module's exports visible everywhere, without an
  import. Use it for configuration, as the example's `ConfigModule` does.
- A module id names one module per application. The same module imported
  from two places (an equal id, providers and imports) is built once; two
  modules with one id and different contents are a
  `DuplicateModuleIdError`.

## Dynamic modules

A module that needs parameters is a function:

```dart
Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);
```

This replaces NestJS's `forRoot` and, because providers can be async,
`forRootAsync`.

## Errors

Every DI failure is a subclass of the sealed `InjectionError`, so a test or
a startup script can match on it. Before any factory runs, the graph is
checked for duplicate module ids, import cycles, duplicate providers,
exports of something the module does not have, and a key that two imports
export into one module. While providers are created, a missing provider is
reported with the chain that needed it:

```text
MissingProviderError: No provider for Clock in module "users" (resolving: UsersService).
```

With annotations most of these errors are found by `dartnest gen`, with a
file, a line and a column, before the program is compiled. The full list
is in the [`dartnest` README](../packages/dartnest/README.md).

## The same with annotations

```dart
@Module(
  id: 'users',
  providers: [
    Value('postgres://localhost/app', token: dbUrl),
    Bind<UserStore, DbUserStore>(),
    UsersService,
  ],
  exports: [UsersService],
)
final class UsersModule {}

@Injectable()
final class UsersService {
  UsersService(this.store, @Inject(dbUrl) this.url);
  final UserStore store;
  final String url;
}
```

The generator writes `Module usersModule()` with the same providers. An
async provider has no annotation of its own: write the module that
creates it on the explicit API, wrap it in a function without required
parameters (`Module appDatabase() => databaseModule(url: ...)`) and list
that function in `imports: [appDatabase]`.
See [annotations-and-codegen.md](annotations-and-codegen.md).
~~~~

**Створити `docs/controllers-and-pipeline.md`:**

~~~~markdown
# Controllers and the request pipeline

## Controllers and routes

A controller is a class with handler methods; `Controller<T>` describes how
to create it and which routes call which method:

```dart
Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  routes: [
    Route.get('', (c, ctx) async => c.list(await ctx.query<int?>('limit'))),
    Route.get('/:id', (c, ctx) async => c.find(await ctx.param<int>('id'))),
    Route.post('', (c, ctx) async => c.create(await ctx.bodyAs(CreateUser.fromJson))),
  ],
)
```

The controller instance is created once, at startup, like a provider of
its module, so it can inject everything that module sees.

- **Paths**: static segments, `:name` parameters and a trailing `*`. A
  static segment wins over a parameter, a parameter over `*`.
- **404 and 405**: an unknown path is 404; a known path with another
  method is 405 with an `allow` header. `HEAD` is served by the `GET` route.
- **Arguments** come from the `ExecutionContext`: `param<T>`, `query<T>`
  (nullable `T` for an optional one), `header`, `bodyAs(fromJson)`, `body`
  for the raw stream. `T` is `String`, `int`, `double`, `num`, `bool` or
  `DateTime`; an enum needs a pipe:
  `ctx.query<Status>('status', pipes: [EnumPipe(Status.values)])` (the
  generator adds it for you). A value that does not convert is a 400 that
  names the parameter.
- **Results**: a `Map`, a `List` or an object with `toJson()` is JSON;
  a `String` is `text/plain`; `null` (or a `void` method) is 204; a
  `Uint8List` or a `Stream<List<int>>` is `application/octet-stream`; an
  `HttpResponse` is sent as it is. `app.serializers.register<T>(...)` adds a
  JSON conversion for a type you do not own.
- **Status and headers**: return an `HttpResponse`, or set them on
  `ctx.switchToHttp().response` and return the body, as the example's
  `TasksController.create` does for `201` and `location`.

## Errors

Throw an `HttpException` to answer with its status:

```dart
throw NotFoundException(message: 'No user $id.');
// 404 {"statusCode": 404, "error": "Not Found", "message": "No user 7."}
```

`BadRequestException`, `UnauthorizedException`, `ForbiddenException`,
`NotFoundException`, `MethodNotAllowedException` and
`ServiceUnavailableException` are built in; extend `HttpException` for
another status. Each takes an optional `details` value (a JSON value, for
example the list of invalid fields). Any other exception is a 500 with
the message `Internal server error`; it goes to `Application.create(onError:)`
(by default printed). `Application.create(debug: true)` puts the error text
and the stack trace into the 500 body; never enable it in production.

## The pipeline

```text
request
  -> middleware (app.use, outermost first)
  -> router (404 / 405)
  -> guards          (application, controller, route)
  -> interceptors    (application, controller, route; each wraps the rest)
  -> pipes           (inside ctx.param / query / bodyAs, per argument)
  -> handler
  -> serialization
exceptions from guards .. serialization
  -> exception filters (route, controller, application) -> default JSON error
```

Components are declared in `Enhancers` at three levels:

```dart
Application.create(appModule, enhancers: const Enhancers(interceptors: [Use<TimingInterceptor>()]));
Controller<T>(..., enhancers: const Enhancers(guards: [Use<ApiKeyGuard>()]));
Route.post('', ..., enhancers: const Enhancers(guards: [Use<RolesGuard>()]));
```

`Use<T>()` resolves `T` as a provider of the controller's module (for the
application level, of the root module), so a guard can inject services. An
instance (`guards: [AllowAll()]`) is used as it is.

| Component | Interface | Example file |
| --- | --- | --- |
| Guard | `FutureOr<bool> canActivate(ExecutionContext)`; `false` is 403, or throw for another status | `example/lib/src/auth/api_key_guard.dart` |
| Route metadata | a `const` subclass of `RouteMetadata`, read with `ctx.metadata<T>()`; the route's wins over the controller's | `example/lib/src/auth/roles.dart`, `roles_guard.dart` |
| Interceptor | `FutureOr<Object?> intercept(ExecutionContext, Next<Object?> next)`; call `next()` at most once | `example/lib/src/common/timing_interceptor.dart` |
| Pipe | `FutureOr<O> transform(I value, ArgumentMeta meta)`; throw `BadRequestException` to reject | `example/lib/src/common/trim_strings_pipe.dart` |
| Exception filter | `extends ExceptionFilter<E>`, `handle(E error, ExecutionContext)`; return a result or throw an `HttpException` | `example/lib/src/tasks/task_not_found_filter.dart` |
| Middleware | `Future<HttpResponse> Function(HttpRequest, Next<HttpResponse>)`, registered with `app.use` | `example/lib/src/common/request_id_middleware.dart` |

Some differences from NestJS:

- Pipes run when the handler reads an argument, on the raw value (a
  `String` for parameters, the decoded JSON for the body), before the
  built-in conversion. A pipe in `Enhancers` sees every argument, so it
  should accept `Object?` and pass through what it does not handle.
- Guards and filters do not see middleware: middleware runs outside the
  router, so an exception thrown in middleware goes straight to the default
  error response.
- A guard can pass data to the handler through `ctx.items`, a map that
  lives for one request (the example's `ApiKeyGuard` stores the caller's
  role there).

## The same with annotations

```dart
@Controller('/tasks')
@UseGuards([ApiKeyGuard])
@UsePipes([TrimStringsPipe])
@UseFilters([TaskNotFoundFilter])
final class TasksController {
  TasksController(this.service);
  final TasksService service;

  @Get()
  List<Task> list(@Query('done') bool? done) => service.list(done: done);

  @Post()
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task create(@Body() CreateTaskDto dto, ExecutionContext context) { ... }
}
```

Each type in `@UseGuards` and its siblings becomes `Use<T>()`, so it must be
a provider visible to the controller's module (the example's `TasksModule`
lists `TrimStringsPipe` and `TaskNotFoundFilter`, and imports `AuthModule`
for the guards). The complete rules for handler parameters are in the
[`dartnest_annotations` README](../packages/dartnest_annotations/README.md).
~~~~

**Створити `docs/annotations-and-codegen.md`:**

~~~~markdown
# Annotations and code generation

Annotations are a shorter way to write the explicit API. They have no
behavior: a generator reads them with the Dart analyzer and writes
`lib/<package>.dartnest.dart`, one ordinary library per package, which you
commit next to your code. Nothing else in your package is changed, and no
`part` files are involved.

## What is generated

For each class the generator writes a function:

| You write | The generated library has |
| --- | --- |
| `@Module(id: 'tasks', ...) final class TasksModule {}` | `Module tasksModule()` |
| `@Controller('/tasks') final class TasksController` | `Controller<TasksController> tasksController()` |
| `@Injectable() final class TasksService` | a private factory used by the module's `Provider` |

They are functions rather than top-level `final`s so that a hot reload can
build the graph again. Pass the root module's function to
`Application.create(appModule)`. The example's committed
[`lib/tasks_api.dartnest.dart`](../example/lib/tasks_api.dartnest.dart)
shows the whole output for a real application.

## Running the generator

| Driver | Command | Use it when |
| --- | --- | --- |
| `dartnest_cli` | `dartnest gen`, `dartnest gen --watch`, `dartnest dev` | the default; fast incremental analysis, hot reload |
| `dartnest_build` | `dart run build_runner build` / `watch` | the package already uses build_runner (see [build-runner.md](build-runner.md)) |

Both produce the same bytes. Run one driver per package.

To keep the committed file honest in CI:

```sh
dartnest gen && git diff --exit-code lib/my_app.dartnest.dart
```

The example does the same in a test (`example/test/generated_library_test.dart`).

## Static validation

The generator checks the module graph before writing anything. A problem
is printed as `path:line:column: error: message [code]`, the generated
library is left as it was, and `gen` exits with 1:

```text
lib/src/todos.dart:19:24: error: No provider for TodoList in module "todos" (resolving: TodosController). [missing_provider]
```

It finds missing and circular dependencies, duplicate module ids and
providers, invalid exports, import cycles, handler parameters it cannot
bind, private types the generated library cannot name, and more; the
[`dartnest_generator` README](../packages/dartnest_generator/README.md)
lists every code. What it cannot see is checked again by
`Application.create` at startup, so a mistake never reaches a request.

## Rules worth knowing

- `Module` and `Controller` are names of both the annotations and the
  explicit API. A file that uses annotations and also needs the explicit
  API (for `Guard`, `ExecutionContext`, `Token`, ...) imports
  `package:dartnest/dartnest.dart` with `hide Controller, Module`.
- Set `@Module(id:)` explicitly. It defaults to the class name, so a rename
  would change the id.
- Injection uses the unnamed public constructor. Every parameter is a
  non-nullable class type or carries `@Inject(token)`.
- `providers` takes `@Injectable()` classes, `Bind<Interface, Impl>()` and
  `Value(value, token: ...)`; `imports` takes `@Module` classes and
  tear-offs of functions without required parameters that return a
  `Module`, which is how hand-written modules (for example one with an
  async provider) join an annotated graph.
- A nullable `@Query` parameter is optional. A non-nullable one is
  required even when it has a Dart default value: the default is never
  used. Make it nullable and apply the default in the method.
- Route metadata are `const` instances of your `RouteMetadata` subclasses,
  placed on the method or the class, like `@Roles([Role.editor])`.

The full list is in the
[`dartnest_annotations` README](../packages/dartnest_annotations/README.md).

## One application, two styles

`example/lib/explicit.dart` wires the example's classes by hand, and
`example/test/e2e_test.dart` runs the same suite against both graphs. Read
the two side by side to see what each annotation stands for.

## Several packages

`gen` handles one package per run. A `@Module` class from another package
is imported from that package's own generated library, so generate the
dependencies first. The generator does not look inside a module from
another package (or inside a module returned by a function): it treats it
as opaque, and for the whole package that references it leaves
`missing_provider` and `circular_dependency` to `Application.create`. See
[faq.md](faq.md#known-limitations).
~~~~

**Створити `docs/adapters.md`:**

~~~~markdown
# Adapters: dart:io and shelf

`package:dartnest` has no server. An application answers an `HttpRequest`
with `app.handle(request)`; an adapter connects that to a real HTTP server.

```dart
final app = await Application.create(appModule, adapter: IoAdapter());
await app.listen(port: 8080);                  // address: 'localhost' by default
// ...
await app.close();                             // graceful; close(force: true) drops connections
```

| | `IoAdapter` (`dartnest_io`) | `ShelfAdapter` (`dartnest_shelf`) |
| --- | --- | --- |
| Server | `dart:io` `HttpServer` | `shelf_io` |
| HTTPS | `IoAdapter(securityContext: ...)` | through your own shelf server |
| Extra dependencies | none | `shelf` |
| Embed in an existing server | no | `shelfHandler(app)` |
| Default headers | none (`dart:io` defaults are cleared) | `date` (added by `shelf_io`) |

Both stream bodies in both directions, answer `HEAD` without a body, route
on the request target only (never on `Host` or `X-Forwarded-*`), have no
request body size limit (the handler reads the body as a stream), and
close gracefully: `app.close()` stops accepting connections and waits for
the requests in flight for up to `closeTimeout` (30 seconds by default),
then drops what is left. Failures that can no longer become a response (a
client that went away, a body stream that fails halfway) go to the
adapter's `onError`, by default stderr.

Both pass the same conformance suite on real sockets
(`packages/dartnest_conformance`), so an application behaves the same on
either; the example's end-to-end tests run on both.

## Choosing

- Start with `IoAdapter`: it has no dependencies and serves HTTPS itself.
- Use `ShelfAdapter` when you want shelf's ecosystem around the
  application, and `shelfHandler(app)` when the application is one part of
  a shelf server you already have:

```dart
final app = await Application.create(appModule);    // no adapter
final handler = const shelf.Pipeline()
    .addMiddleware(shelf.logRequests())
    .addHandler(shelfHandler(app));
await shelf_io.serve(handler, 'localhost', 8080);
```

Mounted under a prefix (a `shelf_router` mount, for example), the
application sees paths relative to it. Closing your server does not close
the application; call `app.close()` yourself.

## Ports and addresses

- `port: 0` asks for an ephemeral port; read it from `adapter.port` after
  `listen`. Tests use this (see `example/test/helpers/loopback_server.dart`).
- `address` is `'localhost'` by default. Inside a container, listen on
  `InternetAddress.anyIPv4` (or `'0.0.0.0'`) to be reachable from outside.
- A `listen` that fails to bind (the port is in use) throws and can be
  retried.

## Shutting down

```dart
await ProcessSignal.sigint.watch().first;
await app.close();
```

`close` is safe to call more than once. Requests that arrive while the
application closes get a 503.

## Headers you set

`HeaderMap` does not reject CR or LF in a header value. Both adapters hand
values to `dart:io`, which refuses such a value when the response is
written: the client gets no response (the connection is closed), the
`FormatException` goes to the adapter's `onError`, and no header is
injected. Never put unchecked user input into a header; see
[faq.md](faq.md#known-limitations).

## Writing an adapter

Implement `HttpAdapter` from `package:dartnest` (`listen` and `close`; the
class documentation states the contract) and run
`AdapterConformance.run` from `dartnest_conformance` against it, as
`packages/dartnest_io/test/io_adapter_conformance_test.dart` does.
`dartnest_conformance` is not published; depend on it by path or git.
~~~~

- [ ] **Step 4: Перевірити `getting-started` і `modules-and-di`**

Run, у тимчасовому пакеті:
1. `dart run dartnest_cli init <tmp>/my_app` з `packages/dartnest_cli`.
2. Додати `dependency_overrides`, як у README CLI.
3. Записати `lib/src/todos.dart` зі сніпета.
4. Додати `imports: [TodosModule]` і `import 'todos.dart';` у
   `lib/src/hello.dart`.
5. `dart pub get && dart run dartnest_cli gen && dart run bin/main.dart`.
6. `curl -X POST -H 'content-type: application/json' -d '{"item": "milk"}' localhost:8080/todos`.

Expected: `["milk"]`. Після того як `providers: [TodoList]` прибрано,
`gen` друкує рядок
`lib/src/todos.dart:19:24: error: No provider for TodoList in module "todos" (resolving: TodosController). [missing_provider]`
і виходить з 1.

Run: перший ```dart-блок `docs/modules-and-di.md` записати в `bin/di.dart`
того ж тимчасового пакета qs і виконати `dart run bin/di.dart`.
Expected: `[ada, linus] from postgres://localhost/app`.

- [ ] **Step 5: Відносні посилання**

Run:

```sh
python3 - <<'EOF'
import re,os,glob
files=['README.md','example/README.md']+glob.glob('docs/*.md')+glob.glob('packages/*/README.md')+glob.glob('packages/*/example/README.md')
bad=0
for f in files:
    for m in re.finditer(r'\]\(([^)\s]+)\)', open(f).read()):
        path,_,anchor=m.group(1).partition('#')
        if m.group(1).startswith('http') or not path: continue
        full=os.path.normpath(os.path.join(os.path.dirname(f),path))
        if not os.path.exists(full): print('MISSING',f,m.group(1)); bad+=1
        elif anchor and full.endswith('.md'):
            heads=[re.sub(r'[^a-z0-9 -]','',h.lower()).replace(' ','-') for h in re.findall(r'^#+ (.*)$',open(full).read(),re.M)]
            if anchor not in heads: print('ANCHOR',f,m.group(1)); bad+=1
print('bad',bad)
EOF
```

Expected: `bad 0` після Task 7 (до нього посилання на `dev-mode.md`,
`build-runner.md`, `testing.md`, `faq.md` ще відсутні: це очікувано,
перевірка повторюється в Task 7).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/*.md
git commit -m "docs: top-level README and the core guides"
```

---

### Task 7: Посібники dev-режиму, build_runner, тестування, FAQ

**Files:**
- Create: `docs/dev-mode.md`, `docs/build-runner.md`, `docs/testing.md`, `docs/faq.md`

**Interfaces:**
- Consumes: README `dartnest_cli` (розділ `dev`), README `dartnest_build`,
  тести прикладу.
- Produces: `faq.md#known-limitations`, `testing.md#a-test-module`.

FAQ містить обов'язкові відомі обмеження, кожне перевірене:
1. **Семантична помилка, що спустошує модель, видаляє бібліотеку.**
   Відтворено: зламаний import `dartnest_annotations` в усіх анотованих
   файлах → `No annotations in lib/; deleted lib/my_app.dartnest.dart.`,
   exit 0. Під `dev` reload не компілюється, застосунок працює на старому
   коді. Після виправлення — `Generated ...` і
   `Reloaded 3 libraries ..., 0 routes changed.`
2. **`ShapeTracker` може перезапускати зайвий раз.** Він порівнює текст
   полів, конструкторів і змінних без резолву.
3. **`@Module` з іншого пакета непрозорий.** `missing_provider` і
   `circular_dependency` лишаються на `Application.create`.
4. **`HeaderMap` не перевіряє CR/LF.** Відтворено через обидва адаптери:
   `dart:io` кидає
   `FormatException: Invalid HTTP header field value` під час запису.
   Клієнт отримує закрите з'єднання без відповіді, помилка йде в `onError`
   адаптера, ін'єкції заголовка немає.

Також у FAQ:
- build_runner видаляє бібліотеку при проблемах;
- reload не перезапускає `main`;
- осиротілий процес після `SIGKILL`;
- Dart-значення за замовчуванням у `@Query` ігнорується;
- немає ліміту тіла;
- що не входить у v1 (спека, розділ 1);
- Windows і macOS не перевірені;
- нижня межа SDK 3.8 заявлена, але не перевірена.

- [ ] **Step 1: Посібники**

**Створити `docs/dev-mode.md`:**

~~~~markdown
# Dev mode and hot reload

```sh
dartnest dev                          # runs bin/main.dart
dartnest dev -t bin/server.dart -- --port 9090
```

`dev` does what `gen --watch` does and also runs the application. After
every save it regenerates `lib/<package>.dartnest.dart` and then, in the
running process:

1. **hot reloads** the changed libraries (the Dart VM's `reloadSources`);
2. **reassembles** every dartnest application in the process: the module
   functions run again, the new graph is validated, providers that already
   exist keep their instances, new providers are created, removed ones are
   dropped, and controllers and the route table are rebuilt. The swap is
   atomic: a request that is running finishes on the old routes.

The process, its port, its open connections and the state of your
providers survive. One line per event tells you what happened:

```text
Started bin/main.dart (pid 4242, VM service http://127.0.0.1:40107/abc=/).
Reloaded 7 libraries in 82 ms, 0 routes changed.
Reloaded 7 libraries in 95 ms, 1 route changed.
Restarting bin/main.dart: lib/src/health/health_controller.dart changed a field, a constructor or a top-level variable.
```

## When it restarts instead

A reload keeps existing objects, so it cannot give them a field they were
created without. `dev` therefore restarts the process (the applications
close, requests in flight finish, a new process starts) when a saved file
changed:

- a field, a constructor, a top-level or static variable, or an enum value;
- anything the VM refuses to reload (for example a type parameter).

The restart line names the file. State held in memory starts over.

The check compares declarations as text, file by file, without resolving
types. It errs on the side of restarting: adding a field with an
initializer, which a reload could handle, still restarts.

## While the code has problems

- A problem the generator finds (`missing_provider`, ...) is printed and
  nothing is reloaded: the application keeps running the previous code.
- A compile error outside `lib/` is printed by the reload and changes
  nothing either.
- A reassemble that fails (a factory that throws, an invalid graph) keeps
  the previous modules and routes and prints the error.
- An application that exits or does not start is started again after the
  next change, never in a loop.

## Keys

In a terminal, `r` reloads and `R` restarts (both also start an
application that is not running). Ctrl+C stops `dev` and the application.
In a terminal the application receives the Ctrl+C too and may end before
it closed gracefully; `SIGTERM` sent to `dev` alone closes it first.

## Things to know

- **A reload does not run `main` again.** Changes to the server setup in
  `main` (the adapter, the port, middleware added with `app.use`) take
  effect after `R`.
- **A `Provider.value` keeps its old value**, like every kept instance. A
  changed configuration value needs a restart.
- **Only `lib/` and the directory of the target are watched.** A change in
  a path dependency or in `tool/` is reloaded with `r`, without the restart
  check; press `R` after changing a field there.
- **`pubspec.yaml` is not watched.** Run `dart pub get`, then `R`.
- **If `dev` is killed with `SIGKILL`, the application keeps running**:
  Dart has no parent-death signal. Stop the orphan yourself (its pid is in
  the `Started` line).
- **Only for development.** `dev` runs the application with the VM service
  enabled on loopback. The service extensions `dev` uses
  (`ext.dartnest.reassemble`, `ext.dartnest.close`) are registered only
  outside product mode, so AOT builds (`dart compile exe`) contain none of
  it.

The [`dartnest_cli` README](../packages/dartnest_cli/README.md#dev) has
every rule, timeout and exit code; the [example](../example/README.md#hot-reload)
walks through a session.
~~~~

**Створити `docs/build-runner.md`:**

~~~~markdown
# build_runner

`dartnest_build` runs the dartnest generator as a build_runner builder. It
writes the same `lib/<package>.dartnest.dart`, byte for byte, as
`dartnest gen`. Use it when the package already runs build_runner for
other builders (`json_serializable`, `freezed`); otherwise `dartnest gen`
and `dartnest dev` are faster and need no configuration.

```yaml
# pubspec.yaml
dev_dependencies:
  build_runner: ^2.10.5
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
dart run build_runner build
dart run build_runner watch
dart run build_runner build --only-check   # build_runner 2.16+: fail if the output is out of date
```

The `package` option is required: build_runner must know the output's
name before the build, and a builder cannot read it from `pubspec.yaml` in
time. A missing or wrong name fails the build with the `build.yaml` to
write.

## Differences from `dartnest gen`

- **Problems delete the library.** `gen` keeps the previous library while
  the sources have problems; build_runner deletes the previous output of a
  failed step, so code that imports the library stops compiling until the
  problems are fixed.
- **The output belongs to build_runner.** A hand-written file at
  `lib/<package>.dartnest.dart` is deleted; `gen` refuses to overwrite one.
- **Types from other builders resolve.** The builder runs after the
  builders that write `.dart` files, so a DTO generated by
  `json_serializable` is visible. `gen` reads only files on disk.
- **No hot reload.** `build_runner watch` regenerates; restart the
  application yourself.

## Using both

They write the same bytes and the same header, so either accepts the
other's output. Give the library one writer at a time:

- `dart run build_runner watch` when other builders run anyway, or
- `dartnest dev` for hot reload. If `build_runner watch` must run beside
  it, set `enabled: false` under `dartnest_build:` in `build.yaml` so the
  two do not both write the library.

Custom constructs need a builder of your own; the
[`dartnest_build` README](../packages/dartnest_build/README.md#own-constructs)
shows the `build.yaml`.
~~~~

**Створити `docs/testing.md`:**

~~~~markdown
# Testing

Everything in dartnest is a value, so tests need no special module and no
server. The example's `test/` directory uses each technique below.

## Services: plain classes

A service is a class with a constructor; create it with what it needs.

```dart
test('list filters by state', () {
  final service = TasksService(InMemoryTaskStore());
  expect(service.list(done: false).map((task) => task.id), [1]);
});
```

## A test module

To test several providers together, or to swap one for a fake, write a
module for the test with the explicit API, also when the application uses
annotations:

```dart
test('a test module provides a fake store through DI', () async {
  final container = await Container.create(
    Module(
      id: 'test',
      providers: [
        Provider<TaskStore>((i) => _EmptyStore()),
        Provider((i) => TasksService(i.get())),
      ],
    ),
  );
  addTearDown(container.close);

  expect(container.root.get<TasksService>().list(), isEmpty);
});
```

There is no `overrideProvider`: compose the graph you want instead. A
module function with parameters (`tasksModule({TaskStore? store})`) is the
usual way to let tests replace a dependency of a real module.

## The HTTP layer without a socket

`TestClient` from `package:dartnest/testing.dart` sends requests through
`app.handle`, the full pipeline (middleware, guards, interceptors, pipes,
filters, serialization) without a server:

```dart
test('GET /health', () async {
  final app = await Application.create(appModule);
  addTearDown(app.close);

  final response = await TestClient(app).get('/health');

  expect(response.status, 200);
  expect(response.json, {'status': 'ok', 'name': 'tasks_api'});
});
```

`TestClient` has `get`, `post`, `put`, `patch`, `delete` and `request`;
`json:` sends a JSON body, `headers:` adds headers. A `TestResponse` has
`status`, `headers`, `bytes`, `text` and `json`. Unlike a real server it
keeps the body of a `HEAD` response.

## End to end on a real socket

To test an adapter as well, listen on an ephemeral loopback port and use
`HttpClient`:

```dart
final adapter = IoAdapter();
final app = await Application.create(appModule, adapter: adapter);
await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
final uri = Uri.http('127.0.0.1:${adapter.port}', '/health');
```

`example/test/helpers/loopback_server.dart` wraps this for both adapters,
and `example/test/e2e_test.dart` runs one suite on both. Pass an
`onError` that collects errors and expect the list to be empty in
`tearDown`: a failure that never reached a response is otherwise invisible.

## The generated library

Check in a test (or in CI) that the committed library matches the sources:

```sh
dartnest gen && git diff --exit-code lib/my_app.dartnest.dart
```

`example/test/generated_library_test.dart` does it in Dart: it copies the
package to a temporary directory, generates there, and compares the
result with the committed file.

## Both styles, one suite

When a package keeps a hand-written graph next to the annotations (as the
example does to document them), run the same tests against both module
functions:

```dart
for (final (name, root) in [('annotations', appModule), ('explicit', explicitAppModule)]) {
  group(name, () { /* ... */ });
}
```
~~~~

**Створити `docs/faq.md`:**

```markdown
# FAQ and known limitations

## FAQ

**Do I have to use annotations?**
No. The explicit API is the framework; annotations are a shorter way to
write it. Applications, tests and libraries work without any code
generation, and the two styles can be mixed in one graph.

**Why one generated file per package instead of `part` files?**
Your files stay untouched, the output is one reviewable diff, and the
generator can validate the whole module graph at once.

**Should I commit the generated library?**
Yes. It is ordinary Dart that changes only when the annotations do, and
committing it means `dart run` works right after `dart pub get`. Check it
in CI with `dartnest gen && git diff --exit-code`.

**Does it work with AOT (`dart compile exe`)?**
Yes. Nothing uses `dart:mirrors`. The hot reload hooks are registered only
outside product mode, so an AOT binary contains none of them.

**Can I use Flutter's `dart:ui` or run in the browser?**
`package:dartnest` itself does not import `dart:io`, but both adapters do,
and the framework is built and tested as a server framework only.

**How do I override a provider in a test?**
There is no `overrideProvider`; build a test module with the providers you
want. See [testing.md](testing.md#a-test-module).

**Where are lifecycle hooks (`OnModuleInit`, `OnApplicationShutdown`)?**
Not in 0.1.0. An async provider's factory is the place for startup work;
for shutdown, close your resources after `await app.close()`.

**Is there OpenAPI support?**
Not yet. The generator already collects what an OpenAPI document needs
(types, doc comments, DTOs); a `dartnest_openapi` package is the next
planned milestone.

**Which Dart versions are supported?**
The packages declare `sdk: ^3.8.0` and use no language feature newer than
Dart 3.8. Development and the tests ran on Dart 3.13; CI runs the
oldest supported SDK (3.8.0) and the current stable.

## Not in 0.1.0

Request-scoped providers, lifecycle hooks, WebSockets and server-sent
events, GraphQL, microservice transports, OpenAPI generation, a `relic`
adapter, and code scaffolding beyond `dartnest init` (no `nest g`).

## Known limitations

These are known and deliberate trade-offs or open problems of 0.1.0.

**An unresolved annotation import deletes the generated library.**
`dartnest gen` keeps the previous library while the sources have problems
it can report: syntax errors and its own diagnostics. An analyzer error
that hides the annotations is not such a problem. If the import of
`package:dartnest_annotations` is broken in every annotated file (a typo,
a missing dependency), the generator sees no annotations and deletes
`lib/<package>.dartnest.dart` in that run, exiting with 0
(`No annotations in lib/; deleted lib/my_app.dartnest.dart.`). Fix the
import and run `gen` again; the file comes back unchanged. Under `dev` the
reload that follows fails to compile and the application keeps running the
previous code; the next save after the fix regenerates and reloads.

**`dev` may restart when a reload would have been enough.** The check
that decides between a reload and a restart compares fields,
constructors, top-level and static variables and enum values as text,
without resolving types. Any change there restarts the process, also when
a reload could have handled it (a new field with an initializer, a
reformatted constructor). The reverse does not happen for files `dev`
watches; for files it does not watch (path dependencies, `tool/`), press
`R` after changing a field.

**The generator cannot see into a module from another package.** A
`@Module` class from another package, and a module returned by a
function, are opaque to the generator. For the whole package that
references one, `missing_provider` and `circular_dependency` are not
reported by `dartnest gen`; `Application.create` still reports them at
startup, with the resolution chain.

**`HeaderMap` does not validate header values.** The core accepts CR and
LF in a header value. With both bundled adapters such a value never
reaches the wire: `dart:io` refuses it when the response is written, the
client's connection is closed without a response, and the error goes to
the adapter's `onError`. A custom adapter must validate values itself.
Do not copy unchecked user input into response headers.

**build_runner deletes the library on problems.** With `dartnest_build`,
a failed build step deletes the previous `lib/<package>.dartnest.dart`, so
code that imports it stops compiling until the problems are fixed.
`dartnest gen` keeps the previous file instead. See
[build-runner.md](build-runner.md).

**A hot reload does not run `main` again.** Changes to the server setup in
`main` need a restart (`R`). A `Provider.value` keeps its old value across
reloads.

**Killing `dev` with `SIGKILL` leaves the application running.** Dart has
no parent-death signal. Stop the orphan process yourself; its pid is in
the `Started` line.

**A Dart default value of a `@Query` parameter is ignored.** A
non-nullable `@Query('limit') int limit = 20` is still required (a
request without it gets a 400). Declare `int? limit` and write
`limit ?? 20` in the method.

**No request body size limit.** Handlers read the body as a stream and
decide how much to accept; `bodyAs` reads all of it. Put a limit in a
proxy or a middleware if clients are untrusted.

**Platforms.** Development and every test run on Linux. macOS is expected
to work like Linux but is not tested. Windows is not verified: path
handling in the CLI is written for it, but `dev` (signals, the terminal
keys, process restarts) has never run there.

**The SDK floor is declared, not yet tested.** The packages declare Dart
3.8; the local runs used Dart 3.13. The CI workflow tests 3.8.0, but it
has not run yet.
```

- [ ] **Step 2: Посилання**

Run: скрипт з Task 6, Step 5.
Expected: `bad 0`.

- [ ] **Step 3: Відтворити обмеження 1 (раз, вручну)**

Run, у пакеті з Task 6, Step 4:
1. `sed -i "s#dartnest_annotations/dartnest_annotations.dart#dartnest_annotations/dartnest_annotation.dart#" lib/src/*.dart && dart run dartnest_cli gen; echo $?`
2. Повернути import і знову запустити `gen`.

Expected: `No annotations in lib/; deleted lib/my_app.dartnest.dart.`,
`0`; після повернення — `Generated lib/my_app.dartnest.dart`.

- [ ] **Step 4: Commit**

```bash
git add docs/*.md
git commit -m "docs: dev mode, build_runner, testing and FAQ guides"
```

---

### Task 8: CI, чекліст випуску, узгодженість ROADMAP/спеки/CLAUDE.md, фінальний dry-run

**Files:**
- Create: `.github/workflows/ci.yaml`, `docs/RELEASING.md`
- Modify: `CLAUDE.md`, `docs/superpowers/ROADMAP.md`, `docs/superpowers/specs/2026-10-13-dartnest-design.md`

**Interfaces:**
- Consumes: порядок публікації (залежності з Task 1), команди всіх
  попередніх задач.
- Produces: `docs/RELEASING.md` — єдине місце, де описано ручні кроки
  випуску.

Порядок публікації: `dartnest_annotations`, `dartnest`, `dartnest_io`,
`dartnest_shelf`, `dartnest_generator`, `dartnest_cli`, `dartnest_build`.
pub.dev відхиляє завантаження, у якого `dependencies` ще немає на pub.dev
(`PackageRejectedException.dependencyDoesNotExists`). `dev_dependencies`
не перевіряються. Тому порядок обов'язковий, а неопубліковані
dev-залежності (OD6) — ні.

- [ ] **Step 1: CI**

**Створити `.github/workflows/ci.yaml`:**

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

permissions:
  contents: read

# Every package and the example, on the SDK floor (3.8.0) and on stable.
# Formatting, lints and the publish dry-run use stable only: the formatter's
# output and the lint set change between SDKs, and pub's checks are those of
# the SDK a release is published with.
jobs:
  test:
    name: Test (Dart ${{ matrix.sdk }})
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        sdk: ['3.8.0', stable]
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: ${{ matrix.sdk }}

      - name: Install dependencies (workspace)
        run: dart pub get

      - name: Verify formatting
        if: matrix.sdk == 'stable'
        run: dart format --output=none --set-exit-if-changed packages example

      - name: Analyze
        if: matrix.sdk == 'stable'
        run: dart analyze --fatal-infos

      - name: Unit tests
        run: |
          for dir in packages/*/ example/; do
            echo "::group::$dir"
            (cd "$dir" && dart test) || exit 1
            echo "::endgroup::"
          done

      - name: Integration tests (dev, build_runner)
        run: |
          (cd packages/dartnest_cli && dart test integration)
          (cd packages/dartnest_build && dart test integration)

      - name: Generation benchmark
        run: cd packages/dartnest_cli && dart test benchmark

  publish-dry-run:
    name: Publish dry-run
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies (workspace)
        run: dart pub get

      # In the order of docs/RELEASING.md; any warning fails the job.
      - name: dart pub publish --dry-run
        run: |
          for package in dartnest_annotations dartnest dartnest_io dartnest_shelf \
              dartnest_generator dartnest_cli dartnest_build; do
            echo "::group::$package"
            (cd "packages/$package" && dart pub publish --dry-run) || exit 1
            echo "::endgroup::"
          done
```

- [ ] **Step 2: Прогнати кроки CI локально (stable)**

Run:

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages example
dart analyze --fatal-infos
for dir in packages/*/ example/; do (cd "$dir" && dart test 2>&1 | tail -1); done
(cd packages/dartnest_cli && dart test integration 2>&1 | tail -1)
(cd packages/dartnest_build && dart test integration 2>&1 | tail -1)
(cd packages/dartnest_cli && dart test benchmark 2>&1 | tail -1)
```

Expected: `0 changed`; `No issues found!`. Кількості тестів:
- unit: `+276`, `+6`, `+18`, `+136`, `+14`, `+172`, `+47`, `+68`, `+54`;
- integration: `+5` (cli), `+1` (build);
- benchmark: `+1`.

- [ ] **Step 3: Чекліст випуску**

**Створити `docs/RELEASING.md`:**

```markdown
# Releasing

How a version of the dartnest packages reaches pub.dev. Every step that
leaves this machine (creating the GitHub repository, pushing, publishing,
tagging) is done by a maintainer by hand; nothing in this repository runs
it automatically.

## Packages and order

Seven packages are published, always together and with the same version
(lockstep): a release bumps all of them, even a package without changes, so
`^0.1.0` constraints between them never mix versions.

| Order | Package | Depends on (published) |
| --- | --- | --- |
| 1 | `dartnest_annotations` | none |
| 2 | `dartnest` | none |
| 3 | `dartnest_io` | `dartnest` |
| 4 | `dartnest_shelf` | `dartnest` |
| 5 | `dartnest_generator` | none (dev: `dartnest`, `dartnest_annotations`) |
| 6 | `dartnest_cli` | `dartnest_generator` |
| 7 | `dartnest_build` | `dartnest_generator` |

pub.dev rejects an upload whose `dependencies` are not on pub.dev yet, so
publish in this order. It does not check `dev_dependencies`.

Not published (`publish_to: none`): `dartnest_conformance` (the adapters'
test suite), the generator's fixture packages `cases_app` and `users_app`,
and the example `tasks_api`. Published packages may list them as dev
dependencies: pub.dev does not require them to exist (checked in the
pub.dev source, `PackageBackend`, on 2026-10-14), pana's checks drop them,
and pub ignores the dev dependencies of a dependency.

## Before the first release

1. **The name.** The packages are named `dartnest*`. On 2026-10-14 none of
   the seven names was taken on pub.dev
   (`https://pub.dev/api/packages/<name>` answered 404). Check again right
   before publishing; a name is taken forever once published. To rename,
   replace `dartnest` in every pubspec, import, README and doc
   (`git grep -l dartnest`), then run every check below.
2. **The repository.** Every pubspec points to
   `https://github.com/4akLoon/dartnest` (branch `master`). Create that
   repository and push `master`, or replace the URL everywhere:
   `git grep -l 'github.com/4akLoon/dartnest'`.
3. **CI.** Push, and wait for `.github/workflows/ci.yaml` to pass on both
   SDKs (3.8.0 and stable). Until it has run once, the SDK floor 3.8 is
   declared but not verified.
4. **The publisher (optional).** A verified publisher (a domain you own)
   shows on pub.dev instead of a personal account. It can be added after
   the first upload with `dart pub` and the pub.dev admin page.

## Every release

1. Pick the version (see "Versions" below) and set it in all seven
   `pubspec.yaml` files and in every `^x.y.z` constraint between them,
   including `example/`, `packages/dartnest_conformance` and the generator
   fixtures. `packages/dartnest_cli/lib/src/init/project_template.dart`
   (`dartnestVersion`) and the `^0.1.0` snippets in the READMEs and `docs/`
   name the version users should depend on: update them too.
2. Add a `## x.y.z` section at the top of each package's `CHANGELOG.md`.
   pub warns when the changelog does not mention the version being
   published. A package without changes gets "No changes; released with
   the other dartnest packages."
3. Run the checks on a clean `master`:

   ```sh
   dart pub get
   dart format --output=none --set-exit-if-changed packages example
   dart analyze --fatal-infos
   for dir in packages/*/ example/; do (cd "$dir" && dart test) || break; done
   (cd packages/dartnest_cli && dart test integration && dart test benchmark)
   (cd packages/dartnest_build && dart test integration)
   ```

4. Dry-run every package, in the order above. Each must end with
   `Package has 0 warnings.` and exit with 0 (any warning exits with 65):

   ```sh
   for package in dartnest_annotations dartnest dartnest_io dartnest_shelf \
       dartnest_generator dartnest_cli dartnest_build; do
     (cd "packages/$package" && dart pub publish --dry-run) || break
   done
   ```

   The dry-run also fails on uncommitted changes: commit first.
5. Commit (`chore: release x.y.z`) and push; wait for CI.
6. Publish, in the same order, one package at a time:

   ```sh
   cd packages/dartnest_annotations && dart pub publish
   ```

   `dart pub publish` asks for confirmation and, the first time, for a
   Google login in the browser. Wait until each package's page shows the
   new version before publishing the next one.
7. Tag the commit, one tag per package, and push the tags:

   ```sh
   for package in dartnest_annotations dartnest dartnest_io dartnest_shelf \
       dartnest_generator dartnest_cli dartnest_build; do
     git tag "$package-vx.y.z"
   done
   git push origin --tags
   ```

## After publishing

- On each package's pub.dev page: the score (pana) and its suggestions,
  the example tab, the API docs (dartdoc runs on pub.dev) and that the
  `repository` link resolves.
- Outside the repository, with no path overrides:

  ```sh
  dart pub global activate dartnest_cli
  dartnest init /tmp/release_check && cd /tmp/release_check
  dart pub get && dartnest gen && dart run bin/main.dart
  curl 'localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
  ```

- Start the next version: CHANGELOG sections are added when a change is
  made, under the version it will ship in.

## Versions

Until 1.0.0, a breaking change raises the minor version (0.1.0 → 0.2.0)
and anything else the patch version. A change of the generator's output
for the same sources is breaking (users' committed generated files
change). Prereleases (`0.2.0-dev.1`) are possible but are not shown to
users by default; the lockstep rule applies to them too.

## Automated publishing (later)

pub.dev can publish from GitHub Actions when a tag is pushed, without a
token: enable "Automated publishing" on each package's admin page (tag
pattern `<package>-v{{version}}`), then add a workflow with
`dart-lang/setup-dart/.github/workflows/publish.yml`. The first version of
each package must still be published by hand.
```

- [ ] **Step 4: CLAUDE.md**

**Замінити в `CLAUDE.md`:**

```markdown
  `docs/superpowers/plans/`; the next plan is written after the previous
  stage ships.

Minimum SDK: Dart 3.8 (`^3.8.0`), also for generated code.
```

**на:**

```markdown
  `docs/superpowers/plans/`; the next plan is written after the previous
  stage ships.
- User documentation: `README.md` and `docs/*.md` (English); the example
  application: `example/` (`tasks_api`, a workspace member, not published);
  releases: `docs/RELEASING.md`.

Minimum SDK: Dart 3.8 (`^3.8.0`), also for generated code.
```

**Замінити в `CLAUDE.md`:**

```markdown
dart analyze                          # repo root; must print "No issues found!"
cd packages/dartnest && dart test     # same for every package
dart format packages                  # a second run must change 0 files
# packages/dartnest_generator, after a deliberate change of generated output:
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
```

**на:**

```markdown
dart analyze                          # repo root; must print "No issues found!"
cd packages/dartnest && dart test     # same for every package
dart format packages example          # a second run must change 0 files
cd example && dart test               # the example: e2e on both adapters, golden check
# the example, after changing its annotations (commit the result):
cd example && dart run dartnest_cli gen
# every published package, in release order, must print "0 warnings":
cd packages/dartnest && dart pub publish --dry-run
# packages/dartnest_generator, after a deliberate change of generated output:
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
```

**Замінити в `CLAUDE.md`:**

```markdown
Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(core): ...`, `fix(...)`, `refactor(...)`, `docs: ...`, `test(...)`).

## Design rules
```

**на:**

```markdown
Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(core): ...`, `fix(...)`, `refactor(...)`, `docs: ...`, `test(...)`).
`.github/workflows/ci.yaml` runs these commands on Dart 3.8.0 and stable.

## Releases

- The seven published packages share one version (lockstep); every
  constraint between workspace members is `^<that version>`. Publishing,
  tags and pushes are done by a maintainer by hand, following
  `docs/RELEASING.md`; no change here publishes anything.
- A user-visible change adds a line to the `CHANGELOG.md` of each package
  it touches, under the version it will ship in.
- Each published package has its own `LICENSE` (a copy of the root one) and
  a self-contained `analysis_options.yaml` (pub.dev analyzes a package
  without the repository around it): the root options plus
  `public_member_api_docs`. A change of the root options is repeated there.
- A public member without `///` fails `dart analyze`
  (`public_member_api_docs` in every published package).

## Design rules
```

**Замінити в `CLAUDE.md`:**

```markdown
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. `dart analyze` clean, tests green, `dart format packages` changes 0
   files, and this file / `docs/` updated if behaviour or structure changed.

## Language
```

**на:**

```markdown
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. `dart analyze` clean, tests green, `dart format packages example`
   changes 0 files, and this file / `docs/` / the package READMEs updated
   if behaviour or structure changed.

## Language
```

- [ ] **Step 5: ROADMAP і спека**

У ROADMAP ✅ стояв лише на рядках 5b і 6. Етапи 1–5 злиті в master
(пам'ять проєкту й git-історія), тож ✅ проставлено всім. Рядок 7
перефразовано: «готовність до випуску» замість «публікація».

**Замінити в `docs/superpowers/ROADMAP.md`:**

```markdown
| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 1 | **Ядро DI** (план `2026-10-13-dartnest-core-di.md`) | `dartnest` | `Container.create(module)` з модулями, провайдерами, токенами, областями видимості, жадібною async-ініціалізацією; всі помилки графа — типізовані, з ланцюжком |
| 2 | **HTTP-конвеєр** (план `2026-10-13-dartnest-http-pipeline.md`) | `dartnest` | `HttpRequest/HttpResponse`, radix-роутер, `ExecutionContext`, `Controller<T>`/`Route` на `HandlerSpec`, guards → interceptors → pipes → handler → filters, серіалізація, `Application.create`, `app.handle`, `TestClient`; e2e без сервера |
| 3 | **Адаптери** (план `2026-10-13-dartnest-adapters.md`) | `dartnest_io`, `dartnest_shelf` | Обидва проходять спільний conformance-набір на реальних сокетах; `shelfHandler(app)` вбудовується в shelf-пайплайн |
| 4 | **Анотації та генератор** (план `2026-10-13-dartnest-annotations-generator.md`) | `dartnest_annotations`, `dartnest_generator` | `Collector` → `PackageModel` (з doc-коментарями, типами, `DtoModel`); `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`; статична валідація з `path:line:col`; golden-тести; згенерований код проходить ті самі e2e, що явний |
| 5 | **CLI** (план `2026-10-14-dartnest-cli.md`) | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
| 5b | **Hot reload / hot restart** (план `2026-10-14-dartnest-hot-reload.md`) ✅ | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
| 6 | **build_runner-драйвер** (план `2026-10-14-dartnest-build-runner.md`) ✅ | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
| 7 | **Приклад і документація** | `example/`, README, pub.dev | Один застосунок у двох стилях, e2e на обох адаптерах у CI; README з quick start для обох стилів; публікація `0.1.0` |

Вимоги до ядра заради hot reload (спека, 10.1) діють з етапу 2: `Application.create`
```

**на:**

```markdown
| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 1 | **Ядро DI** (план `2026-10-13-dartnest-core-di.md`) ✅ | `dartnest` | `Container.create(module)` з модулями, провайдерами, токенами, областями видимості, жадібною async-ініціалізацією; всі помилки графа — типізовані, з ланцюжком |
| 2 | **HTTP-конвеєр** (план `2026-10-13-dartnest-http-pipeline.md`) ✅ | `dartnest` | `HttpRequest/HttpResponse`, radix-роутер, `ExecutionContext`, `Controller<T>`/`Route` на `HandlerSpec`, guards → interceptors → pipes → handler → filters, серіалізація, `Application.create`, `app.handle`, `TestClient`; e2e без сервера |
| 3 | **Адаптери** (план `2026-10-13-dartnest-adapters.md`) ✅ | `dartnest_io`, `dartnest_shelf` | Обидва проходять спільний conformance-набір на реальних сокетах; `shelfHandler(app)` вбудовується в shelf-пайплайн |
| 4 | **Анотації та генератор** (план `2026-10-13-dartnest-annotations-generator.md`) ✅ | `dartnest_annotations`, `dartnest_generator` | `Collector` → `PackageModel` (з doc-коментарями, типами, `DtoModel`); `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`; статична валідація з `path:line:col`; golden-тести; згенерований код проходить ті самі e2e, що явний |
| 5 | **CLI** (план `2026-10-14-dartnest-cli.md`) ✅ | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
| 5b | **Hot reload / hot restart** (план `2026-10-14-dartnest-hot-reload.md`) ✅ | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
| 6 | **build_runner-драйвер** (план `2026-10-14-dartnest-build-runner.md`) ✅ | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
| 7 | **Приклад, документація, готовність до випуску** (план `2026-10-14-dartnest-example-docs-release.md`) ✅ | `example/`, `README.md`, `docs/`, усі пакети | Один застосунок у двох стилях, e2e на обох адаптерах у CI; README з quick start для обох стилів; кожен публікований пакет проходить `dart pub publish --dry-run` без попереджень. Сама публікація `0.1.0` — ручні кроки мейнтейнера за `docs/RELEASING.md` |

Вимоги до ядра заради hot reload (спека, 10.1) діють з етапу 2: `Application.create`
```

**Замінити в `docs/superpowers/specs/2026-10-13-dartnest-design.md`:**

```markdown
# dartnest — NestJS-подібний бекенд-фреймворк на Dart без `dart:mirrors`

Дата: 2026-10-13. Статус: чернетка дизайну для рев'ю.
Робоча назва пакетів — `dartnest`; підлягає заміні.

## 1. Мета та контекст
```

**на:**

```markdown
# dartnest — NestJS-подібний бекенд-фреймворк на Dart без `dart:mirrors`

Дата: 2026-10-13. Статус: v1.0 реалізовано (етапи 1–7 роадмапу); репозиторій
готовий до випуску `0.1.0`, сам випуск — ручні кроки `docs/RELEASING.md`.
Назва пакетів — `dartnest` (2026-10-14 усі сім імен вільні на pub.dev);
остаточно фіксується першою публікацією.

## 1. Мета та контекст
```

**Замінити в `docs/superpowers/specs/2026-10-13-dartnest-design.md`:**

```markdown
| `dartnest_conformance` | Спільний conformance-набір для адаптерів (непублікований тестовий пакет, `package:test` лише тут і в `test/`) | `dartnest`, `test` |
| `dartnest_generator` | Логіка генерації: analyzer `LibraryElement` → код явного API; набір `Construct` | `analyzer`, `code_builder`, `dart_style` |
| `dartnest_cli` | `dart run dartnest_cli gen [--watch]` | `dartnest_generator`, `watcher` |
| `dartnest_build` | Builder для build_runner (агрегуючий, вхід `lib/$lib$`) | `dartnest_generator`, `build` |
| `dartnest_openapi` (v1.1) | `OpenApiConstruct` (статичний `openapi.json` + код документа), модуль `openApiModule` з `/openapi.json` і UI (Scalar/Swagger) | `dartnest`, `dartnest_generator` |
```

**на:**

```markdown
| `dartnest_conformance` | Спільний conformance-набір для адаптерів (непублікований тестовий пакет, `package:test` лише тут і в `test/`) | `dartnest`, `test` |
| `dartnest_generator` | Логіка генерації: analyzer `LibraryElement` → код явного API; набір `Construct` | `analyzer`, `code_builder`, `dart_style` |
| `dartnest_cli` | `dart run dartnest_cli gen [--watch]`, `dev`, `init` | `dartnest_generator`, `watcher`, `vm_service` |
| `dartnest_build` | Builder для build_runner (агрегуючий, вхід `lib/$lib$`) | `dartnest_generator`, `build` |
| `dartnest_openapi` (v1.1) | `OpenApiConstruct` (статичний `openapi.json` + код документа), модуль `openApiModule` з `/openapi.json` і UI (Scalar/Swagger) | `dartnest`, `dartnest_generator` |
```

**Замінити в `docs/superpowers/specs/2026-10-13-dartnest-design.md`:**

```markdown
  самі e2e-тести, що й явний варіант».
- `example/`: один застосунок у двох стилях (явний і анотаційний), e2e на
  обох адаптерах у CI.

## 9. Порядок реалізації (високорівнево)
```

**на:**

```markdown
  самі e2e-тести, що й явний варіант».
- `example/`: один застосунок у двох стилях (явний і анотаційний), e2e на
  обох адаптерах у CI. Реалізація (етап 7): пакет `tasks_api` — член
  workspace, не публікується; анотаційний граф генерує `dartnest_cli gen`
  (згенерований файл закомічено, тест порівнює його з виходом `gen`),
  явний — `lib/explicit.dart`; один e2e-набір на обох графах і обох
  адаптерах через loopback з ефемерним портом.

## 9. Порядок реалізації (високорівнево)
```

- [ ] **Step 6: Commit і фінальний dry-run**

```bash
git add .github docs CLAUDE.md
git commit -m "chore: CI workflow, release checklist and status updates"
```

Run: `git status --short` (порожньо), потім:

```sh
for p in dartnest_annotations dartnest dartnest_io dartnest_shelf dartnest_generator dartnest_cli dartnest_build; do
  (cd packages/$p && dart pub publish --dry-run > /tmp/dry-$p.txt 2>&1; echo "$p exit=$? $(tail -1 /tmp/dry-$p.txt)")
done
```

Expected: сім рядків `exit=0 Package has 0 warnings.` Розміри архівів:
annotations 6 KB, dartnest 76 KB, io 10 KB, shelf 11 KB, generator 72 KB,
cli 54 KB, build 12 KB.

На цьому план закінчується. `dart pub publish` без `--dry-run`, `git push`,
`git tag` і створення репозиторію — ручні кроки `docs/RELEASING.md`.

---

## Самоперевірка

**Покриття вимог.**

| Вимога | Задача |
|---|---|
| Спека §8: `example/`, один застосунок у двох стилях, e2e на обох адаптерах у CI | 2, 3, 8 (`ci.yaml`) |
| ROADMAP 7: README з quick start для обох стилів | 6 |
| Модулі, DI, контролери, guards/pipes/filters, interceptor, middleware, `dart:io`-адаптер у прикладі | 2, 3 |
| Анотації з закоміченим файлом CLI + golden-перевірка | 2 (Step 5, Step 7) |
| Hot reload через `dartnest dev` на прикладі | 3 (Step 6, вручну), README прикладу, `docs/dev-mode.md` |
| Посібники: getting started, модулі й DI, контролери й конвеєр, анотації й кодоген, адаптери, dev-режим, build_runner, тестування, FAQ/обмеження | 6, 7 |
| Чотири обов'язкові обмеження | 7 (`faq.md`) |
| pub.dev: версії, `publish_to`, repository, LICENSE, CHANGELOG, `^0.1.0` проти workspace, приклади, dartdoc, analysis options, topics | 1, 4, 5 |
| Узгодженість ROADMAP / спеки / CLAUDE.md | 8 |
| Лише dry-run, нічого назовні | Global Constraints, 8 |

**Плейсхолдери.** Немає TBD/TODO; кожен файл має повний вміст. Виняток —
`example/lib/tasks_api.dartnest.dart`: його пише `dart run dartnest_cli gen`
(Task 2, Step 5), а golden-тест гарантує, що результат один.

**Узгодженість імен.** Між Tasks 2/3 і документацією збігаються імена:
`appModule`/`explicitAppModule`, `TasksApp.create`, `LoopbackServer`,
`ServerOptions`, `ModuleStyle`, `AdapterKind`, ключі
`reader-key`/`editor-key`, токени `appName`/`apiKeys`. Вивід
`dartnest dev` і `gen` у документах скопійовано з реальних запусків.

**Відтворення плану (replay).** План механічно застосовано до свіжої копії
`70e188a` у `/tmp/claude-1000/s7/replay`: кожен блок «Створити / Замінити»
і кожна команда «Виконати», з комітом після кожної задачі. Результат
порівняно з робочою копією, де план писався. Розбіжностей у дереві немає
(`git diff --stat` порожній), разом з байт-у-байт однаковим
`example/lib/tasks_api.dartnest.dart`. Після replay пройшли:
- `dart pub get`;
- `dart analyze --fatal-infos` → `No issues found!`;
- `dart format` → 0 changed;
- усі unit-, integration- і benchmark-тести з кількостями вище;
- `dart pub publish --dry-run` усіх семи пакетів → `0 warnings`, exit 0.

**Що dry-run показував і як план це закриває.**

| Знахідка dry-run (база `70e188a`) | Розв'язання |
|---|---|
| error: немає `LICENSE` | Task 1, Step 4 |
| error: `test/fixtures/localhost_key.pem` схожий на приватний ключ (`dartnest_io`) | `false_secrets` (Task 1) — це self-signed ключ для HTTPS-тесту |
| warning: немає `homepage`/`repository` | `repository` + `issue_tracker` (OD3) |
| warning: немає `CHANGELOG.md` / не згадує версію | Tasks 4–5 |
| 21 warning у `dartnest_generator`: fixture-файли імпортують `dartnest_annotations` без залежності | dev-залежність `dartnest_annotations` (Task 1) |
| warning: незакомічені файли | dry-run лише після commit (Tasks 1, 4, 5, 8) |
| (pana, не dry-run) `include: ../../analysis_options.yaml` у архіві вказує в нікуди | самодостатні опції (OD7) |
| (pana) приклад `di_example.dart` не впізнається; опис `dartnest_io` 53 символи (< 60) | Task 4; новий опис у Task 1 |
| (dartdoc) 2 нерезолвлені посилання в `dartnest_cli` | Task 5, Step 5 |

**Що не перевірено.**
- CI-workflow не запускався (немає remote), тож нижня межа SDK 3.8.0 —
  лише заява. Локально є тільки Dart 3.13.1 і 3.13.5.
- Справжня публікація й бал pana не перевірені; pana не запускався
  локально.
- URL `https://github.com/4akLoon/dartnest` не існує.
- macOS і Windows не перевірені.
- Hot reload на прикладі перевірено вручну (Task 3, Step 6), а не тестом.
  Автоматичні тести `dev` — integration-тести `dartnest_cli` (етап 5b).
- `dartnest init` проти pub.dev неможливий до публікації; замість нього —
  `init` з `dependency_overrides` (Task 6, Step 4).

## Питання до автора

1. OD3: власник і назва GitHub-репозиторію. Заглушка
   `4akLoon/dartnest` узята з `typed_openapi`. Якщо репозиторій буде
   іншим, `git grep -l 'github.com/4akLoon/dartnest'` дає всі місця.
2. OD2: ім'я `dartnest` — остаточне? Після першої публікації його не
   змінити.
3. OD9: чи потрібні в CI також macOS і Windows (як у `typed_openapi`)? Це
   перевірило б пункт FAQ про платформи. План лишає Ubuntu, бо `dev`
   ніколи не запускався на Windows і впав би одразу.
