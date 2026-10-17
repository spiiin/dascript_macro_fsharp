# Реальное ожидание клавиатуры через Task

Для окна GLFW без Python есть отдельный [пример](TASK_GLFW_KEYBOARD.md).

Из корня checkout в обычном Windows Terminal / PowerShell, без перенаправления:

```powershell
./computation_expressions/run_task_keyboard.ps1
```

Если выполнение `.ps1` запрещено текущей политикой, можно запустить отдельный
процесс без изменения постоянных настроек:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./computation_expressions/run_task_keyboard.ps1
```

Требуются установленный Daslang 0.6.4 и Python 3 со стандартной библиотекой.
Путь SDK задаётся через `-Daslang` или `DASLANG_EXE`; локальный fallback —
`C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe`.

```powershell
./computation_expressions/run_task_keyboard.ps1 -TimeoutMs 30000 -Jit
```

## Что попробовать

- Наберите текст и нажмите Enter: ожидающая Task вернёт строку, включая Unicode.
- Наберите часть строки и подождите: фоновая Task продолжит печатать `HEARTBEAT`.
- Нажмите Esc или Ctrl+C, либо введите `/cancel` + Enter: отменится ожидание ввода.
- Ничего не вводите: через 15 секунд (по умолчанию) сработает общий таймаут ожидания.
- `/quit` + Enter немедленно завершает весь пример.

Это одноразовый диалог. После строки, отмены или таймаута фоновая Task работает
ещё немного, затем пример сам завершает все задачи и освобождает подписки.
При таймауте не требуется нажимать Enter для возврата в PowerShell.
Backspace редактирует текущую строку. Ввод ограничен 1024 кодовыми единицами
UTF-16; stdin-парсер ограничивает строку 4096 байтами UTF-8.

Пример вывода (фоновые сообщения появляются и во время набора):

```text
READY timeout_ms=15000
HEARTBEAT=1
HEARTBEAT=2
INPUT=hello
HEARTBEAT=3
BACKGROUND_AFTER_INPUT=1
SUBSCRIPTIONS=0
Task keyboard demo OK
```

В сценариях отмены и таймаута вместо `INPUT=...` выводится `CANCELLED` либо
`TIMEOUT`. Пример проверяет, что после завершения ожидания фоновая Task всё ещё
работает и успевает сделать следующий шаг.

## Как устроено

[examples/task_keyboard_demo.das](examples/task_keyboard_demo.das) использует
события и обычный пайповый bind:

```das
def read_user_input() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let text=task_wait_event(input_lines) |> bind
        return text
    }
}
```

Планировщик одновременно исполняет ожидание ввода и независимую фоновую Task
с `task_delay_ms`. CancellationToken и TaskTimeout привязаны только к вводу.
Цикл приложения передаёт в `task_tick` реальное прошедшее время через `now_ms`.

[support/task_keyboard_console.py](support/task_keyboard_console.py) читает
клавиши Windows через `msvcrt.kbhit/getwch`, не ожидая Enter в блокирующем вызове.
Он перерисовывает текущую строку после фоновых сообщений. Полная строка или
команда передаётся дочернему daScript через pipe; после единственного сообщения
запускатель закрывает stdin. Сохранённое событие доставляется раньше Error
закрытого источника — см. [TASK_EVENTS.md](TASK_EVENTS.md).

daScript проверяет `fpoll(...,0)` и читает готовые байты ограниченными порциями,
без `fgets`/`ReadLine`. Используется тот же FILE с выключенной буферизацией и
бинарным режимом. Конечный EOF также позволяет дочитать CRT read-ahead на Windows.
Частичный ввод без Enter не останавливает scheduler. EOF без полной строки даёт
Error закрытого источника; источник и подписки затем освобождаются.

Нативного расширения и зависшего потока чтения клавиатуры нет. Python читает
stdout дочернего процесса отдельным потоком; он завершается по EOF и присоединяется
при выходе. После завершения daScript консольный запускатель сам выходит.
Прямой запуск `.das` с терминальным stdin выводит инструкцию использовать launcher,
поскольку готовность Windows-консоли сама по себе не гарантирует готовность строки.

Запускатель рассчитан на интерактивную консоль Windows. Для автоматизации
используйте stdin-протокол примера или fixture ниже; не перенаправляйте вывод
интерактивного запускателя. При самостоятельном использовании протокола отправьте
одну строку UTF-8 с LF и закройте pipe, либо оставьте его открытым для таймаута.

## Проверки

```powershell
./computation_expressions/test_task_keyboard.ps1
./computation_expressions/test_task_keyboard.ps1 -Jit
```

Fixture запускает настоящий daScript с stdin-pipe: ввод строки, разбиение UTF-8
символа между записями, ожидание без Enter, отмена, таймаут с открытым stdin,
EOF и `/quit`. Проверяются прогресс фоновой Task до и после завершения ожидания,
нулевые подписки, успешное завершение процесса и присоединение stdout-reader.
Консольный UI не требует ручного ввода в CI; интерактивный launcher проверяется
отдельно в терминале. AOT-исполнение этого примера не проверялось.
