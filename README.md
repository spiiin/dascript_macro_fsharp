# Type providers и computation expressions

Таблица возможностей builders и общий контракт: [CE_SEMANTICS.md](computation_expressions/CE_SEMANTICS.md).

Две независимые части библиотеки:

- [Type providers](type_providers/README.md): генерация типов, схемы, JSON-данные, примеры и проверки.
- [Computation expressions](computation_expressions/README.md): макрос CE, builders, примеры, проверки и бенчмарки.

Из корня запустите `./run.ps1 -Test`, чтобы проверить обе части.
Скрипты переходят в собственный каталог; их можно вызывать из любой рабочей папки.
Для прямого запуска daScript-примеров перейдите в каталог соответствующей части.
Локальные `require` внутри каждой части сохранены: модули разрешаются рядом с исходным файлом.
Старый плоский путь к модулю нужно заменить на путь в соответствующей подпапке
в настройках вашего проекта или его путях поиска модулей.

## Автоматические проверки

[GitHub Actions](https://github.com/spiiin/dascript_macro_fsharp/actions/workflows/ci.yml)
запускается при каждом `push`, `pull_request` и вручную (`workflow_dispatch`).
На Windows Server 2022 устанавливается официальный SDK Daslang **0.6.4**
с проверкой закреплённой SHA-256 архива. Секреты для запуска не требуются.

Отдельные шаги проверяют:

- Type providers: все примеры и тесты через `type_providers/run.ps1 -Test`.
- CE: примеры, положительные и отрицательные тесты, диагностику,
  независимый экспорт библиотеки и раскрытие оптимизаций через
  `computation_expressions/run_computation.ps1 -Test`.
- JIT: восемь явно перечисленных тестов `run_modes.ps1 -Mode Jit`.
- AOT: генерацию C++ для тех же восьми тестов, без сборки и исполнения AOT-хоста.

Ожидаемые ошибки компиляции проверяются по коду завершения и сообщению;
неожиданная ошибка делает проверку красной. Остальные наборы продолжают
проверяться после ошибки отдельного шага. Логи и отчёты режимов сохраняются
в artifact `windows-daslang-0.6.4-results` на 14 дней, включая неудачные запуски.
Известные аварии JIT из `tests/repro/` в обычный CI не включены — см.
[RELIABILITY.md](computation_expressions/RELIABILITY.md).
Бенчмарки времени не служат порогом прохождения CI.

Типизированные задачи: [TaskBuilder / TaskResultBuilder](computation_expressions/TASKS.md) —
пайповый bind с приостановкой, результат, отмена и адаптер внешних операций.

## Подробности и история возможностей

# Type provider на макросах daScript / Daslang

Также добавлены computation expressions с `ResultBuilder`, `OptionBuilder`,
`StateBuilder`, `WriterBuilder`, `WriterResultBuilder`, `StateResultBuilder` и `ListBuilder`. Примеры состояния игры и журнала —
в [STATE_WRITER.md](computation_expressions/STATE_WRITER.md), `computation_expressions/examples/state_demo.das` и `computation_expressions/examples/writer_demo.das`.
Журнал с остановкой при ошибке — [WRITER_RESULT.md](computation_expressions/WRITER_RESULT.md) и `computation_expressions/examples/writer_result_demo.das`.
Состояние с откатом при Error — [STATE_RESULT.md](computation_expressions/STATE_RESULT.md) и `computation_expressions/examples/state_result_demo.das`.
Освобождение ресурсов — [RESOURCES.md](computation_expressions/RESOURCES.md) и `computation_expressions/examples/resources_demo.das`.
Комбинации и списки — [LIST.md](computation_expressions/LIST.md) и `computation_expressions/examples/list_demo.das`.
Синтаксис bind — `let x = operation() |> bind` или `operation() |> bind`.
Поддерживаются Zero/Combine/Delay, ветвления и циклы с остановкой при Error/None.
Запуск: `./computation_expressions/run_computation.ps1 -Test`. Примеры и устройство —
в [COMPUTATION.md](computation_expressions/COMPUTATION.md) и `computation_expressions/examples/computation_demo.das`, `computation_expressions/examples/computation_control_demo.das`.

Рабочий учебный аналог **generative type provider** из F#: внешняя схема
превращается в реальные поля структуры и типизированную функцию при компиляции.
Проверено с Daslang 0.6.4, синтаксис gen2.

Теперь здесь три варианта:

- `type_providers/main.das`: генерация настоящей структуры и полная загрузка её полей.
- `type_providers/erased_demo.das`: стирание виртуальных типов внутри выражения и ленивое
  раскрытие графа схем. Подробности, ограничения относительно F# и стоимость
  доступа — в [ERASED.md](type_providers/ERASED.md).
- `type_providers/native_demo.das`: ленивая генерация настоящих структур с зависимостями,
  проверка данных при загрузке и передача между функциями. См. [NATIVE.md](type_providers/NATIVE.md).

`run.ps1` запускает все три примера. `./type_providers/measure_lazy.ps1 -Count 10000` проверяет,
что из пространства в 10 000 типов будут загружены только два.
`./type_providers/measure_native.ps1 -Count 10000` проверяет генерацию двух настоящих типов
из такого же по размеру каталога.

## Запуск

```powershell
cd C:\src\dascript_macro_fsharp
.\run.ps1
.\run.ps1 -Test
```

Скрипт ищет `daslang.exe` в PATH и в локальной установке
`C:\src\daslang-0.6.4\daslang_bundle\bin`. Другую установку можно задать:

```powershell
.\run.ps1 -Daslang 'D:\tools\daslang\bin\daslang.exe' -Test
```

Либо из каталога примера: `daslang.exe main.das -no-module-cache`.

Вывод первого примера после compile-time сообщения провайдера:

```text
Alice: health=100, alive=true
after damage: 90
rejected: field 'health': expected integer
OK
```

## Главное место в примере

```das
require json_provider

[json_provider(schema="schemas/player.json")]
struct Player {}
```

Список полей в исходном коде отсутствует. Макрос читает файл:

```json
{
  "fields": [
    { "name": "name", "type": "string" },
    { "name": "health", "type": "int" },
    { "name": "alive", "type": "bool" }
  ]
}
```

Получается структура с `name : string`, `health : int`, `alive : bool`
и функция `try_parse_Player(text, result, error) : bool`.
Обычный компилятор проверяет обращения к полям и их типы.
`type_providers/test_typo.das` и `type_providers/test_wrong_type.das` специально не компилируются.
Запуск с `-Test` считает эти ошибки успешными проверками.

Для эксперимента добавьте в схему поле `level` типа `int`, в
`data/player.json` — `"level": 5`, а в `type_providers/main.das` — чтение `player.level`.
Повторный запуск создаст новое поле без изменения реализации макроса.

## Устройство

- `type_providers/json_provider.das`: `[structure_macro]` и `AstStructureAnnotation.apply()`.
  До вывода типов читает схему, добавляет поля через `add_structure_field`,
  создаёт AST функции через `qmacro_function` и регистрирует её `add_function`.
  `$v(name)` вставляет строковый ключ, `$f(name)` — доступ к настоящему полю,
  `$t(st)` — тип создаваемой структуры. Схема ищется относительно файла,
  содержащего аннотированную структуру, а не файла реализации макроса.
- `type_providers/provider_runtime.das`: перегруженные функции чтения трёх типов полей.
  Выбор перегрузки выполняется компилятором по типу сгенерированного поля.
- `type_providers/main.das`: использование провайдера и загрузка отдельного файла данных.
- `test_*.das`, `tests/`: проверки валидации и ожидаемые ошибки компиляции.

Схема читается только при компиляции. JSON с данными разбирается при выполнении.
При ошибке загрузки `result` остаётся прежним; `error` содержит причину.
Временные JSON-деревья освобождаются в `finally`.

## Границы примера

Это собственный маленький формат описания полей, **не реализация стандарта
JSON Schema** и не вывод типов по образцу JSON. Поддерживаются `string`,
`int` (32 бита) и `bool`. Все поля обязательны, `null` не допускается,
лишние поля данных игнорируются. Для `int` принимается целочисленная JSON-запись:
`1.0` не принимается даже при математически целом значении.
Имена полей: `[a-z_][a-z_0-9]*`; используйте имена, не совпадающие с ключевыми
словами языка. Повторяющиеся имена в схеме отклоняются.

В первом, generative-примере нет вложенных типов, массивов, optional-полей,
erased types и ленивой генерации. Отдельный erased-пример добавляет ссылки
между виртуальными типами, циклы и раскрытие только используемых схем.
Нет отдельной интеграции с IDE и отслеживания зависимостей сторонним build cache.
`run.ps1` передаёт `-no-module-cache`, чтобы схема гарантированно читалась заново. Без этого встроенный AST-кеш может не заметить изменения внешнего JSON; при подключении к системе сборки
добавьте файл схемы в её зависимости. Макрос и пользовательский код находятся
в разных модулях, как требует механизм макросов Daslang.

## Источники

- [F# Type Providers](https://learn.microsoft.com/en-us/dotnet/fsharp/tutorials/type-providers/)
- [Daslang: Structure Macros](https://daslang.io/doc/reference/tutorials/macros/06_structure_macro.html)
- Локальный пример SDK: `tutorials/macros/structure_macro_mod.das`.








## Ленивые последовательности и yield

Добавлен `SequenceBuilder`: нативный однопроходный iterator с `yield`,
`source |> yield_from` и bind через пайпы. См. `computation_expressions/SEQUENCE.md`,
`computation_expressions/examples/sequence_demo.das`, `computation_expressions/tests/test_sequence.das`. `yield` и `yield_from` доступны
также в eager `ListBuilder`. Ограничения захвата и ресурсов описаны в `computation_expressions/SEQUENCE.md`.

Ресурсные области SequenceBuilder (`use_resource`, `try_finally`) реализованы;
пример — `computation_expressions/examples/sequence_resources_demo.das`, правила обхода и захвата —
`computation_expressions/SEQUENCE_RESOURCES.md`. Для обработчика, который может бросить ошибку,
используйте `sequence_each`.

Общие изменяемые локальные значения SequenceBuilder реализованы: изменения
в body видны cleanup и продолжению после ресурсной области. См.
`computation_expressions/examples/sequence_shared_demo.das` и `computation_expressions/SEQUENCE_RESOURCES.md`. Внешние захваты native
генератора по-прежнему копируются; преобразование касается var внутри CE.

TryWith реализован для всех builders, включая ленивое восстановление SequenceBuilder.
Пример — `computation_expressions/examples/try_with_demo.das`, правила и ограничения — `computation_expressions/TRY_WITH.md`.

Общий протокол расширения CE: [BUILDER_PROTOCOL.md](computation_expressions/BUILDER_PROTOCOL.md).
`computation_expressions/examples/reader_demo.das` подключает собственный ReaderBuilder отдельным модулем,
без изменений ядра или фасада computation. Тесты: `./computation_expressions/run_computation.ps1 -Test`.

Независимые проверки с накоплением ошибок: [VALIDATION.md](computation_expressions/VALIDATION.md),
`computation_expressions/examples/validation_demo.das`. ValidationBuilder подключается отдельным модулем;
объединение `left |> validation_zip(right) |> bind` сохраняет пайповый bind.

Общий групповой bind для Result/Option/Validation/List:
[AND_BIND.md](computation_expressions/AND_BIND.md), `computation_expressions/examples/and_bind_demo.das`.
Запись: `left |> and_bind(right) |> bind`.

Оптимизация завершающего bind/return без изменения синтаксиса:
[BIND_RETURN.md](computation_expressions/BIND_RETURN.md), `computation_expressions/examples/bind_return_demo.das`.
List сразу заполняет итоговый массив, без одноэлементного списка на каждый шаг.

BindReturn поддержан также для State, StateResult и WriterResult, включая
все их виды источников. Игровой пример — `computation_expressions/examples/effect_bind_return_demo.das`,
проверки эквивалентности — `computation_expressions/tests/test_effect_bind_return.das`.

Bind2Return для `and_bind → return`: [BIND2_RETURN.md](computation_expressions/BIND2_RETURN.md),
`computation_expressions/examples/bind2_return_demo.das`. Синтаксис прежний; List строит итоговые комбинации
без промежуточного массива пар.

## Bind2

Группы and_bind с произвольным продолжением используют необязательный
`ce_bind2` для Result, Option, Validation и List. Синтаксис прежний;
старые builders сохраняют fallback через MergeSources и Bind.
См. [контракт и ограничения](computation_expressions/BIND2.md) и `computation_expressions/examples/bind2_demo.das`.

## Общий Run и отчёты

Необязательный `ce_run(builder, outcome)` завершает Value/Collect/Sequence CE
и может менять публичный тип результата. Старые builders сохраняют прежний
результат. Отдельный `computation_expressions/support/report_builder.das` превращает Result в отчёт об операции;
пример — `computation_expressions/examples/run_demo.das`. Контракт, владение, диагностика и проверки: [RUN.md](computation_expressions/RUN.md).

## Отложенное выполнение

Отдельный модуль `deferred_computation` добавляет `deferred(builder, data) $(snapshot) { ... }` и `run_deferred(task)`. Снимки владеют данными, каждый
запуск получает независимую копию builder/data. Обычный computation остаётся
немедленным. Пример — `computation_expressions/examples/deferred_demo.das`; контракт и ограничения — [DEFERRED.md](computation_expressions/DEFERRED.md).

## Отложенный Sequence

Каждый запуск deferred Sequence создаёт отдельный итератор, владеющий снимком
до закрытия. Ресурсы тела закрываются перед удалением снимка. Пример —
`computation_expressions/examples/deferred_sequence_demo.das`; контракт и обход с исключениями — [DEFERRED_SEQUENCE.md](computation_expressions/DEFERRED_SEQUENCE.md).

### Переопределяемые For / While

[LOOP_PROTOCOL.md](computation_expressions/LOOP_PROTOCOL.md): необязательные `ce_for` и `ce_while`,
Result/Option с остановкой при Error/None и отдельный `BoundedResultBuilder`
с лимитом итераций. Пример: `computation_expressions/examples/loop_protocol_demo.das`; проверки:
`computation_expressions/tests/test_loop_protocol.das`, `computation_expressions/tests/test_loop_dispatch.das`.

### For с несколькими источниками

[ZIP_FOR.md](computation_expressions/ZIP_FOR.md): необязательный `ce_for_zip` для одновременного обхода
двух и более источников. Result/Option останавливают все источники при Error/None;
пайповый bind и ссылки на элементы сохраняются. Пример: `computation_expressions/examples/zip_for_demo.das`.

### Очистка zip при исключениях

[ZIP_CLEANUP.md](computation_expressions/ZIP_CLEANUP.md): явные курсоры закрываются при native panic в
производителе или теле For. Пример восстановления через `try_with`:
`computation_expressions/examples/zip_cleanup_demo.das`; проверки ресурсов и heap: `computation_expressions/tests/test_zip_exceptions.das`.

Одиночный `For` Result/Option также закрывает iterator-источник при исключении
производителя или тела: [SINGLE_FOR_CLEANUP.md](computation_expressions/SINGLE_FOR_CLEANUP.md).

Стандартный eager For без hooks также закрывает источники при исключениях:
[FALLBACK_CLEANUP.md](computation_expressions/FALLBACK_CLEANUP.md). Пример: `computation_expressions/examples/fallback_cleanup_demo.das`.

Вложенные iterator-источники `for`, `bind` и `yield_from` имеют отдельную
защиту закрытия: [SEQUENCE_NESTED_CLEANUP.md](computation_expressions/SEQUENCE_NESTED_CLEANUP.md).
Пример: `computation_expressions/examples/sequence_nested_cleanup_demo.das`.

Общий необязательный `ce_source(builder,input)` адаптирует источники bind, For,
return_from и yield_from до обычных операций и оптимизаций. Контракт:
[SOURCE_PROTOCOL.md](computation_expressions/SOURCE_PROTOCOL.md). Отдельный builder: `computation_expressions/support/game_source_builder.das`;
пример: `computation_expressions/examples/source_demo.das`.

## Move-only CE

`MoveResultBuilder` и `MoveOptionBuilder`: consuming bind через `var x & = source |> bind`,
выдача владения через `return <- x`. См. [MOVE_CE.md](computation_expressions/MOVE_CE.md),
`computation_expressions/examples/move_ce_demo.das` и `computation_expressions/tests/test_move_ce.das`.

## Move-only коллекции

`ListBuilder(type<T>)` и `SequenceBuilder(type<T>)` поддерживают owning элементы:
`var item & = source |> bind`, `return <- item` / `yield <- item`.
См. [MOVE_COLLECTIONS.md](computation_expressions/MOVE_COLLECTIONS.md) и `computation_expressions/examples/move_collections_demo.das`.

Deferred поддерживает move-only List и Sequence: независимый снимок и результат
на каждый запуск, удержание снимка Sequence до close. Пример:
`computation_expressions/examples/deferred_move_collections_demo.das`; тесты: `computation_expressions/tests/test_deferred_move_collections.das`.

Для ручного обхода move-only Sequence доступен `sequence_next_move(stream, value)`: перенос владения, освобождение предыдущего значения и закрытие при конце/ошибке производителя. Пример — `computation_expressions/examples/sequence_next_move_demo.das`; контракт — [MOVE_COLLECTIONS.md](computation_expressions/MOVE_COLLECTIONS.md).

Move-only ресурсы: `var resource & = acquire() |> use_resource`, единственный
владелец и scoped dispose, включая Sequence/deferred. Пример —
`computation_expressions/examples/move_resources_demo.das`; контракт — [MOVE_RESOURCES.md](computation_expressions/MOVE_RESOURCES.md).

## Reader + Result

`reader_result_builder` добавляет `ReaderResultBuilder(environment)` отдельным
модулем: `reader_ask() |> bind` читает окружение, обычные Result связываются через
пайпы, первая ошибка останавливает CE и циклы. Пример передачи результата между
функциями — `computation_expressions/examples/reader_result_demo.das`. Контракт и ограничения: [READER_RESULT.md](computation_expressions/READER_RESULT.md).

## State + Writer + Result

`state_writer_result_builder` добавляет `StateWriterResultBuilder(initial)`:
состояние откатывается при Error, журнал выполненных шагов сохраняется.
`state_get`, `state_put`, `tell` и обычный Result связываются через пайпы.
Игровой пример — `computation_expressions/examples/state_writer_result_demo.das`; контракт и ограничения:
[STATE_WRITER_RESULT.md](computation_expressions/STATE_WRITER_RESULT.md).

## CoroutineBuilder

`coroutine_builder` добавляет кооперативные сценарии: `yield next_frame()`,
`yield wait_frames(n)`, явные `coroutine_resume`/`coroutine_cancel` и дочерний
сценарий через `yield_from`. Bind сохраняет пайповую семантику Sequence.
Пример — `computation_expressions/examples/coroutine_demo.das`; контракт кадров, ресурсов и deferred:
[COROUTINE.md](computation_expressions/COROUTINE.md).

## Планировщик корутин

`coroutine_scheduler` добавляет регистрацию задач, общий tick, отмену по ID,
статусы и изоляцию ошибок. Планировщик владеет итераторами и закрывает активные
задачи при удалении. Пример — `computation_expressions/examples/coroutine_scheduler_demo.das`; API и ограничения:
[COROUTINE_SCHEDULER.md](computation_expressions/COROUTINE_SCHEDULER.md).

Планировщик поддерживает forget/prune и переиспользование слотов с поколениями
ID. Пример — `computation_expressions/examples/coroutine_slots_demo.das`; старые ID отклоняются после удаления
записи, даже когда её слот уже занят новой задачей.

Завершённый вариант планировщика проверяет владельца каждого ID и предоставляет
`coroutine_scope` для очистки при исключениях внешнего игрового цикла. Пример —
`computation_expressions/examples/coroutine_scope_demo.das`. Полный набор проверок проекта: `./run.ps1 -Test`.

## Сохранённые builders и производительность

`computation(savedBuilder)` поддерживает локальные let/var, поля и параметры
функций. CE получает локальную копию контекста builder; данные за указателями
не копируются глубоко. Изменения State не меняют сохранённые поля исходного builder.
Сохранённый const builder также допускается в deferred. Проверки —
`computation_expressions/tests/test_saved_builder.das`.

Бенчмарки CE против ручного кода: [BENCHMARKS.md](computation_expressions/BENCHMARKS.md).
Запуск: `./run_benchmarks.ps1`; замеры отделены от тестов корректности и компиляции.

Числовой For у StateBuilder использует специализированный native loop через
общий протокол. Разбор, проверки и замеры до/после: [STATE_OPTIMIZATION.md](computation_expressions/STATE_OPTIMIZATION.md).

Оптимизация линейных List bind-цепочек и consuming-map, ограничения по
финализаторам, проверки и бенчмарки до/после: [LIST_OPTIMIZATION.md](computation_expressions/LIST_OPTIMIZATION.md).
