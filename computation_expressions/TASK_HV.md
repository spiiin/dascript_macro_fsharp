# WebSocket через dasHV

`lib/task_hv.das` — необязательный адаптер установленного модуля
`dashv/dashv_boost` из SDK Daslang 0.6.4. Собственного нативного модуля нет.
Основная библиотека CE не импортирует dasHV автоматически.

```das
options gen2
require ./lib/computation_macro.das
require ./lib/task_hv.das

def echo(url:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url) |> bind
        ws_send_text(socket,"hello") |> bind
        let reply=ws_receive_text(socket) |> bind
        return reply
    }
}
```

Задачу запускают через `task_poll` либо планировщик `task_spawn` / `task_tick`.
Полный пример с `CancellationToken`, `TaskTimeout` и часами `now_ms`:
[examples/task_hv_demo.das](examples/task_hv_demo.das).
`./test_task_hv.ps1 -Example` запускает его с локальным echo-сервером Python.

## Два запроса через and_bind

[examples/task_hv_and_bind_demo.das](examples/task_hv_and_bind_demo.das) запускает
два независимых WebSocket одновременно через общий TaskResultBuilder:

```das
def two_requests(urlA:string;urlB:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let pair=exchange(urlA,"one") |> and_bind(exchange(urlB,"two")) |> bind
        return "A={pair.first}; B={pair.second}"
    }
}
```

`exchange` владеет собственным сокетом через `use_resource`. Общая задача
оборачивается в `task_with_cancellation(...,token)` и передаётся в `task_spawn`
с `TaskTimeout(after_ms=...)`. Error первого ребёнка закрывает ожидающего
второго; отмена и таймаут закрывают всю группу. Порядок `.first/.second`
соответствует порядку источников, а не завершения. Подробности: [TASK_AND_BIND.md](TASK_AND_BIND.md).

Запуск: `./test_task_hv.ps1 -AndBind -Example`. Пример показывает успешную пару,
отмену и таймаут на двух соединениях, ожидающих ответ. Для этого тестовый сервер
предоставляет echo- и silent-маршруты; внешняя сеть не требуется.

## Операции

| API | Результат |
|---|---|
| `hv_websocket(config=HvWebSocketConfig())` | Move-only владелец `HvWebSocket` |
| `ws_connect(socket,url)` | Task с `Result<CeUnit>`, ожидание открытия WebSocket |
| `ws_send_text(socket,text)` | Task с `Result<CeUnit>`, передача текста транспорту |
| `ws_receive_text(socket)` | Task с `Result<string>`, следующее целое текстовое сообщение |
| `ce_dispose(socket)` / `delete socket` | Идемпотентное закрытие соединения |
| `hv_websocket_stats()` | Счётчики владельцев, клиентов и операций для диагностики |

Все три операции создают холодные однократные Task: ввод-вывод начинается при
первом опросе. `ws_send_text` завершается после принятия сообщения native API;
это не подтверждение доставки или чтения сервером. Отдельного ожидания drain нет.
Операции можно ожидать в TaskBuilder как Result либо распаковать через bind
в TaskResultBuilder. Ошибки транспорта возвращают `Error`; исключение даёт
`TaskStatus.Failed`; отмена и таймаут дают `TaskStatus.Cancelled`, причину таймаута
проверяют через `task_timed_out` планировщика.

Один сокет допускает одну активную операцию. Конкурирующая операция возвращает
`Error`, не прерывая первую. Повторное подключение требует нового владельца.
Отмена незавершённой начатой операции закрывает всё соединение. Отмена Task до
его первого опроса соединение не открывает и чужую операцию не отменяет.

`use_resource` закрывает сокет при успехе, Error, отмене, таймауте и исключении.
Без CE используйте `var inscope socket <- hv_websocket()`. Внутренние ссылки
сохраняют данные до освобождения всех созданных Task. Удаление владельца
немедленно закрывает транспорт; оставшиеся операции безопасно возвращают Error.
Очистка уничтожает нативный клиент и дожидается завершения его потока.

## Границы

- Сетевой цикл и потоки предоставляет dasHV/libhv; daScript callbacks исполняются
  в потоке опроса Task через `process_event_que`. Используйте один поток для
  владельца, его Task и планировщика.
- В закреплённой версии libhv разрешение имени в `open` синхронное. Отмена и
  таймаут проверяются между опросами, не прерывают DNS и нативную очистку внутри
  одного опроса. Тесты используют `127.0.0.1` и задержанный WebSocket handshake.
- Приём текстовый: бинарные сообщения и текст со встроенным NUL возвращают Error.
  Фрагментированные текстовые сообщения собирает libhv.
- `HvWebSocketConfig`: `max_message_bytes=65536`, `max_queued_messages=16`,
  `max_queued_bytes=262144`; все лимиты положительные. Они ограничивают
  сохранённую daScript-очередь после доставки callback. Это не предел выделений
  нативного парсера и очереди событий dasHV. Обратное давление пока отсутствует.
- Полные проверки самого Task-адаптера выполняются в интерпретаторе и JIT.
  Его WebSocket-путь также собран и исполнен в отдельном
  [AOT-хосте интеграций ReactiveX](../reactivex/AOT_INTEGRATIONS.md) через
  AsyncSequence → Observable: отмена/таймаут handshake и receive, ошибки,
  ранний выход и освобождение ресурсов. Это отдельный набор проверок;
  основной AOT-хост CE по-прежнему не включает native dasHV.

## Проверки

`./test_task_hv.ps1` и `./test_task_hv.ps1 -Jit` проверяют реальный loopback
WebSocket: фрагментированный echo и порядок сообщений, Error и исключение,
отмену и таймаут на handshake и receive, время жизни владельца, конфликт операций.
Сервер проверяет закрытие каждого соединения; повторные запуски проверяют
счётчики ресурсов и неизменность `heap_bytes_allocated()` после прогрева.
Внешняя сеть и Python-пакеты не нужны.

`./test_task_hv.ps1 -AndBind` (также с `-Jit`) проверяет порядок результатов,
групповую отмену, общий таймаут и Error первого запроса при реально работающем
втором. Сервер откладывает ошибку первого до получения сообщения второго.
Каждый тест проверяет закрытие обоих соединений со стороны сервера ещё до
завершения процесса, пропуск продолжений и нулевые счётчики ресурсов.
Повторные прогоны после прогрева проверяют отсутствие роста daScript heap.
