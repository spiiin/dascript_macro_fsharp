# ReactiveX для daScript

Независимая папка четвёртой библиотеки. `lib/reactivex.das` не зависит от CE,
Task, type providers и active patterns. Ядро исполняет callbacks в одном потоке;
временные операции продвигаются явно через scheduler. Это ещё не полная
реализация всех операторов ReactiveX. Дополнительный `lib/reactivex_task.das`
подключает адаптеры CE Task, не добавляя эту зависимость в ядро.
Адаптеры Task и AsyncSequence используют стандартные `$Result<T;string>`
(cases err/ok) и `$Option<T>` (none/some) из SDK 0.6.5-RC2;
[миграция и владение](../computation_expressions/STANDARD_TYPES.md).
Уведомления materialize сохраняют собственный case error.

```das
require ../lib/reactivex.das

var inscope numbers <- rx_range(1,10) |> rx_filter(@(n:int) {return n%2==0}) |> rx_map(@(n:int) {return n*10}) |> rx_take(2)

var inscope subscription <- rx_subscribe(numbers,
    @(value:int) {print("{value}\n")},
    @(message:string) {print("error: {message}\n")},
    @() {print("complete\n")})
// 20, 40, complete. Для синхронного источника подписка уже закрыта.
```

Полный пример: [reactivex_demo.das](examples/reactivex_demo.das).
Практические интеграции: [UI на dasGlfw и WebSocket-поток с отменой](INTEGRATIONS.md).
Запуск: `./reactivex/run_glfw_ui.ps1` и `./reactivex/run_websocket_echo.ps1`
из корня репозитория. Проверки native-интеграций: `./reactivex/test_integrations.ps1 -Jit`.
Их [AOT-хост](AOT_INTEGRATIONS.md): `./reactivex/run_integrations_aot.ps1`.
Операторы принимают исходный descriptor перемещением. Для ответвления цепочки
используйте `rx_clone(source)`: это удержание того же источника, а не новая копия
его состояния. Обычный descriptor допускает повторные `rx_subscribe`.

## Состояние и побочные эффекты

```das
require math
var inscope actions <- rx_subject(type<int>)
var inscope health <- rx_clone(actions) |> rx_tap(@(delta:int) {print("action: {delta}\n")}) |> rx_scan(100,@(hp:int;delta:int) {return max(0,hp+delta)}) |> rx_start_with(100) |> rx_distinct_until_changed()
var inscope sub <- rx_subscribe(health,
    @(hp:int) {print("health: {hp}\n")},
    @(message:string) {print("error: {message}\n")},
    @() {print("complete\n")})
rx_subject_next(actions,-25)
rx_subject_next(actions,0)
rx_subject_next(actions,10)
rx_subject_complete(actions)
// health: 100, 75, 85. tap видит все три действия, включая 0.
```

Исполняемый пример: [stateful_demo.das](examples/stateful_demo.das).

`rx_tap(next)` наблюдает значения без преобразования. Перегрузка
`rx_tap(next,error,complete)` наблюдает также терминальные события. Обработчик
вызывается перед соответствующим downstream callback. Panic внутри tap,
reducer или comparator превращается в единственный downstream `on_error` и
останавливает цепочку; ошибка терминального tap заменяет исходный terminal.
Ошибка самого tap не передаётся его же error callback. Исключения конечного
observer и cleanup остаются native исключениями, после закрытия подписки.
Обычная отписка не вызывает complete/error у tap.

`rx_scan(seed,@(state:S;value:T) {return newState})` допускает разные типы
входа и результата. Накопитель копируется из seed заново при каждой подписке;
пустой вход не выдаёт seed. Начальное состояние отдельно выдаёт `start_with`.
Оба типа должны удовлетворять обычному ограничению Rx на copyable owning payload.

`rx_start_with(value)` выдаёт одно значение того же типа, что и источник,
синхронно при подписке. Если на префиксе downstream завершился через take,
отписался или выбросил исключение, исходный источник не подключается.
Несколько значений можно добавить через `rx_from_array(prefix) |> rx_concat(source)`.

`rx_distinct_until_changed()` использует `==`; перегрузка
`rx_distinct_until_changed(@(previous:T;current:T) {return bool})` подавляет
значение при true. Первое значение всегда выдаётся без comparator. Хранится
последнее **выданное** значение: `1,1,2,1` превращается в `1,2,1`.
История и накопитель независимы у одновременных и повторных подписок;
состояние обновляется перед вызовом downstream. Переданные callbacks принадлежат
descriptor: их явные общие captures разделяются между подписками, как у map/filter.

## Горячие события

```das
var inscope actions <- rx_subject(type<int>)
var inscope selected <- rx_clone(actions) |> rx_filter(@(n:int) {return n>0}) |> rx_take(2)
var inscope subscription <- rx_subscribe(selected,
    @(value:int) {print("action: {value}\n")},
    @(message:string) {print("error: {message}\n")},
    @() {print("finished\n")})

rx_add_cleanup(subscription,@() {print("subscription released\n")})
rx_subject_next(actions,10) // может вызываться из game/UI callback
rx_subject_next(actions,-1)
rx_subject_next(actions,20) // take(2) завершает и отписывает цепочку
rx_subject_next(actions,30) // не доставляется завершённой подписке
```

`rx_unsubscribe(subscription)` отменяет подписку явно; `delete subscription`
или выход из `var inscope` отменяет её автоматически. Отписка не вызывает
`on_complete`. Повторная отписка безопасна, возвращает false. `rx_is_closed`
также возвращает true после завершения, ошибки или удаления handle.

Обычный `rx_subject` не хранит историю значений. `rx_subject_complete` и `rx_subject_error`
завершают текущие подписки; поздний подписчик сразу получает сохранённое
завершение/ошибку, без прежних значений. После терминального события новые
next/complete/error игнорируются. `rx_subscriber_count` показывает число активных
подключений к Subject.

## BehaviorSubject и ReplaySubject

```das
var inscope health <- rx_behavior_subject(100)
rx_subject_next(health,75)
var inscope ui <- rx_subscribe(health,
    @(hp:int) {print("current health: {hp}\n")},
    @(s:string) {panic(s)},@() {}) // немедленно 75
verify(rx_behavior_value(health)==75)
rx_subject_complete(health)
```

```das
var inscope log <- rx_replay_subject(type<string>,2)
rx_subject_next(log,"started")
rx_subject_next(log,"connected")
rx_subject_next(log,"ready") // вытесняет started
rx_subject_complete(log)
var inscope history <- rx_subscribe(log,
    @(s:string) {print("{s}\n")},@(s:string) {panic(s)},@() {print("complete\n")})
// connected, ready, complete — даже после завершения источника.
verify(rx_subject_buffered_count(log)==2)
```

Полный пример: [subject_variants_demo.das](examples/subject_variants_demo.das).

| Источник | Начальное значение | Поздняя подписка до terminal | После complete | После error |
|---|---|---|---|---|
| `rx_subject(type<T>)` | Нет | Только будущие события | Только complete | Только error |
| `rx_behavior_subject(initial)` | Обязательно | Текущее значение, затем будущие события | Только complete | Только error |
| `rx_replay_subject(type<T>,N)` | Нет | Последние N значений в FIFO, затем будущие события | Буфер, затем complete | Буфер, затем error |

