# Метрики CE и ручного кода

```powershell
./run_performance_metrics.ps1 -Iterations 10000 -Samples 5
./run_performance_metrics.ps1 -Jit -Iterations 10000 -Samples 5 -OutputDirectory performance-jit
./measure_compilation.ps1 -Samples 3
```

## Исполнение и выделения

Сохраняются timing samples, парные checksums и остаточный heap до/после.
allocations.csv содержит накопительные дельты heap_allocation_count и
heap_allocation_stats()[0], а также counters строкового heap. Форматирование
отчёта выполняется после снятия показаний. Освобождение не уменьшает накопительные
счётчики. Native/OS-выделения и память LLVM ими не измеряются.

metrics.json объединяет timing, allocations и отдельные сравнения компиляции.
summary.json и compilation/compilation.json сохраняют хеши компилятора и исходников;
compile-samples.csv — сырые времена. Кеш AST отключён, для JIT также отключён
кеш JIT. Маленькие проверочные запуски не доказывают ускорение.

## Независимые пары компиляции и раскрытия

Для Result, State и List используются шесть программ в benchmarks/metrics:
result-ce/manual, state-ce/manual, list-ce/manual. Каждая содержит только свою
реализацию, функцию work и одинаковый драйвер. Ручные варианты не подключают
computation. Перед измерением сравниваются checksums. Ранее обе реализации
компилировались в одной программе; теперь сравнение выполняется отдельно.

Каждый timed sample запускает новый процесс с -dry-run и -log-compile-time:
измеряется startup + compile + simulate, при JIT также codegen, без исполнения
workload. Порядок CE/manual чередуется. Это не чистое время парсинга; фазы
компилятора остаются в логах. Внешнюю нагрузку машины следует учитывать при
интерпретации времён. Runner измеряет компиляцию тремя samples на реализацию;
-Samples верхнего runner управляет runtime samples.

Для каждой программы сохраняется текст -compile-only -log: байты, строки и
число объявлений функций. Тело work находится в entry-модуле, поэтому видно
именно сравниваемую реализацию. Импортированные модули могут печататься не
полностью. Это размер текстового вывода, не всей AST или машинного кода.

## Границы оптимизаций

| Конструкция | Текущий путь | Сохраняющиеся расходы |
|---|---|---|
| Result/Option bind → return | BindReturn при наличии overload | Проверка variant, копирование payload по типу |
| Поддерживаемая группа and_bind → return | Bind2Return либо fallback | Eager источники; fallback может создавать пару |
| State For по range | Native loop | Остальная композиция и снимки состояния |
| Подходящие цепочки List | Один накопитель | Итоговый массив |
| List с границами управления/ресурсами или finalizers | Консервативный fallback | Промежуточные коллекции по форме CE |
| Sequence | Ленивый iterator | Защитные области, курсоры и slots |
| Deferred | Новый clone на запуск | Владение и копирование снимка |

Точные условия: [BIND_RETURN.md](BIND_RETURN.md), [BIND2_RETURN.md](BIND2_RETURN.md),
[STATE_OPTIMIZATION.md](STATE_OPTIMIZATION.md), [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md).
Пороги скорости в функциональных тестах не задаются.
