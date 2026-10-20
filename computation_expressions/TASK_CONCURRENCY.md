# Task: игровой runtime, каналы и параллельная работа

Подключения независимы: `lib/task_runtime.das`, `lib/task_channel.das`,
`lib/task_parallel.das`, `lib/task_jobque.das`. SDK: 0.6.5-RC2. Нового нативного
модуля нет. Старый `task_scheduler(type<T>)` и пайповый bind сохраняются.

## Один runtime для разных результатов

```dascript
var inscope runtime <- task_runtime(TaskSchedulerConfig(max_polls_per_tick=8))
var inscope health <- task_spawn(runtime,task_after_polls(1,100))
var inscope title <- task_spawn(runtime,task_after_polls(0,"ready"))
task_tick(runtime,0)
task_tick(runtime,16)
verify(task_value(health)==100 && task_value(title)=="ready")
```

`task_spawn` возвращает типизированный владеющий ticket. Сам runtime хранит
адаптеры Task<Unit> поверх прежнего планировщика: те же now_ms, таймауты,
очередь активных задач, round-robin и бюджет опросов. Бюджет ограничивает
опросы верхнего уровня; синхронный шаг задачи нельзя прервать посередине.
Typed scheduler остаётся доступен с меньшими накладными расходами.

- `task_status(ticket)`, `task_error(ticket)`, `task_value(ticket)` читают результат.
- `task_cancel(runtime,ticket)`, `task_timed_out(runtime,ticket)` и
  `task_forget(runtime,ticket)` проверяют принадлежность и поколение TaskId.
- `task_await(ticket)` возвращает Task для `|> bind`; он наблюдает runtime,
  самостоятельно не запускает и не опрашивает исходную задачу. Отмена наблюдателя
  не отменяет исходную задачу. Ошибка/отмена исходной задачи передаётся наблюдателю.
- `task_value` копирует либо клонирует результат, как shared Task.
  `task_take(ticket)` перемещает результат без клонирования и опустошает handle;
  требуется единственный оставшийся shared lease. При живых наблюдателях будет
  исключение. Это же правило действует для `task_take(sharedHandle)`.
- `task_prune(runtime)` удаляет завершённые записи; результаты остаются у tickets.
  `task_scheduler_close(runtime)` и уничтожение runtime отменяют активные задачи.
- `task_count`, `task_active_count`, `task_slot_count`, `task_configure`,
  `task_scheduler_config`, `task_scheduler_time`, `task_valid` доступны для runtime.

Результаты с разными типами не приводятся к void?/variant с ручными cast.
Владение обеспечивают существующие shared Task leases. После forget/prune
старый TaskId нельзя использовать для управления записью, даже если ticket
ещё держит результат. Завершённые tickets также нужно удалять.

## Ограниченный channel<T>

`task_channel(type<T>,capacity)` — FIFO между Task в одном потоке. Capacity
положительная; rendezvous с capacity=0 не поддерживается. Это очередь,
в отличие от broadcast-адаптера `task_wait_event`.

| Операция | Результат |
|---|---|
| `task_channel_send(channel,value)` | Task<Result<Unit,string>>, копируемый payload |
| `task_channel_send_move(channel,value)` | Та же задача, потребляет move-only payload при создании |
| `task_channel_receive(channel)` | Task<Result<Option<T>,string>>; один получатель на элемент |
| `task_channel_try_send(channel,value)` / `task_channel_try_send_move` | Немедленный bool; при false источник не перемещается |
| `task_channel_close(channel)` | Закрыть отправку, дочитать буфер, затем успешный None |
| `task_channel_fail(channel,message)` | Ошибка, очистка буфера, Error ожидающим операциям |
| `task_channel_clone(channel)` | Независимый lease той же очереди |
| `task_channel_count`, `task_channel_waiters` | Размер буфера и число зарегистрированных ожиданий |

```dascript
// actions — владелец уровня приложения, как в существующих event-примерах.
var actions:typedecl(task_channel(type<string>,8))
def wait_action() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let event=task_channel_receive(actions) |> bind
        return event is some ? event as some : "closed"
    }
}
```

Pending отправки тоже владеют payload: capacity ограничивает буфер, но не
число заранее созданных Task. Ограничивайте число производителей отдельно.

