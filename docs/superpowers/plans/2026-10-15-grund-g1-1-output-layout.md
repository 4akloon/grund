# G1.1: розкладка виводу і пакет `grund_http_generator` — додаток до плану G1

> Для виконавців: це додаток до `2026-10-15-grund-g1-core-http-generator.md`.
> Задачі 1–15 виконано. Для задач 15a, 16–21 **цей файл має пріоритет** над
> текстом у G1; решта тексту задач G1 (правила емісії, тести, golden-вміст)
> лишається чинною, поки не суперечить цьому файлу чи спеку.

**Спек (обов'язковий):** `docs/superpowers/specs/2026-10-15-grund-generated-output-layout-design.md`
(розділи 2–8). Рішення користувача, на яких він стоїть: вивід по вихідних
бібліотеках; модулі — бібліотека `X_module.g.dart`, `@Api` — `part`
`X_api.g.dart`; суфікс `.g.dart`; HTTP-частина генератора — окремий пакет
`grund_http_generator` (анотації лишаються в `grund_annotations`); `grund_cli`
і `grund_build` знають обидва пакети статично.

## Глобальні обмеження, що додаються

- `grund_generator` (ядро) не містить слів `grund_http`, `HttpApi`, `HttpCtx`,
  `Route`, `HookRef`, імен HTTP-анотацій у `lib/`; це перевіряє тест
  (`test/boundary_test.dart`: читає всі файли `lib/` і шукає заборонені
  підрядки). Імена анотацій `Api/Get/Post/Put/Patch/Delete/Path/Query/Header/
  Cookie/Body/Range/Length/Pattern/OneOf` ядро не знає.
- `grund_http_generator` залежить від `grund_generator`, `analyzer`, `path`;
  `grund_generator` не залежить від нього. `analyzer` дозволений і тут.
- Усі файли виводу мають заголовок генератора, суфікс `.g.dart`, імена
  `X_module.g.dart` і `X_api.g.dart` (поруч із `X.dart`). Плейн `X.g.dart` не
  використовується.
- Англійська мова для коду, `///`, діагностик, README, CHANGELOG, комітів.

## Задача 15a: розділити ядро генератора і HTTP

**Мета.** Поведінка колектора й перевірок не змінюється (140 тестів
генератора лишаються зеленими після перенесення), але HTTP-код переїжджає в
новий пакет `packages/grund_http_generator`, а в ядрі з'являється контракт
розширення.

**Що зробити.**
1. Новий пакет `packages/grund_http_generator` (workspace-член, публікований,
   lockstep-версія як у решти: `pubspec.yaml`, `LICENSE`, `CHANGELOG.md`,
   `README.md`, `analysis_options.yaml` за зразком `grund_generator`).
   Додати в кореневий `pubspec.yaml` workspace.
2. Контракт розширення в `grund_generator` (публічний, експортований з barrel):
   `Construct` отримує фази: **collect** (прочитати власні анотації з
   розв'язаних бібліотек у власну модель; результат кладеться в
   `PackageModel` через типізований слот розширення, а не через поля HTTP),
   **validate**, **claimsProvider** + **bindingsFor** (конструкт заявляє клас у
   `providers` модуля, наприклад `@Api`-клас, і сам повертає його binding та
   ключі залежностей для графових перевірок), **generate** (повертає
   `GeneratedUnit`-и: бібліотеку або `part` для заданого хоста). Підсумок
   `GenerationResult` — відсортований набір «відносний шлях → вміст». Точну
   форму обирає виконавець, але HTTP-слів у ядрі немає.
3. Перенести в `grund_http_generator`: колектор `@Api`/маршрутів/параметрів/
   хуків/DTO/валідаторів/повернених типів (`api_reader`, `route_reader`,
   `param_reader`, `hook_reader`, `dto_reader`, `validator_reader`,
   `body_kind_reader`, `return_reader` та пов'язані), моделі (`ApiModel`,
   `RouteModel`, `ParamModel`, `HookModel`, …), перевірки (`api_check`,
   `route_check`, `route_conflict_check`, `route_paths`, `param_check`,
   `validator_check`), `ApiConstruct`, HTTP-коди `DiagnosticCode`
   (ядро тримає розширюваний тип коду: HTTP-коди оголошує новий пакет),
   `generated_names`-частину про `XRoutes`. Тести й fixture-код (`cases_app`
   HTTP-частини) переїжджають разом.
4. Додати `test/boundary_test.dart` у `grund_generator` (див. обмеження).
5. `CLAUDE.md`: правило залежностей (ядро генератора без HTTP;
   `analyzer` також у `grund_http_generator`), восьмий опублікований пакет.
   (Глобальну заміну «seven» у `docs/RELEASING.md` робить задача 21.)
6. `grund_cli`/`grund_build` у цій задачі не чіпаються (вони червоні до 19).

**Готово, коли:** `dart analyze` чистий і тести зелені в обох пакетах;
`dart format` 0 змін; `boundary_test` проходить; жодних змін поведінки
діагностик (коди й тексти ті самі).

Модель: opus (архітектура, перенесення між пакетами). Рев'ю: sonnet, діф як
файл; перевірити межу `grep`-ом, а не на слово.

## Задача 16 (змінена): емісія модулів у `X_module.g.dart`

Правила емісії 1–9 з G1 лишаються. Зміни: вивід йде **по вихідних
бібліотеках**: для кожної `X.dart` з `@Module` генерується `X_module.g.dart`
(бібліотека з міксинами `$M`); `ImportAllocator` — на файл; `GenerationResult`
— набір файлів; бібліотека без `@Module` виводу не має. Binding провайдера, що
його заявив конструкт-розширення (`claimsProvider`), бере в нього
(`bindingsFor`); ядро самo `YRoutes` не емітить і не знає. Приватні класи
в `providers` — діагностика (недосяжні з іншої бібліотеки). Тести: файл на
бібліотеку; нічого для бібліотеки без модуля; префікси `i1…` у межах файла.

## Задача 17 (змінена): емісія `@Api` у `grund_http_generator` (`X_api.g.dart`)

Правила емісії `HttpApi`-адаптерів з G1 (задача 17) лишаються, але: вони живуть
у `grund_http_generator`; вивід — `part of 'X.dart'` у `X_api.g.dart`, без
власних імпортів (імена беруться з області видимості хоста); хост зобов'язаний
мати `part 'X_api.g.dart';` і префіксні імпорти, що їх вимагає емітер
(мінімум `package:grund_http/grund_http.dart as http`; точний перелік задає
емітер і називає в діагностиці). Нові діагностики `missing_part_directive` і
`missing_required_import` (з `path:line:col`, перевірка по `LibraryElement`
хоста). Binding `YRoutes` для модуля повертає `bindingsFor`; сам `YRoutes`
видно в `Y.dart`, імпорт згенерованого файла модулю не потрібен.

## Задача 18 (змінена): golden-набір, діагностики, еквівалентність

Golden `users_app` — **набір файлів** (`*_module.g.dart`, `*_api.g.dart`) у
`lib/`, перевіряється всім набором (зайвих файлів немає); `users_app` хост-файли
мають `part` і потрібні префіксні імпорти. Решта задачі 18 (cases_app,
еквівалентність з явною формою, детермінізм двох прогонів, e2e) без змін по суті.

## Задача 19 (змінена): `grund_cli` і `grund_build`

Обидва залежать від `grund_generator` і `grund_http_generator` і складають
`[ModuleConstruct(), ApiConstruct()]` статично; CLI знає HTTP-пакет, бо має
шаблони (`grund init`). CLI: запис лише змінених файлів через тимчасовий файл
і rename; ніколи поверх файла без заголовка; при помилках джерел не пишеться
жоден файл; застарілі `*_module.g.dart`/`*_api.g.dart` із заголовком
видаляються, чужі — ні. `grund_build`: один `grundBuilder` з
`buildExtensions` `.dart` → [`_module.g.dart`, `_api.g.dart`]; білдер
файла резолвить досяжні модулі й видає діагностики лише для власних;
CLI і білдер пишуть однакові байти. `GenerationSession` повертає набір файлів.

## Задачі 20–21 (зміни)

20: приклад `tasks_api` — хост-файли з `part` і імпортами, згенеровані
`*.g.dart` закомічено. 21: документація й `CLAUDE.md` (правила CLI-виводу,
вісім пакетів, `RELEASING.md`, `.g.dart`-імена, `part` для `@Api`, межа ядра і
HTTP, `hide`/`as` для `Pattern`/`Cookie`, README генератора), CHANGELOG-и.
