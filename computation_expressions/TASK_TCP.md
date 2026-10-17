# Реальный TCP и закрытие соединения

```das
require ./lib/computation_macro.das
require ./lib/task_scheduler.das
require ./lib/task_tcp.das

// Внутри функции:
var inscope operation <- computation(TaskResultBuilder(type<string>)) {
    let line=task_tcp_request_line("127.0.0.1",port,"ok\n") |> bind
    return "Reply: {line}"
}
// task_with_cancellation(operation,token) и TaskTimeout работают как обычно.
```

Адаптер использует стандартный `daslib/network.Client`. Он отправляет небольшой
запрос и читает одну строку до LF; LF в результат не включается. Получение данных
через tick неблокирующее. В SDK 0.6.4 установление соединения, включая DNS,
синхронное и ограничено connect_timeout_ms (по умолчанию 1000): CancellationToken
и scheduler timeout наблюдаются после возврата connect, не прерывают этот вызов.
Для длительных сетевых connect/DNS нужен иной неблокирующий адаптер хоста.

Это ограниченный протокол одной строки, не HTTP: request максимум 4096 байт,
ответ по умолчанию максимум 65536. Ошибка send, connect, превышение размера и EOF
до LF возвращают Result.error. Native ошибки адаптера дают Failed. Модуль не
вводит новые потоки; он работает в потоке контекста daScript.

Close-callback уничтожает клиент, закрывает socket и освобождает буфер на всех
путях. `task_tcp_stats()` возвращает created/released/active для проверки владения
адаптерами. Проверка на стороне сервера дополнительно подтверждает реальный EOF,
так что счётчик сам по себе не служит доказательством закрытия соединения.

```powershell
./test_task_tcp.ps1
./test_task_tcp.ps1 -Jit
./test_task_tcp.ps1 -Example
```

Python fixture поднимает сервер на случайном свободном loopback-порту, передаёт
порт через CE_TASK_TCP_PORT и удаляет сервер при завершении. Внешняя сеть и
постоянный сервер не нужны. Сценарии: ответ по частям, отмена token во время
ожидания, timeout во время ожидания и ранний EOF сервера. Клиентский cleanup
проверяется по created==released; сервер ждёт EOF после success/cancel/timeout.
Часы теста — реальное elapsed-время, которое явно передаётся scheduler через now_ms.

Пример: [task_tcp_demo.das](examples/task_tcp_demo.das).
Тест: [test_task_tcp.das](tests/test_task_tcp.das),
[fixture](support/task_tcp_fixture.py). Базовые Task проходят отдельное строгое
исполнение AOT; сетевой пример в этой поставке проверяется интерпретатором и JIT,
поскольку стандартный network.das помечен SDK как no_aot.
