# Computation expressions

Текущий результат завершения State/API/диагностики/метрик: [COMPLETION_RESULTS.md](COMPLETION_RESULTS.md).

| Каталог | Содержимое |
|---|---|
| lib/ | 34 публичных модуля без тестовых builders |
| examples/ | Запускаемые примеры |
| tests/ | Положительные и отрицательные проверки; tests/repro/ — известные сбои |
| support/ | Демонстрационные builders и вспомогательные модули примеров/тестов |
| benchmarks/ | Временные нагрузки; benchmarks/metrics/ — независимые пары CE/ручного кода |
| integration_example/ | Шаблон приложения и минимальный собственный builder |

Подключение: [INTEGRATION.md](INTEGRATION.md), [PUBLIC_API.md](PUBLIC_API.md).
Таблица builders: [CE_SEMANTICS.md](CE_SEMANTICS.md). Синтаксис: [COMPUTATION.md](COMPUTATION.md).
State: [STATE_OPERATIONS.md](STATE_OPERATIONS.md). Ошибки: [DIAGNOSTICS.md](DIAGNOSTICS.md).

```powershell
cd C:\src\dascript_macro_fsharp\computation_expressions
./run_computation.ps1 -Test
./test_integration.ps1
./test_diagnostics.ps1
daslang.exe examples/state_operations_demo.das -no-module-cache
./run_performance_metrics.ps1
./run_performance_metrics.ps1 -Jit -OutputDirectory performance-jit
```

Скрипты разрешают пути относительно своего каталога. Из корня приложения:
`require ./lib/computation.das`, из examples/tests: `require ../lib/computation.das`.
Расширение .das и префикс ./ или ../ задают явный файловый require.
Старое плоское расположение модулей заменено на lib/.

Режимы и ограничение JIT: [RELIABILITY.md](RELIABILITY.md). Метрики и границы
оптимизаций: [PERFORMANCE_METRICS.md](PERFORMANCE_METRICS.md), [BENCHMARKS.md](BENCHMARKS.md).
AsyncSequence: [счётчики выделений, ручные варианты и сравнение до/после](ASYNC_SEQUENCE_PERFORMANCE.md).
Исторические дампы и метаданные сохранены без переписывания путей внутри них.

Типизированные задачи TaskBuilder / TaskResultBuilder, ожидание внешних операций и отмена: [TASKS.md](TASKS.md).
Асинхронное получение элементов через Task bind: [AsyncSequenceBuilder](ASYNC_SEQUENCE.md),
[пример](examples/async_sequence_demo.das).
Move-only элементы: `yield <-`, заимствующий bind и передача владения;
[пример с массивами](examples/async_sequence_move_demo.das).
Deferred AsyncSequence, независимые снимки и повторные запуски:
[пример](examples/deferred_async_sequence_demo.das).
Пайповый `left |> and_bind(right) |> bind` для Task через общий протокол:
[TASK_AND_BIND.md](TASK_AND_BIND.md), [пример](examples/task_and_bind_demo.das).

Типизированный планировщик с лимитом опросов, круговым обходом, ID, отменой и историей: [TASK_SCHEDULER.md](TASK_SCHEDULER.md).

Таймауты по now_ms, отмена вложенных ожиданий и освобождение ресурсов: [task_timeout_demo.das](examples/task_timeout_demo.das), [контракт](TASK_SCHEDULER.md#таймауты).

Групповая отмена CancellationToken и передача Cancelled через bind: [TASK_CANCELLATION.md](TASK_CANCELLATION.md), [пример](examples/task_cancellation_demo.das).

Ожидание времени task_delay_ms через now_ms планировщика: [TASK_DELAY.md](TASK_DELAY.md), [пример](examples/task_delay_demo.das).

WhenAll для динамического массива задач, порядок результатов и владеющий массив: [TASK_ARRAY.md](TASK_ARRAY.md), [пример](examples/task_array_demo.das).

Завершение текущего набора Task: [TASK_COMPLETION.md](TASK_COMPLETION.md).
Реальный TCP: [TASK_TCP.md](TASK_TCP.md). Сборка и исполнение AOT: [AOT_RUNTIME.md](AOT_RUNTIME.md).
WebSocket через dasHV: [TASK_HV.md](TASK_HV.md), пайповый bind и владение соединением.
Два WebSocket через and_bind с отменой и таймаутом: [пример](examples/task_hv_and_bind_demo.das).

Ожидание UI/игровых событий: [TASK_EVENTS.md](TASK_EVENTS.md), [пример](examples/task_events_demo.das).

Реальный ввод с клавиатуры, отмена и таймаут без остановки фоновых задач: [TASK_KEYBOARD.md](TASK_KEYBOARD.md).

Клавиатура окна dasGlfw без Python: [TASK_GLFW_KEYBOARD.md](TASK_GLFW_KEYBOARD.md).

Parser, Search и Query: [DOMAIN_BUILDERS.md](DOMAIN_BUILDERS.md), примеры `parser_demo.das`, `search_demo.das`, `query_demo.das`.

Parser: optional/many/many1/sep_by и управление backtracking — [PARSER_COMBINATORS.md](PARSER_COMBINATORS.md).

Search: ограничение числа решений и последовательное объединение альтернатив — [SEARCH_COMBINATORS.md](SEARCH_COMBINATORS.md).

Query: стабильная сортировка, группировка и distinct — [QUERY_OPERATORS.md](QUERY_OPERATORS.md).

Полный пример Query с `<|` и проверкой памяти: [query_full_demo.das](examples/query_full_demo.das).
