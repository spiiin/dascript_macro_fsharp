# Типизированный планировщик Task

`require ./lib/task_scheduler.das` добавляет управление несколькими владельцами
Task. Планировщик однопоточный: приложение явно вызывает `task_tick` из своего
цикла. Он работает с TaskBuilder, TaskResultBuilder, task_from_async и
[комбинаторами Task](TASK_COMPOSITION.md), не меняя пайповый bind.

```das
options gen2
require ./lib/computation_macro.das
require ./lib/task_scheduler.das

def load_player() {
    return <- computation(TaskBuilder(type<int>)) {
        let health=task_after_polls(1,100) |> bind
        return health+5
    }
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>,
        TaskSchedulerConfig(max_polls_per_tick=8))
    let player=task_spawn(scheduler,load_player())
    verify(task_tick(scheduler,0)==1)
    verify(task_tick(scheduler,16)==0)
    verify(task_status(scheduler,player)==TaskStatus.Succeeded)
    verify(task_value(scheduler,player)==105)
    verify(task_forget(scheduler,player))
}
```

Полный [пример игрового цикла](examples/task_scheduler_demo.das) также ожидает
стандартную `[async]`-функцию и показывает TaskResultBuilder.

## Настройка и порядок выполнения

`task_scheduler(type<T>)` создаёт владельца с лимитом 64.
`task_scheduler(type<T>, TaskSchedulerConfig(max_polls_per_tick=N))` задаёт иной
положительный лимит. `task_configure(scheduler, config)` изменяет его между tick;
`task_scheduler_config(scheduler)` возвращает текущую настройку.

Каждый tick опрашивает не более N активных корневых Task и каждую из них не более
одного раза. Обход круговой, со следующего после последнего опрошенного слота.
Новые задачи добавляются в конец активной очереди. Отмена следующей задачи
переставляет курсор на её преемника. Неизрасходованный бюджет не переносится.
Уже завершённая задача, переданная в spawn, сразу попадает в историю.

`task_tick(scheduler, now_ms)` возвращает оставшееся число активных задач.
Время — неотрицательное монотонное int64 в миллисекундах; int также принимается,
равные отметки разрешены. Оно доступно через `task_scheduler_time` (до первого
tick — 0). Таймауты проверяются по этому времени; приоритетов и автоматического
пробуждения по часам нет.

Лимит считает вызовы task_poll верхнего уровня. Одна Task может внутри выполнить
много синхронной работы и опросить вложенные задачи. Это не ограничение времени
кадра и не вытеснение: callback должен быстро возвращать Pending или Ready.
Потоки, транспорт и общий event loop стандартного async_boost не создаются.

## Таймауты

```das
let level=task_spawn(scheduler,load_player(),TaskTimeout(after_ms=30))
// При достижении срока в следующем task_tick:
// task_status(scheduler,level)==TaskStatus.Cancelled
// task_timed_out(scheduler,level)==true
```

`after_ms` — неотрицательный int64. Без третьего аргумента таймаут отключён.
До первого успешного tick длительность отсчитывается от его now_ms; после него —
от последнего принятого now_ms на момент spawn. Поэтому хост может сначала вызвать
пустой tick с текущими часами, затем регистрировать задачи. Планировщик не читает
системное время: если между кадрами прошло время, новый spawn всё ещё использует
последнюю переданную отметку.

При `now_ms >= deadline` задача отменяется **до любого опроса этого tick**.
Все просроченные задачи закрываются независимо от max_polls_per_tick, в порядке
deadline, при равных сроках — регистрации. Затем оставшиеся активные задачи
получают обычный бюджет и круговой обход. Поэтому расходы на cleanup таймаутов
не ограничиваются бюджетом опросов.

Нулевой таймаут отменяет даже немедленно готовую, но ещё не опрошенную Task.
Spawn остаётся ленивым: сама отмена происходит в tick. Уже терминальная Task,
переданная в spawn, сохраняет результат и не получает таймер. Успешное завершение,
обычная ошибка, ручная отмена и close снимают таймер; последующий tick не меняет
причину завершения. Повторное использование слота не наследует старый таймер.

`task_timed_out(scheduler,id)` проверяет причину и доступен до forget/prune.
На обычной отмене он false. При таймауте статус — Cancelled, а ошибка close-callback
даёт Failed с диагностикой task_error и сохраняет task_timed_out=true. Флаг
устанавливается до cleanup, поэтому читающие callbacks тоже видят причину.
Это не Result.error: TaskResultBuilder также отменяется, получить task_value
отменённой задачи нельзя. Несуществующий/устаревший ID вызывает panic.
Отрицательная длительность отклоняется, переданная в spawn Task освобождается.
Суммы времени хранятся в uint64, поэтому срок за пределами int64 clock не
переполняется в уже истёкший; такой срок недостижим в разрешённом диапазоне часов.

Таймаут кооперативный: он проверяется только при следующем tick и не прерывает
выполняющийся синхронный callback. Он закрывает Task, её вложенные ожидания,
use_resource/try_finally и close-callback адаптера. Если внешняя операция требует
собственного cancel, его нужно выполнить в её close-callback.
Пайповый bind внутри CE не меняется.

[Пример](examples/task_timeout_demo.das) показывает загрузку игровых данных,
отмену ожидания и освобождение массива без выполнения продолжения.

## Владение, результаты и ошибки

`task_spawn(scheduler, source)` перемещает source, возвращает TaskId и пока не
исполняет тело. При отклонении spawn (закрытый владелец, повторный вход) переданная
задача закрывается. Задачу в процессе poll передавать нельзя: проверка происходит
до перемещения. Все Task одного scheduler имеют одинаковый T. Для TaskResult:

