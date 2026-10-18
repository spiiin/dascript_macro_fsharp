# Возможности и семантика computation expressions

Короткие операции State: [STATE_OPERATIONS.md](STATE_OPERATIONS.md). Раздельные проверки режимов и законы композиции: [RELIABILITY.md](RELIABILITY.md).

Этот документ фиксирует контракт текущей реализации. Сигнатуры конкретного
builder определяют допустимые источники; общая запись `|> bind` не делает
произвольные контейнеры совместимыми. SearchBuilder пока не реализован.
TaskBuilder и TaskResultBuilder предоставляют cold single-shot задачи и ожидание
внешних операций через poll-адаптер, см. [TASKS.md](TASKS.md).

## Таблица основных builders

«Ресурсы» означает `use_resource`, `try_finally` и `try_with` по общему протоколу.
Для ресурса нужна видимая перегрузка `ce_dispose`. Условия и ограничения
владения ниже обязательны даже там, где стоит «да».

| Builder | Результат обычного CE | `and_bind` | `for` / `while` / zip-for | Ресурсы | `deferred` | Move-only payload результата |
|---|---|---|---|---|---|---|
| ResultBuilder | `ok:T / error:string` | Да: Result | Да / да / да | Да | Да | Нет; использовать MoveResult |
| TaskBuilder(type<T>) | Task<T>, cold single-shot | Да: Task | Да / да / native zip, break/continue | Да | Да | Да: owning bind/return |
| TaskResultBuilder(type<T>) | Task<Result<T>>, cold single-shot | Да: Result и Unit | Да / да / native zip, break/continue | Да | Да | Да: owning bind/return |
| OptionBuilder | `some:T / none:bool` | Да: Option | Да / да / да | Да | Да | Нет; использовать MoveOption |
| ValidationBuilder | `valid:T / invalid:…` | Да: накопление ошибок | Да / да / да | Да | Да | Нет |
| StateBuilder(initial) | `(value:T, state:S)` | Нет | Да / да / да | Да | Да | Нет; состояние также копируемое |
| WriterBuilder | `(value:T, log:string)` | Нет | Да / да / да | Да | Да | Нет |
| StateResultBuilder(initial) | `(result:Result<T>, state:S)` | Нет | Да / да / да | Да | Да | Нет; состояние также копируемое |
| WriterResultBuilder | `(result:Result<T>, log:string)` | Нет | Да / да / да | Да | Да | Нет |
| ReaderBuilder(environment) | `(value:T)` | Нет | Да / да / да | Да | Да | Нет; окружение копируемое |
| ReaderResultBuilder(environment) | `Result<T>` | Да: Result и `reader_ask()` | Да / да / да | Да | Да | Нет; окружение копируемое |
| StateWriterResultBuilder(initial) | `(result:Result<T>, state:S, log:string)` | Нет | Да / да / да | Да | Да | Нет; состояние также копируемое |
| ListBuilder(type<T>) | `array<T>` | Да: копируемые элементы, все пары | Да / да / да | Да | Да | Да: consuming bind и `return <-` / `yield <-` |
| SequenceBuilder(type<T>) | Ленивый iterator | Нет | Да / да / да | Да, до закрытия iterator | Да: новый iterator на запуск | Да: owning slot и `yield <-` |
| MoveResultBuilder | Перемещаемый Result | Да: перенос payload в пару | Да / да / да | Да | Да | Да |
| MoveOptionBuilder | Перемещаемый Option | Да: перенос payload в пару | Да / да / да | Да | Да | Да |
| CoroutineBuilder | `iterator<CoroutineFrame>` | Нет | Да / да / да | Да, до завершения/отмены | Да: новый сценарий на запуск | Не контейнер результата; выдаёт кадры, поддерживает owning-ресурсы |

`Result<T>` в таблице — сокращение для variant с `ok` и `error`, а не отдельное
объявление типа в библиотеке. ListBuilder()/SequenceBuilder() выбирают `int`;
для другого типа результата передайте `type<T>`.

