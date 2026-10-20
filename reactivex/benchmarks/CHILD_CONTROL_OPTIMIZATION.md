# ReactiveX: владельцы child/control со struct finalize

20 октября 2026, Windows x64, SDK 0.6.5-RC2. Исходная версия — b9761d8
после удаления временных iterator leases из внутренних callbacks concat_map.
Снимок библиотеки до изменения сохранён отдельно. Benchmark-файлы для двух
версий побайтово одинаковы и не изменялись в этом проходе.

## Владение и совместимость

RxControlOwner хранит указатель на RxSubscriptionState и является внутренним
primary owner: в finalize он закрывает подписку, затем снимает ссылку на storage.
Указатель владельца обнуляется до вызова cleanup, что делает повторное удаление
безопасным. Если cleanup выбросил исключение, storage всё равно освобождается,
затем исключение передаётся выше. Закрытая подписка не запускает cleanup повторно.

RxFlatChildOwner хранит ссылку на RxFlatChildStorage. Клонирование владельца
увеличивает счётчик; finalize уменьшает его. Удаление одного владельца не закрывает
активного child. Primary control находится внутри storage и уничтожается только
после последней ссылки. Независимые ссылки callbacks, добавленные в предыдущем
проходе, продолжают удерживать storage до завершения своих кадров.

Внутренние local/list owners child и primary controls child/outer у flatten
больше не создают генераторы для владения. Пустое поле unique:iterator<uint8>
остаётся только маркером move-only типа, не создаёт выполняемый iterator и не выделяет память.
Обнулённые и перемещённые владельцы можно удалять повторно. Finalize использует
rx_finalize для сохранения cleanup при native break/continue/return этого SDK.

Публичный RxSubscription, его поле owner, factory rx_subscription, move,
rx_is_closed, rx_unsubscribe и сигнатура rx_subscribe_with сохранены.
Публичный rx_subscribe_with вызывает общий private rx_subscribe_control;
внутренние вызовы принимают RxControlOwner без создания compatibility iterator.
Observer по-прежнему удерживает control через RxControlRef. Новый primary owner
не становится частью поддерживаемого публичного API; служебные struct доступны
компилятору для финализации вложенных типов.

Сохранены идентичность каждого child, FIFO, момент запуска selector, порядок
cleanup до следующего child, отмена всех активных/ожидающих задач, обработка
устаревших sinks и удержание текущего callback. Закрытый retained sink может
удерживать storage/captures до своего удаления, как и до оптимизации; cleanup
активной подписки при этом уже выполнен.

Изменение общее для concat_map, flat_map, switch_map, exhaust_map и subscribe_on.
Другие семейства операторов продолжают использовать прежние владельцы controls.
Нет пула состояний или переиспользования закрытых RxSubscriptionState.

## Методика сравнения

Используется прежний benchmark из 17 сценариев, включая concat_sync,
concat_reuse и concat_queue. Каждый внешний вход создаёт ровно один child.
В concat_reuse внутренний rx_just создан один раз на пакет; clone этого
готового source на каждый вход остаётся частью workload. В concat_queue каждый
child создаёт собственный rx_just |> rx_delay(1), в очереди ждут входные int.

Размеры 32/256/1024, четыре пакета, пять samples на размер и два последовательных
раунда before/after и after/before для Interpreter, JIT и Release AOT.
Manual/Rx чередуются внутри каждого процесса. Дочерние процессы закреплены
за логическим CPU 0. Собственные тесты и сборки завершены до измерений.
Время компиляции в sample не включается. Сторонние процессы не останавливаются.
Перед серией системный счётчик CPU показывал 22%; процессов daslang/cl/link
уже не было. Это контрольная точка перед запуском, а не мониторинг всей серии;
измерения времени остаются локальными и могут зависеть от фоновой нагрузки.

6120 основных samples сверяют checksum до/после и с ручным циклом, включая
завершения и эффекты, и проверяют отсутствие оставшегося heap после teardown.
Дополнительно измеряются 720 пар fill/drain очередей; прогревы исключены.
Heap/string heap относятся к daScript, а не native allocator, LLVM, ОС или пику.
Цену child без постоянной настройки оцениваем разностью расходов N=256/1024.
Рост массивов, зависящий от N, остаётся частью этой оценки.

## Результаты памяти

Во всех трёх режимах счётчики совпали. Ниже — оценка расходов на один child: разность суммарных расходов для N=256 и N=1024, делённая на разность размеров. Постоянная настройка пакета исключена; рост массивов остаётся, если он зависит от размера.

| Сценарий | Выделения на child до → после | Байт на child до → после |
|---|---:|---:|
| concat_sync | 19.000 → 13.000 | 1008.000 → 656.000 |
| concat_reuse | 18.000 → 12.000 | 1000.000 → 648.000 |
| concat_queue | 63.003 → 57.003 | 4524.000 → 4172.000 |

Экономия — ровно 6 выделений и 352 байта на каждый child. Удалены три owning iterator: local child owner, alias в active list и primary control. Также экономятся 2 выделения на outer control каждого flatten-run.

Для асинхронной очереди N=1024 фазы измерены отдельно:

| Фаза concat_queue | Выделения до → после | Выделенные байты до → после |
|---|---:|---:|
| Fill | 72 → 66 | 9512 → 9032 |
| Drain | 64459 → 58321 | 4625344 → 4265248 |

Живой heap после fill при N=1024: 8240 → 7872 байта. Это очередь
входных int и один активный child, а не N одновременно активных children.

Fill создаёт только первый child, оставшиеся входы ждут в FIFO. Поэтому в fill экономятся 6 выделений, а в drain — 6 × (N−1). Память и выделения контрольных observe_on/delay/zip до и после совпали на всех размерах.

## Время

Медиана двух раундов, ns на внешний вход при N=1024, включая создание source, подписки, выполнение и teardown.

| Режим | Сценарий | До → после |
|---|---|---:|
| Interpreter | concat_sync | 19198.2 → 16580.5 |
| Interpreter | concat_reuse | 18776.3 → 16379.8 |
| Interpreter | concat_queue | 74969.6 → 73099.9 |
| Jit | concat_sync | 4282.1 → 3690.2 |
| Jit | concat_reuse | 4247.5 → 3396.7 |
| Jit | concat_queue | 15531.7 → 12186.3 |
| Aot | concat_sync | 3282.2 → 3039.9 |
| Aot | concat_reuse | 3248.0 → 2990.9 |
| Aot | concat_queue | 11164.3 → 10934.6 |

Контрольный неизменённый map, ns на вход в каждом раунде:

| Режим | Раунд | До → после |
|---|---:|---:|
| Interpreter | 1 | 309.0 → 389.1 |
| Interpreter | 2 | 408.7 → 473.3 |
| Jit | 1 | 154.2 → 113.2 |
| Jit | 2 | 109.6 → 108.8 |
| Aot | 1 | 69.1 → 68.1 |
| Aot | 2 | 73.2 → 70.0 |

В этой серии AOT concat_sync ускорился на 7,4%, concat_reuse — на 7,9%,
concat_queue — на 2,1%. Это локальные медианы, а не гарантированное ускорение.
Контрольный map в Interpreter и первом раунде JIT заметно колебался;
поэтому временам этих режимов не приписывается точная величина эффекта.
Изменение общего rx_subscribe_with добавляет промежуточный вызов в Interpreter;
данная серия не позволяет отделить его стоимость от системного шума.
Счётчики выделений памяти, в отличие от времени, воспроизводятся точно.

## Выполненные проверки

95 проверок Interpreter и 95 JIT: 23 примера, 59 положительных тестов и 13 ожидаемых ошибок компиляции. Собраны и исполнены 20 выбранных AOT-тестов: flatten, очереди, reentrancy/lifetime, scheduling/time, recovery и адаптеры Task/AsyncSequence. Новый тест владения и расширенный workload входят в AOT-набор. Main выполнен в AOT со strict linking.

Все 6120 основных samples и 720 фазовых измерений прошли проверку checksum и возвращения heap к исходному размеру после teardown. Хеши измеренных исходников совпали с текущими. Счётчики выделений контрольных сценариев до/после не изменились.

## Регрессионные проверки

test_child_control_ownership.das создаёт 128 одновременно активных children,
чтобы вызвать рост и перемещение массива владельцев. Проверяются завершение
из середины массива в собственном next-callback, закрытие остальных в обратном
порядке, отмена из next и сохранность capture, исключение одного cleanup с
продолжением закрытия остальных детей, сбой connect на 64-м child, синхронное
завершение во время connect, move/delete публичного RxSubscription, устаревшие
sinks и освобождение при break/continue. Cleanup и finalize ресурсов должны
выполниться ровно один раз. Повторные прогоны не должны оставлять живой heap.
Тот же тест прошёл на исходной реализации. Он включён в scripts.ps1 и CI.

## Воспроизведение

Сначала сохранить исходную lib и неизменённые benchmark-файлы в baseline-каталог.
Локальный снимок: .work/child-control/baseline.

```powershell
./reactivex/run.ps1 -Test
./reactivex/run.ps1 -Test -Jit
# Минимальный native-набор; локальная регрессия проверяет больше сценариев.
./reactivex/run_aot.ps1 -Scripts @('tests/test_child_control_ownership.das','tests/test_concat_inner_ownership.das','tests/test_concat_flat_lifetime.das')
./reactivex/run_extended_benchmarks.ps1 -BaselineDirectory ./reactivex/.work/child-control/baseline -OutputDirectory ./reactivex/.work/child-control/measurements -BuildOnly
# Дождаться окончания тестов и сборок.
./reactivex/run_extended_benchmarks.ps1 -BaselineDirectory ./reactivex/.work/child-control/baseline -OutputDirectory ./reactivex/.work/child-control/measurements -RunOnly
```

samples.csv, queue-samples.csv, summary.json, source/compiler hashes и логи
находятся в .work/child-control/measurements; .work игнорируется Git.
Runner проверяет хеши до/после замеров, тождественность benchmark и исполнение
AOT main со strict linking, а не только генерацию C++.

SHA256 lib/reactivex.das:

```text
before 0681E4817E608F9762BE3ADC4D7CCCA3BF144E7DAFC1259918F8338C2A1CA596
after  E87049D1BCF734F9D9BF8EA1C185A05F91DCB5348DBCD18B8B7752CAFC1A03C1
```
