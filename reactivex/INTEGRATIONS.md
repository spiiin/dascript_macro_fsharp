# Практические интеграции ReactiveX

Нужен SDK с модулями `glfw` и `dashv`; закреплённый SDK CI их содержит.
Параметр `-Daslang` у runners или переменная `DASLANG_EXE` выбирает компилятор.

## Окно dasGlfw: события → состояние → UI

Из корня репозитория:

```powershell
./reactivex/run_glfw_ui.ps1
./reactivex/run_glfw_ui.ps1 -Jit
```

Стрелки Up/Down изменяют здоровье на 25, R сбрасывает его в 100. В заголовке
окна показаны здоровье, число обновлений UI и независимый фоновый счётчик.
Esc завершает поток управления; фон продолжает работать до закрытия окна.
OpenGL-контекст, renderer, Python и новый native-модуль не нужны.
Это минимальный UI в заголовке окна, без виджетов и отрисовки.

Основная цепочка из [glfw_ui.das](support/glfw_ui.das):

```das
var inscope states <- rx_clone(actions) |> rx_scan(100,@(hp:int;event:RxUiAction) {
    let next=event.reset ? 100 : hp+event.delta
    return next<0 ? 0 : next>100 ? 100 : next
}) |> rx_start_with(100) |> rx_distinct_until_changed() |> rx_take_until(rx_clone(stop))
```

События native callback приходят в Subject в том же потоке, что и оконный цикл.
`scan` хранит состояние, `distinct_until_changed` исключает перерисовку при
неизменившемся здоровье, `take_until` завершает поток по Esc.
Отдельный `rx_interval` продвигается вызовами `rx_tick` из frame-loop.

Окно владеет native callback chain; цепочка заимствует script lambda.
После Esc callback снимается на следующем frame, после возврата из native
обработчика. При закрытии сначала выполняются `glfw_chain_clear` и удаление
lambda, затем отписка и закрытие scheduler, затем уничтожение окна.
Повторный close безопасен. Helper владеет всем окном и всей его callback chain;
его не следует совмещать с чужими callbacks на том же окне.

Исполняемый пример: [glfw_ui_demo.das](examples/glfw_ui_demo.das).
`-SmokeTest` открывает скрытое окно и автоматически завершает цикл.
Требуется desktop/windowing session даже для скрытого окна.

## WebSocket: CE → AsyncSequence → Observable

Локальный echo-пример без внешних сервисов:

```powershell
./reactivex/run_websocket_echo.ps1
./reactivex/run_websocket_echo.ps1 -Jit
# Свой WebSocket echo endpoint:
./reactivex/run_websocket_echo.ps1 -Url ws://127.0.0.1:9000/echo -Jit
```

Без `-Url` используется существующий loopback fixture на Python standard library:
он запускает локальный WebSocket-сервер и проверяет закрытие клиента. Сам клиент,
обработка событий, Task и Observable написаны на daScript. При подключении
к своему серверу Python не запускается. Нужен endpoint, возвращающий отправленный
текст: пример ожидает три сообщения и сам отменяет дальнейшее чтение.

Производитель из [websocket_echo.das](support/websocket_echo.das):

```das
def websocket_echo_stream(url:string;count:int) {
    return <- computation(AsyncSequenceBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        let connected=ws_connect(socket,url) |> bind
        if(connected is error) {panic(connected as error)}
        for(i in range(count)) {
            let sent=ws_send_text(socket,"message {i}") |> bind
            if(sent is error) {panic(sent as error)}
            let received=ws_receive_text(socket) |> bind
            if(received is error) {panic(received as error)}
            yield received as ok
            task_delay_ms(10) |> bind
        }
    }
}
```

AsyncSequence bind получает Task payload как данные, поэтому Result проверяется
явно. Panic производителя адаптер превращает в Observable `on_error`.
Каждый вызов фабрики создаёт новый stream и новое соединение на подписку.
Ресурс принадлежит stream; `use_resource` закрывает его при нормальном завершении,
ошибке, отмене и раннем выходе. Во время активного producer-frame освобождение
откладывается до возврата из него, чтобы не разрушить работающую корутину.

Связь с Rx в [websocket_echo_demo.das](examples/websocket_echo_demo.das):

```das
var inscope stream <- rx_echo_messages(url,1000,clock) |> rx_timeout(5000,clock) |> rx_take_until(rx_clone(cancel))
var inscope subscription <- rx_subscribe(stream,@(text:string) {
    print("WebSocket: {text}\n");received++
    if(received==3) {rx_subject_next(cancel,0)}
},@(message:string) {print("error: {message}\n")},@() {print("complete\n")})
```

`take_until` по сигналу завершает Observable успешно и закрывает upstream;
следующие сообщения не запрашиваются. Обычная `rx_unsubscribe` или удаление
подписки закрывает upstream без terminal callback. `rx_timeout` — таймаут
бездействия: срок обновляется после каждого сообщения; он даёт `on_error`
с `rx timeout` и закрывает соединение. Закрытие scheduler также даёт ошибку
и освобождает native client. До первого tick отмена не открывает соединение.
Фоновый `rx_interval` в примере продолжает исполняться между сетевыми ожиданиями.

Helper является демонстрацией конечного echo-потока, а не универсальным
WebSocket transport API. Он повторно использует существующий CE dasHV-адаптер;
его [ограничения](../computation_expressions/TASK_HV.md) сохраняются: DNS в native
open синхронный, отмена кооперативная между опросами, текстовые сообщения,
ограниченная внутренняя очередь, без backpressure и ожидания drain.
`127.0.0.1` в проверках исключает зависимость от DNS и внешней сети.

## Проверки и режимы

```powershell
./reactivex/test_integrations.ps1
./reactivex/test_integrations.ps1 -Jit
```

Runner исполняет оба набора тестов и оба примера. Окна в тестах скрыты:
клавиши проходят через `glfw_post_key` и настоящую native callback chain.
Проверяются reducer, подавление дубликатов, Esc, продолжение фона, закрытие
активного окна, повторные открытия и отсутствие роста живого daScript heap.
Сетевой fixture проверяет порядок сообщений, нормальное завершение, отмену
и таймаут во время handshake/receive, `take(1)`, ошибку бинарного сообщения,
ошибку конечного callback, закрытие scheduler, явную отписку, удаление подписки
и отмену до первого poll. Проверяются нулевые счётчики native owners/clients/
operations, отсутствие timers/hooks и физическое закрытие на стороне сервера.

В CI добавлены отдельный шаг JIT и отдельная job исполнения native AOT-хоста.
Интеграции намеренно не входят в `scripts.ps1`: основной runner и core AOT-хост
остаются независимыми от GLFW/HV и доступности оконной сессии.
Примеры и проверки исполнены в интерпретаторе, JIT и отдельном AOT-хосте:
`./reactivex/run_integrations_aot.ps1`.
Устройство хоста, ограничения SDK и результаты: [AOT_INTEGRATIONS.md](AOT_INTEGRATIONS.md).
Локальные логи: `.work/practical-interpreter.log`, `.work/practical-jit.log`.