Отправители и получатели получают FIFO-позиции при первом poll, не при создании
Task. Новая отправка не обгоняет зарегистрированную ожидающую отправку.
Отмена и таймаут удаляют ожидание; уже переданные элементы не откатываются.
При `close` уже ожидающие отправки получают Error. Первый close/fail терминален.
Уничтожение исходного владельца закрывает очередь; pending операции удерживают
память через leases до своего завершения/отмены. Явно закрыть очередь можно и
через клонированный handle. Удаление обычного clone не закрывает очередь.

Channels не потокобезопасны. Не передавайте их в jobque и не вызывайте из
фонового callback. Для межпоточной передачи мост использует стандартный Channel.
Как и другие owning handles CE, channel/queue нельзя неявно переместить из
параметра функции в CE-генератор. Примеры используют сервис уровня приложения;
для обычных lambda доступен явный `capture(:= handle)` с библиотечным clone.
Ресурсы приложения должны жить до последнего шага CE, который к ним обращается.

## Семафор и ограниченный when_all

`task_semaphore(n)` создаёт n разрешений поверх channel<Unit>.
`task_with_semaphore(semaphore,factory)` лениво получает разрешение, только затем
создаёт и выполняет задачу factory. Разрешение возвращается при Success, Error,
исключении, отмене и таймауте. Закрытие семафора отклоняет новые получения;
уже запущенные операции продолжаются.

Низкоуровневые `task_semaphore_acquire` (Task<Result<Unit,string>>) и
`task_semaphore_release` доступны для явного управления, но тогда возврат
разрешения в try_finally — обязанность вызывающего. Предпочтителен
`task_with_semaphore`. Освобождение полного/закрытого семафора явно ошибочно.

```dascript
var inputs <- [1,2,3,4]
var inscope loading <- task_result_when_all_limited(inputs,2,
    @(asset:int) {return <- load_asset(asset)})
```

`task_when_all_limited(inputs,limit,factory)` даёт Task<array<T>>;
`task_result_when_all_limited` даёт Task<Result<array<T>,string>>.
Обе операции потребляют inputs и factory. Limit должен быть положительным.
Пустой массив успешно даёт пустой результат. Порядок результатов соответствует
порядку входа. Фабрики вызываются по порядку и лишь при свободном слоте;
изначальный массив уже запущенных Task не ограничил бы начало внешней работы.
Освободившийся слот используется на следующем poll. За один poll каждый
активный ребёнок опрашивается не более одного раза.

Error в Result-варианте немедленно отменяет остальных активных детей. Нативное
исключение даёт Failed, отмена ребёнка — Cancelled; оставшиеся фабрики не
вызываются. При отмене родителя освобождаются активные дети, входы, результаты и
factory. Владение move-only результатами передаётся в итоговый массив.
Ошибка очистки при отмене передаётся как Failed; разрешение семафора всё равно
возвращается, а остальные дети освобождаются.

## Retry и первая успешная попытка

`task_retry(factory,max_attempts,delay_ms=0l)` вызывает factory(attempt), начиная
с 1. Каждая попытка — новый Task<Result<T,string>>. Повторяется только Result.err;
Success возвращается сразу. Последняя ошибка возвращается как err. Нативное
исключение и Cancelled не повторяются. Между попытками есть хотя бы одна отдача
управления; ненулевой delay работает через now_ms runtime/типизированного
scheduler. Таймаут родителя покрывает всю цепочку, включая задержки.

`task_first_success(children)` потребляет массив Task<Result<T,string>> и
опрашивает их слева направо. Ошибки err пропускаются; первый ok возвращается,
остальные задачи отменяются и освобождаются. При успехах в одном poll побеждает
меньший индекс. Если все дали err, возвращается последняя замеченная ошибка;
пустой массив даёт err "task_first_success: no candidates". Нативные исключения
и отмена передаются родителю, а не маскируются как неуспешные кандидаты.

## CPU-работа через стандартный jobque

```dascript
def decode(asset:int) {var sum=0;for(i in range(asset*1000)) {sum+=i%17};return sum}
// Внутри with_job_que(), queue — живой task_job_queue().
var inscope job <- task_jobque(queue,3,@@decode)
// В TaskResultBuilder: let decoded=task_jobque(queue,3,@@decode) |> bind
```

