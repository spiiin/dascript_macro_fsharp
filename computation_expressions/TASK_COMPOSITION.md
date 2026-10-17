# Совместное ожидание Task и гонка

```das
require ./lib/computation_macro.das
require ./lib/task_combinators.das

var inscope task <- computation(TaskBuilder(type<string>)) {
    let pair = task_when_all(
        task_after_polls(1, "Alice"),
        task_after_polls(2, 85)) |> bind
    return "{pair.first}: health={pair.second}"
}
```

Функции работают с двумя move-only владельцами Task и перемещают их в возвращаемую
задачу. Имена first/second сохраняют порядок аргументов. Типы результатов могут
различаться у when_all; payload по-прежнему должен быть копируемым и владеть данными.
Повторная передача одного владельца в обе позиции отклоняется до перемещения.
После успешной передачи исходные переменные больше не используются.

| Операция | Результат | Завершение |
|---|---|---|
| task_when_all(left, right) | Task<(first:T, second:U)> | После успеха обоих детей |
| task_result_when_all(left, right) | Task<Result<(first:T, second:U)>> | После двух ok либо первого замеченного Error |
| task_race(left, right) | Task<(index:int, value:T)> | По первому замеченному терминальному состоянию; результаты одного типа |

Это кооперативное совместное ожидание в одном потоке. Один poll родителя делает
не более одного poll каждого активного ребёнка, слева направо. Уже завершённый
ребёнок не исполняется повторно. Тело не запускается при создании объединённого
Task; выражения аргументов выполняются обычным порядком daScript при его создании.
Таким образом, адаптеры могут уже владеть зарегистрированными внешними ресурсами.

## Ошибки, результат и отмена

When_all сохраняет оба значения. Обычный Result.error для него является значением:
для короткого замыкания используйте task_result_when_all. В TaskResultBuilder:

```das
var inscope task <- computation(TaskResultBuilder(type<int>)) {
    let pair = task_result_when_all(
        task_after_polls(1, result_ok(10)),
        task_after_polls(2, result_ok(20))) |> bind
    return pair.first + pair.second
}
```

Первый замеченный Error отменяет оставшегося ребёнка. Возвращённый Task имеет
Succeeded с Result.error; продолжение TaskResultBuilder не выполняется. Если левый
ребёнок выдаёт Error сразу, правый в этом poll вообще не запускается, но закрывается.
При двух Error в одном poll приоритет у левого. Это семантика fail-fast, не Validation.

Native exception у любого ребёнка даёт Failed родителя; оставшиеся владельцы
отменяются. Наблюдённый Cancelled ребёнка передаётся родителю, как последовательный
Task bind. Явная отмена родителя даёт Cancelled при успешном cleanup.

## Гонка

```das
var inscope race <- task_race(
    task_after_polls(3, "slow"),
    task_after_polls(1, "fast"))
// После Succeeded: let winner=task_value(race) // index=1, value="fast"
```

Первый терминальный результат выигрывает. Ошибка или отменённый ребёнок тоже
терминальны: Failed/Cancelled передаются гонке, она не ищет следующий успешный результат.
Если левый ребёнок готов, правый в этом poll не опрашивается. Одновременная
готовность поэтому даёт index=0. Это порядок наблюдения, а не сравнение реального
времени завершения внешних операций. Проигравший закрывается до возврата из poll.
Result внутри значения race автоматически не разворачивается; специального
task_result_race в этой версии нет.

## Cleanup и время жизни

Завершение, ошибка, отмена и обычное удаление владельца освобождают обоих детей.
Незавершённые закрываются слева направо; ребёнок, уже завершившийся при poll,
мог выполнить свой cleanup раньше. Поэтому победа правого ребёнка обычно даёт
порядок cleanup «правый, левый». Ошибка cleanup одного не мешает закрыть другого.

Бросающие close-callbacks task_from_poll и task_from_async теперь перехватываются
до выхода из native generator finalizer. В SDK 0.6.4 исключение из финализатора
прерывает освобождение самой closure. Поэтому сообщения временно записываются
в стек ошибок текущего Task-вызова, а Failed устанавливается после освобождения.
При первичной native-ошибке задачи она сохраняется, дополнительные ошибки cleanup её
не заменяют. Если первичной ошибки нет, первая замеченная ошибка cleanup даёт Failed,
включая cleanup проигравшего в успешно закончившейся гонке.
Result.error является обычным результатом: ошибка cleanup в этом случае также
переводит владельца в Failed, а не возвращает доменный Error как успешный итог.

Стек приватный, однопоточный, поддерживает вложенные poll/cancel и сохраняет
буфер максимальной достигнутой глубины до удаления context. Прогретые повторения
не увеличивают его память. Это не механизм межпоточной передачи ошибок.
У raw delete/inscope владелец исчезает: callback освобождается без выброса ошибки
из финализатора. Для получения диагностики используйте task_poll/task_cancel
и task_error либо task_scope. Task_scope при обычном выходе сообщает ошибку
cleanup отмены незавершённого владельца после освобождения; при panic driving-кода сохраняет исходную ошибку.

Это относится к библиотечным close-callbacks. Произвольные native finally и
ce_dispose пользовательских ресурсов по-прежнему должны быть небросающими.
Известное ограничение inscope внутри стандартного [async] остаётся — см. [TASKS.md](TASKS.md).

Пайповый `left |> and_bind(right) |> bind` использует общий ce_merge_sources
и эти же combinators: [TASK_AND_BIND.md](TASK_AND_BIND.md). Динамический task_when_all(tasks) для массива:
[TASK_ARRAY.md](TASK_ARRAY.md). Новые потоки не добавляются.
Планировщик и таймауты по now_ms: [TASK_SCHEDULER.md](TASK_SCHEDULER.md).
Синхронный код ребёнка может блокировать poll.

Пример: [task_combinators_demo.das](examples/task_combinators_demo.das).
Тесты: test_task_combinators, test_task_combinators_lifetime,
test_task_cleanup_errors; последний защищает от утечек при бросающих close-callbacks.

Типизированный планировщик с лимитом опросов, круговым обходом, ID, отменой и историей: [TASK_SCHEDULER.md](TASK_SCHEDULER.md).
