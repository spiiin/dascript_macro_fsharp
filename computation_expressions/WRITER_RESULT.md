# WriterResultBuilder: журнал и остановка при ошибке

```das
require ./lib/computation.das
```

Результат имеет вид `tuple<result:variant<ok:T; error:string>; log:string>`.
Computation выполняется синхронно. При Error следующие шаги не выполняются,
а журнал уже выполненных шагов, включая неудачный шаг, сохраняется.
Тип ошибки в этом прототипе — string, как у ResultBuilder.

## Пример покупки

`purchase_example.das` определяет `find_item`, `check_balance`, `purchase`.
`writer_result_demo.das` проверяет успешную покупку, нехватку золота и отсутствие
товара. В функции purchase используется такой код:

```das
return computation(WriterResultBuilder()) {
    tell("purchase started\n") |> bind
    let item = find_item(id) |> bind
    check_balance(balance, item.price) |> bind
    tell("checks passed\n") |> bind
    completed++
    return item.name
}
```

`find_item` возвращает WriterResult с журналом поиска, `check_balance` — обычный
Result<Unit>. Счётчик completed меняется только при успехе. Это пример проверки
покупки: списания денег и внешних транзакций в нём нет.

При нехватке золота:

```text
result = Error("insufficient gold")
log = "purchase started\nfind item 1\n"
```

## Разрешённые источники bind

| Источник | Правило |
|---|---|
| WriterResult<T> | При Ok передать T продолжению, объединить журналы; при Error остановиться и сохранить журнал |
| Обычный Result<T> | Поднять в WriterResult с пустым журналом |
| `tell(text)`, то есть Writer<Unit> | Поднять в успешный WriterResult<Unit> с этим журналом |

Те же три формы поддержаны для `return source |> return_from`.
`return value` всегда упаковывает значение в Ok; поэтому обычный `return result`
сохраняет Result как вложенный payload. Для распространения его ошибки нужен
bind или return_from.

Произвольный Writer<T> автоматически не поднимается. Явное преобразование:

```das
let recorded = writer_value(42, "computed\n")
let converted = writer_result_ok(recorded.value, recorded.log)
```

Option и State требуют отдельного явного решения об их преобразовании.
Несовместимые источники отклоняются при компиляции.

## Конструкторы

```das
writer_result_ok(42, "success\n")
writer_result_error("not found", type<int>, "lookup failed\n")
writer_result(result_ok(42), "checked\n")
```

Журнал можно опустить: по умолчанию он пуст. Журнал ошибки не формируется
автоматически из текста ошибки — это отдельные поля. Сообщение неудачного
шага задаётся через writer_result_error либо tell перед проверкой.

```das
let outcome = computation(WriterResultBuilder()) {
    tell("before\n") |> bind
    writer_result_error("stop", type<int>, "failed step\n") |> bind
    tell("unreachable\n") |> bind
    return "done"
}
// outcome.result = Error("stop")
// outcome.log = "before\nfailed step\n"
```

## Ветви, циклы и композиция

Поддерживаются прежние if/elif/else, for/while, вложенные computation и вызовы
функций. Промежуточные ветви и тела итераций вычисляют Unit.

Bind добавляет журнал источника перед журналом продолжения. Combine делает то
же для первой части с Unit. Аккумулятор цикла объединяет журналы итераций;
при первой ошибке цикл возвращает ошибку с накопленным журналом. Вложенные
циклы распространяют её наружу без дублирования записей. После сбоя не
вычисляются ни следующая проверка while, ни источники последующих циклов.

Zero — успешный Unit и пустой журнал. Delay использует общий синхронный
механизм. Дополнительного изменения AST-макроса для этого builder не потребовалось:
добавлено публичное подключение `writer_result_builder.das` и перегрузки протокола.

Это накопление возвращаемых данных, не потоковый вывод: tell не печатает в
консоль. Нет rollback уже выполненных внешних эффектов. Исключения языка не
преобразуются автоматически в Error. Move-only payload, async и произвольные
типы ошибки/журнала пока не поддержаны. Как и у WriterBuilder, конкатенация
строк может приводить к квадратичному копированию для длинных журналов.

## Запуск и проверки

```powershell
cd C:\src\dascript_macro_fsharp\computation_expressions
.\run_computation.ps1 -Test
```

`test_writer_result.das` проверяет:

- успех и ошибку на каждой позиции цепочки, исходный текст ошибки;
- переход от int источника к string конечного результата;
- единственное вычисление builder и достигнутого источника;
- точное содержимое журнала, включая записи неудачного шага;
- пустые блоки, Zero, bind без переменной и все формы return_from;
- автоматический подъём Result и tell, вложенные computation;
- выбранные ветви, for/while, пустые и вложенные циклы, ошибку в каждом месте;
- отсутствие эффектов, проверки условия и вычисления источников после ошибки;
- независимость журналов отдельных запусков.

Негативные проверки `test_writer_result_option.das`,
`test_writer_result_writer.das`, `test_writer_result_loop_value.das` проверяют
неподдерживаемые источники bind и не-Unit результат тела цикла.
Общий `../run.ps1 -Test` также включает эти проверки.
