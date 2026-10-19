# Computation expressions для C++-программистов

Этот текст для тех, кто знает C++ (желательно C++20-корутины и `std::expected`),
но не знает F#. Знать F# и теорию типов не нужно. Где применять конкретные
builders и где обычный daslang лучше — в [WHEN_TO_USE.md](WHEN_TO_USE.md).

## Одна фраза

> Computation expression (CE) — это блок обычного последовательного кода, который
> макрос переписывает в вызовы функций **builder**-объекта. Что означает «перейти
> к следующей строке» — продолжить, пропустить остаток, приостановиться,
> повторить для каждого элемента — решает builder, а не язык.

## Знакомая боль

Три вида кода, которые писал каждый:

```cpp
// 1. Лесенка ошибок
auto a = parse(x);   if (!a) return std::unexpected(a.error());
auto b = load(*a);   if (!b) return std::unexpected(b.error());
auto c = check(*b);  if (!c) return std::unexpected(c.error());
return *c * 2;

// 2. Callback hell или ручной конечный автомат
connect(url, [=](Socket s) {
    s.send(msg, [=] {
        s.receive([=](std::string reply) { /* ... */ });
    });
});

// 3. Вложенный перебор с ранним отсечением: флаги, break, goto
```

Во всех трёх случаях **логика линейная, а код — нет**. Между полезными строками
размазан один и тот же служебный код: проверить ошибку, подписать продолжение,
освободить ресурс, откатить позицию.

## Тот же код через CE

```das
// Ошибки: остаток блока не выполняется, если шаг вернул error
let outcome = computation(ResultBuilder()) {
    let a = parse(x)  |> bind
    let b = load(a)   |> bind
    let c = check(b)  |> bind
    return c * 2
}

// Асинхронность: тот же вид кода, но шаги ждут завершения операций
def exchange(url:string;text:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource   // закроется при любом исходе
        ws_connect(socket,url) |> bind
        ws_send_text(socket,text) |> bind
        let reply=ws_receive_text(socket) |> bind
        return reply
    }
}
```

Форма кода одинаковая. Разное поведение задаёт builder в заголовке блока.

## Механизм: «перегружаемая точка с запятой»

Главная мысль: **CE позволяет перегрузить то, что происходит между строками** —
так же, как range-for позволяет перегрузить обход через `begin()`/`end()`.

Блок

```das
computation(builder) {
    let a = parse(x) |> bind
    let b = load(a)  |> bind
    return b * 2
}
```

макрос (упрощённо) разворачивает в

```das
ce_bind(builder, parse(x), $(a) {
    return ce_bind(builder, load(a), $(b) {
        return ce_return(builder, b * 2)
    })
})
```

Остаток блока после каждого `|> bind` превращается в **лямбду-продолжение**,
а `ce_bind(builder, источник, продолжение)` — это точка кастомизации, которую
находит перегрузка по типу builder. Builder решает, вызывать ли продолжение,
когда и сколько раз:

| Builder | Что `ce_bind` делает с продолжением |
|---|---|
| ResultBuilder | вызывает один раз, если `ok`; иначе сразу возвращает ошибку |
| OptionBuilder | вызывает, если `some`; иначе возвращает `none` |
| TaskBuilder | запоминает и вызывает позже, когда операция завершится |
| ListBuilder | вызывает для **каждого** элемента и склеивает результаты |
| SearchBuilder | вызывает лениво для каждой альтернативы, поиск в глубину |
| ParserBuilder | вызывает с новой позицией в тексте; при неудаче — откат |
| StateBuilder | вызывает, протаскивая состояние неявным параметром |

Код внутри блока один и тот же, семантика разная.

## Аналогия с C++20-корутинами

Если аудитория знает корутины, это самый короткий путь:

| C++20 coroutines | CE в этой библиотеке |
|---|---|
| `promise_type` | builder |
| `co_await expr` | `expr \|> bind` |
| `await_suspend(handle)` | `ce_bind(builder, source, continuation)` |
| `co_return v` → `return_value` | `return v` → `ce_return` |
| `co_yield v` → `yield_value` | `yield v` |
| пустое тело → `return_void` | `ce_zero` |
| разрушение фрейма, деструкторы | `use_resource`, `try_finally`, `ce_dispose` |

