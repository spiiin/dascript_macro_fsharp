# WhenAll для массива

```das
var jobs:array<typedecl(task_after_polls(0,0))>
jobs |> emplace(task_after_polls(2,10))
jobs |> emplace(task_after_polls(0,20))
var inscope parent <- computation(TaskBuilder(type<int>)) {
    var values & = task_when_all(jobs) |> bind
    return values[0]+values[1]
}
```

При захвате готового move-only jobs в CE действуют правила capture языка;
обычно удобнее вызвать фабрику массива прямо внутри bind, как в task_array_demo.
task_when_all(jobs) потребляет массив и детей. Task<array<T>> теперь использует
обычное представление Task, без отдельного TaskArrayTag/control и заимствования
буфера из другого владельца. T может быть копируемым или move-only.

Один poll посещает активных детей по индексам, не более одного раза каждого.
Завершённые повторно не исполняются. Результаты сохраняют порядок входа независимо
от порядка готовности. Пустой массив успешно возвращает пустой результат при
первом poll. Кеш уже успешного ребёнка также сохраняется. Передача ребёнка,
который сейчас исполняет poll, отклоняется до перемещения массива.

task_value(parent) возвращает независимый deep clone, который может пережить
parent и запись scheduler. task_take(parent) переносит массив без копирования
и потребляет задачу. При await используйте `var values & = ... |> bind`:
продолжение может приостановиться ещё раз, владелец значения останется жив.

Result.error в обычном task_when_all — данные. Для fail-fast:

```das
var inscope task <- task_result_when_all(make_result_tasks())
// Task<Result<array<T>>>; первый наблюдённый Error отменяет остальных.
```

TaskResultBuilder разворачивает этот Result через bind. При одновременной
готовности приоритет у меньшего индекса. Task<Unit> в Result-combinators
нормализуется к успешному Result<Unit>. Shared handles тоже можно объединять;
каждый ожидатель получает свою копию результата, общий кеш не потребляется.

Native failure, отмена ребёнка/родителя и timeout закрывают оставшихся детей.
При ошибке освобождаются частично накопленные значения; ошибка close не мешает
освободить другие источники. Приоритет ошибок соответствует TASK_COMPOSITION.md.
Все виды результата должны владеть данными, включая вложенные array/table.

Проверки: test_task_array, test_task_array_lifetime, test_task_owned;
пример: [task_array_demo.das](examples/task_array_demo.das).
