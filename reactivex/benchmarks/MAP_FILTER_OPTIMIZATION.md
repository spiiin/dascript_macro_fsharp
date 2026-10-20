# map/filter: удержание состояния без iterator-ссылок

Замер 20 октября 2026, Windows x64, SDK 0.6.5-RC2, одинаковый компилятор и
benchmark до/после. Размеры 32, 512, 4096; четыре пакета, пять повторов;
ниже медиана при 4096. Время компиляции исключено.

## Изменение

Обработчики `map` и `filter` удерживают source и downstream напрямую через
существующие счётчики ссылок. Два временных iterator lease на оператор больше
не создаются. Указатели разрешаются один раз при подписке; на событии нет
повторных вызовов `rx_state` для этих двух состояний.

Каждый обработчик владеет двумя удержаниями до своего уничтожения. Порядок
освобождения прежний: downstream, затем source, под `rx_finalize`. Публичные
дескрипторы, пайпы, доставка ошибок selector/predicate через on_error, порядок
эффектов, отписка и владение пользовательскими captures сохраняются.
Это не слияние операторов и не кеш подписок.

## Память

Постоянная настройка исключена разностью результатов при размерах 512 и 4096.
Счётчики отражают daScript heap; native allocator, LLVM, ОС и peak memory
не измеряются. Для int string heap allocations равны нулю.

| Сценарий | Выделений на подписку до → после | Байт до → после |
|---|---:|---:|
| subscribe_chain | 31 → 23 | 1696 → 1168 |
| behavior_subscribe | 27 → 23 | 1560 → 1296 |
| replay_subscribe | 27 → 23 | 1560 → 1296 |

Все три режима дают одинаковые счётчики. Прямая подписка на range не меняется.
Нулевые выделения на событие прогретого Subject сохраняются; небольшие
allocations/unit в полном benchmark амортизируют настройку и завершение.

## Время

| Режим | Сценарий | До, нс/единицу | После, нс/единицу |
|---|---|---:|---:|
| interpreter | range | 241.58 | 191.85 |
| interpreter | map | 553.19 | 287.29 |
| interpreter | filter | 811.71 | 380.02 |
| interpreter | chain | 1055.57 | 495.79 |
| interpreter | subject | 1681.95 | 421.51 |
| interpreter | subscribe_chain | 15647.46 | 7763.76 |
| interpreter | behavior_subscribe | 44610.34 | 32579.83 |
| interpreter | replay_subscribe | 55540.72 | 35800.04 |
| jit | range | 124.80 | 117.69 |
| jit | map | 323.07 | 214.80 |
| jit | filter | 434.92 | 354.33 |
| jit | chain | 588.27 | 384.58 |
| jit | subject | 589.15 | 521.80 |
| jit | subscribe_chain | 11979.56 | 7185.59 |
| jit | behavior_subscribe | 8980.34 | 8530.02 |
| jit | replay_subscribe | 10621.61 | 9157.29 |
| aot | range | 65.20 | 35.38 |
| aot | map | 150.84 | 66.63 |
| aot | filter | 197.53 | 90.00 |
| aot | chain | 135.41 | 113.56 |
| aot | subject | 127.11 | 115.83 |
| aot | subscribe_chain | 4975.16 | 3680.36 |
| aot | behavior_subscribe | 7128.83 | 7318.02 |
| aot | replay_subscribe | 8617.85 | 7620.70 |

Единица — входной элемент; для subscribe-сценариев — подписка.
Время заметно зависит от нагрузки машины: baseline interpreter/JIT запускались
одновременно со сборкой AOT; correctness-прогоны частично пересекались со
сборкой/исполнением after AOT. Эти замеры не доказывают универсальное ускорение.
Сокращение выделений и байтов проверяется независимо от времени.

## Проверки и воспроизведение

В каждом режиме benchmark проверяет 690 samples: совпадение checksum ручного
кода и Rx, нулевой retained heap. AOT-хост исполняется со strict linking и
main->aot=yes; генерация C++ сама по себе не считается исполнением.

`test_subscription_ownership.das` дополнен ошибками selector/predicate с
удалением всей цепочки из on_error, включая исключение в самом on_error.
Оба captures живы внутри terminal callback и освобождаются после выхода
из текущего вызова. Тест прошёл на исходном и изменённом коде.

- Interpreter: полный run.ps1 -Test; 23 примера, 54 положительных теста,
  13 отрицательных проверок компиляции — всё успешно.
- JIT: тот же полный набор из 90 проверок с -jit -jit-no-cache и
  -no-module-cache. После 47 завершённых проверок последовательный процесс
  остановлен; оставшиеся 43 положительных скрипта выполнены в четырёх
  независимых процессах. Проверены полнота покрытия и отсутствие дубликатов.
- AOT: 13/13 выбранных тестов успешно собраны и исполнены со strict linking
  и AOT main: базовый Rx, lifetime, subscription ownership, Subject dispatch /
  fanout / reentrant, cached Subject dispatch / clone, selection / recovery
  lifetime, Task / AsyncSequence adapter lifetime, queue payloads.
  Benchmark отдельно собран и исполнен до и после.

Артефакты: `.work/map-filter-before/`, `.work/map-filter-after/`,
`.work/map-filter-comparison.csv`, `.work/map-filter-*-tests.log`.
Артефакты исключены из Git. Повторить текущую версию:
`./reactivex/run_benchmarks.ps1 -Mode All`.
Предыдущий вариант библиотеки: `.work/map-filter-before/reactivex.das`;
соответствующая исходная версия в Git — 8b26773.

В старом SUBSCRIPTION_OPTIMIZATION.md исправлена контрольная таблица времени:
CSV использовал десятичную запятую, которая ранее ошибочно разбиралась как
разделитель разрядов. Числа восстановлены из исходного subscription-paired.csv;
исходные замеры и вывод об отсутствии универсального ускорения сохранены.