Поддержка move-only результата не равна поддержке move-only ресурса.
`var resource & = acquire() |> use_resource` доступен через общий ресурсный
механизм и в CE с копируемым результатом. Сырые указатели сами по себе не
становятся владельцами. Для List несколько consuming bind не означают
декартово копирование одного move-only объекта: действуют правила переноса
и области владения из [MOVE_COLLECTIONS.md](MOVE_COLLECTIONS.md).

## Демонстрационные builders

| Builder | `and_bind` | Циклы | Ресурсы / deferred | Особенность |
|---|---|---|---|---|
| BoundedResultBuilder | Нет | For для range, While и zip-for с бюджетом | Общий Value-протокол / ограничения снимков | Бюджет отдельный для каждого цикла |
| GameSourceBuilder | Да: Result после адаптации | Общий fallback, включая TargetRange через Source | Общий Value-протокол / ограничения снимков | `ce_source` адаптирует предметные типы |
| ReportBuilder | Да: Result | Общий Value-протокол | Общий Value-протокол / ограничения снимков | `ce_run` упаковывает Result в completed/failed |

Они показывают расширение протокола отдельным модулем. Реализации из
`protocol_test_builders.das` и других test-fixtures не являются публичным набором
builders. Отсутствие `and_bind` не компенсируется автоматически обычным bind:
нужна перегрузка `ce_merge_sources` для конкретных источников.

## Время выполнения и порядок эффектов

Обычные Value/Owned/Collect CE выполняются синхронно при достижении
`computation(builder)`. Выражение builder вычисляется один раз; сохранённый
builder, поле или аргумент функции допускаются. State-контекст текущего CE
локален; это не неявная мутация переданного savedBuilder.

Sequence и Coroutine создают ленивые итераторы: тело начинается при запросе
элемента/возобновлении. Код до создания CE и выражение builder остаются обычными
вычислениями. Coroutine не добавляет потоки или сетевое async-ожидание.
Task начинает тело при первом task_poll. Pending приостанавливает продолжение;
готовый источник продолжает его в том же poll. Успешный результат кешируется.
Result.error завершает TaskResult со статусом Succeeded; native panic даёт Failed,
явная отмена — Cancelled. Области ресурсов закрываются и в этих путях.
Task поддерживает break/continue, return_from, Unit/Zero, deferred, shared-await
и move-only payload; контракт: [TASK_COMPLETION.md](TASK_COMPLETION.md).
Нативные синхронные участки могут блокировать poll.
`task_from_async` связывает стандартные [async]-источники с Task: ждёт полного
завершения, возвращает последний res либо CeUnit для void. Промежуточный res
не завершает Task; код и исключения после него сохраняются. Только wait-события
добавляют приостановки адаптера. Для внешнего cleanup есть перегрузка с callback;
ограничение native inscope в SDK 0.6.4 описано в [TASKS.md](TASKS.md).
Совместное ожидание двух владельцев задаётся task_when_all/task_result_when_all,
гонка — task_race, из отдельного модуля task_combinators.das. Группа
`and_bind` использует общий ce_merge_sources, см. [TASK_AND_BIND.md](TASK_AND_BIND.md). Порядок опроса, отмена оставшихся детей и обработка
бросающих close-callbacks описаны в [TASK_COMPOSITION.md](TASK_COMPOSITION.md).

Обычный bind сначала вычисляет источник. После успешного связывания выполняется
продолжение, которое может вычислить следующий источник. При Error/None/invalid
Result-подобные builders пропускают продолжение; выражения следующих источников,
условия следующих итераций и последующие приобретения ресурсов не выполняются.

`and_bind` отличается от последовательных bind:

```das
let result = computation(ResultBuilder()) {
    let pair = left() |> and_bind(right()) |> bind
    return pair.first + pair.second
}
```

Оба выражения источников достигнутой группы выполняются слева направо один раз,
даже если левое вернуло Error/None/invalid или пустую коллекцию. Native panic
прерывает вычисление сразу: недостигнутые источники уже не запускаются.
Это не параллельное выполнение.

