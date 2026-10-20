# Стандартные Result и Option

CE использует `daslib/result` и `daslib/option` из SDK 0.6.5-RC2. Они публично
подключены через builder_protocol: обычному приложению достаточно своего
стандартного require computation. Самостоятельный require daslib/result/option
также допустим, конфликтующих собственных some/none/move_some больше нет.

| Было | Стало |
|---|---|
| `variant<ok:T;error:string>` | `$Result<T;string>` — `variant<err:string;ok:T>` |
| `variant<some:T;none:bool>` | `$Option<T>` — `variant<none;some:T>` |
| `value is error` / `value as error` | `value is err` / `value as err` для Result |
| Конструирование `none=true` | `none(type<T>)` либо `default<$Option<T>>` |
| Default Result был ok(default T) | Default Result — err с пустой строкой |
| Default Option был some(default T) | Default Option — none без payload |

```dascript
require ./lib/computation.das
let value=computation(ResultBuilder()) {
    let n=ok(40,type<string>) |> bind
    return n+2
}
verify(result::unwrap(value)==42)

let absent=computation(OptionBuilder()) {
    let n=option::none(type<int>) |> bind
    return n+1
}
verify(option::is_none(absent))
```

Пайповый bind и общий протокол builders не изменились. Result-builders сохраняют
прикладную ошибку типа string; использование произвольного E в `$Result<T;E>`
не добавлено этим изменением. Task, TaskResult, AsyncSequence, комбинаторы,
сетевые адаптеры и адаптеры ReactiveX используют то же стандартное представление.
Parser optional также возвращает стандартный Option, а диагностический результат
Parser с позицией и собственный накопительный Validation сохраняют свои типы.

## Конструкторы и владение

- `result_ok(value)` и `result_error(message,type<T>)` сохранены как обёртки над
  `result::ok(value,type<string>)` и `result::err(message,type<T>)`.
- `some`, `none`, `move_some` доступны из стандартной option. Для не копируемого
  payload some/ok используют стандартное клонирование; явное перемещение задаётся
  move_some/move_ok. Сохраняются MoveResultBuilder и MoveOptionBuilder с их
  потребляющим bind и `return <- value`.
- `move_ok(value)` — CE-обёртка со стандартным типом Result<T,string> и обходом
  ошибки AOT SDK 0.6.5-RC2: перемещение tuple с массивом прямо в initializer
  variant не очищает источник. Обёртка сначала создаёт пустой ok, затем отдельно
  перемещает поле. Стандартная двухаргументная форма остаётся доступной; для таких
  tuple в CE используйте одноаргументную обёртку. `move_error` / `move_none`
  также сохранены, но возвращают стандартные типы.
- `ce_move_some(value)` применяет тот же обход для стандартного Option. Его используют
  MoveOptionBuilder, Parser optional и AsyncSequence; при ручном перемещении tuple
  с массивами в Option под AOT используйте эту CE-обёртку вместо move_some.
- После перемещения всего Result/Option исходный variant сбрасывается в свой
  default: err/none. Нельзя читать `source as ok` или `source as some`, чтобы
  проверить пустоту перемещённого значения; проверяйте соответствующий case.

Изменение несовместимо с прежними явными объявлениями variant, bool-payload none
и проверками `is error`. Старые типы не поддерживаются скрытыми преобразованиями;
все библиотечные потребители обновлены согласованно. Если используется явный
конструктор variant, запись `variant type<$Result<T;string>>(ok=value)` корректна;
для пользовательского кода предпочтительнее стандартный ok/err.

## Что не переименовывается

`TaskStatus.Failed`, `TaskStatus.Cancelled`, строковое поле task.error и исключения
остаются отдельными состояниями, а не ветками Result. Error-уведомление ReactiveX
materialize также сохраняет case `error`: это другой протокол, не Result.
Накопление ошибок Validation и границы отката StateResult не меняются.

## Проверки

[test_standard_outcomes.das](tests/test_standard_outcomes.das) проверяет обычные
стандартные конструкторы, отсутствие конфликтов require, standard unwrap/is_ok/
is_some, остановку CE, новые defaults, перемещение массивов, вложенные пары трёх and_bind, TaskResult и
отсутствие роста живой памяти. Он включён в основной runner, mode_tests.json и
в стандартный список исполнения AOT. Существующие проверки CE, Task, AsyncSequence
и Rx-адаптеров используют новое представление.

Вложенные merge удаляют служебные имена выведенных generic-параметров из
публичного типа пары: это позволяет связывать три и более источника без
конфликта имён в стандартных шаблонах. Представление данных не меняется.

SDK не изменяется и не включается в поставку. Для этой версии библиотеки нужен SDK
со стандартными daslib/result и daslib/option указанного формата.

## Проверка миграции, 20 октября 2026

Режимы проверены раздельно на неизменённом SDK 0.6.5-RC2.

| Режим | Проверенный объём |
|---|---|
| Интерпретатор | Полный run_computation.ps1 -Test; полный reactivex/run.ps1 -Test (90 проверок) |
| JIT | 13 выбранных тестов CE/Task/Rx плюс test_task_glfw_keyboard.ps1 -Jit |
| Исполнение AOT CE | standard_outcomes, move_ce, async_sequence_move, async_sequence_zip, parser_combinators, task_owned, task_result — 7/7 |
| Исполнение AOT Rx | task_adapters, task_adapter_lifetime, async_sequence_adapters, async_sequence_adapter_lifetime, notifications — 5/5 |
| Исполнение native AOT | Тесты и демонстрации GLFW/WebSocket — 4/4; fallback отвергается |

AOT проверяет собранные хосты со строгим связыванием и AOT main, а не только
генерацию C++. Полные JIT/AOT-наборы этой таблицей не заявляются. Для повторения
выборочного AOT-прогона CE доступен параметр run_aot.ps1 -Scripts с массивом
путей относительно computation_expressions. Тест standard_outcomes включён
также в обычные CI-наборы интерпретатора, JIT и AOT.
