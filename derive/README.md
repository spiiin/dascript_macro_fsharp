# Derive для daScript

`[derive]` генерирует Debug, Equality, Hash и opt-in Clone/Diff/Patch/Builder/валидацию/JSON для обычной структуры. Макрос добавляет
типизированные функции в модуль структуры; перечень полей и обращения к ним
определяются при компиляции. Нового нативного модуля не требуется.

```das
options gen2
require ./lib/derive.das

[derive]
struct Stats {health:int;mana:int}
[derive]
struct Player {name:string;stats:Stats}

[export]
def main() {
    let player=Player(name="Alice",stats=Stats(health=100,mana=25))
    print("{derive_debug(player)}\n")
    verify(derive_equal(player,player))
    verify(derive_hash(player)==derive_hash(player))
}
```

Вывод: `Player{name="Alice", stats=Stats{health=100, mana=25}}`.
[Валидация](VALIDATION.md) поддерживает правила полей, вложенные пути, накопление ошибок, пользовательские проверки полей и элементов и уникальность по ключу. [JSON](JSON.md) поддерживает запись и загрузку с валидацией, строгий режим, стандартный Option, три состояния JsonField, строковые enum и tagged variant. [Глубокое копирование](CLONE.md) включается через clone=true. [Диагностический Diff](DIFF.md) включается через diff=true. [Типизированный Patch](PATCH.md) поддерживает конфликты, валидацию и атомарное применение. [Builder](BUILDER.md) поддерживает required, native defaults, пайповые setters и валидацию при сборке. [JSON Schema](SCHEMA.md) генерирует описание JSON-контракта при компиляции. [Сквозной пример](examples/workflow_demo.das) соединяет Builder, JSON, Clone, Diff и Patch. [Optics](OPTICS.md) добавляют чтение и независимое изменение вложенных полей через пайпы. [Prism](PRISM.md) поддерживает частичные пути через Option, JsonField и случаи variant.
Генераторы случайных данных пока не реализованы.

## Публичный API

| Операция | Результат |
|---|---|
| `[derive]` | Генерирует Debug, Equality и Hash |
| `derive_builder(type<Model>)` / `derive_build(draft,root="")` | Типизированный draft и Option результата с ошибками (builder=true,validate=true) |
| `derive_json_schema(type<T>,strict=true)` | Compile-time строка JSON Schema 2020-12 по JSON-контракту |
| `optic(path)` / `optic_then(prefix,suffix)` | Постоянные составные пути к полям |
| `source \|> optic_get(path)` | Независимый снимок выбранного поля |
| `source \|> optic_set(path,value)` / `source \|> optic_over(path) <\| block` | Новый корень с заменой/преобразованием поля |
| `prism(path)` / `prism_then(prefix,suffix)` | Постоянные частичные пути через поля и случаи |
| `source \|> prism_try_get(path)` / `prism_matches(path)` | Option-снимок или проверка совпадения |
| `source \|> prism_set(path,value)` / `prism_over(path) <\| block` | Независимый корень; обновление только при совпадении |
| `derive_debug(value)` | `string`: имя структуры, имена и значения полей |
| `derive_equal(left,right)` | `bool`: структурное равенство полей в порядке объявления |
| `derive_make_patch(expected,desired)` | Собственные typed-снимки $TypedPatch<T> |
| `derive_apply_patch(current,patch,root="")` | Новый кандидат в Option и ошибки; current заимствуется |
| `derive_apply_patch_to(var current,patch,root="")` | Атомарный commit после проверки, возвращает ошибки |
| `derive_diff(before,after,root="")` (diff=true) | Owning array<DiffChange>: пути и снимки изменений |
| `derive_clone(value)` (clone=true) | Глубокая копия, оригинал заимствуется |
| `derive_hash(value)` | `uint64`: хеш имени структуры и значений полей в том же порядке |

Настройки по умолчанию: `debug=true, equality=true, hash=true, clone=false, diff=false, patch=false, builder=false, validate=false, json=false`.

```das
[derive(debug=false)]
struct Key {scene:int;entity:int}

[derive(debug=true,equality=false,hash=false)]
struct Diagnostic {message:string}
```

Hash требует включённой Equality. Неизвестные, повторные и не-bool настройки,
а также отключение всех операций дают ошибку компиляции. Отключённая операция
для этой структуры недоступна. Сгенерированные функции не устанавливают
перегрузки стандартных `==` или `hash`: вызывайте их явно.

## Поддерживаемые данные

- Обычные structs, в том числе с owning-полями; классы и наследование запрещены.
- Вложенные structs с `[derive]` или с пользовательскими одноимёнными функциями.
- Числовые скаляры, bool, string и enum.
- Фиксированные и динамические массивы, включая вложенные массивы и массивы
  структур из другого модуля. Порядок и длина массивов значимы.
- Пустые структуры и массивы.

Tuple, table, указатели, блоки/лямбды, итераторы, векторы и произвольные
нативные handles не получают неявного обхода. Для расширения используйте обычную
структуру-обёртку с явными операциями. Вложенным значениям нужны только те
операции, которые включены для содержащего их типа.

Debug/Equality/Hash заимствуют данные, не копируют и не перемещают owning-массивы и не
закрывают переданные ресурсы. После вызова время жизни данных остаётся у владельца.
Работа с массивами использует индексы: исключение пользовательской операции
не оставляет активного native array iterator. Пользовательские операции могут
бросать исключения; они передаются вызывающему коду без преобразования.

