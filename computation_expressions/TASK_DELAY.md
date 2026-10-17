# Ожидание времени: task_delay_ms

`task_delay_ms(duration_ms)` возвращает холодную Task<CeUnit>, использующую
только now_ms текущего task_tick. Она не блокирует поток и не читает системные часы.
Подключение: `require ./lib/task_scheduler.das` (включает task_delay.das).

```das
def cooldown() {
    return <- computation(TaskBuilder(type<int>)) {
        task_delay_ms(30) |> bind
        return 7
    }
}
// В main:
var inscope scheduler <- task_scheduler(type<int>)
let id=task_spawn(scheduler,cooldown())
verify(task_tick(scheduler,1000)==1)
verify(task_tick(scheduler,1029)==1)
verify(task_tick(scheduler,1030)==0 && task_value(scheduler,id)==7)
```

Полный [игровой пример](examples/task_delay_demo.das) удерживает данные во время
ожидания и показывает успешное завершение, CancellationToken и TaskTimeout.

## Семантика времени

- Длительность — неотрицательный int или int64 в миллисекундах.
- Отсчёт начинается при **первом опросе самой задержки**, когда bind дошёл до неё.
  Создание Task и spawn не запускают таймер задержки.
- Завершение происходит при now_ms >= start_ms + duration_ms на очередном опросе.
  При duration_ms=0 продолжение может выполниться в том же tick, без дополнительного кадра.
- Равные отметки времени не продвигают положительную задержку. Скачок часов
  разрешает её завершение при следующем опросе, без подсчёта пропущенных кадров.
- Повторные задержки начинаются каждая от своего текущего now_ms. Неиспользованный
  интервал предыдущего ожидания не переносится: delay(10), завершённый при 1000,
  затем ещё delay(10) даёт следующий срок 1010.
- Сложение выполняется в uint64. Срок за пределами допустимого int64 now_ms
  не переполняется в прошлое; он недостижим в разрешённом диапазоне часов.

TaskDelay использует бюджет и круговой обход scheduler. До срока она остаётся
обычной активной Task: планировщик опрашивает корневую задачу, задержка проверяет
время и возвращает Pending, не выполняя продолжение CE. Поэтому достигнутый срок
не гарантирует продолжение именно в этом tick, если очередь до задачи ещё не дошла.
Отдельной очереди припаркованных задержек и автоматического пробуждения нет.
TaskTimeout по-прежнему обрабатывается до poll независимо от бюджета.

Цепочка нулевых задержек может выполнить много синхронной работы в одном poll;
это не способ принудительно уступить следующий кадр. Лимит опросов не является
лимитом времени исполнения пользовательского кода.

## TaskResult и композиция

Обычный пайповый bind работает и в TaskResultBuilder:

```das
var source <- computation(TaskResultBuilder(type<int>)) {
    task_delay_ms(10) |> bind
    let n=task_after_polls(0,result_ok(6)) |> bind
    return n+1
}
```

TaskResult теперь принимает Task<CeUnit> как операцию без доменного Error.
Native failure и Cancelled по-прежнему передаются через bind. Для прочих значений
нужна Task<Result<T>>, автоматического преобразования любого Task<T> нет.
Delay можно передавать в task_when_all и другие обычные Task-комбинаторы;
вложенные задачи используют тот же now_ms текущего tick.

## Отмена и ресурсы

В течение ожидания ресурсы use_resource/try_finally остаются у CE. Ручная отмена,
наблюдённый CancellationToken, TaskTimeout, закрытие/удаление scheduler и
task_scheduler_scope при panic хоста закрывают задержку и освобождают ресурсы.
Продолжение после bind не выполняется. TaskResult также получает Cancelled,
а не Result.error. Порядок и приоритет cleanup-ошибок остаются прежними.

```das
var inscope group <- cancellation_token()
let id=task_spawn(scheduler,task_with_cancellation(cooldown(),group))
let active=task_tick(scheduler,2000)
cancellation_cancel(group)
let remaining=task_tick(scheduler,2001)
verify(task_status(scheduler,id)==TaskStatus.Cancelled)
```

Токен замечается в очередь опроса; при маленьком бюджете отмена может потребовать
нескольких tick. При совпадении срока TaskTimeout и готовности задержки сначала
срабатывает TaskTimeout. Задержку можно отменить или удалить и вне tick: для
cleanup часы не требуются.

## Часы и ограничения

`require ./lib/task_delay.das` позволяет создавать задержки отдельно, но опрос
требует активного task_tick. Обычный task_poll вне этого вызова переводит delay
в Failed с сообщением `task_delay_ms: polling requires task_tick scheduler clock`,
включая нулевую задержку. Отрицательная длительность вызывает panic при создании;
в теле CE он становится Failed и закрывает уже открытые ресурсы.

Текущий tick предоставляет снимок owner/now_ms на весь синхронный вызов, включая
опрос вложенных Task и cleanup таймаутов. Вложенный tick другого scheduler временно
использует свои часы и восстанавливает внешние после возврата или ошибки.
Контекст часов не сохраняется через yield и не содержит указателей на scheduler.

Уже начатая задержка привязывается к ID владельца scheduler. Перемещение самого
scheduler сохраняет этот ID и ожидание. Опрос начатой delay под другим scheduler
даёт Failed с сообщением `task_delay_ms: scheduler changed while waiting`:
так нельзя незаметно смешать разные временные базы. После выхода из tick часы
не остаются доступными для произвольных последующих task_poll.
Внутренние ce_task_clock_scope/TaskClockSample не являются пользовательским API.
Все обращения остаются однопоточными и внутри одного daScript context.

Ожидание добавляет генератор Task<Unit>; на каждом tick есть постоянные расходы
на установку/восстановление снимка часов. Приватный массив снимков сохраняет
максимальную достигнутую ёмкость вложенных tick до удаления context. После
прогрева повторения не увеличивают память.

Проверки: [test_task_delay.das](tests/test_task_delay.das) — границы, ноль,
скачки времени, повторные интервалы, бюджет, TaskResult, композиция, вложенные
часы и перенос; [test_task_delay_lifetime.das](tests/test_task_delay_lifetime.das) —
отмена, timeout, token, break, исключения, finally и 32 повторения со стабильным heap.
