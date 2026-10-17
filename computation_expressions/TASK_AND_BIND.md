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

TaskResult объединяет Result и Unit-источники; Unit автоматически считается
успешным. Owning array Task также можно включать в группы. Move-only payload
заимствуется через `var pair & = left |> and_bind(right) |> bind`, а передача
наружу записывается `return <- pair.first`. Shared-await и deferred реализованы:
[TASK_COMPLETION.md](TASK_COMPLETION.md). Bind2/Bind2Return оптимизации Task
не добавлены; используется обычная семантика совместного ожидания.

Прежнее ограничение inscope для локальных Task внутри CE устранено: их время
жизни теперь управляется защищённой областью, а не native inscope через yield.
Пользовательские финализаторы должны быть небросающими.

Пример: [task_and_bind_demo.das](examples/task_and_bind_demo.das).
Проверки: [test_task_and_bind.das](tests/test_task_and_bind.das),
[test_task_and_bind_lifetime.das](tests/test_task_and_bind_lifetime.das).
Последний проверяет порядок освобождения, ошибки фабрик/poll/close,
Cancelled через try_with, токен, таймаут, raw delete и отсутствие роста heap
на повторных прогонах. Эти два теста включены отдельно в JIT и AOT-generation;
генерация C++ не подтверждает исполнение AOT.
