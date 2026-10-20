# Когда использовать CE, а когда обычный daslang

Сравнение с идиоматическими средствами daslib и модулей SDK 0.6.5-RC2.
Числа скорости — из [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md),
[STATE_OPTIMIZATION.md](STATE_OPTIMIZATION.md), [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md)
и [ASYNC_SEQUENCE_PERFORMANCE.md](ASYNC_SEQUENCE_PERFORMANCE.md); это отдельные
запуски на одной машине, а не универсальная цена bind.

## Общий принцип

daslang императивен: `var`, генераторы, `[async]`, `try/recover`, `finally`/`defer`,
`var inscope`. CE окупается, когда:

1. **эффект протягивается через много шагов** — ошибка, отмена, ожидание, откат
   позиции, журнал, — и вручную получается лесенка `if (r is err) return ...`;
2. **нужна гарантированная очистка ресурсов** при ошибке, отмене, таймауте,
   panic и досрочном `break`, а стандартные средства этого не дают.

Если нет ни того, ни другого, обычный код проще и быстрее.

## Короткое правило

| Ситуация | Что брать |
|---|---|
| Асинхронность, отмена, ресурсы | TaskBuilder / TaskResultBuilder, AsyncSequenceBuilder, CoroutineBuilder |
| Ошибка через длинную цепочку, особенно с откатом состояния/журнала | ResultBuilder, StateResultBuilder, WriterResultBuilder, StateWriterResultBuilder |
| Маленький контекстно-зависимый парсер с точной диагностикой | ParserBuilder |
| Перебор с отсечениями и лимитом решений | SearchBuilder |
| Простые проверки, коллекции, запросы | `daslib/result`, `daslib/option`, генераторы массивов, `daslib/linq`, `daslib/functional` |
| Полноценная грамматика | `dasPEG` |
| Мутабельное состояние без ошибок | обычный `var` |

## Result / Option, MoveResult / MoveOption

- **Идиоматично:** `daslib/result` и `daslib/option` (`and_then`, `map`, `unwrap_or`, `??`),
  `match` или `is`/`as`. Оператора раннего выхода вроде `?` из Rust в daslib нет.
- **CE лучше:** 3+ зависимых шага, которые могут упасть. Цепочка `and_then` уходит
  вправо вложенными блоками, CE остаётся линейным. Внутри цепочки работают
  `use_resource` / `try_finally`; `and_bind` вычисляет оба источника и берёт первую ошибку.
- **Обычный код лучше:** 1–2 проверки, горячие циклы. Result CE ≈1.8× медленнее
  в интерпретаторе и ≈2.5× под JIT в прежних измерениях; эти числа получены
  до перехода на стандартные типы.
- **Совместимость:** CE использует стандартные `$Result<T;string>` (err/ok) и
  `$Option<T>` (none/some); функции daslib принимают результаты без адаптера.
  [Миграция и владение](STANDARD_TYPES.md).
- Примеры: [computation_demo.das](examples/computation_demo.das),
  [move_ce_demo.das](examples/move_ce_demo.das), [and_bind_demo.das](examples/and_bind_demo.das).

## Validation

- **Идиоматично:** `var errors : array<string>`, `push` на каждую проверку,
  в конце `if (empty(errors))`.
- **CE лучше:** независимые поля, которые нужно и проверить, и сразу собрать
  в результат. `validation_zip` накапливает все ошибки, результат либо валиден
  целиком, либо нет; независимые проверки комбинируются с зависимыми.
- **Обычный код лучше:** плоская форма — массив ошибок проще.
- Пример: [validation_demo.das](examples/validation_demo.das).

## State / Writer / Reader и варианты с Result

- **Идиоматично:** состояние — `var s : State&` в параметре; журнал — `array<string>`
  или `daslib/logger`; окружение — обычный параметр или захват в лямбду.
- **CE лучше:** в основном варианты с Result (StateResult, WriterResult,
  StateWriterResult, ReaderResult). Там важна чистота: исходный `initial`
  не мутирует, а при ошибке результат несёт состояние и журнал на момент ошибки.
  Вручную это требует копий состояния на шагах.
- **Обычный код лучше:** голые State / Writer / Reader — в императивном языке
  это просто `var`. State под JIT после оптимизаций ≈1.0× ручного кода,
  в интерпретаторе всё ещё ≈6–20×.
- Примеры: [state_demo.das](examples/state_demo.das),
  [state_result_demo.das](examples/state_result_demo.das),
  [writer_result_demo.das](examples/writer_result_demo.das),
  [reader_result_demo.das](examples/reader_result_demo.das),
  [state_writer_result_demo.das](examples/state_writer_result_demo.das).

