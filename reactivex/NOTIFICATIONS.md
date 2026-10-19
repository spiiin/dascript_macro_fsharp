# materialize и dematerialize

`source |> rx_materialize()` переводит протокол Observable в обычные данные.
`source |> rx_dematerialize()` восстанавливает из них протокол. Уведомления можно
логировать, фильтровать, сохранять в ReplaySubject или передавать через observe_on
с теми же правилами владения, что и остальные copyable owning значения Rx.

## Тип и конструкторы

Тип уведомления для T — структурный `variant<complete;next:T;error:string>`.
Его можно указать как `typedecl(rx_notification(type<T>))`:

```dascript
var value=rx_notification_next(42)
var failure=rx_notification_error("offline",type<int>)
var completed=rx_notification_complete(type<int>)

verify(value is next && value as next==42)
verify(failure is error && failure as error=="offline")
verify(completed is complete)
```

`rx_notification(type<T>)` также возвращает complete: первый вариант не содержит
данных и является значением по умолчанию. Терминальные варианты уведомления не
конструируют и не финализируют фиктивный T. Доступ к значению — через `is next`
и `as next`, к ошибке — через `is error` и `as error`. К complete доступа к payload
нет. Строковые значения и сообщения конструкторы сохраняют снимками.

T должен соответствовать обычному контракту Rx: copyable owning. Move-only
значения, заимствованные window/group дескрипторы и массивы buffer в уведомлениях
не поддерживаются. Сначала преобразуйте такой payload в обычные данные.

## Порядок событий

| Вход materialize | Выход |
|---|---|
| next(value) | next уведомления `next:value` |
| complete | next уведомления `complete`, затем настоящий complete |
| on_error(message) | next уведомления `error:message`, затем настоящий complete |

После error-уведомления дополнительного complete-уведомления нет. Ошибка источника,
включая пустое сообщение, становится данными; error callback подписчика materialize
при этом не вызывается. Пустой источник выдаёт одно complete-уведомление и завершается.

```dascript
var inscope source <- rx_range(1,2) |> rx_concat(rx_throw("offline",type<int>)) |> rx_materialize()
var inscope subscription <- rx_subscribe(source,
    @(event:typedecl(rx_notification(type<int>))) {
        if(event is next) {print("next: {event as next}\n")}
        elif(event is error) {print("error as data: {event as error}\n")}
        else {print("complete as data\n")}
    },@(message:string) {panic(message)},@() {print("done\n")})
// next: 1; next: 2; error as data: offline; done.
```

Полный пример с обратным преобразованием:
[notifications_demo.das](examples/notifications_demo.das).

| Вход dematerialize | Выход |
|---|---|
| next уведомления `next:value` | next(value) |
| next уведомления `error:message` | настоящий on_error(message), остановка upstream |
| next уведомления `complete` | настоящий complete, остановка upstream |
| Настоящий on_error/complete источника уведомлений | Тот же настоящий terminal |

Первый terminal окончателен: последующие уведомления и эффекты синхронного
источника не выполняются. Для потока без закодированного terminal достаточно
настоящего complete источника уведомлений. `rx_dematerialize` принимает только
указанный тип variant, а не int/string или другой формат описания событий.

```dascript
var inscope source <- rx_range(1,4) |> rx_map(@(n:int) {
    if(n==3) {return rx_notification_complete(type<int>)}
    return rx_notification_next(n)
}) |> rx_dematerialize()
// Подписчик получит 1, 2, complete; значение 4 уже не обрабатывается.
```

Для обычных источников `materialize |> dematerialize` сохраняет значения, terminal
и порядок их наблюдения. Преобразования добавляют внутренние очереди и копирование
payload, поэтому не обещают ту же стоимость исполнения или число финализируемых
копий, что исходная цепочка.

## Отписка, исключения и владение

Операторы используют общий control подписки: unsubscribe/delete или terminal
dematerialize немедленно закрывает upstream и отменяет ожидающую доставку. Отписка
не создаёт завершающее уведомление. Если отписаться в callback терминального
уведомления materialize, последующий настоящий complete уже не вызывается.

Вложенные события custom rx_create источников сериализуются. Текущее значение
полностью обрабатывается до вложенного next/terminal. Materialize ставит terminal
уведомление и настоящий complete в очередь до вызова пользовательского callback,
чтобы между ними не могли попасть новые значения источника.

on_error является частью протокола. Исключение из observer callback, factory или
teardown остаётся исключением; materialize его не превращает в error-уведомление.
При таком исключении закрывается подписка и освобождаются ожидающие значения и
захваченные ресурсы. Если предыдущий оператор сам превратил исключение в on_error,
materialize обработает этот on_error обычным образом.

Состояние и очереди отдельные для каждой подписки. Доставка синхронная, в текущем
потоке; асинхронного планирования эти операторы не добавляют. Для него используйте
observe_on, например `materialize |> observe_on(clock) |> dematerialize`.
Очередь вложенных уведомлений не ограничена и не обеспечивает backpressure.

## Проверки и запуск

- [test_notifications.das](tests/test_notifications.das): конструкторы, порядок,
  пустое сообщение ошибки, round-trip, остановка по encoded terminal, настоящие
  terminals, повторные подписки, вложенные события и отложенные строки.
- [test_notification_lifetime.das](tests/test_notification_lifetime.das):
  unsubscribe/delete/take, исключения callbacks и teardown, освобождение captures,
  отсутствие фиктивного payload в terminal-уведомлениях, отмена ожидающего payload
  и повторные проверки живой памяти.
- [failed_dematerialize_type.das](tests/failed_dematerialize_type.das) и
  [failed_materialize_payload.das](tests/failed_materialize_payload.das): отказ при
  неверном входном типе и заимствованном payload.

Пример и положительные тесты входят в scripts.ps1 для интерпретатора, JIT и
строгого AOT-хоста в CI; отрицательные проверки включены в run.ps1 -Test.

```powershell
./reactivex/run.ps1 -Test
./reactivex/run.ps1 -Test -Jit
./reactivex/run_aot.ps1
```

Локальная проверка 2026-10-19, Windows SDK 0.6.5-RC2:

- Полный интерпретатор: 77 положительных сценариев и 13 ожидаемых ошибок
  компиляции — PASS.
- JIT: notifications_demo, test_notifications, test_notification_lifetime,
  test_reentrancy, test_selection_lifetime, test_scheduling_lifetime и обе новые
  негативные проверки — PASS.
- Собран и исполнен AOT-хост для тех же шести положительных сценариев — 6/6 PASS,
  с проверкой AOT main и fail_on_no_aot, без fallback.

Полные JIT/AOT-наборы в этом проходе не запускались. Логи из корня репозитория:
`.work/notifications-interpreter.log`, `.work/notifications-jit.log`,
`.work/notifications-aot.log`, `.work/notifications-aot-runtime/runtime-summary.json`.
