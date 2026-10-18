# Parser, Search и Query

Три отдельных публичных модуля расширяют общий CE-протокол. Из приложения:

```das
options gen2
require ./lib/computation_macro.das
require ./lib/parser_builder.das
require ./lib/search_builder.das
require ./lib/query_builder.das
```

`computation_macro.das` не менялся для этих builders. Они поддерживают обычные
ветвления, циклы, `use_resource`, `try_finally`, `try_with` и `deferred`.
Query/Search работают с копируемыми элементами. Parser также поддерживает owning
массивы повторений; см. [PARSER_COMBINATORS.md](PARSER_COMBINATORS.md). `and_bind` поддерживает Query (декартовы пары),
но не Parser (зависимые позиции) или Search. Отсутствующий hook даёт обычную
диагностику общего протокола.

## ParserBuilder

```das
let parsed=computation(ParserBuilder(text="hp = 85")) {
    parser_literal("hp") |> bind
    parser_spaces() |> bind
    parser_literal("=") |> bind
    parser_spaces() |> bind
    let health=parser_int() |> bind
    parser_eof() |> bind
    return health
}
assert(parsed is parsed && (parsed as parsed).value==85)
```

Успех — `parsed=(value=T, position=int, committed=bool)`. Ошибка —
`failure=ParseDiagnostic(position, line, column, expected)`.
Позиция — смещение в байтах UTF-8, начиная с нуля; строка и колонка начинаются
с единицы. Новая строка определяется LF, колонка также считает байты, не Unicode
символы. В примере `hp = nope` ошибка integer в позиции 5, строке 1, колонке 6.

Builder содержит исходный `text` и текущую `position` (по умолчанию 0).
Позиция меняется успешным bind; при failure следующие шаги не выполняются.
Сохранённый builder не изменяется: CE работает с собственной копией.
Начальная позиция должна находиться в пределах `[0, length(text)]`.
`parser_eof` нужен явно: без него допустим разобранный префикс.

| Операция | Поведение |
|---|---|
| `parser_literal(text)` | Точное совпадение строки, возвращает эту строку |
| `parser_int()` | ASCII цифры с необязательным минусом, int32; переполнение — failure |
| `parser_spaces()` | Ноль или больше space/tab/CR/LF; возвращает CeUnit |
| `parser_eof()` | Проверка конца входа, CeUnit |
| `parser_call(@@grammar)` | Вызов вложенной функции `grammar(cursor:ParserBuilder)` |
| `parser_choice(left, right)` | Левый успех имеет приоритет; после обычной неудачи правый стартует с исходной позиции |

Для альтернатив целых грамматик:

```das
def bracketed(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("[") |> bind
        let n=parser_int() |> bind
        parser_literal("]") |> bind
        return n
    }
}
// Внутри другого Parser CE:
// let n=parser_choice(parser_call(@@bracketed),parser_int()) |> bind
```

Вложенная грамматика возвращает такой же parsed/failure. Обе альтернативы
должны возвращать один тип значения. Committed/fatal ошибка прекращает выбор альтернатив. При двух обычных ошибках выбирается самая дальняя
позиция; на одинаковой позиции expected объединяются слева направо через `or`.
Возврат позиции не отменяет внешние эффекты неудачной альтернативы. Для
предсказуемого backtracking распознаватели должны быть чистыми.
Failure — значение, не исключение; native panic обрабатывается через try_with.
Нет автоматического пропуска пробелов, мемоизации или поддержки левой рекурсии.

## SearchBuilder

```das
var inscope solutions <- computation(SearchBuilder()) {
    let x=search_choose([1,2,3]) |> bind
    let y=fixed_array(10,20) |> bind
    search_guard(x!=2) |> bind
    yield x+y
}
// sequence_each выдаёт 11, 21, 13, 23 и закрывает iterator.
sequence_each(solutions) $(n:int) {print("{n}\n")}
```

Это ленивый поиск в глубину, слева направо. Bind — выбор очередного варианта;
неудачная ветвь возвращается к ближайшему выбору. `search_guard(false)` оставляет
ветвь без решений и не выполняет её продолжение. Данные внешних объектов и
эффекты не откатываются. Бесконечная левая ветвь может не дать перейти к правой:
справедливого обхода или breadth-first scheduling нет.

