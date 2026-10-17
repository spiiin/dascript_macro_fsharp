# StateBuilder и WriterBuilder

Для сокращения get → put доступны [state_modify и state_gets](STATE_OPERATIONS.md).

Синхронные computation expressions поверх общего AST-макроса. Подключение:

```das
require ./lib/computation.das
```

Запуск всех builders и их тестов:

```powershell
cd C:\src\dascript_macro_fsharp\computation_expressions
.\run_computation.ps1 -Test
```

## State: значение и конечное состояние

`StateBuilder(initial)` создаёт типизированный контекст для копируемого типа
состояния `S`. Computation выполняется сразу над локальной копией контекста
и возвращает `tuple<value:T; state:S>`. Нет глобального состояния.

```das
struct GameState {
    health : int
    gold : int
}

let initial = GameState(health=100, gold=5)
let outcome = computation(StateBuilder(initial)) {
    var game = state_get() |> bind
    game.health -= 25
    game.gold += 3
    state_put(game) |> bind

    let current = state_get() |> bind
    return current.health > 0
}
// outcome.value == true
// outcome.state.health == 75; outcome.state.gold == 8
// initial.health == 100; initial.gold == 5
```

- `state_get() |> bind` возвращает снимок текущего состояния. Изменение этого
  снимка не заменяет состояние контекста до `state_put(...) |> bind`.
- `state_put(new_state) |> bind` заменяет состояние и возвращает CeUnit.
  Тип `new_state` должен совпадать с типом состояния builder.
- `return value` возвращает значение вместе с текущим состоянием.
- Блок без return возвращает CeUnit вместе с конечным состоянием.
- `state_result(value, state)` конструирует готовую пару результата и состояния.

`state_get` и `state_put` создают описания операций; исполняет их Bind.
Простое создание `let op = state_put(...)` ничего не меняет.
Копирование состояния — обычное копирование daScript, не глубокое клонирование
объектов за указателями. Для изолированных снимков используйте состояние из
копируемых значений, как в примерах, без разделяемых изменяемых ссылок.

## Передача между функциями и повторный запуск

`game_state_example.das` содержит GameState и функцию
`play_turn(initial, damage, reward)`. Она уменьшает здоровье, увеличивает число
ходов и начисляет награду в цикле, если персонаж жив. Её результат можно
связать в другой computation:

```das
let adventure = computation(StateBuilder(initial)) {
    let before = state_get() |> bind
    let survived = play_turn(before, 25, 3) |> bind
    let after = state_get() |> bind
    return after.gold
}
```

Bind готового `tuple<value:T; state:S>` **заменяет текущее состояние на state
этого результата** и передаёт value продолжению. Поэтому для последовательного
продолжения передавайте в функцию снимок текущего состояния. Просто вычислить
вложенный workflow без bind недостаточно, чтобы изменить внешний контекст.
`return prepared |> return_from` возвращает готовый результат, принимая его
состояние; повторной упаковки нет.

Это eager State API, а не хранимое ленивое значение вида `S -> (T, S)`.
Чтобы выполнить workflow с другим начальным состоянием, снова вызовите функцию
`play_turn`. Повторный bind уже вычисленной пары импортирует тот же снимок,
но не повторяет исходные операции.

`state_demo.das` показывает композицию функций и лечение двумя зельями в while.
Вывод: `health=85, gold=8; turns=1`. Начальное состояние остаётся прежним.

## Writer: значение и журнал

Writer возвращает `tuple<value:T; log:string>`. Bind и Combine соединяют строки
в порядке выполнения слева направо. Нет общего изменяемого журнала.

```das
let report = computation(WriterBuilder()) {
    tell("turn started\n") |> bind
    let gold = writer_value(3, "reward +3\n") |> bind
    if (gold > 0) { tell("reward accepted\n") |> bind }
    for (i in range(2)) { tell("event {i}\n") |> bind }
    return gold * 10
}
// report.value == 30
// report.log содержит пять строк в порядке выполнения.
```

- `writer_value(value, log)` создаёт значение с журналом; log по умолчанию пуст.
- `tell(message)` создаёт Writer с CeUnit. Сообщение добавляется в общий результат
  только при bind, return_from или другом явном объединении.
- `return value` создаёт Writer с пустым собственным журналом; предыдущие Bind
  и Combine добавляют свои сообщения к итоговому результату.
- `return prepared |> return_from` сохраняет значение и журнал готового Writer.
- Zero возвращает CeUnit и пустой журнал.
- Разделители и переводы строк задаются явно в сообщениях, автоматически
  ничего не добавляется.

`writer_demo.das` показывает отдельную функцию `reward`, bind её результата,
ветку и цикл. Два независимых computation не разделяют журнал.

## Циклы и общая реализация

В `computation.das` появился аккумулятор результата цикла. Он начинается с
`ce_zero`, после каждой итерации объединяется с её результатом через
`ce_loop_append`, затем проверяется `ce_loop_failed`:

- Result/Option сохраняют прежнюю остановку при Error/None.
- State принимает конечное состояние итерации.
- Writer добавляет журнал итерации к накопленному журналу.

И пустые, и завершающие, и вложенные for/while сохраняют эффекты корректно.
Тело итерации и промежуточная ветка по-прежнему вычисляют Unit. Для State/Writer
`ce_loop_failed` всегда false: у них нет собственной семантики ошибки.
Если Writer возвращает Result как полезное значение, Error сам по себе
не прекращает Writer. Для сочетания журнала и остановки при Error добавлен отдельный
[WriterResultBuilder](WRITER_RESULT.md).

Реализация находится в `computation_effects.das`. StateBuilder — generic
функция-фабрика контекста `tuple<kind:StateContext; state:S>`, потому что тип
состояния различается. WriterBuilder — структура без полей. Макрос создаёт
из аргумента builder локальную изменяемую копию; блоки-продолжения выполняются
синхронно и не сохраняются за пределами своего стека.

## Проверки и ограничения

`test_computation_effects.das` проверяет:

- состояние игры после урона, смерти, награды и композиции функций;
- неизменность исходных значений и прежних снимков, независимость повторных запусков;
- единственное вычисление builder и источника bind;
- разные типы состояния, в том числе int; 10 000 итераций без рекурсии по итерациям;
- пустые блоки, пустые/вложенные/завершающие циклы, ветвления и return_from;
- точное содержимое и порядок журнала, отсутствие дублирования;
- отсутствие эффекта от несвязанных операций и отсутствие общего журнала.

Негативные тесты `test_state_wrong_type.das`, `test_writer_mixed.das`,
`test_state_loop_value.das`, `test_writer_loop_value.das` должны не компилироваться.
Общий runner проверяет эти ошибки и прежние тесты Result/Option.

Поддерживаются копируемые состояния и payload. Move-only значения, async,
отмена и rollback в этих builders не добавлены. Для освобождения ресурсов
добавлены [Using/TryFinally](RESOURCES.md).
Writer использует конкретно string, не произвольный тип журнала. Конкатенация
строк в длинных циклах может приводить к квадратичному копированию текста;
для больших журналов нужен отдельный вариант с буфером или списком записей.


Для отката состояния при Error добавлен отдельный [StateResultBuilder](STATE_RESULT.md).



Числовой For у StateBuilder использует специализированный native loop через
общий протокол. Разбор, проверки и замеры до/после: [STATE_OPTIMIZATION.md](STATE_OPTIMIZATION.md).
