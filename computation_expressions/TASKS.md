# TaskBuilder и TaskResultBuilder

Ближайший стандартный аналог — [daslib/async_boost](https://daslang.io/doc/stdlib/generated/async_boost.html):
аннотация [async], await и await_next_frame также раскрываются в генераторы.
Наш модуль использует ту же базовую возможность языка. Отличия — CE-протокол,
один кешируемый результат, явные статусы и отмена, общий ресурсный контракт,
TaskResult с коротким замыканием при Error и callback-адаптер внешних операций.
Для простого сценария с await достаточно стандартного async_boost. Стандартная
библиотека также имеет async_run/race/timeout; аналоги этих combinators в нашем
Task API пока не реализованы. Потоки и jobs предоставляет отдельный jobque.

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
`TaskResultBuilder(type<T>)` ожидает Task<Result<U>>: bind извлекает ok,
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
Явная отмена имеет статус Cancelled. Ожидание уже отменённого ребёнка вызывает
Failed у родителя; общего cancellation token в этой версии нет.

При return, Error, отмене и исключении закрываются вложенные источники,
use_resource и try_finally. TryWith позволяет восстановиться после native panic.
Освобождающие функции должны быть небросающими. Если close внешнего адаптера всё же
бросил исключение, его lambda освобождаются, а задача получает Failed.

Поддержаны последовательные bind, bind без переменной, if/else, for/while,
ранний return, use_resource, try_finally и try_with. Break/continue внутри Task CE,
and_bind, return_from, неявный Zero для Task<Unit>, move-only payload и deferred
для самих Task пока не поддержаны. Завершение цикла без return не равно успешному Unit.
Публичный Task scheduler, WhenAll/race, shared await нескольких владельцев,
дедлайны и автоматическое распространение отмены как отдельного статуса — следующие шаги.

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

## Общий протокол

`ce_protocol(builder)` возвращает `ce_resumable_protocol(type<Event>)`.
Общий lowering преобразует bind/return в события генератора, затем использует
существующую защиту Sequence для обхода источников и ресурсных областей.
Конкретные имена TaskBuilder/TaskResultBuilder ядро computation_macro не проверяет.
Builder определяет `ce_await_source`, `ce_await_pending`, `ce_await_value`,
`ce_await_failed`, `ce_await_failure`, `ce_await_return` и `ce_sequence_run`.
Await-source — владеющий iterator событий с полем ready; Pending не запускает
продолжение. Terminal-событие закрывает весь корневой iterator до следующего resume.

Новые Task-сценарии включены в полный набор интерпретатора. Четыре положительных
Task-файла отдельно прошли JIT и генерацию AOT и включены в run_modes.ps1:
всего там восемь файлов. Это конечный набор сценариев, не доказательство для любых
сочетаний типов и исключений. Генерация AOT не подтверждает исполнение AOT-хоста.
