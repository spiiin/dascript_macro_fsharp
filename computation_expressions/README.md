# Computation expressions

Текущий результат завершения State/API/диагностики/метрик: [COMPLETION_RESULTS.md](COMPLETION_RESULTS.md).

| Каталог | Содержимое |
|---|---|
| lib/ | 23 публичных модуля без тестовых builders |
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
Исторические дампы и метаданные сохранены без переписывания путей внутри них.

Типизированные задачи TaskBuilder / TaskResultBuilder, ожидание внешних операций и отмена: [TASKS.md](TASKS.md).