- Result и ReaderResult выбирают первую ошибку в порядке источников.
- Option возвращает None при отсутствии любого значения.
- Validation объединяет ошибки слева направо. Обычный последовательный bind
  Validation останавливается на invalid и не собирает ошибки недостигнутых шагов.
- List строит все пары: левый источник — внешний обход, правый — внутренний.
- MoveResult/MoveOption дополнительно передают владение полезными значениями.

Два последовательных коллекционных bind List/Sequence также дают вложенный
обход. Оставшееся тело выполняется для каждой комбинации, поэтому находящиеся
в нём эффекты повторяются. List собирает результат целиком; Sequence производит
элементы по запросу. Для повторного внутреннего обхода одноразового iterator
нужен новый источник, а не повторное использование уже потреблённого iterator.

Оптимизации BindReturn/Bind2Return/Bind2 и накопителя List обязаны сохранять
порядок наблюдаемых эффектов и владение. Они не обещают отсутствие временных
значений для любой формы CE. Пользовательские финализаторы могут ограничивать
выбор оптимизированного пути; см. [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md).

## Циклы и остановка

For с одним источником обходит его последовательно. For с несколькими
источниками — одновременный zip-обход до кратчайшего источника, а не декартово
произведение. Выражения источников вычисляются при входе в цикл слева направо.

Value-builders требуют Unit-результат тела итерации. Result/Option и их
ошибочные комбинации прекращают цикл и оставшуюся часть CE на Error/None.
State передаёт состояние следующей итерации; Writer накапливает журнал.
List может накопить ноль элементов отдельного шага, не превращая пустой
результат итерации в ошибку всего обычного For.

`ce_for`, `ce_while`, `ce_for_zip` могут переопределяться для Value/Collect.
При отсутствии hook работает общий fallback, если builder реализовал нужные
операции протокола. Sequence/Coroutine используют генераторные циклы; eager
hooks не изменяют их семантику. Произвольные native break/continue не являются
общим контрактом Value CE. Break внешнего потребляющего цикла Sequence означает
досрочное прекращение обхода; для освобождения нужен корректный владелец/закрытие.

## State: что именно откатывается

StateBuilder не предоставляет откат. Его bind для state_put меняет локальное
состояние текущего CE; state_get возвращает его копию. Сами конструкторы
`state_get()` и `state_put(...)` только описывают операции: выполняет их bind.

StateResult и StateWriterResult при Error, распространяемом через bind,
Combine или return_from, возвращают начальное состояние всего принимающего CE.
Откатываются и успешные итерации, и ранее импортированные успешные дочерние
результаты. Ошибочный дочерний результат не подменяет границу отката родителя
своим снимком. Вложенный CE имеет собственный initial; принятие его успеха
родителем ещё не является независимым коммитом.

```das
let outcome = computation(StateResultBuilder(100)) {
    state_put(75) |> bind
    result_error("отказ", type<CeUnit>) |> bind
    return "готово"
}
assert(outcome.result is error && outcome.state == 100)
```

Откат касается значения поля state. Он не отменяет печать, сетевые запросы,
изменение внешних переменных, файлы или мутацию объектов по общим указателям.
State/StateResult не выполняют глубокий clone произвольного графа объектов.
Изоляция исходного initial обеспечивается только настолько, насколько его
копируемые поля действительно независимы. Move-only состояние не поддержано.

Готовый дочерний результат без bind/return_from не меняет контекст родителя.
`return result_error(...)` возвращает Result как вложенный payload; это не то же
самое, что `return result_error(...) |> return_from`, распространяющий ошибку.

## Error/None и исключения

| Событие | Поведение |
|---|---|
| Error / None / invalid | Обычное значение; соответствующий bind останавливает продолжение |
| `try_with` вокруг Error/None | Обработчик не вызывается |
| Перехватываемый native panic/assert | Вызывает ближайший подходящий try_with; автоматически в Error/None не преобразуется |
| Исключение вышло из CE | Результат этого CE не возвращается |
| Ошибка компиляции | Не перехватывается try_with |