Отличие: протокол C++ заточен под **приостановку** — продолжение вызывается
ровно один раз, сейчас или позже. В CE продолжение можно вызвать **ноль раз**
(ошибка), **один раз** (Result), **позже** (Task) или **много раз** (List,
Search). Поэтому одним механизмом выражаются:

- цепочки `std::expected` — в C++23 это `and_then`, в CE линейный код;
- async/await — в C++ корутины;
- генераторы — в C++ `std::generator`;
- перебор и запросы — в C++ ranges и вложенные циклы;
- парсеры — в C++ Boost.Spirit или ручной рекурсивный спуск.

В C++ это пять разных механизмов, в CE — один.

## Минимальный builder

Builder — обычная структура плюс несколько перегрузок. Полностью рабочий пример
из [integration_example/identity_builder.das](integration_example/identity_builder.das),
который просто передаёт значение дальше:

```das
struct IdentityBuilder {}
def ce_protocol(builder:IdentityBuilder) {return CeValueProtocol()}
def ce_unwrap(builder:IdentityBuilder; source:tuple<value:auto(T)>) : T {return source.value}
def ce_bind(builder:IdentityBuilder; source:tuple<value:auto(T)>; next:block<(item:T):auto(R)>) : R {
    return invoke(next,source.value)        // вызвать продолжение один раз
}
def ce_return(builder:IdentityBuilder; value:auto(T)) {return (value=value)}
def ce_zero(builder:IdentityBuilder) {return (value=CeUnit())}
def ce_combine(builder:IdentityBuilder; first:tuple<value:CeUnit>; next:block<():auto(R)>) : R {return invoke(next)}
```

Чтобы превратить его в Result-подобный builder, достаточно поменять тело
`ce_bind`: если источник — ошибка, вернуть её, не вызывая `next`. Всё остальное —
ветвления, циклы, ресурсы, `and_bind` — макрос разворачивает через тот же протокол.
Полный список точек кастомизации — в [BUILDER_PROTOCOL.md](BUILDER_PROTOCOL.md).

## Чего это позволяет достичь

1. **Линейный код для нелинейного управления.** Асинхронный обмен читается как
   синхронный, цепочка проверок — как код без проверок.
2. **Эффект описан в одном месте.** Как распространять ошибку, отмену или таймаут,
   написано один раз в builder, а не в каждой функции.
3. **Гарантированная очистка на всех путях.** RAII, который работает через
   приостановки, отмену, таймауты и panic. В стандартном daslang `[async]`
   (SDK 0.6.4 и 0.6.5-RC2) локальный `var inscope` освобождается на первом
   ожидании ([repro](tests/repro/repro_async_inscope.das)); в Task CE этого нет.
4. **Композиция.** `a |> and_bind(b)`, `task_when_all`, `task_race`, групповая
   отмена токеном работают для любых задач одинаково.
5. **Предметные мини-языки без новых ключевых слов.** Парсер, поиск, запросы —
   одна конструкция с разными builders.

## Чего это стоит

- **Производительность.** Продолжения и обёртки не бесплатны. По бенчмаркам
  репозитория Result CE в 1.8–2.5 раза медленнее ручных проверок, List —
  в 1.3–2.3 раза; Sequence и State под JIT — около 1.0×
  ([BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md), [STATE_OPTIMIZATION.md](STATE_OPTIMIZATION.md),
  [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md)).
- **Абстракция.** Чтобы понять строку, нужно знать builder сверху — та же цена,
  что у перегрузки операторов.
- **Отладка.** Стек вызовов проходит через сгенерированные продолжения;
  примеры раскрытия макроса — [state_expansion_after.txt](state_expansion_after.txt),
  [list_expansion_after.txt](list_expansion_after.txt); сообщения об ошибках — [DIAGNOSTICS.md](DIAGNOSTICS.md).
- **Без эффекта не нужно.** Если нет ошибок, ожиданий или ресурсов, обычный
  императивный код с `var` проще и быстрее.

## Правило применения

Используйте CE, когда **эффект протягивается через много шагов** (ошибка,
отмена, ожидание, откат, журнал) или **нужна очистка через приостановки**.
Иначе пишите обычный daslang. Подробно по каждому builder —
[WHEN_TO_USE.md](WHEN_TO_USE.md), примеры Task — там же.

## Про слово «монада»

Термин из теории для того, что делает `ce_bind`. Для понимания и использования
CE он не нужен. C++-программистам больше помогают аналогии с `promise_type`
и `std::expected::and_then`.
