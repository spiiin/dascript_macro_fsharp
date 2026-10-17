# Короткие операции State

`state_modify` заменяет get → преобразование → put; `state_gets` возвращает
проекцию состояния. Работают внутри computation/deferred с StateBuilder,
StateResultBuilder и StateWriterResultBuilder:

```das
struct Hero {hp:int;gold:int}
let turn=computation(StateBuilder(Hero(hp=100,gold=5))) {
    state_modify($(hero:Hero) {
        return Hero(hp=hero.hp-25,gold=hero.gold)
    }) |> bind
    let health=state_gets($(hero:Hero) {return hero.hp}) |> bind
    return health
}
assert(turn.value==75 && turn.state.hp==75)
```

Mapper вызывается один раз на достигнутую операцию. Modify вычисляет новое
копируемое состояние, затем обычный bind StatePut устанавливает его. Gets
возвращает копируемый результат проекции без замены состояния. В StateWriterResult
проекция не добавляет журнал. Error следующих шагов откатывает modify по общей
границе транзакции; внешний эффект внутри mapper автоматически не откатывается.

Это CE-маркеры с одним block-аргументом. Макрос подставляет текущий builder
и вызывает `ce_state_modify` / `ce_state_gets`; block не сохраняется в операции
и не выходит за время вызова. Здесь нет heap-lambda или скрытого deferred.
Без завершающего `|> bind` такой marker не является самостоятельным API.
Поля состояния и результаты проекций должны поддерживать обычное копирование.

Проверки: [test_state_operations.das](tests/test_state_operations.das), включая
транзакционный откат, журнал, циклы и независимые повторные deferred-запуски.

Исключения mapper/projection, пропуск после Error и повтор после неудачного запуска: [test_state_operations_failures.das](tests/test_state_operations_failures.das). Короткий пример: [state_operations_demo.das](examples/state_operations_demo.das).
