# ReaderResultBuilder

Окружение только для чтения и обычный Result с ошибкой типа `string`.
Builder подключается отдельным модулем, без изменения `computation.das`:

```das
require ./lib/computation_macro.das
require ./lib/reader_result_builder.das

let damage = computation(ReaderResultBuilder(rules)) {
    let config = reader_ask() |> bind
    let base = validate_attack(level) |> bind
    return base * config.damageMultiplier
}
```

`validate_attack` возвращает `result_ok(value)` или
`result_error(message, type<T>)`. Итог CE — `$Result<T;string>`.
Обычные функции могут принимать окружение, выполнять собственный ReaderResult CE
и возвращать Result для следующего пайпового bind. Пример двух атак:
`reader_result_demo.das`.

## Семантика

- `reader_ask()` читает окружение текущего builder. Он совместим с ReaderBuilder.
- Окружение копируется в builder; поддерживаются копируемые типы. Глубокая
  неизменяемость объектов за пользовательскими указателями не обеспечивается.
- `bind` при Error не вызывает продолжение. BindReturn сохраняет это правило.
- `and_bind` допускает Result и `reader_ask()` в любом порядке; при нескольких
  ошибках сохраняется первая слева. Выражения обоих источников вычисляются,
  как и у ResultBuilder; это не параллельное исполнение.
- Пустой CE возвращает `Ok(CeUnit())`; ветвления и bind без переменной работают.
- `return result |> return_from` передаёт готовый Result без обёртки.
- `for`, одновременный обход нескольких источников и `while` используют
  стандартное раскрытие общего протокола. Первая ошибка прекращает цикл и CE.
- `use_resource`, `try_finally` и `try_with` используют общий протокол ресурсов.
  Error — значение, а не исключение: он не вызывает обработчик `try_with`.
  Builder не преобразует native panic в Error автоматически.

Обычный CE выполняется немедленно. Для сохранения вычисления используйте
`deferred(ReaderResultBuilder(rules), data) $(snapshot) { ... }` из модуля
`deferred_computation`. Каждый `run_deferred` получает собственный снимок;
ограничения допустимых захватов описаны в `DEFERRED.md`.

## Границы

Это Value-протокол с копируемыми окружением и успешным значением; move-only
результаты не поддерживаются этим builder. Отката внешних побочных эффектов нет.
Для вложенного вычисления с другим окружением передайте другое значение в
`ReaderResultBuilder`; отдельной операции `local` пока нет.

Builder можно сохранить: `let savedBuilder = ReaderResultBuilder(rules)`, затем
использовать `computation(savedBuilder)` или `deferred(savedBuilder, data)`.
Макрос ожидает завершения вывода типа локальной переменной перед выбором
протокола. Повторные CE получают собственные локальные контексты builder.

## Проверки

`test_reader_result.das` проверяет ошибки, BindReturn, групповой bind, ветвления,
все формы циклов, закрытие ресурсов при завершении/Error/native panic,
отсутствие утечек в проверяемых сценариях и повторные deferred-запуски после
выхода из функции, создавшей окружение. `test_reader_result_readonly.das` должен
не компилироваться: изменение полученного через `let` окружения запрещено.