Host создаёт thread pool через `with_job_que` либо `create_job_que`/его shutdown.
`task_job_queue()` управляет каналами и временем жизни передаваемых контекстов;
сам pool он не создаёт. Для собственного C++ хоста добавьте перед
Module::Initialize():

```cpp
NEED_ALL_DEFAULT_MODULES;
NEED_MODULE(Module_JobQue);
```

jobque не входит в NEED_ALL_DEFAULT_MODULES. В поставляемом AOT-хосте
регистрация и AOT-библиотека daslib/jobque_boost уже добавлены. Отправка холодная: native job появляется на первом poll.
Отмена до первого poll не создаёт канал и не запускает работу.

`task_jobque(queue,input,@@work)` сохраняет клонированный снимок входа;
`task_jobque_move` потребляет его перемещением. Work — функция T → R, а не lambda
с заимствованным состоянием главного потока. SDK исполняет её в клонированном
контексте и клонирует результат через свой Channel. Поддерживаются строки,
структуры и массивы; сырой pointer/borrowed payload отклоняется. Work не должен вызывать CE Task, runtime или обычные CE channels из worker.
Владеющие
входные данные обычной копирующей формы оформляйте через var inscope.

Итог — Task<Result<R,string>>. Нативный panic внутри worker ловится на границе
потока и передаётся как err (текст SDK может содержать перевод строки).
Отсутствие thread pool даёт Failed, без зависшего native канала.

Отмена/таймаут прекращают ожидание, но не убивают уже выполняющийся CPU-код.
При живом владельце queue они не ждут worker. `task_jobque_collect(queue)`
неблокирующе удаляет завершённые каналы без ожидающих Task; вызывайте его в
игровом цикле. `task_jobque_channels()` показывает число ещё живых каналов.
Последний lease queue при уничтожении присоединяет оставшиеся jobs и освобождает
каналы: это граница shutdown, которая может ждать. Поэтому держите владельца
queue живым до завершения игрового цикла. Бесконечный worker нельзя безопасно
прервать этим мостом. Для отмены самого алгоритма нужен отдельный межпоточный
кооперативный протокол; обычный CancellationToken CE для этого не предназначен.

## Примеры и проверки

- [task_runtime_channel_demo.das](examples/task_runtime_channel_demo.das): runtime
  с разными типами, производитель/потребитель, backpressure и пайповый bind.
- [task_parallel_jobque_demo.das](examples/task_parallel_jobque_demo.das): jobque,
  загрузка двух ассетов одновременно, retry, first_success, semaphore и таймаут.
- test_task_runtime_channel / runtime_lifetime / channel_lifetime / parallel /
  parallel_lifetime / jobque / jobque_lifetime / concurrency_edges включены в обычный interpreter
  runner, mode_tests (JIT/генерация AOT) и стандартный список исполнения AOT.

Запуск из корня: `./computation_expressions/run_computation.ps1 -Test`.
Новые примеры можно запускать напрямую через daslang.exe с -no-module-cache.

## Результаты проверки, 20 октября 2026

- Полный `run_computation.ps1 -Test`: успешен, включая TCP/WebSocket, GLFW,
  диагностику и проверки раскрытия BindReturn/State/List.
- Новые сценарии: 8 тестов и 2 примера в интерпретаторе и JIT.
- Регрессия shared Task и CancellationToken: ещё 3 сценария JIT.
- AOT: все эти 13 сценариев собраны и исполнены со strict linking и AOT main;
  fallback в интерпретатор не разрешён.
- 4 теста Rx Task/AsyncSequence-адаптеров: интерпретатор и JIT успешны.
- Экспорт 38 модулей и подключение в стороннем проекте: успешны.

Повторные запуски проверяют стабильность живой heap-памяти и освобождение
native каналов; отдельно проверяются владение массивами, FIFO, остановка фабрик,
групповая отмена, таймаут, borrowed string# из callback и исключения cleanup.
В процессе исправлена утечка временного массива в ce_cancellation_isolate,
проявлявшаяся при групповой отмене через shared Task/runtime.
