# and_bind для Task

```das
options gen2
require ./lib/computation_macro.das
require ./lib/task_combinators.das

// Внутри функции:
var inscope task <- computation(TaskBuilder(type<int>)) {
    let pair=task_after_polls(1,10) |> and_bind(task_after_polls(2,20)) |> bind
    return pair.first+pair.second
}
verify(task_poll(task)==TaskStatus.Waiting)
verify(task_poll(task)==TaskStatus.Waiting)
verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==30)
```

Группа раскрывается через общий `ce_merge_sources(builder,left,right)`.
TaskBuilder использует `task_when_all(left,right)`, TaskResultBuilder —
`task_result_when_all(left,right)`. Отдельный resumable builder может определить
свою перегрузку без изменения макроса; пример есть в `test_task_and_bind.das`.
Подключите `task_combinators.das` либо публично импортирующий его
`task_scheduler.das`: один `task_builder.das` не включает операции композиции.

## Порядок

Тело CE холодное. При достижении группы выражения источников вычисляются
слева направо ровно один раз, до опроса детей. Возвращённые владельцы
перемещаются в общую задачу; исходными переменными больше не пользуются.
Один владелец нельзя передавать в несколько позиций: источники потребляются
последовательно; для каждого нужен свой экземпляр Task.

При каждом опросе группы каждый незавершённый ребёнок опрашивается не более
одного раза: сначала левый, затем правый. Ожидания перекрываются кооперативно,
потоки не создаются. Пара `.first/.second` сохраняет порядок источников,
даже если правый завершился раньше. Продолжение выполняется только после
успеха обоих. Завершившиеся дети повторно не опрашиваются.

`a |> and_bind(b) |> and_bind(c) |> bind` даёт
`pair.first.first`, `pair.first.second`, `pair.second`.
Правая вложенная группа также поддержана. Допустим bind без переменной.

## Ошибки, отмена и владение

- TaskBuilder принимает обычные Task с копируемыми владеющими payload разных
  типов. `Result.error` внутри них остаётся данными.
- TaskResultBuilder объединяет Task с `Result<A>` и `Result<B>`.
  Первый замеченный Error завершает группу доменной ошибкой; итоговый статус
  Succeeded, продолжение пропускается. При одновременной готовности приоритет
  у левого источника; если левый ещё ожидает, может победить ошибка правого.
- Native panic даёт Failed. Отменённый ребёнок либо запрос CancellationToken
  даёт Cancelled всей группе. Отмена не перехватывается через `try_with`.
  Недостигнутые опросы в этом проходе пропускаются.
- Все оставшиеся дети закрываются при ошибке, отмене, таймауте или удалении
  родителя. Источники, уже созданные до исключения следующей фабрики,
  также освобождаются, включая промежуточные вложенные группы.
- Ошибки close-callback не препятствуют закрытию других детей. Исходный
  native panic сохраняется; иначе первая ошибка cleanup переводит родителя
  в Failed, в том числе вместо доменного Error или Cancelled.

Для TaskResult смешивание `Task<Unit>` и `Task<Result<T>>` в одной группе
не поддержано; Unit-операцию можно ожидать отдельным bind. Owning array Task
от `task_when_all(array)` также ожидается отдельным заимствующим bind:
`var values & = task_when_all(jobs) |> bind`. Shared-await одного владельца,
move-only payload пары и Bind2/Bind2Return оптимизации Task не добавлены.
Произвольные пользовательские финализаторы должны оставаться небросающими.

Для локальных источников внутри тела CE используйте `var left <- make_task()`
и затем передавайте их в bind/and_bind. Не добавляйте `inscope` этим локальным
Task в SDK 0.6.4: перенос такого native generator-local может привести к ошибке
`calling first on already open iterator`. Владелец группы освобождает переданные
источники. Внешний итоговый Task по-прежнему объявляется `var inscope task <- ...`.

Пример: [task_and_bind_demo.das](examples/task_and_bind_demo.das).
Проверки: [test_task_and_bind.das](tests/test_task_and_bind.das),
[test_task_and_bind_lifetime.das](tests/test_task_and_bind_lifetime.das).
Последний проверяет порядок освобождения, ошибки фабрик/poll/close,
Cancelled через try_with, токен, таймаут, raw delete и отсутствие роста heap
на повторных прогонах. Эти два теста включены отдельно в JIT и AOT-generation;
генерация C++ не подтверждает исполнение AOT.
