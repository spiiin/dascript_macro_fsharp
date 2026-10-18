# Полный текущий набор Task

Task остаётся кооперативной cold single-shot задачей: тело начинает первый poll,
готовый результат кешируется, фоновые потоки не создаются. Для нового исполнения
нужна фабрика либо `deferred`. Ниже закрытый список расширений текущего этапа.

| Возможность | Использование |
|---|---|
| Передача результата другой задачи | `return child() |> return_from` |
| Unit/Zero | `TaskBuilder(type<CeUnit>)` / `TaskResultBuilder(type<CeUnit>)` могут завершиться без return; также доступен `return` |
| Управление циклами | `break` / `continue` в for, zip-for и while, в том числе после bind и внутри ресурсов |
| Move-only результат | `TaskBuilder(type<array<T>>)` либо владеющая структура; `return <- value` |
| Move-only bind | `var value & = child() |> bind`; источник держит значение до конца продолжения |
| Владение локальными данными | `var data <- ...`, `:=` и `var inscope data <- ...` внутри CE получают защищённую область, живущую через приостановки |
| Повторные запуски | `deferred(TaskBuilder(...),data) $(snapshot) { ... }`, затем `run_deferred(saved)` |
| Разделяемое ожидание | `task_share(source)`, `task_shared_clone(handle)`, `task_from_shared(lease)` |
| Группы Result и Unit | `task_delay_ms(5) |> and_bind(check()) |> bind` в TaskResultBuilder |
| Массивы Result | `task_result_when_all(jobs)` возвращает Task<Result<array<T>>> |
| Гонка Result | `task_result_race(left,right)` возвращает Result пары index/value |
| Вложенные owning результаты | Пары, массивы, гонки, scheduler и and_bind работают с владеющими payload |
| Source | Перегрузки `ce_source` действуют на одиночный bind, листья and_bind и источники циклов |
| Реальный TCP | [TASK_TCP.md](TASK_TCP.md) |
| Исполнение AOT | [AOT_RUNTIME.md](AOT_RUNTIME.md), `run_aot.ps1` |

## Владение результатом

```das
var inscope task <- computation(TaskBuilder(type<array<int>>)) {
    var values <- [1,2,3]
    task_after_polls(1,CeUnit()) |> bind
    return <- values
}
verify(task_poll(task)==TaskStatus.Waiting)
verify(task_poll(task)==TaskStatus.Succeeded)
var inscope values <- task_take(task)
```

`task_value` копирует обычные значения; для move-only данных возвращает независимый
deep clone, сохраняя кеш. `task_take(task)` переносит кеш и потребляет владельца.
`task_take(scheduler,id)` переносит результат и удаляет завершённую запись:
прежний ID становится недействительным. У shared-производителя кеш не изымают:
ожидатели получают независимые результаты, чтобы один потребитель не разрушил
данные другого.

Внутри CE move/clone/inscope-локальные владельцы живут в защищённых ячейках,
а не в native inscope, который SDK 0.6.4 и 0.6.5-RC2 может завершить при yield. Это устраняет
прежнее ограничение для локальных Task с inscope. Они освобождаются при return,
отмене, исключении и выходе из области. Внешние обычные daScript-функции сохраняют
свои стандартные правила: там используйте inscope или явное освобождение.

`Task<CeUnit>` успешно завершается в конце тела. Для других T отсутствие return
остаётся ошибкой; default<T> автоматически не подставляется. `return_from`
сохраняет Error, Failed и Cancelled дочерней задачи.

## Shared-await

```das
var inscope handle <- task_share(load_once())
var inscope a <- task_from_shared(task_shared_clone(handle))
var inscope b <- task_from_shared(task_shared_clone(handle))
// Оба await-источника наблюдают одного производителя и один кеш.
```

Handle — move-only lease; клонирование увеличивает счётчик ссылок. Последний
lease закрывает незавершённого производителя. `task_cancel(handle)` отменяет
его для всех. Отмена или таймаут отдельного ожидателя освобождает только его
lease: динамический токен ожидателя не передаётся общему производителю.
Производитель может иметь свой явно установленный CancellationToken.

Данные shared-задачи не вычисляются повторно. Продвижение остаётся явным:
poll вызывают ожидатели или scheduler; число poll не привязано к числу кадров.
Параллельный вызов из других потоков не поддержан. При захвате move-only lease
в обычный native generator действуют правила explicit capture/unsafe daScript;
в готовые CE передавайте отдельные lease, не перемещайте одного владельца дважды.

## Deferred и память

Каждый запуск клонирует снимок и создаёт новую задачу. Сам deferred, исходные
данные и другие запуски можно удалить; рабочий снимок живёт до закрытия source
данного Task. Это проверяется при успехе, отмене, незапущенном владельце и
для move-only результата. Исполняемые captures, стековые ссылки и уже созданные
Task в снимок не включаются: snapshot должен владеть обычными данными.

Ресурсные функции и пользовательские финализаторы должны быть небросающими.
Библиотечные close-callback могут сообщить ошибку: исходная native-ошибка
сохраняется, иначе первая ошибка cleanup даёт Failed. Error остаётся данными,
Cancelled — управляющим состоянием, а не перехватываемым текстом panic.

## Примеры и проверки

[task_extended_demo.das](examples/task_extended_demo.das) объединяет deferred,
move-only результат, shared-await, отмену одного ожидателя и scheduler.
Дополнительные тесты: test_task_extended, test_task_loops, test_task_owned,
test_task_shared, test_task_deferred. Тесты владения повторяют сценарии и
сравнивают прогретое значение heap_bytes_allocated.

Граница текущего набора: он не добавляет потоки, HTTP/TLS, распределённый executor
или автоматическое исполнение без poll/tick. Это отдельные транспортные и
планировочные решения, а не незавершённые ветки описанной семантики Task.