Native panic сам по себе не запускает транзакционный откат. Если его перехватили
внутри State/StateResult CE, изменения состояния до исключения сохраняются.
Обработчик StateResult может явно вернуть Error через return_from — тогда
сработает обычная граница отката. Ошибка самого обработчика выходит наружу.

Writer/WriterResult не возвращают журнал незавершившегося результата упавшего
тела try_with: обработчик строит свой результат и журнал. Это отличается от
обычного Error, при котором WriterResult сохраняет накопленный журнал.
StateWriterResult также сохраняет журнал при обычном Error; сам Error запись
в журнал не добавляет. Контракт восстановления журнала при исключении не следует
подменять правилом сохранения журнала при Error.

Eager List при восстановлении возвращает коллекцию обработчика вместо
частично построенной коллекции упавшего тела. Sequence сохраняет уже выданные
элементы и после очистки упавшего источника продолжает iterator обработчика.
Исключение потребителя находится снаружи Sequence CE и его try_with.

## Ресурсы и владение

Ресурс приобретается один раз при достижении use_resource; вложенные ресурсы
освобождаются в обратном порядке. Очистка приобретённых ресурсов выполняется
при нормальном завершении, Error/None и перехватываемом исключении. Если само
приобретение завершилось неуспешно, за частичные выделения отвечает acquire.
use_resource начинает отвечать за ресурс только после успешного приобретения.

В Sequence/Coroutine ресурс живёт до завершения своей ленивой области или
закрытия iterator. Закрытие не исполняет обычное продолжение после yield.
Отмена Coroutine закрывает его ресурсы. Для потребителя Sequence, который может
бросить исключение, используйте sequence_each или явную защищённую очистку.
Один лишь inscope внутри прерванного native try не гарантирует unwind на panic.

try_finally не превращает ошибку в успешный результат. Ошибка cleanup может
заменить исходное исключение; внешние cleanup продолжают выполняться. Cleanup
и пользовательские finalizers следует писать без исключений. Защита CE
распространяется на принадлежащие ему источники и ресурсные области, а не на
любой произвольный native-ресурс пользователя.

## Deferred

Deferred — оболочка над builder, а не отдельная семантика bind. При создании
builder и data вычисляются один раз и клонируются в сохранённый снимок; тело
ещё не запускается. Каждый run_deferred создаёт независимый рабочий снимок.
Это повторное выполнение, а не кеширование результата.

Внешние локальные значения передаются явно через data/snapshot. Указатели,
handles, blocks, lambdas и iterators в снимке, включая вложенные поля,
отклоняются. Пользовательский clone обязан обеспечивать независимость данных.
Глобальные переменные и внешние эффекты не изолируются. Перенос между Context
не поддержан. Поэтому «да» в таблице не означает поддержку любого builder/data.

Value/Owned/Collect выполняются синхронно при каждом запуске. Sequence/Coroutine
возвращают новый ленивый iterator, удерживающий рабочий снимок до закрытия.
Ресурсы тела освобождаются до снимка. Повторный запуск допустим после ошибки
предыдущего; сохранённое вычисление и возвращённый iterator — отдельные владельцы.
Для move-only коллекций каждый запуск создаёт собственные элементы; ссылки
на снимок не могут произвольно выходить наружу. Специальный iterator<T&>
owning Sequence описан в [DEFERRED_SEQUENCE.md](DEFERRED_SEQUENCE.md).

## Подтверждение и границы проверок

Матрица сверена с перегрузками в модулях builders и общим макросом; наличие
общего протокольного пути не означает отдельный тест каждого декартова сочетания
builder × ресурс × тип × runtime. Основные существующие проверки:

- [test_and_bind.das](tests/test_and_bind.das), [test_reader_result.das](tests/test_reader_result.das),
  [test_move_ce.das](tests/test_move_ce.das): объединение источников и остановка.
- [test_state_result.das](tests/test_state_result.das),
  [test_state_writer_result.das](tests/test_state_writer_result.das): границы отката и журнал.