`search_choose(array)` **потребляет** динамический массив и владеет им до
закрытия источника. Для неизменяемых небольших наборов можно напрямую bind
`fixed_array(...)`; заимствованный именованный массив должен жить до закрытия
поиска. Не передавайте незащищённый временный динамический массив напрямую в
генераторный bind: используйте `search_choose`.

`search_once(source)` и синоним `search_cut(source)` оставляют первое решение
этого источника, немедленно закрывая оставшийся перебор. Отсечение имеет явную
область: окружающие выборы по-прежнему перебираются. Это не глобальный Prolog cut.
Если source пуст, решения нет. Брошенное исключение не считается неудачной
ветвью и не запускает backtracking.

Поиск закрывается через `sequence_each`, `sequence_close` или уничтожение
владеющего iterator. После внешнего `break` явно закрывайте источник, если его
владелец ещё остаётся в области. Ресурсы закрываются при исчерпании, scoped cut,
досрочном закрытии и ошибке производителя/потребителя. `sequence_each` защищает
и путь исключения из callback потребителя.

`search_take(source,n)` ограничивает перебор и закрывает источник до выдачи n-го
решения; при `n <= 0` закрывает без чтения. `search_append(left,right)` перебирает
левый поиск, затем правый, сохраняя повторы. Оба потребляют iterator и поддерживают
пайпы: `let n=left() |> search_append(right()) |> search_take(3) |> bind`.
Порядок, владение и раннее закрытие: [SEARCH_COMBINATORS.md](SEARCH_COMBINATORS.md).

## QueryBuilder

```das
var inscope rows <- computation(QueryBuilder(type<string>)) {
    let n=fixed_array(1,2,3) |> bind
    query_where(n>1) |> bind
    return "n={n}"
}
assert(length(rows)==2 && rows[0]=="n=2" && rows[1]=="n=3")
```

Builder выполняется немедленно и собирает `array<T>`. Return — проекция строки,
`query_where(bool) |> bind` — фильтрация текущей строки. Остаток тела выполняется
один раз для каждого прошедшего сочетания источников; порядок эффектов сохранён.
Коллекционные операции можно использовать и без CE:

```das
var inscope filtered <- source |> query_where <| $(row:Row){return row.enabled}
var inscope projected <- filtered |> query_select <| $(row:Row){return row.name}
var inscope joined <- query_join(left,right,
    $(row:Left){return row.key}, $(row:Right){return row.key})
```

Операторы заимствуют входные массивы, не перемещая их. Возвращаемые динамические
массивы нужно сохранять во владельцах `var inscope`; особенно промежуточные
результаты цепочек обычных функций. Входы — фиксированные или динамические массивы.
Join возвращает пары `.first/.second`: это стабильный inner equijoin с сохранением
дубликатов, сначала порядок левых строк, затем правых. Left key вычисляется один
раз на левую строку, right key — для каждой пары. Реализация nested-loop,
O(left × right), без индекса или оптимизатора запросов.

Query использует механизм накопления и защиты ресурсов List; это запросы в
памяти, без SQL, LINQ provider, пользовательских ключевых слов или переноса
фильтрации на сервер. Стабильные order_by, group_by и distinct описаны в [QUERY_OPERATORS.md](QUERY_OPERATORS.md).
Outer join пока не поддерживается.

## Проверки

`run_computation.ps1 -Test` запускает примеры, положительные проверки,
ошибки неподдержанного and_bind/move-only типов и повторные deferred-запуски.
Новые положительные наборы также включены в `mode_tests.json` для interpreter,
JIT и отдельной генерации AOT C++. Генерация не доказывает AOT-исполнение. Отдельно `run_aot.ps1` собирает
и исполняет перечисленные положительные наборы в строгом AOT-хосте вместе с Task/AsyncSequence;
проверяются `fail_on_no_aot` и `main->aot`. См. [AOT_RUNTIME.md](AOT_RUNTIME.md).

Search/Query и deferred проверяют стабильность прогретого heap на повторных
запусках, включая cleanup при исключениях и досрочном закрытии Search.
Примеры: [Parser](examples/parser_demo.das), [Search](examples/search_demo.das),
[Query](examples/query_demo.das).

Проверка перед публикацией 2026-10-18: полный `run.ps1 -Test` прошёл;
итоговый `run_modes.ps1 -Mode Jit` — 49/49, строгий `run_aot.ps1` — 44/44
с `main->aot` и `fail_on_no_aot`. Дополнительно прошли active patterns под JIT,
генерация AOT C++ и сетевые/клавиатурные проверки CI под JIT.
