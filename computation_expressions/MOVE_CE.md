# CE с передаваемым владением

`require computation` подключает `MoveResultBuilder`, `MoveOptionBuilder` и
конструкторы `move_ok`, `move_error`, `move_some`, `move_none`.
Они работают с обычными variant, содержащими массивы, таблицы или структуры
с непереписываемыми через `=` полями. Отдельной heap-обёртки CE не добавляет.

```das
var inscope result <- computation(MoveResultBuilder()) {
    var items & = move_ok([101, 202]) |> bind
    items |> push(303)
    return <- items
}
assert(length(result as ok) == 3)
```

Bind потребляет исходный variant: переносит его в локального владельца и
передаёт продолжению временную изменяемую ссылку на payload. `var items & =`
не копирует массив и не забирает владение из защитной области bind.
`return <- items` явно передаёт владение в результат. Получатель использует
`var inscope result <- ...`; результат можно перенести дальше между функциями.
После переноса нельзя рассчитывать на прежнее содержимое источника; для массива
оно становится пустым. Это не линейная система типов: компилятор не запрещает
всякое повторное использование перемещённой переменной.

Если следующий шаг выдаёт Error/None или бросает исключение, продолжение
останавливается, а владелец освобождает не переданный наружу payload. Bind без
переменной тоже потребляет и освобождает payload. Копируемые значения допускают
обычные `let n = ... |> bind` и `return n`. Для move-only payload используйте
ссылочный bind и `return <-`; `var x <- source |> bind` запрещён диагностикой.

```das
move_error("inventory unavailable", type<array<int>>)
move_none(type<array<int>>)

// and_bind вычисляет оба источника, затем переносит payload в пару.
var pair & = load_inventory() |> and_bind(load_inventory()) |> bind
```

Поддерживаются ветвления, unit-циклы с остановкой при Error/None, `return_from`,
`ce_source`, `try_with`, `try_finally`, а также `use_resource`. Для move-only
ресурса используйте `var r & = acquire() |> use_resource`: [MOVE_RESOURCES.md](MOVE_RESOURCES.md).
Для `and_bind` действует прежняя eager-семантика: правая сторона вычисляется
даже при Error/None слева. При исключении справа временный левый источник
освобождается. Уже существующая переменная слева остаётся у вызывающего кода
до фактического входа в merge. При таком исключении её очистка остаётся
обязанностью вызывающего кода: native panic сам по себе не раскручивает
`inscope`, находящийся внутри прерванного native try.

`deferred` тоже может возвращать такой результат: каждый запуск создаёт своё
владение. Правила снимков сохраняются, ссылки на снимок не должны выходить наружу.

## Границы

Это новые builders с явной семантикой владения. Старые Result/Option, State,
Writer не получают автоматически move-only payload. Move-only элементы
List/Sequence теперь описаны отдельно в [MOVE_COLLECTIONS.md](MOVE_COLLECTIONS.md).
Move-only ресурсы поддержаны отдельной owning-веткой use_resource
([MOVE_RESOURCES.md](MOVE_RESOURCES.md)). Для payload с ручным уничтожением через пользовательский finalizer
сам finalizer должен корректно освобождать данные и не бросать исключений.
Защита покрывает payload, принадлежащий bind, и промежуточные CE-результаты;
произвольные локальные native-ресурсы внутри пользовательского блока по-прежнему
требуют своего управления временем жизни. Сырые указатели не становятся owning.

## Расширение протокола

`ce_protocol(builder) -> CeOwnedProtocol()` включает перемещение CE-результатов,
изменяемые callback-аргументы bind и `ce_return_move(builder, var value)` для
`return <- value`. `ce_bind` обязан потреблять источник, удерживать его владельца
на время синхронного continuation и освобождать при исключении. Continuation
не должен сохраняться для вызова после завершения bind.

Для циклов нужны `ce_zero`, `ce_collect_append`, `ce_loop_failed` и
`ce_collect_rethrow`; встроенные owned builders принимают unit-результаты тела.
Общие For/While hooks и ce_source остаются доступны. Операции ресурсов должны
перемещать результат и защищать его при ошибке cleanup. См. `move_builders.das`.
BindReturn/Bind2 fusion для этой стратегии отключена: используется защищённый Bind.

`move_ce_demo.das` показывает игровой инвентарь и передачу между функциями.
`test_move_ce.das` проверяет Error/None, исключения, grouped bind, структуры,
повторные deferred-запуски и возврат `heap_bytes_allocated()` к исходному уровню.
Два отрицательных теста проверяют диагностику копирования и неверного bind.