## List

- **Идиоматично:** генератор массива `[for (x in a); x * 2; where x > 0]`,
  вложенные `for` с `push`, `daslib/linq` и `linq_boost` (`_where |> _select`).
- **CE лучше:** недетерминированный перебор с зависимыми шагами — второй источник
  зависит от первого значения, пустой источник обрывает ветку; move-only элементы
  (`yield <-`, consuming bind).
- **Обычный код лучше:** почти всегда для простых комбинаций и map/filter.
  List даже после оптимизаций ≈1.3–2.3× медленнее ручного кода.
- Примеры: [list_demo.das](examples/list_demo.das),
  [move_collections_demo.das](examples/move_collections_demo.das).

## Sequence

- **Идиоматично:** `generator<T>() <| $ { yield ...; return false }`,
  `[iterator for (...)]`, `daslib/functional` (`map`, `filter`, `flat_map`).
- **CE лучше:** ленивая последовательность с ресурсами и досрочным `break`
  потребителя — закрытие гарантировано; вложенные источники через `bind` и
  `yield_from`. По скорости на уровне ручного защищённого генератора (≈1.0×).
- **Обычный код лучше:** простой генератор без ресурсов — `generator<T>` и так нативный.
- Примеры: [sequence_demo.das](examples/sequence_demo.das),
  [sequence_resources_demo.das](examples/sequence_resources_demo.das),
  [sequence_nested_cleanup_demo.das](examples/sequence_nested_cleanup_demo.das).

## Search

- **Идиоматично:** вложенные `for` с `yield` в `generator`, рекурсивный генератор,
  ручной стек.
- **CE лучше:** задачи с ограничениями (головоломки, планирование, подбор):
  ленивый поиск в глубину, раннее отсечение, лимит числа решений, последовательное
  объединение альтернатив. Вручную это превращается в набор флагов.
- **Обычный код лучше:** маленькое пространство фиксированной глубины.
- Примеры: [search_demo.das](examples/search_demo.das),
  [search_alternatives_demo.das](examples/search_alternatives_demo.das).

## Query

- **Идиоматично:** `daslib/linq` + `linq_boost` (`_where`, `_order_by`, `group_by`,
  `distinct`); `_fold` из `linq_fold` сливает цепочку в один цикл. Для таблиц —
  `sql_linq`, для ECS — `query` из `decs_boost`.