## Равенство и хеш

Для одного типа соблюдается `derive_equal(a,b) => derive_hash(a)==derive_hash(b)`
при согласованных пользовательских операциях. Разные значения могут иметь
одинаковый хеш: он не является уникальным ID, проверкой целостности или
криптографической подписью. В хеш-таблице после совпадения хеша проверяйте равенство.

Float/double используют обычное числовое равенство: `+0` и `-0` равны и имеют
одинаковый хеш, `NaN` не равен даже самому себе. Поэтому полные законы
эквивалентности для данных с NaN не обещаются. Null/пустая строка следуют
семантике SDK и получают одинаковый хеш. Строки хешируются библиотечным FNV-1a;
скаляры и enum-значения используют библиотечное перемешивание SplitMix64
битового представления. Формат хеша не является
контрактом сохранений, сети или совместимости между версиями SDK.

Debug экранирует строки и сохраняет порядок полей. Это диагностический вывод,
а не JSON или формат для обратного чтения. Debug создаёт строки в string heap;
его объём и сборка мусора регулируются контекстом daScript.

## Пользовательские операции

```das
struct EntityId {raw:int}
def derive_equal(a,b:EntityId) : bool {return a.raw%100==b.raw%100}
def derive_hash(value:EntityId) : uint64 {return derive_hash(value.raw%100)}
def derive_debug(value:EntityId) : string {return "EntityId({value.raw%100})"}

[derive]
struct Target {id:EntityId;title:string}
```

Здесь равенство и хеш используют один логический ID. Содержащая структура
вызывает эти операции напрямую. Для потенциально бросающих операций в примерах
используется `verify`, поскольку daScript запрещает побочные эффекты в `assert`.

## Примеры и проверки

- [derive_demo.das](examples/derive_demo.das): простой вложенный тип.
- [game_demo.das](examples/game_demo.das): игровые данные с owning-массивом,
  типы в [game_model.das](examples/game_model.das).
- [patch_demo.das](examples/patch_demo.das): typed-снимки, конфликты, независимые правки, атомарный commit и валидация.
- [diff_demo.das](examples/diff_demo.das): диагностические снимки, массивы, состояния обёрток и variant.
- [clone_demo.das](examples/clone_demo.das): глубокая копия, вложенные owning-данные, обёртки и variant.
- [custom_demo.das](examples/custom_demo.das): пользовательские операции и настройки.

Из корня репозитория:

```powershell
./derive/run.ps1 -Test
./derive/run.ps1 -Test -Jit
./derive/run.ps1 -Test -AotGenerate
./derive/run_aot.ps1
./derive/test_integration.ps1
./derive/test_integration.ps1 -Jit
```

`-Daslang` или `DASLANG_EXE` выбирает компилятор. По умолчанию используется
`C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe`.
Текущий набор: 18 исполняемых примеров, 32 положительных и 114 отрицательных тестов.
Проверяются поля, порядок массивов, независимые владельцы, разные модули,
пользовательские операции, настройки, экранирование, null/пустая строка, знаковый
ноль, NaN и законы композиции на конечных данных.

Тесты owning-массивов выполняют 32 повтора после прогрева; остальные проверки
памяти — 16. `heap_bytes_allocated()` контролирует живой context heap массивов,
а не string heap или весь процесс. Генерация C++ сама по себе не подтверждает
AOT-исполнение: `run_aot.ps1` собирает хост, требует `fail_on_no_aot` и
проверяет `main->aot` для каждого сценария. В build-каталоге лежат сгенерированные
C++, а в output-каталоге — runtime-логи и `runtime-summary.json`.

Для сборки AOT нужны Windows x64, Visual Studio 2022 с C++ и CMake. Хост
использует SDK recovery shim `aot_host/recover_064.h`, как существующий CE-хост.
Скрипт отслеживает изменение исходников во время сборки и отклоняет такой прогон.

## Подключение в другом проекте

```powershell
./derive/export_library.ps1 -Destination C:/path/to/new-package
```

Экспорт содержит `lib/derive.das`, `lib/derive_runtime.das`, `lib/derive_validation.das`, `lib/derive_json_runtime.das`, `lib/derive_types.das`, `lib/derive_variant_macros.das`, `lib/derive_diff.das`, `lib/derive_patch.das`, `lib/derive_builder.das`, `lib/derive_schema.das`, `lib/derive_optics.das`, `lib/derive_optics_runtime.das`, примеры, эту инструкцию
и manifest. Каталог назначения должен быть новым. В приложении:

```das
require ./lib/derive.das
```

Для собственного AOT-хоста сгенерируйте `-aotlib` для `derive_runtime.das`, `derive_validation.das`, `derive_json_runtime.das`, `derive_diff.das`, `derive_patch.das`, `derive_builder.das`, `derive_optics_runtime.das`, стандартных JSON-модулей (см. [JSON.md](JSON.md)) и
для модулей приложения, где объявлены используемые derived-типы. Макрос-модуль
`derive.das` работает при компиляции; сгенерированные функции принадлежат модулю
аннотированной структуры. Экспорт не требует CE, type providers или ReactiveX.

Набор исполняемых сценариев задаётся scripts.json, ожидаемых ошибок —
negative_tests.json. Интерпретатор, JIT без кеша и исполнение строгого AOT-хоста
проверяются отдельно. Экспорт проверяется независимым приложением в двух режимах.
Существующие CE/ReactiveX/type-provider модули derive не импортирует.
