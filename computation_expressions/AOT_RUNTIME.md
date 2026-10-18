# Сборка и исполнение AOT

```powershell
./run_aot.ps1 -Daslang C:/sdk/bin/daslang.exe
```

Нужны Windows x64, Visual Studio 2022 с C++ toolchain, CMake и SDK Daslang v0.6.5-RC2
с headers, import libraries и runtime DLL. Скрипт собирает host в `.work/aot-build`,
сохраняет runtime-логи и JSON в `.work/aot-runtime` и запускает каждый из 39
положительных тестов (27 Task, восемь AsyncSequence и четыре Parser/Search/Query/deferred) отдельным процессом. Список берётся из mode_tests.json;
отрицательные компиляционные тесты и сетевой fixture туда не входят.
Скрипт задаёт DAS_DIR явно, чтобы ранее настроенный build-каталог не сохранял
другой SDK из кеша CMake при изменении -Daslang.
Перед сборкой и после неё runner сравнивает SHA-256 исходников библиотеки,
выбранных тестов и support. Если исходники менялись параллельно, прогон
прерывается: требуется повторная сборка согласованных AOT-файлов.
Для Parser отдельно генерируется AOT стандартного daslib/strings_convert.

Процесс соответствует [официальному AOT workflow](https://daslang.io/doc/reference/tutorials/integration_cpp_13_aot.html):

1. `daslang -aot test.das test.cpp` генерирует код теста и его generic-функций.
2. `-aotlib` генерирует runtime-модули зависимостей: одного .cpp теста недостаточно
   для негeneric библиотечных функций.
3. CMake компилирует все .cpp и связывает их с DAS::libDaScriptDyn из SDK.
4. Host включает policies.aot и fail_on_no_aot, проверяет simulate и main->aot,
   затем вызывает main через evalWithCatch. Исключение или отсутствие AOT даёт
   ненулевой exit; интерпретатор не используется как скрытый fallback тестов.

Для долгоживущих задач host явно задаёт `policies.persistent_heap=true`.
Именно policy применяется при simulate: одного аргумента `true` конструктору
Context недостаточно. Persistent heap возвращает блоки при произвольном порядке
освобождения captures и итераторов. Линейный heap по умолчанию может удерживать
освобождённые блоки до сброса контекста; для него нельзя требовать постоянного
heap_bytes_allocated между повторными запусками. Проверки ниже используют
persistent heap, как основной runner SDK.

Проверяются три разных результата: интерпретатор, JIT, AOT runtime. Отдельная
генерация C++ остаётся в `run_modes.ps1 -Mode AotGenerate`; она не доказывает
ни сборку, ни исполнение. runtime-summary.json содержит exit и явный результат
AotRuntimePassed по каждому файлу. В нём проверяется наличие контрольной строки
host после проверки main->aot.

Для C++ исправлены размеры служебных меток: вместо zero-sized daScript-структур
используется байтовое поле, чтобы layout tuple совпадал с C++. Полезная семантика
CeUnit не изменилась. result_ok/some снимают const/ref с payload: иначе SDK мог
сгенерировать variant с const-полем, которому C++ запрещает присваивание.
Сгенерированный C++ вручную не исправляется.
`move_ok` создаёт variant и затем перемещает payload отдельным присваиванием:
для поля `ok <- value` прямо в конструкторе variant SDK 0.6.4 мог сгенерировать
shallow copy, не очистив исходного владельца. Проверка включает owning пары
в TaskResult and_bind и task_result_race, а также состояние исходного payload.

В SDK 0.6.4 и v0.6.5-RC2 обнаружено отдельное отличие AOT `das_try_recover`: обработчик
вызывается до установки `last_exception` и восстановления контекста, поэтому
теряется текст ошибки, а повторный panic из recover может попасть в тот же handler.
Шаблон хоста принудительно подключает `aot_host/recover_064.h` ко всем единицам
трансляции. Этот локальный shim воспроизводит порядок интерпретатора: сначала
восстанавливает стек, ABI и внешний throwBuf, сбрасывает stopFlags, переносит
exception в last_exception, затем вызывает handler. DLL и исходники SDK не меняются.
На 0.6.5 также восстанавливается fastCallDepth перед handler.
Имя recover_064.h сохранено для совместимости структуры экспорта.
При собственном хосте используйте тот же header и настройки CMake;
одной линковки с SDK без этого обхода для проверяемых сценариев недостаточно.

Скрипт рассчитан на текущий Windows SDK. Это проверка перечисленных Task/AsyncSequence/Parser/Search/Query-сценариев,
не утверждение о любом произвольном builder, внешнем модуле или C++-хосте. Известные
State/JIT repro из RELIABILITY.md остаются отдельными проверками другого режима.
