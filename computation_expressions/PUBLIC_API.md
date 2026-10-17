# Публичный API computation expressions

Требуется Daslang 0.6.4 со стандартной daslib. SDK не включён в экспорт.

В поставке `lib/` содержит только библиотечные модули. Из корня приложения:

```das
options gen2
require ./lib/computation.das
```

Дополнительные подключения: `./lib/reader_builder.das`, `./lib/reader_result_builder.das`,
`./lib/validation_builder.das`, `./lib/state_writer_result_builder.das`,
`./lib/deferred_computation.das`, `./lib/coroutine_builder.das`, `./lib/coroutine_scheduler.das`.
Типизированные задачи: `./lib/task_builder.das`, см. [TASKS.md](TASKS.md).
Вложенные файлы приложения используют соответствующий относительный путь
с расширением `.das`, например `require ../lib/computation.das`.

## Builders и результаты

| Builder | Результат |
|---|---|
| ResultBuilder / OptionBuilder | variant ok/error / some/none |
| MoveResultBuilder / MoveOptionBuilder | Те же варианты с передаваемым владением |
| StateBuilder(initial) | `(value, state)` |
| WriterBuilder | `(value, log)` |
| StateResultBuilder(initial) | `(result, state)`, откат state при Error |
| WriterResultBuilder | `(result, log)`, журнал сохраняется при Error |
| StateWriterResultBuilder(initial) | `(result, state, log)`, откат state и сохранение журнала при Error |
| ReaderBuilder(environment) / ReaderResultBuilder(environment) | `(value)` / Result |
| ValidationBuilder | valid/invalid с накоплением ошибок в and_bind |
| ListBuilder(type<T>) | Владеющий array<T> |
| SequenceBuilder(type<T>) | Ленивый iterator, для move-only элементов — owning slot |
| CoroutineBuilder | Ленивый iterator<CoroutineFrame> |
| TaskBuilder(type<T>) | Однократная задача с результатом T, запуск через task_poll |
| TaskResultBuilder(type<T>) | Задача с Result<T>, Error пропускает продолжение |

ListBuilder()/SequenceBuilder() выбирают int. Обычные Value CE выполняются
немедленно; Sequence/Coroutine — при обходе/возобновлении. State/Reader и обычные
Result/Option используют копируемые данные. Для move-only нужны owning builders
или соответствующий List/Sequence. По умолчанию нет сетевого async или потоков.
Task поддерживает неблокирующее ожидание через callback-адаптер; сетевой транспорт
и потоки сам модуль не предоставляет. API: task_poll, task_status, task_value,
task_error, task_cancel, task_scope, task_from_poll, task_after_polls.

## Прикладные операции

`T`, `S`, `E` ниже — обозначения типов, а не буквальные объявления daScript.

| Операция | Назначение |
|---|---|
| `result_ok(value)`, `result_error(message, type<T>)` | Успех / прикладная ошибка |
| `some(value)`, `none(type<T>)` | Наличие / отсутствие |
| `move_ok(value)`, `move_some(value)` | Потребляют value перемещением |
| `move_error(message, type<T>)`, `move_none(type<T>)` | Неуспешные owning-результаты |
| `state_get()`, `state_put(state)` | Описания чтения / замены состояния, выполняемые через bind |
| `state_modify($(state:S) {return nextState})` | Преобразовать состояние, завершается bind |
| `state_gets($(state:S) {return projection})` | Прочитать часть состояния, завершается bind |
| `state_result(value, state)` | Готовый результат обычного State |
| `state_result_ok(value,state)`, `state_result_error(message,type<T>,state)`, `state_result_value(result,state)` | Готовые StateResult |
| `writer_value(value, log="")`, `tell(message)` | Значение с журналом / запись Unit в журнал |
| `writer_result_ok(value,log="")`, `writer_result_error(message,type<T>,log="")`, `writer_result(result,log="")` | Готовые WriterResult |
| `state_writer_result_ok(value,state,log="")`, `state_writer_result_error(message,type<T>,state,log="")`, `state_writer_result_value(result,state,log="")` | Готовые StateWriterResult |
| `reader_ask()`, `reader_value(value)` | Окружение / готовый результат Reader |
| `validation_ok(value)`, `validation_error(message,type<T>)`, `left |> validation_zip(right)` | Проверки и объединение независимых ошибок |
| `deferred(builder,data) $(snapshot) {...}`, `deferred(builder) {...}` | Владеющий снимок для повторных запусков |
| `run_deferred(task)` | Новый запуск; task передаётся изменяемым владельцем |
| `sequence_each(source, action)` | Защищённый обход и закрытие источника, включая исключение action |
| `sequence_each_move(source, action)` | Защищённый обход owning-элементов по ссылке |
| `sequence_next_move(source, value)` | Получить следующий элемент перемещением, возвращает bool |
| `sequence_close(source)` | Явное закрытие итератора |
| `next_frame()`, `wait_frames(count)` | События ожидания Coroutine, выдаются через yield |
| `coroutine_resume(task)`, `coroutine_cancel(task)` | Продолжить / закрыть сценарий |

Владельцы результата обычно принимаются через `var inscope result <- ...`.
Consuming bind записывается `var item & = source |> bind`, передача наружу —
`return <- item` / `yield <- item`. Нельзя сохранять заимствованную ссылку на
слот дольше его владельца. Снимки deferred не принимают произвольные указатели,
handles и stack blocks; каждый run клонирует рабочие данные.

## Scheduler

`CoroutineScheduler` и `CoroutineTaskId` предоставляют:

- `coroutine_spawn(scheduler, source)` — передать сценарий, получить ID;
- `coroutine_tick(scheduler)` — обновить активные задачи;
- `coroutine_status`, `coroutine_error`, `coroutine_valid` — запрос состояния ID;
- `coroutine_cancel(scheduler,id)` — отменить задачу;
- `coroutine_forget`, `coroutine_prune` — удалить завершённые записи;
- `coroutine_task_count`, `coroutine_slot_count` — число задач / слотов;
- `coroutine_close(scheduler)` — закрыть все задачи;
- `coroutine_scope($(var scheduler:CoroutineScheduler) {...})` — защищённая область scheduler.

## CE-маркеры и расширение

`source |> bind`, `left |> and_bind(right) |> bind`, `return value`,
`return source |> return_from`, `yield value`, `source |> yield_from`,
`resource |> use_resource`, `try_finally(body,cleanup)`, `try_with(body,handler)`
раскрываются макросом. Поддержка зависит от builder. and_bind eager и не запускает
потоки; Error/None не являются исключениями. StateResult откатывает только поле
state, не внешние эффекты или объекты по указателям.

`identity_builder.das` и `main.das` в экспортированном примере показывают
минимальный CeValueProtocol с ce_bind/ce_unwrap/ce_return/ce_zero/ce_combine.
Новые правила определяются перегрузками ce_* рядом с builder, без регистрации.
Для and_bind нужна ce_merge_sources, для циклов — соответствующие операции
протокола. Внутренние курсоры, slots и устройство снимков не являются API.