- **CE лучше:** редко — когда запрос удобнее как блок со связанными переменными,
  join через `and_bind` и логикой между шагами (как query expression в F#).
- **Обычный код лучше:** по умолчанию. LINQ в SDK развитее, быстрее (fusion)
  и знаком читателю. Query стоит считать экспериментальным.
- Примеры: [query_demo.das](examples/query_demo.das),
  [query_full_demo.das](examples/query_full_demo.das).

## Parser

- **Идиоматично:** `dasPEG` (`parse(...) { var rule : T; rule(...) <| action }`) —
  генерация PEG-парсера на этапе компиляции; `daslib/regex` для токенов;
  `strings_boost`, `json`, `toml` для простых форматов.
- **CE лучше:** маленький встроенный контекстно-зависимый парсер (следующее
  правило зависит от уже разобранного значения), точная диагностика
  (line/column/expected), управление backtracking через `committed`.
  В dasPEG действия с состоянием прямо запрещены.
- **Обычный код лучше:** настоящая грамматика (выражения, язык) — dasPEG декларативнее.
- Примеры: [parser_demo.das](examples/parser_demo.das),
  [parser_combinators_demo.das](examples/parser_combinators_demo.das).

## Coroutine

- **Идиоматично:** `daslib/coroutines` (`[coroutine]`, `co_await`, `yeild_from`,
  `cr_run_all`) или `async_boost` (`await_next_frame`, `async_timeout` по кадрам);
  `iterator<bool>` тоже по сути корутина.
- **CE лучше:** игровые сценарии с ресурсами и отменой — `coroutine_cancel`
  закрывает области ресурсов; точное `wait_frames(n)`; `CoroutineScheduler`.
- **Обычный код лучше:** простое «подождать кадр» без ресурсов — `[coroutine]` короче.
- Примеры: [coroutine_demo.das](examples/coroutine_demo.das),
  [coroutine_scheduler_demo.das](examples/coroutine_scheduler_demo.das).

## Task / TaskResult (scheduler, cancellation, delay, events, TCP, HV)

- **Идиоматично:** `async_boost` (`[async]`/`await`, `async_run_all`, `async_race`,
  `async_timeout`); для настоящего параллелизма — `jobque_boost`.
- **CE лучше:** самый сильный кейс библиотеки. Типизированный кешируемый результат,
  статусы Succeeded/Failed/Cancelled, групповая отмена через CancellationToken
  сквозь вложенные bind, таймауты по `now_ms`, `when_all` / `race` / `and_bind`,
  move-only payload, закрытие ресурсов при ошибке, отмене, таймауте и panic.
  В стандартном `[async]` SDK 0.6.4 и 0.6.5-RC2 локальный `var inscope`
  освобождается на первом ожидании
  ([repro_async_inscope.das](tests/repro/repro_async_inscope.das)); в Task CE этого нет.
- **Обычный код лучше:** покадровая логика без ресурсов и отмены — `[async]` достаточно.
- **Инфраструктура:** один `task_runtime` для задач разных типов, `task_channel`
  и `task_channel_select`, `task_progress`, семафор и `when_all` с лимитом,
  `task_retry` / `task_first_success`, дочерние токены отмены с причиной,
  `task_next_deadline` и дамп задач ([TASK_CONCURRENCY.md](TASK_CONCURRENCY.md)).
- **Потоки и сеть:** сами Task кооперативны и однопоточны (нативный синхронный код
  блокирует poll), но тяжёлую работу можно вынести в jobque: `task_jobque`,
  `task_jobque_cancellable` (кооперативная отмена worker), `task_jobque_stream`
  (много значений из worker с backpressure) и `task_http` поверх блокирующего
  HTTP-клиента dasHV.
- Примеры: [task_demo.das](examples/task_demo.das),
  [task_cancellation_demo.das](examples/task_cancellation_demo.das),
  [task_timeout_demo.das](examples/task_timeout_demo.das),
  [task_async_demo.das](examples/task_async_demo.das),
  [task_async_resources_demo.das](examples/task_async_resources_demo.das),
  [task_hv_demo.das](examples/task_hv_demo.das),
  [task_toolkit_demo.das](examples/task_toolkit_demo.das).

## AsyncSequence

- **Идиоматично:** прямого аналога нет; вручную — генератор плюс явный цикл
  `task_poll` / `next`.
- **CE лучше:** асинхронный поток элементов (сеть, события) с backpressure:
  `next` запрашивает ровно один элемент, отмена закрывает весь поток; async `for`
  и zip по двум потокам. Ручной вариант длинный и легко теряет очистку.
- **Цена:** ≈8–28 выделений на элемент в зависимости от сценария.
- Примеры: [async_sequence_demo.das](examples/async_sequence_demo.das),
  [async_sequence_zip_demo.das](examples/async_sequence_zip_demo.das),
  [async_sequence_move_demo.das](examples/async_sequence_move_demo.das).

## Сильные примеры Task / TaskResult

Код ниже взят из запускаемых примеров и слегка сокращён: `require`, счётчики
и `verify` опущены. Общий мотив — то, что на `[async]` пришлось бы писать
вручную и что легко сломать: закрытие ресурса на каждом пути выхода, отмена
вложенных ожиданий, типизированный итог со статусом.

### 1. Две сетевые операции параллельно, с отменой и таймаутом

[task_hv_and_bind_demo.das](examples/task_hv_and_bind_demo.das)

```das
def exchange(url:string;text:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url) |> bind
        ws_send_text(socket,text) |> bind
        let reply=ws_receive_text(socket) |> bind
        return reply
    }
}
def two_requests(urlA:string;urlB:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let pair=exchange(urlA,"one") |> and_bind(exchange(urlB,"two")) |> bind
        return "A={pair.first}; B={pair.second}"
    }
}
// Запуск: task_spawn(scheduler,task_with_cancellation(two_requests(a,b),token),
//                    TaskTimeout(after_ms=5000))
```

Что даёт CE:
- ошибка любого шага (`connect`/`send`/`receive`) возвращается как `error`, остальные шаги не выполняются;
- `and_bind` опрашивает оба обмена вместе; при отмене или таймауте отменяются оба, ожидающая операция dasHV снимается, а **оба сокета закрываются** (после любого исхода `hv_websocket_stats().active==0`);
- итог различим: `Succeeded` + `ok`/`error`, `Cancelled` (отдельно `task_timed_out`), `Failed` при panic.

На `[async]` пришлось бы вручную вести флаг отмены в каждом цикле ожидания,
закрывать сокеты на каждом раннем выходе и отдельно кодировать вид исхода.

### 2. Загрузка с ресурсом и таймаутом: ресурс освобождается, продолжение не выполняется

[task_timeout_demo.das](examples/task_timeout_demo.das)

```das
def prepare_level() {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = load_data() |> use_resource      // ce_dispose(LevelData)
        let bonus=task_after_polls(10,5) |> bind
        applied++                                      // не выполнится при таймауте
        return length(data.items)+bonus
    }
}
var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=2))
let level=task_spawn(scheduler,prepare_level(),TaskTimeout(after_ms=30))
// ... task_tick(scheduler,now_ms) каждый кадр
// после таймаута: Cancelled, task_timed_out==true, released==1, applied==0
```

Таймаут считается по `now_ms` планировщика, а не по числу кадров. Бюджет
`max_polls_per_tick` ограничивает работу за кадр. Именно здесь стандартный
`[async]` в SDK 0.6.4/0.6.5-RC2 ломается: локальный `var inscope` освобождается
на первом ожидании ([repro](tests/repro/repro_async_inscope.das)).

### 3. Групповая отмена: выход с уровня отменяет все его задачи

[task_cancellation_demo.das](examples/task_cancellation_demo.das)

```das
var inscope level <- cancellation_token()
var inscope scheduler <- task_scheduler(type<int>)
let player=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
let npc=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
let unrelated=task_spawn(scheduler,task_after_polls(1,7))
task_tick(scheduler,0)
cancellation_cancel(level)   // игрок покинул уровень
task_tick(scheduler,16)
// player и npc: Cancelled, их ресурсы освобождены; unrelated: Succeeded, 7
```

Один токен на область жизни (уровень, экран, сессию). Отмена проходит сквозь
вложенные `bind` до текущего ожидания, а задачи вне области не затрагиваются.

### 4. Динамический WhenAll: порядок результатов не зависит от порядка завершения

[task_array_demo.das](examples/task_array_demo.das)

```das
def load_asset(id,delay:int) {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = acquire() |> use_resource
        task_delay_ms(delay) |> bind
        return id*10+length(data.items)
    }
}
var source <- computation(TaskBuilder(type<int>)) {
    var results & = task_when_all(asset_jobs()) |> bind   // array задач 0,1,2
    // завершились в порядке 1,2,0, но results[i] соответствует задаче i
    return results[0]+results[1]+results[2]
}
```

`task_when_all` принимает владеющий массив задач произвольной длины. Если одна
задача падает или отменяется, остальные отменяются, а их ресурсы закрываются
([TASK_ARRAY.md](TASK_ARRAY.md), [TASK_COMPOSITION.md](TASK_COMPOSITION.md)).

### 5. Ожидание UI-события: диалог как одна функция

[task_events_demo.das](examples/task_events_demo.das)

```das
var actions:typedecl(task_event_source(type<string>))
def on_confirm_clicked() {task_event_emit(actions,"confirm")}   // UI callback

def confirmation_dialog() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let action=task_wait_event(actions) |> bind
        return action=="confirm" ? "Purchase confirmed" : "Purchase declined"
    }
}
let dialog=task_spawn(scheduler,task_with_cancellation(confirmation_dialog(),token),
                      TaskTimeout(after_ms=5000))
```

Callback не выполняет продолжение синхронно: оно идёт на следующем `task_tick`.
При закрытии UI (отмене токена) или таймауте подписка снимается автоматически:
`task_event_subscriber_count(actions)==0`, `task_event_stats()` без утечек.
Без CE это пара «callback + конечный автомат состояний диалога» с ручной отпиской.

### 6. Совместимость со стандартным `[async]`: when_all и race

[task_combinators_demo.das](examples/task_combinators_demo.das),
[task_async_resources_demo.das](examples/task_async_resources_demo.das)

```das
[async]
def standard_name() : string {await_next_frame();yield "Alice"}

def load_player() {
    return <- computation(TaskBuilder(type<string>)) {
        let data=task_when_all(task_from_async(standard_name()),task_after_polls(2,85)) |> bind
        return "{data.first}: health={data.second}"
    }
}
var inscope race <- task_race(task_after_polls(3,"slow"),task_from_async(standard_name()))
// winner.index==1, winner.value=="Alice"; проигравшая задача отменена
```

Существующий код на `async_boost` не нужно переписывать: `task_from_async`
заворачивает его в Task. Для ресурсов, которыми владеет `[async]`-функция,
есть перегрузка с close-callback, которая гарантирует очистку и при отмене:
`task_from_async(standard_read(request),@() { unsafe {delete request} })`.

### Где Task CE не нужен

Однокадровая анимация, «подождать N кадров» или линейный скрипт без ресурсов,
отмены и типизированного итога — здесь короче `[coroutine]` или `[async]`.
Тяжёлые синхронные вычисления — в `jobque_boost`: poll-модель не даёт потоков,
и нативный синхронный код блокирует тик.
