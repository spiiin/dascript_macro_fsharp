# Move-only элементы List и Sequence

Обычные `ListBuilder(type<T>)` и `SequenceBuilder(type<T>)` выбирают стратегию
владения автоматически, если T нельзя копировать. Пример: структура с `array`.
Для копируемых элементов прежнее поведение builders сохраняется.

```das
struct Loot {items:array<int>}

var inscope rewards <- computation(ListBuilder(type<Loot>)) {
    var reward & = loot_list() |> bind
    reward.items |> push(100)
    return <- reward
}

var inscope stream <- computation(SequenceBuilder(type<Loot>)) {
    var reward & = loot_sequence() |> bind
    reward.items |> push(200)
    yield <- reward
}
```

Полный исполняемый пример: `move_collections_demo.das`; фабрики игровых предметов
и ресурсного источника: `move_collection_support.das`.

## List

Результат — обычный `array<T>`. `yield <-` и `return <-` передают элемент в массив
через emplace, без clone. `yield_from`/`return_from` перемещают входные элементы.
Промежуточные массивы принадлежат CE и освобождаются при исключении.

Ссылочный bind `var reward & = source |> bind` потребляет исходный массив;
продолжение заимствует очередной элемент. После bind динамический массив источника
пуст; у fixed array перемещены элементы. Если элемент не выдан наружу, он удаляется
вместе с владельцем. Нельзя сохранить ссылку на него за пределами продолжения.
Для получения обычных значений из move-only входов тоже доступен такой bind:

```das
var inscope sizes <- computation(ListBuilder()) {
    var reward & = loot_list() |> bind
    return length(reward.items)
}
```

Для copyable List этот **явный ссылочный bind** включает потребление источника;
обычный `let x = source |> bind` сохраняет прежнюю семантику.

`and_bind` сохраняет декартово произведение и потому требует копируемых входных
элементов. Move-only входы отвергаются диагностикой: один владелец не может
одновременно попасть в несколько пар. Можно использовать вложенный bind,
создающий новый источник для каждой итерации, либо явное клонирование.

## Sequence

Внутренний генератор передаёт значение в принадлежащий итератору слот.
Публичный тип для move-only T — `iterator<T&>`: это временное заимствование
текущего элемента, действующее **до следующего шага или закрытия итератора**.
Такой слот нужен потому, что native `for` daScript 0.6.4 не удаляет move-only
значения из собственного value-слота. Перед следующим шагом и при close
наш итератор удаляет оставшийся payload.

```das
var inscope selected:Loot
{
    var inscope stream <- loot_sequence()
    for(reward in stream) {
        selected <- reward // selected теперь владеет данными; слот пуст
        break              // закрывает поток и ресурсный источник
    }
}
// selected остаётся действительным после закрытия потока.
```

Если элемент не нужен после итерации, его не требуется вручную удалять.
Обычный обход, break, закрытие непрочитанного потока и закрытие внешнего CE
освобождают принадлежащие потоку данные. Вложенные bind, `yield_from`,
`use_resource`, `try_finally` и `try_with` используют ту же защиту.

Для внешнего callback, который может бросить исключение, используйте
`sequence_each` (чтение) или `sequence_each_move` (изменение и перенос):

```das
var inscope saved:array<Loot>
var inscope stream <- loot_sequence()
sequence_each_move(stream) $(var reward:Loot) {saved |> emplace(reward)}
```

Эти функции закрывают поток при ошибке производителя или потребителя.
Native `for` вне CE по-прежнему не гарантирует закрытие при исключении тела;
это ограничение runtime. Не сохраняйте ссылку итерации: перенесите значение.
Finalizers ресурсных источников должны освобождать ресурсы без исключений,
как и для прежнего Sequence. Сырые указатели не становятся owning.

## Протокол и границы

Для move-only выходов List использует `CeOwnedProtocol` с массивом результата;
`ce_loop_failed` всегда false. Перегрузки операций находятся в `list_builder.das`.
Явный mutable-reference bind copyable collection использует типовой hook
`ce_unwrap_borrow(builder, source)` и изменяемый continuation. Внешний collection
builder может добавить его и соответствующий consuming `ce_bind`.

Move-only Sequence возвращает свой owning-slot iterator из `ce_sequence_run`.
Внутренние forwarding yield перемещают элемент, сохраняя обычные copyable yield.
Дескрипторы builders содержат нулевой типовой указатель вместо экземпляра T;
он не выделяет память и не разыменовывается.