- [test_loop_protocol.das](tests/test_loop_protocol.das), [test_zip_for.das](tests/test_zip_for.das):
  циклы, порядок и ранняя остановка.
- [test_try_with.das](tests/test_try_with.das), [test_sequence_try_with.das](tests/test_sequence_try_with.das),
  [test_move_resources.das](tests/test_move_resources.das): исключения и очистка.
- [test_deferred.das](tests/test_deferred.das), [test_deferred_snapshots.das](tests/test_deferred_snapshots.das),
  [test_deferred_move_collections.das](tests/test_deferred_move_collections.das): повторные запуски и владение.

Полный запуск: `./run_computation.ps1 -Test` из этой папки, либо
`../run.ps1 -Test` для всего репозитория. Это проверка интерпретатора
Daslang v0.6.5-RC2, не подтверждение всех путей под JIT/AOT.
История сбоя JIT на State + panic/cleanup и текущий обход return в recover:
[RELIABILITY.md](RELIABILITY.md). Отдельный `test_recover_portability` включён
в interpreter/JIT-набор и проверяет State и владеющие результаты.

Подробные контракты: [AND_BIND.md](AND_BIND.md), [LOOP_PROTOCOL.md](LOOP_PROTOCOL.md),
[ZIP_FOR.md](ZIP_FOR.md), [RESOURCES.md](RESOURCES.md), [TRY_WITH.md](TRY_WITH.md),
[MOVE_CE.md](MOVE_CE.md), [MOVE_COLLECTIONS.md](MOVE_COLLECTIONS.md), [DEFERRED.md](DEFERRED.md).

Типизированный планировщик с лимитом опросов, круговым обходом, ID, отменой и историей: [TASK_SCHEDULER.md](TASK_SCHEDULER.md).

Task scheduler: TaskTimeout(after_ms=...) отменяет задачу до poll при достижении срока, независимо от бюджета опросов. TaskResult также получает Cancelled, а не Result.error; ошибка cleanup даёт Failed при сохранении task_timed_out=true. Контракт часов и владения: [TASK_SCHEDULER.md](TASK_SCHEDULER.md#таймауты).

Task bind и комбинаторы передают Cancelled ребёнка родителю без panic; try_with его не перехватывает. CancellationToken добавляет кооперативный групповой запрос, наблюдаемый при poll. Ресурсы закрываются; ошибка cleanup даёт Failed. См. [TASK_CANCELLATION.md](TASK_CANCELLATION.md).

task_delay_ms — холодная Task<CeUnit>, отсчёт от первого poll по now_ms scheduler. TaskResultBuilder допускает Task<CeUnit> без доменного Error; отмена/исключения передаются как обычно. Детали времени и владения: [TASK_DELAY.md](TASK_DELAY.md).

task_when_all(array) сохраняет порядок входных индексов. Failed/Cancelled передаются вверх с закрытием остальных детей. Result.error внутри элементов остаётся данными. Владеющий массив заимствуется через var results & = ... |> bind и живёт через последующие ожидания продолжения. [TASK_ARRAY.md](TASK_ARRAY.md).
# WebSocket Task

Необязательный адаптер dasHV сохраняет тот же контракт TaskResultBuilder:
Error пропускает продолжение, Cancelled распространяется через bind,
use_resource закрывает соединение при любом выходе. Таймаут действует через
now_ms планировщика. Отмена активной операции закрывает весь сокет;
отмена до первого опроса не начинает ввод-вывод. Ограничения DNS, очередей,
одновременных операций и отправки: [TASK_HV.md](TASK_HV.md).

## Task и события

`task_wait_event` подписывается при первом poll, сохраняет первое событие и
освобождает подписку до продолжения либо при отмене/таймауте/удалении Task.
Emit делает broadcast только существующим подпискам, без replay и inline callbacks.
Закрытый источник возвращает Error, отмена даёт Cancelled. Источник и emit
работают в одном потоке. Полный контракт: [TASK_EVENTS.md](TASK_EVENTS.md).
