# AOT интеграций dasGlfw и dasHV

Из корня репозитория:

```powershell
./reactivex/run_integrations_aot.ps1
# Отдельные каталоги и ограничение параллелизма:
./reactivex/run_integrations_aot.ps1 -Parallel 2 -OutputDirectory ./ci-results/native-aot -BuildDirectory ./reactivex/.work/native-aot-build
```

Требуются Windows x64, Visual Studio 2022 C++, CMake, Python standard library,
оконная сессия и закреплённый Windows SDK 0.6.5-RC2. Окна тестов скрыты;
OpenGL-контекст не создаётся. Сеть используется только для загрузки проверенного
по SHA256 архива libhv при первой сборке и для локального WebSocket fixture.
Внешнего WebSocket-сервиса, установки libhv/OpenSSL или сборки нового I/O-модуля
не требуется. `-Daslang` / `DASLANG_EXE` выбирает этот SDK; runner проверяет
хеши компилятора и native-модулей, поскольку AOT-совместимость привязана к их ABI.

`-BuildOnly` только собирает хост и не означает, что проверки исполнения прошли.
Полный запуск сам конфигурирует отдельный `RX_NATIVE_INTEGRATIONS=ON` target,
генерирует C++, собирает Release-хост, запускает четыре скрипта и отрицательную
проверку. Неполные или неуспешные проверки завершают runner с ошибкой.

## Что исполнено

Локальный прогон 2026-10-19, SDK 0.6.5-RC2:

| Скрипт | Результат |
|---|---|
| `tests/test_glfw_ui.das` | AOT: reducer, подавление дубликатов, Esc, работа фона, снятие callbacks, закрытие и повторное открытие окна, неизменный живой heap |
| `examples/glfw_ui_demo.das` | AOT: скрытое окно, настоящий frame-loop, фоновый timer, автоматическое закрытие |
| `tests/test_websocket_echo.das` | AOT: 22 соединения открыты и закрыты, включая 4 незавершённых handshake; отмена, таймаут, ранний выход, ошибки и освобождение ресурсов |
| `examples/websocket_echo_demo.das` | AOT: 3 сообщения по порядку, отмена из callback, продолжающийся фон, сервер подтвердил закрытие соединения |
| `tests/failed_native_aot_unlinked.das` | Отклонён: AOT-код main отсутствует; тело скрипта не исполняется |

У всех четырёх положительных запусков `main->aot=yes` и strict linking.
Хост использует `fail_on_no_aot=true`. Для ошибки проверки фиксируются exit code
и отдельный runtime log. Отрицательный тест запрещает тихую замену исполнения
скрипта интерпретатором; строка исходника в диагностике не считается выводом тела.

Сетевые проверки покрывают нормальное завершение, `take_until`, `take(1)`,
явную отписку и удаление подписки, отмену до первого poll, ошибку бинарного
сообщения, исключение потребителя и закрытие scheduler. Отмена и таймаут проверены
как на handshake, так и во время ожидания сообщения. После каждого случая
проверяются нулевые native owners/clients/operations, отсутствие timers/hooks,
закрытие соединения на удалённой стороне и отсутствие роста живого daScript heap
при повторении набора. Это те же сценарии, что и в интерпретаторе/JIT.

Дополнительно повторены оба обычных integration runners в интерпретаторе и JIT,
а также AOT-пример ядра, тест владения подпиской и адаптер AsyncSequence.

## Устройство и границы совместимости

Основной AOT-хост ядра и `scripts.ps1` сохраняют прежний состав. Опция native
использует собственный `aot_host/native/main.cpp`, регистрирует JobQue и загружает
только два нужных dynamic module descriptors SDK. Все скриптовые тела CE/Rx и
используемого `dashv_boost` имеют AOT-реализации. Разбор скрипта и инициализация
module descriptors по-прежнему выполняются компилятором daScript.

В SDK 0.6.5-RC2 статические CMake targets GLFW/HV содержат пути машины издателя;
AOT-заголовок HV отсутствует, а GLFW-заголовок не объявляет PollEvents. Поэтому
хост не использует эти static targets и не пересобирает native-транспорт.
Он связывает SDK import libraries GLFW, а недостающие HV/PollEvents вызовы
направляет в native entry points уже загруженных SDK-модулей. Адреса разрешаются
один раз на функцию; для ABI используются SDK `JitSideT` / `ResolvedWrapType`,
в том числе uint64-представление handles. Здесь не вызывается Context::eval
для вычислений приложения и не запускается LLVM JIT.

Проверки и удаление handles также выполняются в исходном native-модуле, чтобы
не создать второй HandleRegistry в хосте. Аллокатор HttpRequest нужен для
связывания полного SDK `dashv_boost` AOT-library и тоже берётся из native-модуля;
новых проверок HTTP API этот прогон не заявляет. Native DLL не копируются вторым
экземпляром: runner временно добавляет исходные SDK-каталоги в PATH и затем
восстанавливает окружение.

Совместимые объявления и generator находятся в `aot_host/native/`.
`upstream_aot_hv_065.h` взят из
[daScript v0.6.5-RC2](https://github.com/GaijinEntertainment/daScript/blob/v0.6.5-RC2/modules/dasHV/src/aot_hv.h),
лицензия — `aot_host/native/LICENSE.dascript`. Перегенерация:
`python reactivex/aot_host/native/generate_hv_header.py`.
Используется закреплённый SDK libhv commit
`303f50c7b23f250c5b620d92c04b41060e1701c2`, SHA256 архива
`43f425dae61d060913c5ce280c9776dfb98c61bb965a38c5a38d4788a7295201`.
CMake только конфигурирует и собирает его include-дерево; libhv не компилируется
и не связывается в хост. Изменение SDK требует отдельной проверки native ABI
и обновления хешей, а не простого снятия проверки версии.

Семантика сети остаётся прежней: DNS может быть синхронным, отмена кооперативная
между poll; тесты используют 127.0.0.1. Успех AOT не расширяет эти гарантии.

## CI и отчёты

Добавлена отдельная job `reactivex-native-aot` на windows-2022. Она устанавливает
закреплённый SDK, собирает и исполняет хост, проверяет отсутствие fallback и
публикует build/runtime logs, peer JSON и `runtime-summary.json`.
Существующие interpreter/JIT и core-AOT jobs остаются отдельными.
Удалённый CI запустится при push/PR; локальный прогон не является его результатом.

По умолчанию результаты находятся в `.work/integrations-aot-runtime/`:
`runtime-summary.json` содержит хеши компилятора и хоста, source stamp, статус
strict linking/main AOT, результат отрицательной проверки и результат каждого
скрипта. `*.peer.json` фиксирует фактическое закрытие соединений сервером.
Хост: `.work/integrations-aot-build/Release/reactivex_aot.exe`.
Для его ручного запуска нужны те же SDK-каталоги в PATH; обычный способ запуска —
runner, который также поднимает loopback fixture и задаёт smoke-режим окна.