Для всех трёх вариантов используются одни операции `rx_subject_next`,
`rx_subject_complete`, `rx_subject_error`, `rx_subscriber_count` и `rx_clone`.
Пайповые операторы подключаются как обычно. Правила поздних терминальных подписок
соответствуют [BehaviorSubject](https://github.com/ReactiveX/rxjs/blob/7.8.2/src/internal/BehaviorSubject.ts)
и [ReplaySubject](https://github.com/ReactiveX/rxjs/blob/7.8.2/src/internal/ReplaySubject.ts) RxJS.

Replay требует положительный размер N, хранит не больше N значений и вытесняет
самое старое. Ограничение действует по числу элементов; Для ограничения по времени есть перегрузка с window_ms и scheduler; правила ниже в разделе «Временной replay и настройки share».
Behavior хранит ровно одно значение. `rx_behavior_value` возвращает его копию;
после complete чтение допустимо, после error оно выбрасывает native исключение.
Вызов этого getter для другого вида Subject также считается ошибкой.
Next после принятого complete/error игнорируется и не изменяет буфер.

Replay выполняется синхронно из отдельного снимка. Отписка или downstream take
останавливает его сразу. Повторные next/complete/error из callback не вклиниваются
в середину снимка, а ставятся в общую очередь Subject. История обновляется перед
рассылкой соответствующего события. Подписчик, добавленный во время рассылки,
получает уже применённую историю, затем ещё ожидающие события, без дубликата
текущего next. Это сохраняет принятую в библиотеке сериализацию callbacks;
`rx_behavior_value` внутри callback ещё не видит next, стоящий в очереди.

Ошибка observer остаётся native исключением: проблемная подписка закрывается,
остальные подписчики и очередь продолжают работать. Буфер не очищается при
отписке или terminal: он нужен поздним подписчикам, а у Behavior — также getter.
Он освобождается с последним владеющим handle, включая удержания активных
подписок. Снимок replay временный и удаляется после доставки, остановки или ошибки.
Входные строки initial/next и кешируемое сообщение ошибки явно копируются;
нативный callback может затем переиспользовать свой символьный буфер.
Все payload остаются copyable owning значениями по общему контракту Rx.

## Общая подписка: share и share_replay

```das
var inscope clock <- rx_virtual_scheduler()
var inscope hub <- rx_interval(10,clock) |> rx_take(2) |> rx_tap(@(n:int64) {print("compute: {n}\n")}) |> rx_share_replay(1)
var inscope a <- rx_subscribe(hub,@(n:int64) {print("A: {n}\n")},@(s:string) {panic(s)},@() {})
rx_advance_by(clock,10) // compute 0, A 0
var inscope b <- rx_subscribe(hub,@(n:int64) {print("B: {n}\n")},@(s:string) {panic(s)},@() {}) // B 0 из кеша
rx_advance_by(clock,10) // compute 1, A 1, B 1; источник завершился
var inscope c <- rx_subscribe(hub,@(n:int64) {print("late C: {n}\n")},@(s:string) {panic(s)},@() {}) // C 1, complete; без нового таймера
```

Полное сравнение: [share_demo.das](examples/share_demo.das).

`source |> rx_share()` создаёт одну группу подписчиков с обычным Subject.
`source |> rx_share_replay(N)` использует ReplaySubject, сохраняя последние N
значений; N положительный, по умолчанию 1. Первый подписчик подключает исходный
Observable, следующие присоединяются к тому же подключению. Последний уходящий
подписчик отменяет незавершённое подключение. Отписка одного не затрагивает других.

Правила сброса фиксированы:

| Событие | share | share_replay |
|---|---|---|
| Новый подписчик при активном источнике | Только будущие значения | Снимок последних N, затем будущие значения |
| Последний подписчик ушёл до terminal | Отписка от источника, сброс группы | Отписка от источника, сброс группы и кеша |
| Следующая подписка после такого сброса | Новое подключение | Новое подключение без старого кеша |
| Error источника | Рассылка error, сброс; следующая подписка создаёт новую попытку | То же, старый кеш не воспроизводится |
| Complete источника | Рассылка complete, сброс; следующая подписка подключает источник заново | Сохраняются N значений и complete; поздние подписки читают кеш без переподключения |

Это соответствует [share со сбросом по error/complete/refcount zero](https://github.com/ReactiveX/rxjs/blob/7.8.2/src/internal/operators/share.ts)
и [shareReplay с refCount=true](https://github.com/ReactiveX/rxjs/blob/7.8.2/src/internal/operators/shareReplay.ts),
с ограниченным размером кеша по умолчанию. Перегрузки с RxShareOptions задают reset-флаги; keep-alive закрывается через rx_share_close.
Перегрузка share_replay с window_ms ограничивает возраст кеша; правила описаны ниже.

`rx_clone(hub)` присоединяется к существующей группе. Два отдельных вызова
`rx_share` над копиями одного source создают две независимые группы.
Общую работу, например map/tap или запуск Task, помещайте **до** share;
операторы после него исполняются отдельно для каждого подписчика.

Синхронный источник может успеть завершиться до второго обычного subscribe:
у share это будут два запуска, у share_replay второй получит завершённый кеш.
Подписка из активного callback регистрируется сразу, но запуск новой группы
откладывается до завершения старой рассылки, cleanup и синхронного connect.
Повторные синхронные переподключения обрабатываются итеративно. Уже закончившееся
поколение не может отменить новое подключение своими запоздалыми cleanup.

Сброс не перезапускает закрытых подписчиков автоматически. Для повторов текущей
подписки нужен retry; для новых ресурсов на каждое подключение — rx_defer или
фабрика Task. При переподключении используется исходный Observable descriptor.
Уже завершённый горячий источник сам по себе новых данных не создаёт.

Native исключения отличаются от on_error. Исключение connect или observer при
живой общей рассылке закрывает неработающее поколение и сбрасывает его кеш;
остальные подписчики закрываются без искусственного error/complete, исключение
передаётся вызывающему. При ошибке observer текущая рассылка сначала достигает
других подписчиков. Ошибка отдельного позднего подписчика при replay закрывает
только его подписку и не уничтожает успешный кеш или живое подключение остальных.

Ресурсы подключения освобождаются при его завершении, ошибке или отмене последним
подписчиком. Исходный descriptor и успешно завершённый Replay-кеш принадлежат
hub и живут до удаления последнего его владеющего handle. Активные подписки
удерживают hub, поэтому исходную переменную можно удалить до их завершения.

## Публичные операции

| API | Назначение |
|---|---|
| `rx_range(first,count)` | Холодный синхронный диапазон int; проверяет размер и переполнение |
| `rx_from_array(values)` | Холодный источник из собственного снимка массива |
| `rx_defer(factory)` | Вызывает owning lambda-фабрику нового Observable для каждой подписки |
| `rx_just(value)` | Холодный источник: один next, затем complete |
| `rx_empty(type<T>)` | Немедленный complete без значений |
| `rx_throw(message,type<T>)` | Немедленный on_error с сообщением; не native panic |
| `rx_subject(type<T>)` | Горячая рассылка текущим подписчикам |
| `rx_behavior_subject(initial)` | Горячий источник с начальным и текущим значением |
| `rx_replay_subject(type<T>,buffer_size)` | Горячий источник с FIFO последних buffer_size значений |
| `rx_behavior_value(subject)` | Копия текущего значения BehaviorSubject; после error выбрасывает исключение |
| `rx_subject_buffered_count(subject)` | Число сохранённых значений: 0 у обычного Subject, 1 у Behavior, до N у Replay |
| `source |> rx_map(selector)` | Преобразование, в том числе со сменой типа |
| `source |> rx_filter(predicate)` | Фильтрация |
| `source |> rx_take(count)` | Независимый счётчик на подписку; немедленная остановка по лимиту |
| `source |> rx_skip(count)` | Пропустить первые count элементов отдельно на каждой подписке |
| `source |> rx_take_while(predicate)` | Выдавать префикс до первого false; исключить этот элемент и завершить подписку |
| `source |> rx_skip_while(predicate)` | Пропустить префикс true, затем выдавать всё без повторного вызова predicate |
| `source |> rx_pairwise()` | Соседние элементы как tuple previous/current; первая пара после второго элемента |
| `source |> rx_finally(action)` | Один вызов owning lambda на каждую подключённую подписку при любом закрытии |
| `source |> rx_with_latest_from(other)` | Пара first/second только на next основного source, после первого other |
| `source |> rx_exhaust_map(selector)` | Один внутренний поток; новые outer значения игнорируются, пока он активен |
| `source |> rx_reduce(seed,reducer)` | Один итог на complete, включая seed для пустого потока; тип итога может отличаться |
| `source |> rx_first()` / `rx_last()` | Первый/последний элемент; пустой источник даёт on_error |
| `source |> rx_default_if_empty(value)` | Подставить value только при успешном пустом complete |
| `source |> rx_publish()` | Connectable Observable: подписки принимаются, источник запускается по rx_connect |
| `published |> rx_ref_count()` | Автоматические connect на первом и disconnect на последнем подписчике |
| `source |> rx_window(count[,skip])` | Горячие внутренние Observable для групп элементов |
| `source |> rx_group_by(key_selector[,max_groups])` | Горячая группа на каждый ключ; порядок появления ключей и значений сохраняется |
| `source |> rx_materialize()` | next/error/complete как обычные значения уведомлений; затем успешный complete |
| `source |> rx_dematerialize()` | Уведомления обратно в значения и terminal; encoded terminal немедленно останавливает upstream |
| `rx_notification_next(value)` / `rx_notification_error(message,type<T>)` / `rx_notification_complete(type<T>)` | Конструкторы уведомлений; `rx_notification(type<T>)` задаёт их тип и возвращает complete |
| `rx_group_key(group)` / `rx_group_marker(type<K>,type<T>)` | Снимок ключа группы / маркер типа для сигнатуры callback |
| `source |> rx_window_time(duration[,period],clock)` | Горячие внутренние Observable для временных окон |
| `source |> rx_take_until(notifier)` | Остановить источник по первому next другого потока |
| `source |> rx_tap(on_next[,on_error,on_complete])` | Побочные эффекты перед передачей соответствующего события дальше |
| `source |> rx_scan(seed,reducer)` | Накопитель на подписку, выдаёт новое состояние после каждого входного значения |
| `source |> rx_start_with(value)` | Синхронный префикс перед подключением источника |
| `source |> rx_distinct_until_changed([equal])` | Пропуск повторов относительно последнего выданного значения |
| `left |> rx_merge(right)` | Подключить оба входа и объединять события до завершения обоих |
| `left |> rx_concat(right)` | Подключить right после успешного завершения left |
| `left |> rx_combine_latest(right)` | После первого значения с каждого входа выдавать пары последних значений |
| `left |> rx_zip(right)` | Сопоставлять элементы двух входов по порядковому номеру |
| `source |> rx_switch_map(selector)` | Новый Observable на каждое значение; предыдущая внутренняя подписка отменяется |
| `source |> rx_flat_map(selector[,max_active])` | Объединяет внутренние потоки; при лимите ожидающие значения хранятся в FIFO |
| `source |> rx_concat_map(selector)` | Последовательные внутренние подписки, эквивалент flat_map с лимитом 1 |
| `source |> rx_share()` | Одно refcounted подключение на группу; сброс по error/complete/последней отписке |
| `source |> rx_share_replay([buffer_size])` | Общая подписка с ограниченным кешем; successful complete сохраняется; размер по умолчанию 1 |
| `rx_timer(duration_ms,scheduler)` | Один int64 со значением 0 после задержки, затем complete |
| `rx_interval(period_ms,scheduler)` | Последовательность int64 0, 1, 2, …; первая выдача после периода |
| `source |> rx_delay(duration_ms,scheduler)` | Задерживает next/complete; error передаётся немедленно |
| `source |> rx_debounce(duration_ms,scheduler)` | Последнее значение после паузы; при complete выдаёт остаток сразу |
| `source |> rx_timeout(duration_ms,scheduler)` | Ошибка при паузе от подписки или последнего next |
| `source |> rx_observe_on(scheduler[,rx_queue(...)])` | Доставка next/error/complete через планировщик; очередь по умолчанию 256 значений |
| `source |> rx_subscribe_on(scheduler)` | Подключение источника через планировщик; отписка немедленная |
| `source |> rx_catch_error(handler)` | При on_error переключается на Observable, возвращённый owning lambda handler(message) |
| `source |> rx_retry(retries,delay_ms,scheduler)` | Не более retries дополнительных подписок после ошибок, с постоянной задержкой |
| `rx_clone(source)` | Дополнительный владеющий descriptor того же источника |
| `rx_subscribe(source,on_next,on_error,on_complete)` | Подключение трёх owning lambdas; возвращает RxSubscription |
| `rx_subscription()` + `rx_subscribe_with(control,source,...)` | Создать control до начала синхронной выдачи; подключить можно один раз |
| `rx_unsubscribe`, `rx_is_closed` | Остановка и состояние подписки |
| `rx_add_cleanup(subscription,action)` | Передать owning lambda освобождения ресурсов |
| `rx_subject_next`, `rx_subject_complete`, `rx_subject_error` | Уведомления Subject |
| `rx_subscriber_count(subject)` | Число активных подписчиков |

`take(0)` завершает подписку без подключения к источнику и без вызова defer-фабрики.
Состояние take создаётся для каждой подписки. Пользовательский stateful selector
и его захваченные данные принадлежат descriptor и разделяются подписками.
Если каждому запуску нужны новые captures, создавайте цепочку внутри `rx_defer`.

## Остановка по сигналу

```das
var inscope clock <- rx_virtual_scheduler()
var inscope closeWindow <- rx_subject(type<string>)
var inscope updates <- rx_interval(10,clock) |> rx_take_until(rx_clone(closeWindow))
var inscope sub <- rx_subscribe(updates,
    @(frame:int64) {print("update: {frame}\n")},
    @(message:string) {print("error: {message}\n")},
    @() {print("finished\n")})
rx_advance_by(clock,25) // update: 0, update: 1
rx_subject_next(closeWindow,"close") // finished; interval и его таймер закрыты
rx_advance_by(clock,100) // больше событий нет
```

Исполняемый пример: [take_until_demo.das](examples/take_until_demo.das).

`source |> rx_take_until(notifier)` сохраняет тип элементов source; у notifier
может быть другой тип. Значение сигнала не передаётся downstream. Сначала
подключается notifier: синхронный next завершает выход, а синхронный error
завершает его с ошибкой, **без подключения source**. Завершение notifier без
значений не останавливает source. Эти правила соответствуют
[takeUntil в RxJS](https://rxjs.dev/api/operators/takeUntil).

Первый next notifier вызывает complete и отписывает оба входа. Complete/error
основного источника также закрывает notifier; error любого входа передаётся
downstream. Обычная отписка закрывает оба входа без терминального уведомления.
Каждая подписка имеет собственные controls. Прошлый next горячего Subject не
воспроизводится при новой подписке.

При сигнале из активного on_next оба входа останавливаются сразу, но terminal
доставляется после возврата текущего callback, без вложенного вызова observer.
Ошибки очищают очередь значений; успешное завершение сохраняет порядок ранее
принятых значений. При синхронном connect terminal ожидает возврата connect,
включая позднюю регистрацию cleanup. Уже запущенный callback нельзя прервать:
он заканчивает выполнение, новые события игнорируются.

Cleanup обоих входов запускается даже при ошибке одного cleanup. При успешном
завершении ошибка cleanup остаётся native исключением и закрывает подписку;
при существующей ошибке входа сохраняется исходный on_error. Ошибки observer
и connect также распространяются как native исключения после закрытия входов.

## Merge и concat

```das
var inscope keyboard <- rx_subject(type<string>)
var inscope network <- rx_subject(type<string>)
var inscope mixed <- rx_clone(keyboard) |> rx_merge(rx_clone(network))
var inscope stages <- rx_range(1,2) |> rx_concat(rx_defer(@() {return <- rx_range(10,2)}))
```

Оба входа должны выдавать один тип элементов. Как другие операторы, merge/concat
забирают descriptors перемещением. Для повторного использования или двух веток
одного Subject нужны отдельные `rx_clone`. Передача одного owning handle дважды
отклоняется. Можно соединять разные виды источников и строить цепочки из трёх
и более входов: `a |> rx_merge(b) |> rx_merge(c)`.

| Поведение | merge | concat |
|---|---|---|
| Подписки | На left, затем на right без ожидания завершения left | Сначала только left, после его завершения right |
| Горячие события | Доставляются от обоих активных входов в порядке поступления | События right до подключения теряются; replay нет |
| Завершение | После завершения обоих входов | После последовательного завершения обоих |
| Ошибка | Немедленно останавливает оба входа | Останавливает текущий вход; следующий не запускается |
| Отписка / downstream take | Закрывает оба активных входа | Закрывает текущий; будущий не запускается |

Это соответствует обычным [Merge](https://reactivex.io/documentation/operators/merge.html)
и [Concat](https://reactivex.io/documentation/operators/concat.html), без delay-error.
Merge не добавляет потоки исполнения или scheduler: полностью синхронный left
успевает выдать значения до начала подключения right. Если downstream take или
ошибка завершат подписку при подключении left, right вообще не подключается.

Concat откладывает **подписку**, а выражение правого аргумента вычисляется при
построении цепочки. Чтобы отложить сам запуск производителя, используйте rx_defer.
При переключении сначала выполняется teardown первой подписки. Снимки текущей
рассылки и активные callback frames могут удерживать captures до своего выхода.
Ошибка teardown отменяет всю цепочку и не запускает следующий источник.

На каждый rx_subscribe создаются независимые управляющие состояния и счётчики
завершения. Ошибка любого входа отменяет детей сразу, даже при повторном входе
из on_next. Сам on_error доставляется после возврата из текущего on_next;
накопленные, ещё не доставленные значения при ошибке отбрасываются. Для merge
очередь сериализует повторные события даже от **разных** Subject. Обычные next
и complete проходят в порядке очереди; terminal выдаётся один раз.

Полный пример с одинаковыми горячими событиями для обоих операторов и отдельной
отложенной второй стадией: [merge_concat_demo.das](examples/merge_concat_demo.das).

## Combine_latest и zip

```das
var inscope temperatures <- rx_subject(type<int>)
var inscope rooms <- rx_subject(type<string>)
var inscope latest <- rx_clone(temperatures) |> rx_combine_latest(rx_clone(rooms))
var inscope pairs <- rx_clone(temperatures) |> rx_zip(rx_clone(rooms))
var inscope subscription <- rx_subscribe(latest,
    @(value:tuple<first:int;second:string>) {print("{value.first}: {value.second}\n")},
    @(message:string) {panic(message)},@(){})
rx_subject_next(temperatures,20)
rx_subject_next(temperatures,21)
rx_subject_next(rooms,"outside") // latest: (21,"outside"); zip: (20,"outside") при отдельной подписке
rx_subject_next(rooms,"inside")  // latest: (21,"inside"); zip: (21,"inside")
```

Операторы возвращают `tuple<first:L;second:R>`; типы входов могут различаться.
Нужное представление результата выбирается последующим `rx_map`. Descriptors
перемещаются; для повторного использования входа нужен `rx_clone`.
Полный пример с подпиской на обе цепочки: [latest_zip_demo.das](examples/latest_zip_demo.das).

| Поведение | combine_latest | zip |
|---|---|---|
| Первая пара | После первого значения с каждого входа | После первого значения с каждого входа |
| Следующие пары | При каждом next, с последним значением другого входа | По одному элементу из каждой FIFO-очереди |
| Завершившийся вход | Последнее значение остаётся доступным до завершения второго входа | Накопленные элементы остаются до сопоставления |
| Завершение результата | Оба входа завершились; либо один завершился без значения | Завершён хотя бы один вход и исчерпана его очередь |
| Память | Одно последнее значение каждого входа | Непарные элементы; без rx_queue очередь не ограничена |

Семантика пар соответствует [CombineLatest](https://reactivex.io/documentation/operators/combinelatest.html)
и [Zip](https://reactivex.io/documentation/operators/zip.html). Пустой завершившийся вход
немедленно завершает результат и отписывает другой вход. Подписки создаются слева
направо: синхронный cold left выдаст всё до подключения right. Поэтому latest
при первом событии right использует последнее значение cold left. Если left пуст
или завершился ошибкой, right не подключается. Это однопоточные push-операторы,
без планировщика и backpressure.

На каждую подписку создаются отдельные последние значения и очереди. Ошибка любого
входа немедленно отменяет оба подключения, удаляет буферы и недоставленные пары;
on_error получает исходное сообщение после возврата из активного on_next.
Обычное завершение сохраняет порядок уже подготовленных пар. Повторные вызовы
из callbacks сериализуются, пары сохраняют снимок на момент прихода события.
Отписка, удаление RxSubscription и downstream take закрывают оба входа и очищают
буферы. Исключения observer callbacks распространяются вызывающему после cleanup.

## Switch_map, flat_map и concat_map

Selector — owning lambda, возвращающая новый владеющий Observable descriptor.
Тип входного и выходного элемента может различаться. Горячий источник из capture
возвращается через `rx_clone`, а холодный можно создать прямо в selector:

```das
var inscope expanded <- rx_range(1,2) |> rx_flat_map(@(n:int) {return <- rx_range(n*10,2)})
var inscope subscription <- rx_subscribe(expanded,
    @(n:int) {print("{n}\n")},@(message:string) {panic(message)},@(){})
// 10, 11, 20, 21 — каждый внутренний диапазон синхронный.
```

Для переключения, например между потоками ответов на пользовательские запросы:

```das
var inscope requests <- rx_subject(type<int>)
var inscope first <- rx_subject(type<string>)
var inscope second <- rx_subject(type<string>)
var a <- rx_clone(first)
var b <- rx_clone(second)
var selector <- @ capture(<-a,<-b) (request:int) {
    if(request==1) {return <- rx_clone(a)}
    return <- rx_clone(b)
} finally {delete a;delete b}
var inscope responses <- rx_clone(requests) |> rx_switch_map(selector)
var inscope subscription <- rx_subscribe(responses,
    @(s:string) {print("{s}\n")},@(message:string) {panic(message)},@(){})
rx_subject_next(requests,1)
rx_subject_next(first,"first response")
rx_subject_next(requests,2) // отключает first перед вызовом selector(2)
rx_subject_next(first,"stale response") // не доставляется
rx_subject_next(second,"second response")
rx_subject_complete(requests) // ждёт second
rx_subject_complete(second)
```

Полное сравнение на одних событиях: [flat_switch_demo.das](examples/flat_switch_demo.das).
Семантика соответствует [FlatMap и SwitchMap](https://reactivex.io/documentation/operators/flatmap.html).

| Поведение | switch_map | flat_map |
|---|---|---|
| Новый внешний next | Закрывает старую внутреннюю подписку, затем вызывает selector и подключает новую | Вызывает selector и добавляет внутреннюю подписку к активным |
| Внутренние next | Только от текущего источника | От всех активных источников в порядке поступления |
| Завершение внешнего входа | Ждёт текущую внутреннюю подписку | Ждёт все активные внутренние подписки |
| Завершение внутреннего входа | Освобождает его подключение; внешний продолжает работать | Удаляет только завершившуюся подписку; остальные продолжают работать |
| Ошибка selector, внешнего или активного внутреннего входа | Останавливает всю цепочку | Останавливает всю цепочку |
| Отписка / удаление подписки / downstream take | Закрывает внешний и текущий внутренний вход | Закрывает внешний и все внутренние входы |

Без лимита selector вызывается сразу для каждого внешнего значения, при каждой подписке.
Его собственные captures принадлежат descriptor и разделяются подписками;
для отдельных captures на запуск используйте `rx_defer`. Списки внутренних
подписок независимы. Все возвращаемые selector Observable должны иметь один
статический тип descriptor; разные экземпляры Subject или диапазона допустимы.

Порядок доставки сериализован даже при повторных событиях из разных Subject.
При переключении switch_map удаляет ещё не доставленные события старой подписки;
уже исполняющийся on_next заканчивается обычным образом. Ошибка удаляет всю очередь
и отменяет входы немедленно, а on_error доставляется после активного on_next.
Ошибка отменённого внутреннего источника больше не влияет на результат.
Исключения observer callbacks закрывают всю цепочку и распространяются вызывающему.
Все подключения отменяются даже при ошибке одного teardown.

Вначале выполняется отписка от старого источника. Captures его callback могут
жить до возврата из уже активной рассылки; это сохраняет данные текущего кадра.
Завершившиеся синхронные внутренние источники удаляются после возврата из connect,
чтобы успел выполниться поздно зарегистрированный cleanup.

Операторы не добавляют потоки или scheduler. Синхронный внутренний источник
исполняется внутри текущего внешнего on_next; новые события того же Subject,
поставленные в очередь из callback, обрабатываются после его возврата.
У flat_map без второго аргумента число активных подписок не ограничено.
Backpressure и delay-error не поддерживаются.
Нельзя возвращать один owning descriptor повторно без `rx_clone`.

### Ограничение параллельных работ и последовательный обход

```das
var inscope clock <- rx_virtual_scheduler()
var serialClock <- rx_scheduler_clone(clock)
var parallelClock <- rx_scheduler_clone(clock)
var inscope serial <- rx_range(1,3) |> rx_concat_map(@ capture(<-serialClock) (id:int) {
    return <- rx_timer((4-id)*10,serialClock) |> rx_map(@ capture(copy(id)) (tick:int64) {return id})
} finally {delete serialClock})
var inscope parallel <- rx_range(1,3) |> rx_flat_map(@ capture(<-parallelClock) (id:int) {
    return <- rx_timer((4-id)*10,parallelClock) |> rx_map(@ capture(copy(id)) (tick:int64) {return id})
} finally {delete parallelClock},2)
var inscope a <- rx_subscribe(serial,@(id:int) {print("serial: {id}\n")},@(s:string) {panic(s)},@() {})
var inscope b <- rx_subscribe(parallel,@(id:int) {print("parallel: {id}\n")},@(s:string) {panic(s)},@() {})
rx_advance_by(clock,100)
// serial: 1, 2, 3. parallel: 2, 1, 3.
```

Полный пример: [concat_flat_limit_demo.das](examples/concat_flat_limit_demo.das).

`rx_flat_map(selector,max_active)` принимает положительный int. При заполнении
лимита следующие внешние **значения** сохраняются в FIFO отдельно для каждой
подписки. Selector и создание внутреннего Observable откладываются до появления
свободного слота. Завершение любого внутреннего потока запускает следующий
ожидающий элемент после его cleanup; ждать завершения всей группы не нужно.
Лимит ограничивает подписки, а не число потоков ОС: эти операторы сами не
добавляют scheduler или многопоточность.

`rx_concat_map(selector)` — тот же механизм с лимитом 1: сохраняются порядок
вызовов selector и последовательность внутренних потоков. Flat_map с лимитом
больше 1 выдаёт результаты по времени поступления; порядок исходных работ
не гарантируется. Синхронные потоки могут завершаться до получения следующего
внешнего значения, поэтому фактическое число одновременно активных подписок
может оказаться меньше лимита. Если selector возвращает горячий поток,
его события до отложенного подключения не воспроизводятся.

Завершение внешнего входа ждёт активные подписки **и очередь**. Ошибка внешнего
или внутреннего входа, ошибка selector, отписка и downstream take отменяют
активные подключения и очищают очередь без вызова selector для оставшихся
значений. Исключения observer/connect/cleanup распространяются после закрытия
подписки; ошибка cleanup не запускает следующую работу. При реентерабельных
selector/cleanup сохраняются лимит и FIFO. Большая очередь синхронно
завершающихся потоков обрабатывается итеративно.

Сам по себе лимит активных подписок **не ограничивает размер очереди** и не
замедляет внешний источник. Ограничение ожидания задаётся отдельным аргументом
`rx_queue(capacity, policy)`, см. раздел «Ограничения очередей».

## Планировщик и виртуальное время

Перенос подключения и доставки: [observe_on / subscribe_on](SCHEDULING.md).

`rx_scheduler.das` можно подключить отдельно; `reactivex.das` экспортирует его
публично. Время — неотрицательные монотонные миллисекунды `int64`; длительности
принимают `int` и `int64`. Ни фонового потока, ни sleep в планировщике нет.
В приложении передавайте его монотонное время в `rx_tick` из цикла кадров/событий:

```das
var inscope clock <- rx_scheduler(1000)
var inscope ticks <- rx_interval(10,clock) |> rx_take(2)
var inscope subscription <- rx_subscribe(ticks,
    @(n:int64) {print("tick: {n}\n")},@(message:string) {panic(message)},@(){})
rx_tick(clock,1016)
rx_tick(clock,1032)
verify(rx_is_closed(subscription))
```

Начальное время задаётся до создания подписок; по умолчанию это 0.
Все просроченные действия pumped scheduler исполняются при переданном now_ms.
Interval назначает следующий период от фактической выдачи: при позднем кадре
он не воспроизводит сразу все пропущенные тики.

В тестах виртуальные часы исполняют действия на точных сроках, без ожидания:

```das
var inscope clock <- rx_virtual_scheduler()
var inscope source <- rx_interval(5,clock) |> rx_take(3)
var inscope subscription <- rx_subscribe(source,
    @(n:int64) {print("virtual: {n}\n")},@(message:string) {panic(message)},@(){})
rx_advance_to(clock,15) // события на 5, 10, 15 мс
verify(rx_is_closed(subscription) && rx_pending_count(clock)==0)
```

| API | Контракт |
|---|---|
| `rx_scheduler(start_ms=0)` | Владелец планировщика для `rx_tick` |
| `rx_virtual_scheduler(start_ms=0)` | Владелец виртуальных часов для `rx_advance_to/by` |
| `rx_scheduler_clone(clock)` | Удерживает хранение, но не предотвращает закрытие владельцем |
| `rx_now_ms(clock)` | Последнее принятое время, либо срок текущего виртуального действия |
| `rx_schedule(clock,delay_ms,action[,on_close])` | Owning lambdas; возвращает RxScheduledId, привязанный к этому scheduler |
| `rx_cancel(clock,id)` | Удаляет ожидающее действие и captures, не вызывает action/on_close; повторно false |
| `rx_tick(clock,now_ms,max_actions=10000)` | Продвигает обычный scheduler; возвращает число вызванных actions |
| `rx_advance_to(clock,target_ms,max_actions=10000)` | Исполняет виртуальные действия со сроком до target включительно |
| `rx_advance_by(clock,duration_ms,max_actions=10000)` | Относительное продвижение виртуальных часов |
| `rx_pending_count(clock)` | Число ожидающих действий |
| `rx_on_scheduler_close(clock,action)` | Owning callback закрытия, даже без pending timers; возвращает ID для rx_cancel |
| `rx_close_listener_count(clock)` | Число обработчиков закрытия, отдельно от ожидающих действий |
| `rx_scheduler_close`, `rx_scheduler_closed` | Закрытие и состояние; повторное закрытие безопасно |

При одинаковом сроке действует порядок регистрации, включая действия с нулевой
задержкой, добавленные из другого action. Нулевая задержка не вызывает callback
внутри rx_schedule: нужен tick/advance. Отрицательные длительности, переполнение
срока, время назад, неверный режим и повторный tick того же scheduler из callback
отклоняются. Для бесконечных источников используйте конечный target или take.

Бюджет actions ограничивает один вызов. При исчерпании бюджета виртуальное время
остаётся на последнем исполненном сроке, если до target ещё есть работа;
повторный advance_to с тем же target продолжает её. В обычном scheduler now_ms
уже равен переданному кадру. Ошибка action освобождает его captures и прерывает
текущий pump; флаг busy снимается, оставшиеся действия можно продолжить новым вызовом.

Удаление первичного `var inscope clock` закрывает scheduler независимо от clones.
Закрытие отсоединяет очередь и обработчики закрытия; сначала вызывает обработчики,
затем каждый pending on_close, даже если предыдущий
бросил исключение, затем освобождает callbacks и передаёт первую ошибку.
Активные временные Observable получают `on_error("rx scheduler closed")`, закрывая
свои входы, в том числе простаивающие delay/debounce без единого таймера.
Регистрация rx_on_scheduler_close на закрытом scheduler вызывает callback сразу
и освобождает его. Обычная отмена запланированного действия или обработчика
закрытия через rx_cancel не вызывает этот callback.
Первичный clock должен жить до завершения подписок; captures его копий и pending
actions сами по себе не продолжают работу после удаления владельца.

## Временные операторы

```das
var inscope clock <- rx_virtual_scheduler()
var inscope input <- rx_subject(type<int>)
var inscope stable <- rx_clone(input) |> rx_debounce(10,clock) |> rx_delay(2,clock)
var inscope subscription <- rx_subscribe(stable,
    @(n:int) {print("stable: {n}\n")},@(message:string) {panic(message)},@(){})
rx_subject_next(input,1)
rx_advance_to(clock,5)
rx_subject_next(input,2)
rx_advance_to(clock,17) // только 2: debounce на 15, delay до 17
rx_subject_complete(input)
rx_advance_to(clock,19)
verify(rx_is_closed(subscription))
```

Timer/interval холодные: счётчик и срок начинаются с подписки. Interval требует
положительный период; остальные длительности могут быть нулевыми. Delay хранит
все ожидающие значения; debounce — только последнее. Timeout запускает watchdog
до подключения входа и заменяет его после каждого next; при срабатывании выдаёт
`on_error("rx timeout")` и отменяет вход. Синхронный источник может успешно
завершиться до первого pump даже при timeout(0).

[Delay](https://reactivex.io/documentation/operators/delay.html) сдвигает next и
complete, но при error немедленно удаляет ожидающие значения.
[Debounce](https://reactivex.io/documentation/operators/debounce.html) при complete
сразу выдаёт последнее ещё не выданное значение, затем complete; при error
остаток удаляется. Эти notifications сериализуются с активным callback.
На границе срока определяет порядок операций: advance_to сначала выполнит все
действия со сроком <= target, а последующий вызов Subject происходит после них.

Завершение, ошибка, take и отписка удаляют соответствующие таймеры и callbacks.
Delay может продолжать выдачу после завершения входа, пока не доставит очередь
и отложенный complete. Без аргумента rx_queue объём очереди delay не ограничен. Пример обоих видов часов
и всех временных операторов: [time_demo.das](examples/time_demo.das).

## Адаптеры CE Task

Подключите `require ../lib/reactivex_task.das`. Для синтаксиса computation отдельно
нужен `computation_expressions/lib/computation_macro.das`, как в CE-примерах.
Модуль ядра reactivex.das по-прежнему можно использовать без CE.

| API | Результат |
|---|---|
| `rx_first_task(source)` | Холодная Task<Result<T,string>>, ожидающая первое значение Observable |
| `rx_from_task(factory,clock,poll_ms=1)` | Холодный Observable<T>: новая owning Task<T> из factory на подписку |
| `rx_from_task_result(factory,clock,poll_ms=1)` | Observable<T>: Task<Result<T,string>> с преобразованием domain Error в on_error |

Rx → Task подписывается при первом poll. Первое значение защёлкивается и сразу
отключает Rx-подписку. Callback Rx не запускает продолжение Task: результат
читается текущим poll при синхронной подписке либо следующим poll при внешнем событии.
Завершение без значения возвращает Result.Error("rx: source completed without value"),
on_error возвращает Result.Error с исходным сообщением. В TaskResultBuilder это
останавливает дальнейшие шаги через обычный `|> bind`. В TaskBuilder можно
получить сам Result. Прямая отмена, CancellationToken и таймаут TaskScheduler
удаляют Rx-подписку и сохраняют стандартный статус Cancelled. Удаление неполученной
Task также закрывает её ожидание; отмена до первого poll вообще не подписывается.

Task → Rx вызывает factory при подписке, а первый poll назначает на ближайший
pump с нулевой задержкой. Затем Task получает один poll каждые poll_ms, пока
не завершится. Период должен быть положительным. Factory должна возвращать
новую owning Task для каждой подписки; уже запущенную Task с чужими часами
переносить сюда не следует. Task delay использует время Rx scheduler, поэтому
`task_delay_ms(...) |> bind` работает и под виртуальными часами без TaskScheduler.
Это кооперативный опрос, не перенос работы в другой поток.
Если приложение использует и TaskScheduler, и RxScheduler, его цикл продвигает
оба планировщика. Принадлежащую rx_from_task задачу отдельно в TaskScheduler
регистрировать не нужно: её опросом и владением занимается адаптер.

Успешная Task выдаёт один next и complete; Failed вызывает on_error с сообщением,
Cancelled вызывает on_error("rx task cancelled"). В rx_from_task обычный
Result является значением; rx_from_task_result выдаёт ok как next и error как
on_error. Ошибка factory тоже вызывает on_error. Обычная отписка от Observable
отменяет его Task и будущие polls, без terminal notification. Закрытие scheduler,
внешний timeout и switch_map отменяют соответствующие Task и освобождают captures.
Если отписка произошла внутри текущего Task poll, отмена завершается сразу после
его возврата, чтобы не удалять исполняемый generator. Ошибки cleanup передаются
по общим правилам Rx/Task. Результаты должны соответствовать копируемому owning
payload Rx; move-only результаты Task нельзя рассылать через этот адаптер.

Полный пример `ввод → debounce → switch_map(Task) → timeout` и ожидания действия
через пайповый bind: [time_task_demo.das](examples/time_task_demo.das).
Повторная подписка создаёт новую Task; captures самой factory разделяются, как
у rx_defer. Для внешнего ввода/вывода factory может вернуть существующую CE Task
с адаптером сетевой операции; отписка вызовет её стандартный cleanup.

## Восстановление после ошибок

Ошибки как данные: [materialize / dematerialize](NOTIFICATIONS.md).

```das
var inscope clock <- rx_virtual_scheduler()
var inscope source <- rx_defer(@(){return <- rx_throw("offline",type<int>)}) |> rx_retry(2,10,clock) |> rx_catch_error(@(message:string) {return <- rx_just(42)})
var inscope subscription <- rx_subscribe(source,
    @(n:int) {verify(n==42)},@(message:string) {panic(message)},@(){})
rx_advance_to(clock,20) // первая попытка на 0, повторы на 10 и 20; затем fallback
verify(rx_is_closed(subscription))
verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
```

Семантика [Catch](https://reactivex.io/documentation/operators/catch.html):
значения исходного входа проходят до ошибки. Затем его подключение закрывается
и handler один раз получает сообщение; возвращённый Observable становится новым
входом. Тип элемента сохраняется, но вид descriptor может отличаться от исходного.
На успешном complete handler не вызывается. Ошибка fallback передаётся дальше,
а не вызывает тот же handler ещё раз. Исключение из handler преобразуется в
on_error; возвращённый moved/deleted descriptor также даёт on_error.
Для дальнейшего восстановления можно добавить следующий rx_catch_error.

До вызова handler выполняется teardown неудачного подключения. Для синхронного
источника переключение ждёт возврата из connect, включая поздний cleanup.
В горячей рассылке callbacks и их captures могут оставаться на стеке до возврата
из текущего publish, хотя подписка уже снята. Сам handler и его captures принадлежат
descriptor; отдельные подписки имеют независимое состояние переключения.
Как у switch_map, handler должен иметь один статический тип возвращаемого descriptor.

Семантика [Retry](https://reactivex.io/documentation/operators/retry.html):
при on_error оператор повторно подписывается на исходный descriptor. `retries`
считает **дополнительные** попытки: 0 — одна исходная подписка, 2 — максимум три.
Бюджет не сбрасывается после next. Successful complete завершает всю цепочку;
после исчерпания попыток передаётся последнее сообщение on_error.
Значения предыдущих попыток не откатываются и могут повторяться при новой подписке.

Первое подключение выполняется при rx_subscribe. Каждый повтор, даже при delay_ms=0,
ставится в scheduler после cleanup предыдущего подключения. Нужен tick/advance;
рекурсивного subscribe из синхронного on_error нет. Это позволяет ограничить
число действий бюджетом scheduler и отменить даже длинную цепочку мгновенных ошибок.
Задержка отсчитывается от обработки ошибки. На pumped scheduler повтор может
начаться позже срока, в следующем кадре; виртуальные часы исполнят его точно на сроке.
Отрицательные retries/delay отклоняются, бесконечных повторов нет. Predicate и backoff доступны через дополнительные перегрузки, описанные ниже.

Retry не создаёт новый источник самостоятельно. Для нового соединения и ресурсов
на каждую попытку используйте rx_defer или rx_from_task[_result] с фабрикой новой
Task. Повторная подписка на завершившийся ошибкой Subject снова получит его
сохранённую ошибку; она не перезапускает Subject. Переподписка восстанавливает
соединение, но не отменяет уже совершённые внешние эффекты.

Отписка, удаление RxSubscription и downstream take закрывают активную попытку
и удаляют ожидающий повтор и обработчик закрытия scheduler. Отмена не вызывает
on_complete/on_error. Закрытие scheduler отменяет как активную попытку, так и
ожидание повтора, выдавая on_error("rx scheduler closed"). Подписка с уже закрытым
scheduler сразу получает эту ошибку, не подключая вход, в том числе при retries=0.
Ошибка планирования, например переполнение срока, тоже завершает цепочку.

Catch/retry реагируют на **on_error**. Исключения observer callbacks или teardown
распространяются вызывающему и не вызывают повтор или fallback. Если teardown
неудачной попытки бросил исключение, дальнейшее восстановление прекращается.
rx_map/rx_filter/rx_defer и Task-адаптеры сами преобразуют свои ошибки в on_error,
поэтому они совместимы с recovery. Фабрика низкоуровневого rx_create должна
сигнализировать ошибки через rx_sink_error; её native panic не является on_error.
Доставка downstream notifications сериализуется даже при закрытии scheduler из on_next.

Порядок операторов определяет политику: `retry |> catch_error` сначала исчерпывает
попытки, затем подключает fallback; `catch_error |> retry` повторяет всю цепочку,
если fallback тоже завершился ошибкой. Вложите recovery внутрь selector switch_map,
если ошибка отдельного запроса не должна завершать внешний поток действий пользователя.

Примеры: [recovery_demo.das](examples/recovery_demo.das) и
[task_recovery_demo.das](examples/task_recovery_demo.das). Второй использует
TaskResultBuilder с пайповым bind, задержку Task, успешную третью попытку,
кэшированный ответ после исчерпания попыток и отмену во время ожидания повтора.

## Создание собственного источника

`rx_create(type<T>,factory)` вызывает factory с заимствованным sink на подписку.
Это точка расширения, используемая Task-адаптером:

```das
var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
    rx_sink_next(sink,42)
    rx_sink_complete(sink)
})
var inscope subscription <- rx_subscribe(source,
    @(n:int) {verify(n==42)},@(message:string) {panic(message)},@(){})
verify(rx_is_closed(subscription))
```

Для отложенных callbacks удерживайте sink через rx_sink_clone и удаляйте capture
в native finally. До запуска операции зарегистрируйте teardown через
rx_sink_add_cleanup(sink,action). Операции rx_sink_next/error/complete и
rx_sink_stopped соблюдают общий контракт observer. Factory не должна сохранять
заимствованный параметр без clone; у source, возвращённого через rx_create,
все подписки вызывают одну factory с её общими captures.

## Контракт и владение

Основа — [Observable Contract ReactiveX](https://reactivex.io/documentation/contract.html):
последовательность next, затем не более одного complete/error. Отписка останавливает
дальнейшую доставку и освобождает подключение. Уведомления исполняются последовательно
в одном контексте daScript. Нельзя вызывать API одновременно из нескольких потоков.

Повторный `rx_subject_next` из callback ставится в очередь и выполняется после
текущего события. На каждое уведомление берётся снимок подписчиков. Подписчик,
добавленный во время текущей рассылки, начинает со следующего уведомления;
отписавшийся до своей очереди не получает текущий next. Порядок доставки —
порядок регистрации. Subject не ведёт replay и не предоставляет backpressure.

Ошибка selector/predicate/defer-фабрики вызывает `on_error` и останавливает
источник. Исключение пользовательского observer callback закрывает его подписку
и распространяется вызывающему `rx_subscribe`/`rx_subject_next`/terminal-операции.
Оно не превращается в дополнительный on_error. При рассылке Subject остальные
подписчики всё равно получают свои уведомления, очередь остаётся работоспособной.

Cleanup выполняется один раз: после terminal callback либо при отписке/удалении
подписки. Если добавить cleanup после закрытия, он вызывается сразу. Все
зарегистрированные actions вызываются в порядке регистрации, даже если один бросил
исключение; после освобождения передаётся первая ошибка. Ошибка observer callback
имеет приоритет над ошибкой cleanup. Пользовательские финализаторы захваченных
данных должны освобождать ресурсы без исключений.

Callbacks и фабрики передаются как owning `@` lambdas, а не стековые `$` blocks.
Библиотека удаляет переданные lambdas и вызывает их native `finally`. daScript
не освобождает произвольные move-захваты lambda автоматически: для массива,
собственного владеющего handle и подобных captures нужен явный `finally`:

```das
var offsets:array<int>
offsets <- [10]
var selector <- @ capture(<-offsets) (n:int) {return n+offsets[0]} finally {delete offsets}
var inscope source <- rx_range(1,3) |> rx_map(selector)
```

Переданный selector может пережить исходную локальную переменную. Активная
подписка удерживает нужную цепочку и callbacks даже после удаления внешнего
Observable descriptor. При этом descriptor Subject сам по себе не является
подпиской: для завершения всех listeners вызывайте complete/error либо удаляйте
их RxSubscription.

Broadcast payload пока должен быть копируемым и самостоятельно хранить данные.
Исключения — заимствованные пакеты buffer и дескрипторы window: правила описаны в разделах о владении пакетами и окнами.
Числа, строки, подходящие структуры/tuple/variant поддержаны. Move-only массив
может быть снимком `rx_from_array` или захватом callback, но не отдельным элементом
потока. Вложенные указатели, ссылки, handles, callbacks и iterator в payload
отклоняются диагностикой. Поддержка move-only событий потребует отдельной модели
передачи/разделения владения для нескольких подписчиков.

## Запуск и проверки

```powershell
./reactivex/run.ps1
./reactivex/run.ps1 -Test
./reactivex/run.ps1 -Test -Jit
./reactivex/run.ps1 -Test -AotGenerate
./reactivex/run_aot.ps1
```

Используется `$env:DASLANG_EXE`, либо локальный SDK 0.6.5-RC2.
Можно явно передать `-Daslang <путь к daslang.exe>`.
AotGenerate проверяет только генерацию C++, без сборки/исполнения AOT-хоста.
Успех интерпретатора, JIT, генерации C++ и исполнения AOT учитывается раздельно.

`run_aot.ps1` требует CMake и Visual Studio 2022 с C++ x64 и Windows SDK.
Он генерирует C++, собирает Release-хост и запускает каждый положительный script
в отдельном процессе. Используется тот же SDK, что указан через `-Daslang` или
`DASLANG_EXE`; его CMake package обязателен. Параметры `-BuildDirectory`,
`-OutputDirectory` и `-Parallel` (по умолчанию 2) управляют сборкой и отчётами.
Список `scripts.ps1` общий для всех режимов: все 20 примеров и 42 положительных
наборов, включая Task и три набора адаптеров AsyncSequence. Отрицательные
compile-проверки исполняются через `run.ps1 -Test`, в AOT-хост они не включаются.

Хост включает `fail_on_no_aot` и дополнительно проверяет `main->aot` перед вызовом.
Используется общий с CE recovery workaround для SDK 0.6.5-RC2
(`computation_expressions/aot_host/recover_064.h`). Явно помеченный `[no_aot]`
helper проверки string GC остаётся интерпретируемым: SDK запрещает `heap_collect`
в native функции с owning iterator locals. Остальной код проверяется строгим
AOT-связыванием; это ограничение явно сохраняется, а не маскируется fallback.

Логи каждого запуска и `runtime-summary.json` находятся по умолчанию в
`reactivex/.work/aot-runtime`. Отдельная CI job `reactivex-aot` собирает и исполняет
этот же набор при push/PR; отчёты и transcript сборки загружаются как artifact.

Исполнение AOT также проверяет строковый `rx_first_task`: тип payload в pending
Result нормализуется без временного `const`, иначе SDK генерирует несовместимые
C++ TVariant для ожидания и готового значения. Регрессия в test_task_adapters
проверяет next, complete без значения, error и cancel для строкового источника.

42 положительных набора и 20 примеров проверяют cold/hot семантику, повторные подписки,
составные изменения типов, terminal-события, ошибки операторов и observers,
реентерабельность, изменение списка подписчиков, RAII/явную отписку, cleanup
после завершения и ошибки cleanup. Повторные циклы проверяют стабильный heap;
счётчики финализаторов подтверждают освобождение captures. Десять отрицательных
проверок отклоняют move-only, вложенные заимствованные payload и несовпадающие
типы входов merge/concat или catch fallback, а также move-only результат Task-адаптера. Наборы test_combine и test_combine_lifetime
проверяют холодные и горячие входы, порядок подключения/событий, повторные
подписки, ошибки обоих источников и фабрик, отписку на разных стадиях, take,
реентерабельные next/error/complete и освобождение ресурсов/heap после повторений.
Наборы test_latest_zip и test_latest_zip_lifetime дополнительно проверяют
FIFO/последние значения, неодинаковые типы и длины входов, пустые входы,
сохранение буферов после завершения одного входа, ошибки обоих входов и фабрик,
исключения observers/cleanup, удаление descriptor во время подписки и освобождение
captures/heap после завершения, ошибок, take и явной/автоматической отписки.
Наборы test_flat_switch и test_flat_switch_lifetime проверяют отмену предыдущего
внутреннего входа перед selector, объединение нескольких активных входов,
ожидание их завершения после внешнего complete, ошибки selector/фабрики/входов,
отписку и take, независимые подписки, вложенные преобразования со сменой типов,
реентерабельное переключение/error, удаление descriptor и освобождение ресурсов
при отмене уже исполняющегося callback. Проверяются счётчики финализаторов
и стабильность heap после повторных запусков, включая длинные серии внутренних connect.
test_scheduler проверяет FIFO сроков, отмену, budget, ошибки callbacks,
закрытие и монотонность/переполнение часов. test_time/test_time_lifetime проверяют
границы сроков, режимы interval, debounce flush, немедленный error delay,
watchdog reset, отписку и освобождение таймеров/ресурсов. Task-наборы проверяют
оба направления, пайповый bind, domain Error/Failed/Cancelled, таймауты обоих
планировщиков, токены, повторные подписки, владение captures и отмену во время poll.
test_recovery/test_recovery_lifetime проверяют базовые источники, handler/fallback,
порядок значений до и после ошибки, лимиты и сроки повторов, последнее сообщение,
нулевую задержку с бюджетом, teardown перед переключением, отмену активной попытки
и ожидания, ошибки callbacks/cleanup, закрытый scheduler, повторные подписки,
изменение типов в соседних операторах, счётчики финализаторов и стабильность heap.

test_stateful_operators/test_stateful_lifetime проверяют порядок эффектов tap,
префикс до connect и остановку на нём, независимое состояние scan/distinct,
смену типа накопителя, стандартное и пользовательское сравнение, ошибки всех
callbacks, реентерабельные события, удаление descriptor во время подписки,
завершение/take/отписку/исключения, счётчики финализаторов и стабильность heap.

test_take_until/test_take_until_lifetime проверяют порядок подключения и событий,
разные типы входов, синхронную остановку до запуска source, пустой notifier,
ошибки обоих входов, независимые подписки, реентерабельный сигнал, совпадение
сроков таймеров, отписку/take/RAII, ошибки observer/connect/cleanup,
поздний cleanup, счётчики финализаторов и стабильность heap.

test_concat_flat_limit/test_concat_flat_lifetime проверяют лимиты 1/2/3,
последовательность selector и результатов, заполнение освободившегося слота,
ожидание очереди после внешнего complete, горячие источники, строковые значения,
большой синхронный backlog, ошибки входов/selector/factory/connect/observer/cleanup,
реентерабельные selector и teardown, take/отписку/RAII, освобождение таймеров,
captures и heap.

test_subject_variants/test_subject_variant_lifetime проверяют начальное/текущее
значение, поздние подписки до и после terminal, ограничение и вытеснение истории,
строки, FIFO и реентерабельные подписки/события, take и отписку во время replay,
ошибки callbacks/cleanup, удаление исходного descriptor, освобождение snapshots,
captures и heap после повторных запусков. Сохранность строк истории при явном
string GC проверяется в helper `[no_jit, no_aot]`: SDK запрещает `heap_collect`
в native функции с владеющими iterator locals. Остальные проверки этого набора
исполняются в выбранном режиме; генерация C++ учитывается отдельно от AOT runtime.

test_share/test_share_lifetime проверяют одно подключение для нескольких
подписчиков, независимые группы, кеш и все правила сброса, refcount/take/RAII,
синхронные источники и поздний cleanup, реентерабельные подписки и 64 повторных
переподключения, ошибки connect/observer/cleanup, изоляцию ошибки replay,
удаление исходного handle, счётчики финализаторов и стабильность heap.

## Бенчмарки

`./reactivex/run_benchmarks.ps1 -Mode All` сравнивает Rx с ручным кодом
в интерпретаторе, JIT и исполняемом AOT: время, накопительные выделения
и байты на входное событие, подписку или создаваемую цепочку.
Проверяются одинаковые результаты и отсутствие оставшейся памяти heap.
Методика и ограничения: [benchmarks/README.md](benchmarks/README.md).
Для Subject есть сценарии с 1, 2, 8 и 32 подписчиками и
[сравнение оптимизации рассылки](benchmarks/SUBJECT_FANOUT_OPTIMIZATION.md).
Цепочки и пачки повторных событий из callback измеряются отдельно:
[оптимизация очереди Subject](benchmarks/SUBJECT_REENTRANT_OPTIMIZATION.md).
BehaviorSubject, ReplaySubject и стоимость replay при подписке:
[сравнение до/после](benchmarks/CACHED_SUBJECT_OPTIMIZATION.md).
Создание подписок: [сравнение до/после](benchmarks/SUBSCRIPTION_OPTIMIZATION.md).

## Следующие этапы

- Backpressure и многопоточные планировщики — отдельные расширения модели.
- Интеграции с UI-циклом и сетевыми источниками готовы: [INTEGRATIONS.md](INTEGRATIONS.md), включая [исполнение AOT](AOT_INTEGRATIONS.md).
- Расширение бенчмарков на планировщики, очереди и адаптеры AsyncSequence;
  оптимизация расходов, обнаруженных в базовых измерениях.

## Ограничения очередей

Прежние перегрузки сохраняют неограниченные очереди. Для ограничения числа
**элементов** добавьте `rx_queue(capacity, policy)`; capacity должен быть больше
нуля. Политика по умолчанию — `RxOverflowPolicy.error`.

| Оператор | Вызов через пайп | Что ограничено |
|---|---|---|
| flat_map | `source |> rx_flat_map(selector, max_active, rx_queue(32, policy))` | Ожидающие внешние значения, отдельно от max_active исполняемых подписок |
| concat_map | `source |> rx_concat_map(selector, rx_queue(32, policy))` | Ожидающие внешние значения; одна исполняемая подписка |
| zip | `left |> rx_zip(right, rx_queue(32, policy))` | Отдельная очередь непарных значений каждого входа |
| delay | `source |> rx_delay(100, clock, rx_queue(32, policy))` | Значения, ожидающие срока доставки |

- `RxOverflowPolicy.error`: единственный `on_error` с сообщением
  `rx_flat_map: queue overflow` (также для concat_map), `rx_zip: queue overflow`
  либо `rx_delay: queue overflow`. Активные подписки закрываются, ожидающие
  значения и таймеры освобождаются; complete после ошибки не вызывается.
- `RxOverflowPolicy.drop_oldest`: освобождается самое старое ожидающее значение,
  принимается новое. У delay сразу отменяется таймер вытесненного значения.
- `RxOverflowPolicy.drop_latest`: новое значение игнорируется, прежняя очередь
  сохраняется. Для отброшенного значения не создаётся таймер/внутренняя подписка.

Лимит относится к каждой подписке независимо. Активные flat_map/concat_map jobs
не вытесняются; selector отброшенных ожидающих значений не вызывается.
При zip после отбрасывания сопоставляются первые оставшиеся значения: номера
исходных событий не сохраняют пары. Завершение zip по исчерпанному входу
по-прежнему отменяет второй вход и освобождает его очередь.

В delay terminal complete не занимает место значения и не отбрасывается:
может существовать ещё один timer для complete сверх capacity. Ошибка источника
по-прежнему немедленная. Уже готовая очередь доставки при реентрантном callback
не входит в этот лимит. Отписка, ошибка и закрытие scheduler отменяют все таймеры.
Это ограничение буфера, не backpressure: producer продолжает работать.
Лимит элементов также не ограничивает размер одного payload в байтах.

```das
var inscope clock <- rx_virtual_scheduler()
var source <- rx_range(1,5) |> rx_delay(10,clock,rx_queue(2,RxOverflowPolicy.drop_oldest))
var inscope sub <- rx_subscribe(source,
    @(n:int) {print("{n}\n")},
    @(s:string) {panic(s)},
    @() {print("done\n")})
delete source
rx_advance_by(clock,10) // 4,5,done; таймеры 1,2,3 уже отменены.
```

Все четыре оператора и политики: [queue_limits_demo.das](examples/queue_limits_demo.das).
Порядок, ошибки, native исключения observer, отписка и баланс освобождений
проверяются в [test_queue_limits.das](tests/test_queue_limits.das), включая
повторные проходы с проверкой `heap_bytes_allocated()`.

Финализаторы copyable payload проверяются отдельно в
[test_queue_payloads.das](tests/test_queue_payloads.das): удаление из очереди,
доставка, отмена timer и исключение downstream освобождают принадлежащие
оператору копии. Захваченные пользователем значения по-прежнему нужно освобождать
в `finally` своих callbacks, если их тип требует явного `delete`.

## Throttle, sample и buffer

| Вызов | Поведение |
|---|---|
| `source |> rx_throttle(ms, clock)` | Первое событие проходит сразу, следующие подавляются до `now >= first_time + ms` |
| `source |> rx_sample(ms, clock)` | На каждом периодическом тике выдаёт последнее новое значение |
| `source |> rx_buffer(count)` | Неперекрывающиеся пакеты по count элементов; scheduler не нужен |
| `source |> rx_buffer_time(ms, clock)` | Неперекрывающиеся временные окна, отсчитываемые от подписки |
| `source |> rx_buffer(ms, clock)` | Короткая форма buffer_time |
| `source |> rx_buffer(count, ms, clock)` | Пакет закрывается по count или времени; после заполнения отсчёт окна начинается заново |

Все размеры и интервалы положительные. Каждый subscriber получает собственные
буфер, фазу sample и границы throttle. Повторная подписка начинает их заново.
Scheduler один и тот же API, что у timer/delay; фоновых потоков не появляется.

**Throttle** использует время scheduler в момент события. Это leading-вариант:
последнее подавленное событие не выдаётся ни по таймеру, ни при complete.
Подавленные события не продлевают интервал. Таймеры не создаются, но регистрируется
обработчик закрытия scheduler. Поэтому для продвижения времени нужен tick/advance
даже без pending timers. При переполнении int64 deadline цепочка получает on_error.

**Sample** ставит первый timer при подписке и хранит максимум одно значение.
Тик очищает сохранённое значение, так что без новых событий повторной выдачи нет.
На успешном complete последнее ещё не выданное значение выдаётся сразу, затем
complete; ожидать следующего тика не нужно. Пустой источник не выдаёт next.

**Buffer** выдаёт только непустые пакеты. Успешный complete сначала выдаёт
неполный пакет, затем terminal. Ошибка источника немедленно отбрасывает остаток.
У time-only buffer число элементов внутри окна не ограничено: для ограничения
пакета используйте комбинированную форму с count. Перекрывающиеся окна и отдельный шаг между началами задаются дополнительными
перегрузками buffer/count/skip и buffer_time/duration/period; см. раздел ниже.

Sample и временные buffer поддерживают один pending timer на подписку. На
виртуальных часах обрабатываются точные сроки, включая пустые окна. На обычном
scheduler пропущенные интервалы объединяются: тик с опозданием выдаёт один
актуальный результат, следующий timer отсчитывается от обработанного now_ms.
Если поступление данных и timer имеют одинаковый срок, действует FIFO scheduler
по порядку регистрации. Для обычных вызовов rx_subject_next и advance важен
порядок этих вызовов: событие после advance попадает уже в следующее окно.

Отписка, take и delete подписки освобождают остаток и отменяют timer без terminal.
Закрытие scheduler выдаёт `on_error("rx scheduler closed")`, освобождая вход,
остаток и callbacks. Подписка на закрытые часы не подключает источник.
Исключения observer/connect остаются native исключениями после закрытия цепочки;
в on_error автоматически не превращаются. Ошибка cleanup при успешном complete
или отписке также распространяется как native исключение. При обработке on_error
очистка выполняется полностью, но её ошибка не заменяет исходную ошибку потока.

### Владение пакетами

Входные элементы сохраняют обычное ограничение Rx: copyable owning payload.
`buffer` выдаёт `array<T>`, принадлежащий текущему кадру доставки. Обработчик
получает **заимствованный массив только на время вызова**, включая время после
отписки из этого же обработчика. Реентерабельное поступление событий не изменяет
уже выданный пакет. После возврата обработчика пакет и его элементы освобождаются.

Пакет можно пропустить через `filter`, `tap`, `take`, `skip`, `take_while`,
`skip_while`, `finally` или обработать в `map`.
Для сохранения выполните явное клонирование `snapshot := batch` в свой массив;
его дальнейшее освобождение — ответственность владельца snapshot.
Операторы, сохраняющие события (`delay`, `share_replay`, `zip`, `scan` и другие),
по-прежнему требуют copyable значение. Перед ними преобразуйте batch через map
в нужный copyable результат. Компилятор подсказывает это вместо неявного копирования
move-only массива. Это специальный поток пакетов, а не общая поддержка move-only
broadcast payload в остальных источниках и операторах.

```das
var inscope clock <- rx_virtual_scheduler()
var inscope input <- rx_subject(type<int>)
var source <- rx_clone(input) |> rx_buffer(3,10,clock) |> rx_map(@(batch:array<int>) {
    var total=0
    for(n in batch) {total+=n}
    return total
})
var inscope sub <- rx_subscribe(source,
    @(n:int) {print("sum: {n}\n")},
    @(s:string) {panic(s)},
    @() {print("done\n")})
delete source
rx_subject_next(input,1)
rx_subject_next(input,2)
rx_advance_by(clock,10) // sum: 3
rx_subject_next(input,4)
rx_subject_complete(input) // sum: 4, done
```

Сравнение операторов на одном входе: [rate_buffer_demo.das](examples/rate_buffer_demo.das).
Проверки порядка, границ времени, FIFO совпадающих сроков, повторных подписок,
native исключений, отписки, in-flight пакетов, snapshot и освобождения heap:
[test_rate_buffer.das](tests/test_rate_buffer.das),
[test_rate_buffer_lifetime.das](tests/test_rate_buffer_lifetime.das),
[test_rate_buffer_payloads.das](tests/test_rate_buffer_payloads.das).

## Observable ↔ AsyncSequence

Отдельный модуль `lib/reactivex_async_sequence.das` подключает существующие Task
адаптеры и CE AsyncSequence. Ядро `reactivex.das` по-прежнему от них не зависит.
Новых нативных модулей, потоков или Python для адаптеров не требуется.

| Вызов | Результат |
|---|---|
| `source |> rx_to_async_sequence(rx_queue(capacity, policy))` | Один owning stream с ограниченной очередью |
| `source |> rx_to_async_sequence(32, RxOverflowPolicy.error)` | Короткая форма с положительным лимитом |
| `factory |> rx_from_async_sequence(clock)` | Повторно подписываемый Observable, создающий stream на каждую подписку |

### Observable → AsyncSequence

Без аргументов rx_to_async_sequence использует 32 элемента и error;
rx_from_async_sequence по умолчанию опрашивает через 1 ms, третий аргумент
вызова (после factory и clock) позволяет изменить poll_ms.

Адаптер **потребляет descriptor** source; используйте rx_clone(source), если он
ещё нужен. Создание stream и создание запроса async_sequence_next не подписывают
источник: подписка начинается на первом task_poll запроса. До этого события
горячего источника не сохраняются. Удаление не начатого stream/next не вызывает
factory источника.

Лимит всегда положительный, включая переданный вручную RxQueueOptions;
неограниченного режима у этого адаптера нет. Очередь содержит принятые, ещё не
переданные consumer значения. Уже переданный элемент и текущий callback в лимит
не входят. Каждый новый stream получает независимую очередь/подписку.

- `error`: переполнение немедленно отписывает upstream, очищает очередь; текущий
  или следующий next завершается TaskStatus.Failed с сообщением
  `rx_to_async_sequence: queue overflow`.
- `drop_oldest`: освобождает старейшее ожидающее значение и сохраняет новое.
- `drop_latest`: игнорирует входящее значение, сохраняя прежнюю очередь.

Синхронный источник может заполнить очередь целиком в первом poll, прежде чем
consumer получит первый элемент. Для такого источника тоже действуют выбранные
лимит и политика. При успешном on_complete подписка закрывается, но очередь
дочитывается по FIFO; затем next возвращает None. При on_error очередь очищается
немедленно, upstream закрывается, а next становится Failed. Это ошибка Task,
а не элемент Result. Последующие события не принимаются.

Ошибка не требует ещё одного poll для остановки подписки. Но сам stream и его
descriptor нужно дочитать или закрыть, чтобы освободить оставшееся хранение.
Отмена pending next закрывает stream и подписку. То же происходит при отмене
содержащего Task, его timeout или удалении владельца stream. Ошибка cleanup
при task_cancel переводит отменяемый Task в Failed после освобождения ресурсов.

```das
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
var task <- computation(TaskBuilder(type<int>)) {
    var stream & = rx_range(1,3) |> rx_to_async_sequence(3) |> use_resource
    var total=0
    while(true) {
        let item=async_sequence_next(stream) |> bind
        if(item is none) {break}
        total+=item as some
    }
    return total
}
verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==6)
delete task
```

В AsyncSequenceBuilder можно писать обычный асинхронный For:
`for(n in source |> rx_to_async_sequence(...)) { ... }`.
For потребляет child stream и закрывает его при break и ошибке тела, **до**
продолжения остального CE, даже если тот снова приостановится. TaskBuilder
читает через `async_sequence_next(stream) |> bind`, как в примере выше.
При ручном while break лишь выходит из цикла: use_resource закрывает stream
при выходе из своего scope. Если Task после break продолжает ждать другую работу,
закройте stream сразу через async_sequence_close(stream).

Обычные входные элементы должны быть copyable owning payload. Для заимствованных
`array<T>` от buffer есть специальная поддержка: адаптер **клонирует** пакет
в собственный массив, при условии copyable owning T. Асинхронный consumer получает
owning пакет и может держать его через bind. Для такого move-only результата
используйте `var item & = async_sequence_next(stream) |> bind`: borrowed значение
сохраняется в owning кадре ожидания до конца продолжения. Уже доставленный пакет остаётся
валидным после закрытия stream; ожидающие в очереди пакеты освобождаются при
отмене/ошибке/вытеснении. Это не перенос произвольных move-only Rx payload.

### AsyncSequence → Observable

Передаётся фабрика `@() {return <- make_stream()}`, создающая **новый** stream.
Адаптер потребляет фабрику; она вызывается при каждой Rx-подписке. Тело холодного
producer начинает выполняться только при первом scheduler tick/advance. Фабрика
не вызывается при подписке на уже закрытый scheduler. Перенос частично запущенного
stream с другими часами в фабрике не поддерживается; возвращайте свежий stream.

На каждую подписку существует максимум один активный next и один timer опроса.
Первая попытка запланирована на 0 ms, последующие — через положительный poll_ms.
За один вызов timer выдаётся максимум один элемент: синхронный бесконечный
producer не занимает весь tick. Значения выдаются по порядку. Переполнение очереди
в этом направлении не требуется: следующий next создаётся только после доставки
предыдущего. Это кооперативный опрос, не фоновое исполнение.

Task bind внутри producer, включая task_delay_ms, использует now_ms Rx scheduler.
Ошибка producer/next, отменённый next или исключение factory дают on_error;
отмена producer имеет сообщение `rx async sequence cancelled`. None даёт
on_complete. Значения Result/Option сами по себе остаются данными.
Исключение конечного Rx observer распространяется как native исключение после
закрытия producer. Отписка, take и delete подписки отменяют pending next,
закрывают stream и снимают timer/обработчик закрытия scheduler без terminal.
Если отписка вызвана из самого producer, его освобождение откладывается до
возврата текущего poll. Закрытие scheduler выдаёт on_error и также освобождает всё.
Ошибки cleanup не мешают остальной очистке; ошибка отмены next/закрытия producer
при отписке распространяется как native исключение.

Выходные элементы этого направления должны удовлетворять обычному ограничению
Rx на copyable owning payload. Move-only AsyncSequence поддерживает сама CE,
но перед broadcast такие значения нужно преобразовать в copyable результат.

```das
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
var inscope clock <- rx_virtual_scheduler()
var source <- @() {
    return <- computation(AsyncSequenceBuilder()) {
        for(n in range(1,4)) {
            task_delay_ms(2) |> bind
            yield n*10
        }
    }
} |> rx_from_async_sequence(clock) |> rx_take(2)
var inscope sub <- rx_subscribe(source,
    @(n:int) {print("{n}\n")},
    @(s:string) {panic(s)},
    @() {print("done\n")})
delete source
rx_advance_to(clock,20) // 10,20,done; producer закрыт досрочно.
verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
```

При Observable → AsyncSequence временной Rx-источник требует внешнего tick/advance
своих часов, а ожидающий consumer — task_poll/task_tick. Сам адаптер Rx-часы
не продвигает. Пределы очереди предотвращают накопление, но не замедляют producer:
это по-прежнему не backpressure. Все вызовы выполняются в одном контексте/потоке.

Пример с For/break, пайповым bind, обратным адаптером и owning пакетами:
[async_sequence_adapters_demo.das](examples/async_sequence_adapters_demo.das).
Проверки порядка, политик, ошибок, отмены/timeout, реентерабельной отписки,
не начатых stream, snapshot и heap:
[test_async_sequence_adapters.das](tests/test_async_sequence_adapters.das),
[test_async_sequence_adapter_lifetime.das](tests/test_async_sequence_adapter_lifetime.das),
[test_async_sequence_adapter_batches.das](tests/test_async_sequence_adapter_batches.das).

При реализации устранена утечка CE resource scope на исключении из disposer:
Task/AsyncSequence finalizer теперь сообщает ошибку через Task cleanup scope после
освобождения владельцев, вместо исключения из native generator finalizer.
Отдельная CE-регрессия без зависимости от Rx:
[test_async_sequence_cleanup_failure.das](../computation_expressions/tests/test_async_sequence_cleanup_failure.das).

## Префиксы, соседние пары и finally

```das
require ../lib/reactivex.das
var source <- rx_range(1,8) |> rx_skip(1) |> rx_skip_while(@(n:int) {return n<4}) |> rx_take_while(@(n:int) {return n<7}) |> rx_pairwise() |> rx_finally(@() {print("closed\n")})
var inscope sub <- rx_subscribe(source,
    @(p:tuple<previous:int;current:int>) {print("{p.previous} -> {p.current}\n")},
    @(s:string) {panic(s)},@() {print("done\n")})
delete source
// 4 -> 5; 5 -> 6; done; closed.
```

`rx_skip(0)` передаёт все значения; отрицательный count — native ошибка при
построении, переданный source освобождается. Большой count не останавливает
источник: до terminal пропускаются все его значения. Счётчик не переполняется:
он уменьшается до нуля и дальше не меняется.

`take_while` проверяет каждое входное значение до первого false, не выдаёт его,
доставляет complete и прекращает входные эффекты. `skip_while` включает первое
значение false и больше predicate не вызывает: последующие значения могут снова
соответствовать predicate и всё равно выдаются. Predicate failure становится
одним on_error; upstream error проходит без изменений, complete после error нет.

`pairwise` выдаёт `(previous, current)` для соседних **выданных ему** значений,
а не всех значений до фильтрации. Пустой/одноэлементный поток не выдаёт пар;
при завершении или ошибке неполная пара не выдаётся. Счётчики, latch и история
создаются заново на каждой подписке, включая поздние и повторные подписки.
Строки в истории сохраняются как owning snapshots. Обычные ограничения на
copyable owning payload действуют и для пар; заимствованный `array<T>` от buffer
сначала нужно преобразовать в copyable значение. skip/take_while/skip_while/finally
пакеты не сохраняют и могут передавать их дальше без копирования массива.

`rx_finally` — owning lambda без аргументов. Он вызывается ровно один раз на
**подключённую подписку**, включая complete, on_error, take/take_while,
rx_unsubscribe, уничтожение подписки и native исключения source/observer.
Само удаление неподключённого descriptor освобождает captures, но не вызывает
action. Если downstream `take(0)` или закрытый control не подключил источник,
finally для этого источника не регистрируется.

Порядок: terminal callback, затем cleanup подписки в порядке регистрации.
finally добавляется после возврата upstream connect, то есть после teardown,
зарегистрированного upstream при подключении. При синхронном закрытии upstream
cleanup выполняется немедленно, finally — после возврата/исключения из connect.
Для вложенных finally порядок — от внутреннего к внешнему. Cleanup, добавленный
позже, исполняется по общим правилам rx_add_cleanup; это не гарантия порядка
относительно произвольного будущего добавления cleanup.

Исключение action остаётся native, не превращается в on_error, не отменяет уже
доставленный terminal и не мешает другим cleanup. Если одновременно было native
исключение source/observer, сохраняется исходная ошибка. Отписка из самого
finally безопасна: control уже закрыт. Callback и его captures могут оставаться
живыми до возврата текущей доставки; оставшийся descriptor также сохраняет
переданную lambda до своего удаления.

[selection_demo.das](examples/selection_demo.das) показывает всю цепочку.
[test_selection.das](tests/test_selection.das) проверяет значения, границы,
независимость подписок, строки, predicate failures и reentrancy.
[test_selection_lifetime.das](tests/test_selection_lifetime.das) проверяет порядок
cleanup, native ошибки, отписку, captures и стабильный heap после повторений.
Все три включены в общий scripts.ps1 и исполнение AOT-хоста в CI.

## Триггеры и exhaust_map

`primary |> rx_with_latest_from(other)` подключает other первым. Только next primary
создаёт пару `(first, second)`; до первого other значения primary теряются, а не
накапливаются. Обновление other ничего не выдаёт. После complete other последнее
значение сохраняется. Если other завершился без значения, primary продолжает
работать до своего terminal, но пар нет. Complete primary закрывает оба входа;
ошибка любого входа немедленно закрывает оба. Payload обоих входов copyable owning.

`rx_exhaust_map(selector)` использует те же правила ошибок и освобождения, что
flat_map, но игнорирует новые outer next во время активного child, его connect,
selector или teardown. Selector для пропущенных значений не вызывается; очереди
повторных действий нет. Complete outer ждёт активный child. После синхронного
завершения child следующее outer значение может запустить новый child.

[triggers_retry_demo.das](examples/triggers_retry_demo.das) показывает действие
пользователя + последние настройки, защиту от повторного запуска и итог reduce.

## Retry с predicate и backoff

Прежний `rx_retry(retries,delay_ms,clock)` сохраняет поведение. Дополнительные формы:

```das
require ../lib/reactivex.das
var inscope clock <- rx_virtual_scheduler()
var source <- rx_throw("temporary",type<int>) |> rx_retry(3,
    @(message:string;retry:int) {return message=="temporary"},
    @(retry:int) {return int64(retry)*10l},clock)
var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {},@() {})
rx_advance_to(clock,100)
delete source
```

Predicate получает исходное сообщение и номер **повтора с 1**. False передаёт
последнюю ошибку дальше; функция задержки при этом не вызывается. Retries — число
дополнительных подписок. Predicate и delay_for вызываются после teardown попытки,
отдельно на каждом повторе и каждой подписке. Даже задержка 0 планируется через
clock, поэтому синхронные ошибки не создают рекурсию и подчиняются budget.

`source |> rx_retry_backoff(retries,initial_ms,max_ms,clock[,predicate])` использует
initial, initial*2, initial*4, … с ограничением max_ms. Нулевая initial остаётся 0.
Умножение защищено от переполнения. Predicate/delay_for failure становится on_error;
отрицательная задержка и переполнение срока тоже дают on_error. Отписка и закрытие
clock снимают ожидающий повтор и lifecycle hook. Native observer/cleanup ошибки
сохраняют общую семантику Rx и не запускают retry.

## Итоговые значения

`rx_reduce(seed,reducer)` выдаёт ровно одно накопленное значение при complete.
Пустой источник выдаёт seed. До complete промежуточных результатов нет; ошибка
источника или reducer не выдаёт накопитель. Тип seed/результата может отличаться
от входного. Для промежуточных результатов по-прежнему используется scan.

`rx_first()` останавливает upstream сразу после первого значения; `rx_last()`
сохраняет последнее до complete. Пустой complete даёт on_error соответственно
`rx_first: empty source` или `rx_last: empty source`. `rx_default_if_empty(value)`
передаёт обычные значения как есть, а value выдаёт только при пустом успешном
complete; источник с ошибкой не заменяется. Эти операторы требуют copyable owning
payload; borrowed buffer/window сначала нужно преобразовать.

## Временной replay и настройки share

`rx_replay_subject(type<T>,buffer_size,window_ms,clock)` и
`source |> rx_share_replay(buffer_size,window_ms,clock[,settings])` ограничивают
историю и количеством, и возрастом. Оба лимита положительные. Элемент с
`age >= window_ms` уже истёк. Очистка ленивая: при next, подписке и запросе
rx_subject_buffered_count; отдельных таймеров на кеш нет. Между такими операциями
истёкшие элементы ещё могут занимать память. После complete/error возраст также
учитывается, а само terminal-событие не истекает. Закрытый clock больше не движется;
это не отдельный сигнал завершения Subject/кеша.

Настройки `RxShareOptions`:

| Поле | Значение по умолчанию | Действие |
|---|---|---|
| reset_on_error | true | Новая генерация после on_error |
| reset_on_complete | true | Новая генерация после успешного complete |
| reset_on_refcount_zero | true | Отключить активный upstream и сбросить кеш при последней отписке |

`rx_share(settings)` использует эти настройки. У `rx_share_replay(buffer_size)`
и его временной формы default отличается только `reset_on_complete=false`, как
и раньше. При явно переданном settings используются ровно его поля. False для
reset_on_error/complete сохраняет соответствующий terminal и текущий кеш для
поздних подписчиков. Истечение кеша само по себе не перезапускает terminal source.

False для reset_on_refcount_zero оставляет **активный upstream** и кеш между
подписчиками. Для бесконечного источника это требует явной границы жизни:
`rx_share_close(hub)` перед удалением последних views. Простое удаление descriptor
не разрывает активную keep-alive связь. Close идемпотентен: отключает upstream,
закрывает текущие подписки без искусственного terminal, удаляет кеш и запрещает
новые подключения; поздняя подписка получает пустой complete. Все cleanup
выполняются даже при исключении одного из них, после чего исключение распространяется.

[connectable_cache_demo.das](examples/connectable_cache_demo.das) показывает
временной replay и keep-alive с явным close.

## publish / connect / ref_count

`source |> rx_publish()` создаёт горячий connectable Observable без replay.
`rx_subscribe(published,...)` пока только регистрирует observer.
`var connection <- rx_connect(published)` запускает один upstream и возвращает
RxSubscription: unsubscribe/delete этого владельца отключает upstream. Сам publish
и его observers остаются пригодными для повторного connect после ручного отключения.
Пропущенные в отключённом состоянии события не воспроизводятся.

Повторный connect при активном соединении возвращает owning alias **того же**
соединения; второй upstream не создаётся. Закрытие любого такого alias закрывает
общее соединение. Source complete/error завершает внутренний Subject; после
terminal publish не перезапускается. Для автоматического сброса используйте share.
Native ошибка observer закрывает текущее соединение и остальные текущие подписки
без придуманного on_error; явный последующий connect к nonterminal publish возможен.
Если teardown уже создал новое соединение, завершение старого не отменяет его и
не закрывает новых подписчиков. Публичный descriptor можно удалить из callback: текущая операция удерживает внутреннюю ссылку.

`published |> rx_ref_count()` подписывает observer перед connect, подключает источник
при первом подписчике и отключает при последнем. После отключения nonterminal
источник можно подключить снова; terminal сохраняется. Несколько ref_count views
одного publish используют общий счётчик. Ручной connect и ref_count управляют тем же
соединением: каждый из владельцев может его отключить, независимых upstream нет.

## Перекрывающиеся buffer и window

Группировка по ключу: [group_by — API, владение и примеры](GROUP_BY.md).

- `source |> rx_buffer(count,skip)` — пакеты размера count, начало каждые skip элементов.
- `source |> rx_buffer_time(duration_ms,period_ms,clock)` — длительность окна и период открытия заданы отдельно.
- `source |> rx_window(count[,skip])` — те же count/skip, но выдаются внутренние Observable.
- `source |> rx_window_time(duration_ms[,period_ms],clock)` — временные внутренние Observable.

Все размеры/периоды положительные. Меньший шаг даёт пересечение, больший — gaps,
в которых входные значения не попадают ни в одну группу. Count начинается с первого
окна при подписке и открывает следующее после каждых skip элементов. Window поэтому
выдаёт начальное пустое окно даже для пустого source и может выдать последнее пустое
окно ровно на границе skip. Buffer пустые пакеты не выдаёт. При complete неполные
непустые buffer выдаются в порядке открытия, а window завершаются. При ошибке partial
buffer отбрасываются, всем открытым window и внешнему observer передаётся ошибка.

Временные интервалы полуоткрытые. Первое окно открывается при подписке; следующее
через period_ms. При совпадении сроков действует FIFO регистрации scheduler,
включая закрытие старого и открытие нового окна. Каждый открытый интервал имеет
свой timer закрытия, плюс один общий timer открытия и lifecycle hook. Отписка,
ранний выход, native ошибки и закрытие clock снимают всё и отключают upstream.
Часы сохраняют прежнюю virtual/manual семантику, включая coalescing manual tick.

Buffer выдаёт borrowed array по прежнему контракту. Window выдаёт **borrowed горячий
Observable** на время on_next. Подпишитесь в callback до первого элемента окна;
для сохранения дескриптора выполните rx_clone(window). У окна replay нет: поздняя
подписка пропускает прошлые значения. map может преобразовать descriptor, а
filter/tap/take/skip/while/finally могут передавать его без сохранения. flat_map/
concat_map принимают selector с явным rx_clone(window); лимит активных подписок
может приводить к поздней подписке на уже открытое горячее окно и потере его префикса.
Другие retaining-операторы требуют обычный copyable payload и отклоняют descriptor.
Это специальный поток окон, не произвольные move-only broadcast значения.

Внешняя подписка владеет **всеми открытыми окнами**. Её отмена завершает внутренние
окна успешным complete и не создаёт terminal внешнему observer; сохранённый descriptor
после этого уже закрыт. Отписка отдельного внутреннего observer не останавливает
остальные окна или внешний источник. Ошибка одного cleanup не мешает закрытию остальных.
Количество одновременно открытых окон определяется count/skip или duration/period;
time-only buffer всё ещё может накопить много элементов внутри одного окна.

[sliding_windows_demo.das](examples/sliding_windows_demo.das) показывает пакеты,
потоки окон с flat_map и виртуальные часы. Новые наборы:
[test_trigger_recovery.das](tests/test_trigger_recovery.das),
[test_connectable_cache.das](tests/test_connectable_cache.das),
[test_sliding_windows.das](tests/test_sliding_windows.das),
[test_expansion_lifetime.das](tests/test_expansion_lifetime.das).
Все включены в interpreter/JIT и strict AOT runtime через общий scripts.ps1.