```das
var inscope requests <- task_scheduler(type<variant<ok:int;error:string>>)
```

Для разных T можно держать несколько scheduler. Фабрика возвращает типизированный
move-only tuple; внутренние frames, records и slot не являются API. Их нельзя
изменять или передавать содержащуюся Task обратно в spawn.

| API | Результат |
|---|---|
| `task_valid(scheduler,id)` | Проверка owner, slot, generation; false для moved-from owner |
| `task_status(scheduler,id)` | Created, Waiting, Succeeded, Failed или Cancelled |
| `task_value(scheduler,id)` | Копия T, только после Succeeded |
| `task_error(scheduler,id)` | Диагностика Failed |
| `task_timed_out(scheduler,id)` | Отменена именно по таймауту, включая ошибку её cleanup |
| `task_count(scheduler)` | Активные и сохранённые терминальные записи |
| `task_active_count(scheduler)` | Только активные записи |
| `task_slot_count(scheduler)` | Число выделенных слотов, включая свободные |
| `task_cancel(scheduler,id)` | Закрыть активную задачу; false, если уже терминальная |
| `task_forget(scheduler,id)` | Удалить терминальную запись; false для активной |
| `task_prune(scheduler)` | Удалить все терминальные записи, вернуть их количество |
| `task_scheduler_close(scheduler)` | Отменить всех активных, запретить spawn; история доступна |

Неверный/устаревший ID вызывает panic у операций, кроме task_valid.
TaskId — идентификатор, не владелец: копирование ID не продлевает жизнь записи.
Перемещение scheduler сохраняет ID; исходный владелец становится пустым.
Повторное использование слота увеличивает generation, её переполнение не допускается.
Повторный close безопасен, tick закрытого scheduler возвращает 0.

Native exception переводит отдельную задачу в Failed; другие продолжают свой tick.
Result.error — нормальное Succeeded со значением error, автоматической отмены
соседних задач нет. Ошибка close-callback переводит отменяемую Task в Failed,
остальные всё равно закрываются. Диагностику следует прочитать до forget/prune.
Ограничения бросающих native finalizers из [TASKS.md](TASKS.md) остаются в силе.

Из poll и cleanup разрешены запросы, но повторные tick/spawn/cancel/close/
configure/forget/prune того же scheduler отклоняются. Удалять или перемещать
исполняющийся scheduler из callback нельзя. Все обращения выполняются из одного
daScript context и потока; межпоточной синхронизации нет.

## Завершение и память

`var inscope scheduler <- ...` закрывает активные задачи при обычном выходе.
Для panic внешнего игрового цикла используйте consuming scope:

```das
var scheduler <- task_scheduler(type<int>)
task_scheduler_scope(scheduler, $(var owner) {
    let id=task_spawn(owner,load_player())
    let remaining=task_tick(owner,0)
    // panic здесь также закроет задачи и освободит владельца.
})
```

Scope потребляет scheduler и удаляет его и при успехе, и при panic, сохраняя
первичную ошибку хоста. После удаления владельца читать статусы уже нельзя.
При обычном неявном удалении исчезает и получатель диагностики cleanup;
для её чтения вызовите close и task_error до удаления владельца.

Результаты сохраняются до forget/prune или удаления владельца. Активная очередь
отдельна от истории: tick не сканирует завершённые записи. Prune обходит все
выделенные слоты; forget работает по ID, свободные слоты используются повторно.
Массивы сохраняют достигнутую ёмкость до удаления scheduler. Проверки прогретых
повторений контролируют отсутствие роста heap и парность открытия/закрытия:

- [test_task_scheduler.das](tests/test_task_scheduler.das): бюджет, порядок, время, Result.
- [test_task_scheduler_safety.das](tests/test_task_scheduler_safety.das): ID, перенос, ошибки и повторный вход.
- [test_task_scheduler_lifetime.das](tests/test_task_scheduler_lifetime.das): ресурсы, отмена, destructor, panic хоста, память.
- [test_task_timeouts.das](tests/test_task_timeouts.das): границы времени, бюджет, порядок, ID и переполнение.
- [test_task_timeout_lifetime.das](tests/test_task_timeout_lifetime.das): Task/TaskResult, async-адаптер, ресурсы, повторный вход и стабильный heap.

Таймеры хранятся отдельной упорядоченной очередью в слотах, без дополнительной
аллокации на каждый таймер. Регистрация таймера — O(T) в худшем случае при T
активных таймерах; одинаковые или возрастающие сроки добавляются за O(1).
Первый tick сдвигает все ранее созданные таймеры на свою временную базу за O(T).
Дальнейшие tick проверяют только голову очереди и истёкшие таймеры;
снятие отдельного таймера — O(1), без учёта выполнения cleanup.
Задачи без таймаута и терминальная история в этом обходе не участвуют.

Эти пять файлов включены в отдельные запуски интерпретатора, JIT и генерации AOT.
Генерация AOT C++ не означает проверку исполнения AOT-хоста.

Общая отмена группы через task_with_cancellation(task,token): [TASK_CANCELLATION.md](TASK_CANCELLATION.md). В отличие от таймеров, запрос наблюдается при очередном опросе каждой обёртки и подчиняется бюджету tick; до его обработки ресурс остаётся у задачи.

Ожидание заданного времени в CE: task_delay_ms(duration_ms) |> bind. Текущий now_ms доступен вложенным Task на время tick; задержки подчиняются бюджету опросов. [TASK_DELAY.md](TASK_DELAY.md).
