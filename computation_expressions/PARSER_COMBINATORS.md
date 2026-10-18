# Parser: optional, repetition, attempt и commit

```das
options gen2
require ./lib/computation_macro.das
require ./lib/parser_builder.das

var inscope result <- computation(ParserBuilder(text="[1,-2,3]")) {
    parser_literal("[") |> bind
    parser_commit() |> bind
    var items & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
    parser_literal("]") |> bind
    parser_eof() |> bind
    return <- items
}
assert(result is parsed && (result as parsed).value[1] == -2)
```

| Операция | Результат и остановка |
|---|---|
| `parser_optional(p)` | `some:T / none:bool`; none только при отсутствии совпадения без потребления входа |
| `parser_many(p)` | `array<T>`, ноль или больше элементов |
| `parser_many1(p)` | `array<T>`, хотя бы один элемент; при отсутствии первого сохраняет его диагностику |
| `parser_sep_by(item, separator)` | `array<T>`, включая пустой список; после потреблённого separator обязательно нужен item |
| `parser_attempt(p)` | При обычной ошибке разрешает откат к началу именно p, сохраняя дальнюю позицию диагностики |
| `parser_commit()` | Нулевая операция CeUnit; последующие ошибки текущей ветви запрещают переход к следующей альтернативе |
| `parser_commit(p)` | Обёртка: ошибка p committed, успешный p устанавливает commit для следующих шагов |

## Backtracking

Для совместимости `parser_choice(left,right)` по-прежнему пробует right после
обычной ошибки left, даже если left успел прочитать префикс. Автоматического cut
после любого потребления нет. После committed-ошибки right не вычисляется.

```das
parser_choice(parser_commit(parser_literal("abc")),parser_literal("abd"))
// На "abd": ошибка 'abc' в позиции 2, правая ветвь не запускается.

parser_choice(parser_attempt(parser_commit(parser_literal("abc"))),parser_literal("abd"))
// На "abd": попытка откатывается, правая ветвь успешно возвращает "abd".
```

Обёртки можно применять к целым грамматикам через `parser_call(@@grammar)`.
`attempt` не снимает commit, выполненный ДО начала этой попытки. Успешная попытка
не отменяет сделанный внутри commit. Вложенный choice после уже выполненного
commit всё ещё может выбирать свои локальные альтернативы; сам commit сохраняется
для ошибки окружающей ветви.

`optional`, `many` и поиск конца `sep_by` различают отсутствие совпадения и
повреждённую конструкцию. Например, optional("ab") на "ax" возвращает failure,
а optional(attempt("ab")) — none с позицией 0. Переполнение int — ошибка, даже
если её диагностическая позиция указывает на начало числа.
Успехи ранее выполненных шагов не откатываются из-за attempt следующего шага:
для возврата всего составного распознавателя оборачивайте всю грамматику.

У `sep_by(int, ",")` строка "1," ошибочна: separator уже потреблён.
Attempt только вокруг следующего int не разрешает trailing separator; для
отката всей конструкции нужен attempt вокруг всего sep_by/вложенной грамматики.
Пустой separator допустим, если item продвигает позицию.

Откат меняет управление разбором и позицию, но не отменяет print, внешние записи
или изменения объектов. Распознаватели альтернатив должны быть чистыми.
Native panic не превращается в отсутствие совпадения и обрабатывается try_with.

## Владение результатами

Повторения возвращают настоящие владеющие массивы, в том числе вложенные.
Parser использует CeOwnedProtocol: источник bind живёт до конца продолжения,
`var items &` заимствует его payload. Чтобы передать массив наружу, нужен
`return <- items`; снаружи результат сохраняют в `var inscope result <- ...`.
Нельзя сохранять заимствованную ссылку дольше владельца. Для копируемых значений
прежняя запись `let n=parser_int() |> bind` сохраняется.

Optional также может содержать owning payload: например,
`parser_optional(parser_call(@@parse_array))`. Элементы, частичные массивы и
вложенные массивы освобождаются при обычной ошибке, исключении, cut и завершении
продолжения; deferred создаёт независимые результаты каждого запуска.
Custom-грамматика с owning результатом может использовать `parser_ok_move`.

Успех теперь имеет поля `(value, position, committed)`; прежние `value` и
`position` сохранены. Если собственный парсер вручную объявлял тип variant,
предпочтите `parser_ok` / `parser_ok_move` / `parser_error` для согласованного типа.

## Диагностика и защита повторений

`position`, `line`, `column`, `expected` сохраняют прежний смысл: позиция и
колонка считаются в байтах UTF-8; position от 0, line/column от 1, новая строка LF.
На двух незафиксированных ошибках choice выбирает дальнюю; на равных позициях
объединяет expected. Committed/fatal ошибка имеет приоритет перед альтернативой.

Добавлены `committed` и `fatal`, а также служебные `consumed`, `rewound`,
`rewind_position`. Последние отличают область отката от места дальней ошибки:
вложенный attempt не делает уже прочитанный внешний префикс необязательным.

Если элемент many/many1/sep_by успешно завершается с позицией не больше начальной,
повторение немедленно возвращает fatal failure с expected
`many: parser succeeded without advancing input` (либо many1/sep_by).
Это ошибка грамматики, а не обычное несовпадение. Её нельзя скрыть optional,
attempt или следующей альтернативой choice. Например, many(spaces) и
many(optional(int)) могут встретить успех нулевой длины и будут отклонены.
Пользовательский распознаватель обязан возвращать позицию в пределах входа;
повторения не прерывают зависший или блокирующий код самого распознавателя.

## Проверки

Пример: [parser_combinators_demo.das](examples/parser_combinators_demo.das).
`test_parser_combinators` проверяет границы попыток, cut, диагностику, пустые и
повреждённые списки, nullable-парсеры и вложенные owning результаты.
`test_parser_combinator_lifetime` проверяет освобождение при частичном разборе,
исключениях callback/cleanup, восстановлении и повторных deferred-запусках;
после прогрева 16 повторений должны сохранять heap_bytes_allocated.
Оба файла регистрируются в общем runner, JIT и строгом AOT runtime наборе.