`deferred` поддерживает эти встроенные descriptors, если их типовой указатель
нулевой и payload T сам владеет данными. Каждый запуск получает независимый
глубокий клон снимка. Ссылочный результат move-only Sequence удерживает снимок
до close: сначала закрываются дочерний итератор и текущий элемент, затем снимок.
Обычные указатели в snapshot/payload и произвольные reference-итераторы остаются
запрещены. Пример: `deferred_move_collections_demo.das`; подробности ниже.

`test_move_collections.das` повторно проверяет heap baseline, перенос и
освобождение массивов/элементов, полное завершение, break, исключения,
вложенные источники, recovery и cleanup. Отрицательные тесты проверяют попытку
копировать элемент List и недопустимый декартов product.

## Повторный запуск move-only вычисления

```das
require ./lib/deferred_computation.das

var inscope task <- deferred(ListBuilder(type<Loot>),loot_list()) $(snapshot) {
    var reward & = snapshot |> bind
    reward.items |> push(100)
    return <- reward
}
var inscope a <- run_deferred(task)
var inscope b <- task |> run_deferred
// a и b владеют разными массивами и могут пережить task.
```

```das
var inscope task <- deferred(SequenceBuilder(type<Loot>),loot_list()) $(snapshot) {
    for(i in range(length(snapshot))) {yield <- snapshot[i]}
}
var inscope first <- run_deferred(task)
var inscope second <- run_deferred(task)
delete task
var inscope selected:Loot
for(reward in first) {selected <- reward;break}
sequence_each(second) $(reward:Loot) {print("{length(reward.items)}\n")}
// selected остаётся владельцем данных после закрытия first.
```

На создании task снимок клонируется для хранения; на каждом `run_deferred`
создаётся ещё один глубокий клон для конкретного запуска. Это явная цена
повторяемости: move-only не означает запрет предусмотренного clone.
List выполняет тело при запуске; Sequence начинает выполнять тело только
при обходе, но память под его снимок выделяется уже при запуске.
Перемещение элементов в результат не добавляет клонирования на каждый yield.

Ссылка на текущий элемент Sequence по-прежнему действует лишь до next/close.
`sequence_each` и `sequence_each_move` закрывают поток при исключении callback.
Native for вне CE требует этих helpers либо явного close при исключении тела.
Закрытие непрочитанного потока также освобождает его снимок. Удаление task
не отменяет уже созданные потоки: они владеют отдельными снимками.

`test_deferred_move_collections.das` проверяет независимые и перекрывающиеся
запуски, удаление task до обхода, перенос элементов, cleanup до удаления
снимка, повторный close, завершение, break и ошибки. Проверки используют
счётчик finalizer снимка и `heap_bytes_allocated()`. Отрицательные тесты
сохраняют запрет pointer-payload и произвольного reference-result; ненулевой
типовой маркер встроенного builder отвергается перед созданием снимка.

## Ручной обход: sequence_next_move

`sequence_next_move(stream, value)` переносит следующий move-only элемент в
самостоятельную переменную-владельца. Поддерживаются `iterator<T&>` от
SequenceBuilder/deferred и native `iterator<T>`, выдающий owning значения.

```das
var inscope stream <- run_deferred(task)
var inscope reward:Loot
while(sequence_next_move(stream, reward)) {
    consume(reward)
}
```

- При `true` прежнее содержимое reward освобождено, reward владеет новым элементом.
- При `false` поток закрыт, последнее значение reward сохранено.
- При исключении производителя поток закрыт, последнее значение сохранено,
  исключение передано вызывающему коду.
- Повторный вызов на закрытом потоке возвращает false.

`reward` должен быть отдельным владельцем, а не ссылкой на текущий слот самого
потока. Копируемые элементы отвергаются диагностикой; для них существует `next`.
Вызывающий код отвечает за `inscope` результата и за закрытие потока при
досрочном выходе из ручного while: `break` сам по себе не закрывает поток.
Аналогично исключение в теле while требует собственного try/recover с close;
если нужен готовый защищённый обход, используйте `sequence_each_move`.
Финализаторы элементов должны быть не бросающими.

Ручное чтение позволяет чередовать deferred-запуски независимо друг от друга.
Пример: `sequence_next_move_demo.das`. Проверки владения, heap, конца потока,
producer error, явного досрочного закрытия и замены результата:
`test_sequence_next_move.das`.

Оптимизация линейных List bind-цепочек и consuming-map, ограничения по
финализаторам, проверки и бенчмарки до/после: [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md).
