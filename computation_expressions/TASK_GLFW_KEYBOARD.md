# Клавиатура окна dasGlfw и Task

Из корня checkout:

```powershell
./computation_expressions/run_task_glfw_keyboard.ps1
```

Нужен Daslang 0.6.4 с установленным SDK-модулем `glfw` (dasGlfw).
Python, внешний процесс чтения и новый нативный модуль не используются.
PowerShell-скрипт только запускает `.das`; сам ввод полностью обрабатывается
daScript и существующими callbacks GLFW.

```powershell
./computation_expressions/run_task_glfw_keyboard.ps1 -TimeoutMs 30000 -Jit
```

Путь компилятора задаётся `-Daslang` или `DASLANG_EXE`, локальный fallback —
`C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe`. Можно запустить
[examples/task_glfw_keyboard_demo.das](examples/task_glfw_keyboard_demo.das)
напрямую через daslang.exe, без скрипта; таймаут по умолчанию — 15 секунд.

## Управление

Дайте фокус появившемуся окну. Ввод, состояние ожидания и фоновый счётчик
видны в **заголовке окна**. Это минимальный пример без рендерера и текстового
виджета: GLFW создаёт окно с `GLFW_NO_API`, OpenGL-контекст не нужен.

- Печатайте текст; Backspace удаляет последний Unicode code point.
- Enter завершает ожидание строкой; пустая строка тоже допустима.
- Esc отменяет только ожидание ввода.
- Если ничего не подтверждать, срабатывает таймаут.
- F2 после завершения, отмены или таймаута начинает новое ожидание с новым сроком.
- Закройте окно крестиком для завершения всего примера.

Фоновая Task увеличивает счётчик каждые 500 мс, включая время набора, а также
после завершения/отмены/таймаута. Окно остаётся открытым. F2 не перезапускает
фоновую задачу и не сбрасывает её счётчик. F2 во время активного ожидания
игнорируется, поэтому удержанием клавиши нельзя продлевать его срок.

Поддерживается до 64 code points, включая кириллицу и astral Unicode.
Backspace работает по code points, а не по grapheme clusters; полноценного
редактора и UI для IME composition этот пример не реализует.

## Поток событий

Общая реализация примера находится в
[support/task_glfw_keyboard.das](support/task_glfw_keyboard.das).
Это демонстрационный модуль с одним окном, не новый публичный builder.

```das
def private read_input() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let value=task_wait_event(events) |> bind
        continued++
        return value
    }
}
```

`glfwPollEvents` доставляет key/char callbacks. Char callback получает Unicode
code point; key callback обрабатывает Enter, Esc, Backspace и F2. Enter вызывает
`task_event_emit`, Esc запрашивает CancellationToken. Callbacks не возобновляют
CE напрямую: затем игровой цикл вызывает `task_tick(scheduler,now_ms)`.
В примере часы берутся из `glfwGetTime`; проверки используют виртуальное время.

CancellationToken и TaskTimeout относятся только к вводу. Фоновая Task работает
в том же планировщике и приостанавливается через `task_delay_ms(...) |> bind`.
Если Enter и Esc обработаны до следующего tick, отмена имеет приоритет над
уже сохранённым событием. Повторный Enter не публикует несколько результатов.

Подписка Task удаляется при успехе, отмене и таймауте. Оконные callbacks остаются
до закрытия окна, чтобы работали редактирование и F2; это другой срок владения.
Пример держит владельцев script lambdas, потому что native callback registry
не владеет ими. При закрытии сначала вызывается `glfw_chain_clear`, затем
удаляются и явно обнуляются lambdas, закрывается планировщик, освобождается
источник событий, уничтожается окно и вызывается `glfwTerminate`.
Повторное закрытие безопасно в интерпретаторе и JIT.

Пример владеет своим GLFW init/terminate. При встраивании в существующую игру
используйте её окно и цикл событий вместо создания второго владельца GLFW.
Обработка окна и Task выполняется в одном потоке.

## Проверки без Python

```powershell
./computation_expressions/test_task_glfw_keyboard.ps1
./computation_expressions/test_task_glfw_keyboard.ps1 -Jit
```

[tests/test_task_glfw_keyboard.das](tests/test_task_glfw_keyboard.das) создаёт
настоящее **скрытое** окно GLFW без графического контекста и подаёт события через
штатные `glfw_post_key` / `glfw_post_char`. Это тест native dispatch и script
callbacks, а не симуляция физических нажатий клавиш ОС.

Проверяются Unicode и Backspace, игнорирование invalid code points и repeat,
Enter и пустой ввод, Esc, таймаут, новый срок после F2, отмена сохранённого события,
рост фонового счётчика, закрытие окна при активном ожидании, отсутствие подписок
и владельцев callbacks после закрытия. Повторные циклы создания/закрытия проверяют
неизменность `heap_bytes_allocated()` после прогрева.

Runner также выполняет настоящий entrypoint примера в скрытом smoke-режиме:
реальные часы, фоновая Task и автоматическое закрытие окна. Для отдельного запуска:

```powershell
./computation_expressions/run_task_glfw_keyboard.ps1 -SmokeTest -TimeoutMs 1000
```

Проверки требуют доступного windowing session: при ошибке glfwInit/CreateWindow
они завершаются ошибкой, не выдавая пропуск за успех. Проверяются интерпретатор
и JIT; AOT-исполнение этого оконного примера не проверено.
