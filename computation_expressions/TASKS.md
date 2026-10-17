# TaskBuilder и TaskResultBuilder

Совместное ожидание и гонка: [TASK_COMPOSITION.md](TASK_COMPOSITION.md),
модуль task_combinators.das. Доступны task_when_all, task_result_when_all и task_race.

Ближайший стандартный аналог — [daslib/async_boost](https://daslang.io/doc/stdlib/generated/async_boost.html):
аннотация [async], await и await_next_frame также раскрываются в генераторы.
Наш модуль использует ту же базовую возможность языка. Отличия — CE-протокол,
один кешируемый результат, явные статусы и отмена, общий ресурсный контракт,
TaskResult с коротким замыканием при Error и callback-адаптер внешних операций.
Для простого сценария с await достаточно стандартного async_boost. Стандартная
библиотека также имеет async_run/race/timeout; набор Task-combinators описан в
[TASK_COMPOSITION.md](TASK_COMPOSITION.md). Потоки и jobs предоставляет отдельный jobque.

```das
options gen2
require ./lib/computation_macro.das
require ./lib/task_builder.das

var inscope task <- computation(TaskResultBuilder(type<string>)) {
    let name = task_after_polls(2, result_ok("Alice")) |> bind
    let health = task_after_polls(1, result_ok(85)) |> bind
    return "{name}: {health}"
}

// Вызывать из игрового цикла или цикла событий, продолжая другую работу.
let status = task_poll(task)
// После Succeeded: let result = task_value(task)  // Result<string>
```

`TaskBuilder(type<T>)` ожидает Task<U> и возвращает Task<T>.
`TaskResultBuilder(type<T>)` ожидает Task<Result<U>> или Task<CeUnit>: bind извлекает ok,
а error завершает всю задачу с Result.error, пропуская продолжение.
`return value` в этом builder автоматически оборачивает значение в ok.
Тип результата задаётся явно; payload должен быть копируемым и владеть данными.
Вложенные указатели, ссылки, lambda, block и iterator в payload запрещены.

## Выполнение и владение

Задача — move-only владелец генератора с типизированным результатом. Создание CE
сохраняет вычисление: тело начинает исполняться при первом task_poll.
Это **cold, single-shot** семантика первой версии; она отличается от немедленного
старта F# task. Повторный poll завершённой задачи возвращает сохранённый статус
без повторного исполнения. Для нового запуска вызовите функцию-фабрику ещё раз.
Генератор сохраняет копии внешних значений согласно правилам capture daScript.
Ссылки на стек не становятся безопасными из-за создания Task.

Один poll выполняет синхронные шаги до следующего Pending или конечного результата.
Готовые источники не требуют дополнительного прохода цикла событий. У source
ровно один успешный результат; повторных выполнений продолжения нет.
Если тело заканчивается без return, задача становится Failed с диагностикой.
Произвольный долгий синхронный код внутри CE может задержать весь poll.

| Операция | Поведение |
|---|---|
| `task_poll(task)` | Возвращает Waiting, Succeeded, Cancelled или Failed |
| `task_status(task)` | Читает статус, включая Created до первого poll |
| `task_value(task)` | Копия результата только после Succeeded; иначе panic |
| `task_error(task)` | Сообщение native exception при Failed |
| `task_cancel(task)` | Закрывает Created/Waiting, возвращает true; повторно false |
| `task_scope(task, $(var owner) { ... })` | Перемещает владельца в защищённую область; закрывает и при panic внешнего кода |
| `task_after_polls(n, value)` | Тестовый источник: n состояний Pending, затем результат |
| `task_from_async(source)` | Перемещает стандартный async-итератор, ожидает завершения, возвращает последний res или CeUnit для void |
| `task_from_async(source, closeLambda)` | Также владеет close callback; вызывает его ровно один раз после закрытия источника |

Bind **перемещает дочернюю задачу** в родительскую. Не используйте исходную переменную
после передачи. Отмена родителя отменяет и закрывает ожидаемого ребёнка.
Для прямого владельца используйте inscope при обычном выходе и task_scope,
если driving-код может бросить исключение: native inscope не защищает все такие
пути в используемом runtime. При передаче владения не удаляйте вручную его поля.
Повторный вход в poll/cancel исполняемой задачи запрещён. API однопоточный.

## Error, исключение и отмена

Result.error — обычный результат **успешно завершённой** TaskResult: статус
Succeeded, task_value возвращает error. Native panic означает Failed,
его сообщение хранится отдельно в task_error; он не преобразуется в Result.error.
Явная отмена имеет статус Cancelled. Ожидание отменённого ребёнка передаёт
Cancelled родителю через вложенные bind, без перехвата в try_with.
Общий CancellationToken и групповой запрос: [TASK_CANCELLATION.md](TASK_CANCELLATION.md).

При return, Error, отмене и исключении закрываются вложенные источники,
use_resource и try_finally. TryWith позволяет восстановиться после native panic.
Освобождающие функции должны быть небросающими. Если close внешнего адаптера всё же
бросил исключение, его lambda освобождаются, а задача получает Failed.

Поддержаны последовательные bind, bind без переменной, if/else, for/while,
ранний return, use_resource, try_finally и try_with. Break/continue внутри Task CE,
and_bind, return_from, неявный Zero для Task<Unit>, move-only payload и deferred
для самих Task пока не поддержаны. Завершение цикла без return не равно успешному Unit.
Публичный scheduler и таймауты по now_ms доступны в [TASK_SCHEDULER.md](TASK_SCHEDULER.md).
WhenAll для массива и shared await нескольких владельцев пока не реализованы.

## Внешние операции

`task_from_poll(pollLambda, closeLambda)` перемещает обе lambda в задачу.
Poll callback возвращает `task_pending(type<T>)` либо `task_ready(value)`.
Он должен быстро проверить готовность уже зарегистрированной операции и вернуть
управление, не выполнять блокирующий запрос. Close вызывается ровно один раз,
в том числе при отмене до первого poll. Он освобождает handle и снимает регистрацию
или отменяет ещё не завершившуюся операцию. Удаление capture lambda — часть cleanup.

Callback может владеть heap handle через capture и close, но за время жизни
borrowed-указателей отвечает адаптер. Callback не должен обращаться к уничтоженному
стеку. Нельзя вызывать API этих задач из другого потока: завершение нужно доставлять
в поток владельца через механизм хоста.

Этот модуль не создаёт потоки и не реализует HTTP/socket transport. Он позволяет
приостановить продолжение и принять готовность от внешнего API. На следующем шаге
можно подключить реальный неблокирующий транспорт через task_from_poll.
`task_after_polls` — модель ожидания для детерминированных примеров, не сетевой запрос
и не ожидание заданного числа секунд.

Примеры: [task_demo.das](examples/task_demo.das),
[task_external_demo.das](examples/task_external_demo.das).
Проверки: test_task, test_task_result, test_task_control, test_task_lifetime,
отрицательные test_task_and_bind и test_task_pointer — через run_computation.ps1 -Test.

## Стандартные [async]-функции

```das
require daslib/async_boost

[async]
def read_health() : variant<ok:int;error:string> {
    await_next_frame()
    yield result_ok(85)
}

// Внутри main или другой обычной функции:
var inscope task <- computation(TaskResultBuilder(type<int>)) {
    let health = task_from_async(read_health()) |> bind
    return health + 10
}
```

Адаптер поддерживает `iterator<variant<res:T;wait:bool>>` и void-вариант
`iterator<bool>`. Он не требует изменений async_boost и не запускает поток.
Требования к payload те же, что у Task: копируемые данные без borrowed-указателей.
Для TaskResultBuilder async-функция выдаёт Result<T>, для TaskBuilder — обычный T.
Void даёт Task<CeUnit>; напрямую ожидается в TaskBuilder через bind без переменной.

Контракт: ожидать **полного завершения**, сохранить **последний res**. Код после
yield res выполняется; исключение после уже выданного результата даёт Failed.
Несколько res в одном синхронном участке не добавляют Pending. Каждый wait, даже
после res, даёт отдельный Pending. Конечный Result.error проверяется TaskResultBuilder
после завершения источника и пропускает продолжение CE. Это не немедленная остановка
самого источника при первом промежуточном error. Типизированный источник без единого
res даёт Failed с сообщением `task_from_async: async completed without a result`.
Void без ожиданий завершается сразу с CeUnit.

От стандартного await отличается число приостановок: async_boost 0.6.4 также
вставляет ожидание после res, адаптер — только для настоящих wait-событий.
Если сама async-функция использует await, вставленные им wait остаются частью
её событий и сохраняются. Мы не удаляем их и не изменяем стандартный макрос.

Переданный iterator перемещается в адаптер сразу; исходную переменную после этого
использовать нельзя. Само выражение source вычисляется при создании адаптера,
тело cold async-итератора начинается при poll. Адаптер закрывает источник до
передачи результата продолжению, а также при исключении и отмене, включая отмену
до первого poll. Close callback выполняется после закрытия источника, затем его
lambda освобождается. При бросающем close явный poll/cancel получает Failed, повторного close нет. При raw delete/inscope callback освобождается без выброса из финализатора; подробности в TASK_COMPOSITION.md.
Обычный delete/inscope владельца также закрывает источник.

### Ограничение SDK 0.6.4

В проверенном Windows bundle стандартная [async]-функция с локальным
`var inscope` может освободить его при первом await_next_frame, а при следующем
возобновлении выдать `invalid label index`. Воспроизведение без нашей библиотеки:
[repro_async_inscope.das](tests/repro/repro_async_inscope.das). Это известный сбой,
а не проходящий тест; в обычные run_computation/run_modes он не включён.
Адаптер не исправляет код, уже некорректно раскрытый стандартным макросом.

Для ресурса, который должен пережить ожидание, используйте CE use_resource вокруг
bind либо перегрузку с close callback. Во втором случае handle размещается
в устойчивой heap-области, стандартная async-функция заимствует его, а callback
освобождает. Он вызывается даже для не начавшей выполнение операции. Для владения
родительским Task при panic внешнего driving-кода сохраняется task_scope.
Не захватывайте в callback адрес локальной переменной стека.

Примеры: [task_async_demo.das](examples/task_async_demo.das),
[task_async_resources_demo.das](examples/task_async_resources_demo.das).
Тесты порядка, вложенного native await, Error/исключений, отмены, порядка cleanup,
32 повторений со стабильным heap: test_task_from_async и test_task_from_async_lifetime.

## Общий протокол

`ce_protocol(builder)` возвращает `ce_resumable_protocol(type<Event>)`.
Общий lowering преобразует bind/return в события генератора, затем использует
существующую защиту Sequence для обхода источников и ресурсных областей.
Конкретные имена TaskBuilder/TaskResultBuilder ядро computation_macro не проверяет.
Builder определяет `ce_await_source`, `ce_await_pending`, `ce_await_value`,
`ce_await_failed`, `ce_await_failure`, `ce_await_return` и `ce_sequence_run`.
Await-source — владеющий iterator событий с полем ready; Pending не запускает
продолжение. Terminal-событие закрывает весь корневой iterator до следующего resume.

Новые Task-сценарии включены в полный набор интерпретатора. Восемнадцать положительных
Task-файлов включены в отдельные JIT/AOT проверки run_modes.ps1:
всего там двадцать два файла. Это конечный набор сценариев, не доказательство для любых
сочетаний типов и исключений. Генерация AOT не подтверждает исполнение AOT-хоста.

Типизированный планировщик с лимитом опросов, круговым обходом, ID, отменой и историей: [TASK_SCHEDULER.md](TASK_SCHEDULER.md).

Ожидание времени task_delay_ms через часы scheduler и Unit bind в TaskResultBuilder: [TASK_DELAY.md](TASK_DELAY.md).
