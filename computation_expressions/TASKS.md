# TaskBuilder и TaskResultBuilder

Полный текущий контракт и новые возможности: [TASK_COMPLETION.md](TASK_COMPLETION.md).
Совместное ожидание: [TASK_COMPOSITION.md](TASK_COMPOSITION.md),
[TASK_ARRAY.md](TASK_ARRAY.md), [TASK_AND_BIND.md](TASK_AND_BIND.md).

```das
options gen2
require ./lib/computation_macro.das
require ./lib/task_scheduler.das

var inscope task <- computation(TaskResultBuilder(type<string>)) {
    let player=task_after_polls(1,result_ok("Alice"))
        |> and_bind(task_after_polls(2,result_ok(85))) |> bind
    return "{player.first}: {player.second}"
}
```

Пайп на отдельной строке требует скобок у всего выражения; в запускаемых примерах
группа записана одной строкой. Тело Task холодное и однократное. Продвигайте его
через task_poll либо task_tick scheduler. Готовое значение кешируется.

TaskBuilder ожидает Task<U>. TaskResultBuilder ожидает Task<Result<U>> либо
Task<CeUnit>; обычный return автоматически создаёт ok, Error пропускает
продолжение. `return child() |> return_from` передаёт результат и состояние child.
Для Task<Unit> окончание тела и `return` — успешный Zero; для других T отсутствие
return даёт Failed. Поддержаны циклы, zip, break/continue, ресурсы, try_with,
and_bind через общий ce_merge_sources и Source. Детали: TASK_COMPLETION.md.

## Владение и исполнение

Task — move-only владелец iterator. Результат может быть копируемым либо
move-only и должен владеть данными: array/table и владеющие структуры допустимы,
вложенные pointers, references, native handles, executable captures и iterator
не допускаются. Для move-only используйте `var value & = child() |> bind` и
`return <- value`. task_value возвращает копию/deep clone; task_take переносит
результат и потребляет владельца. Примеры: task_extended_demo и test_task_owned.

Один poll исполняет синхронные шаги до Pending или конечного результата.
Результат, эффекты и освобождение завершённой задачи не повторяются. Блокирующий
код внутри poll блокирует и вызывающий поток. Других потоков модуль не создаёт.
Ссылки на стек не становятся безопасными из-за создания Task; для повторных
запусков с данными используйте deferred, который владеет снимком каждого запуска.

| API | Назначение |
|---|---|
| task_poll / task_status | Продвинуть / прочитать Created, Waiting, Succeeded, Failed, Cancelled |
| task_value / task_take | Скопировать либо перенести успешный результат |
| task_error | Native error при Failed |
| task_cancel / task_scope | Закрыть / защищённо владеть задачей в driving-коде |
| task_from_poll(poll,close) | Неблокирующий внешний адаптер, close вызывается ровно один раз |
| task_after_polls / task_after_polls_move | Детерминированные источники ожидания, второй переносит payload |
| task_from_async(source[,close]) | Ожидать стандартный [async] до полного завершения |
| task_share / task_shared_clone / task_from_shared | Один производитель, кеш и несколько ожидателей |
| task_when_all / task_result_when_all / task_race / task_result_race | Совместное ожидание и гонки |
| task_delay_ms | Ожидание по now_ms scheduler |
| task_tcp_request_line | Реальное получение строки по TCP |

TaskResult.error имеет статус Succeeded и не является исключением.
Native panic даёт Failed, отмена — Cancelled и не перехватывается через try_with.
Ресурсы закрываются при успехе, Error, отмене, таймауте и исключении. Бросающие
close-callback освобождаются и сообщают ошибку через Task; пользовательские
финализаторы должны оставаться небросающими. Исходная native-ошибка имеет приоритет.

## Стандартный async_boost

Ближайший стандартный аналог — [async_boost](https://daslang.io/doc/stdlib/generated/async_boost.html).
Task использует ту же базовую возможность генераторов; добавляет CE-протокол,
кешируемый типизированный результат, явные статусы, групповую отмену и владение.
task_from_async принимает iterator<res:T/wait:bool> и void iterator<bool>.
Он ждёт полного завершения, возвращает последний res либо CeUnit; промежуточный
res не завершает Task, код и ошибки после него сохраняются. Поддержан move-only res.
Для внешнего cleanup есть overload с close lambda.

В исходном стандартном [async] SDK 0.6.4 и 0.6.5-RC2 inscope-локальные ресурсы могут
освободиться на await/yield: Task-адаптер не исправляет его сгенерированное тело.
Там используйте явное внешнее владение/close callback. Внутри нашего Task CE
move/clone/inscope-локальные владельцы преобразуются в защищённые области,
поэтому прежнее ограничение локальных Task с inscope устранено.

## Scheduler и проверки

[TASK_SCHEDULER.md](TASK_SCHEDULER.md): настраиваемый бюджет, now_ms, ID, timeout.
[TASK_CANCELLATION.md](TASK_CANCELLATION.md): token и Cancelled через вложенные bind.
[TASK_DELAY.md](TASK_DELAY.md): task_delay_ms. [TASK_TCP.md](TASK_TCP.md): сетевой тест.
[AOT_RUNTIME.md](AOT_RUNTIME.md): сборка и настоящее исполнение AOT-хоста.

Полная регрессия: run_computation.ps1 -Test. В mode_tests.json — 44 файла,
включая 27 положительных Task-тестов и восемь AsyncSequence; JIT и генерация AOT проверяются отдельно.
run_aot.ps1 собирает и исполняет эти 39 тестов со строгой AOT-линковкой.
Сетевой fixture отдельно проверяется в interpreter и JIT.
