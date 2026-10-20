# Ограничение JIT/AOT SDK 0.6.5-RC2: default фиксированного массива

`jit_fixed_array_default.das` не импортирует derive. Интерпретатор выполняет его
успешно, но LLVM JIT завершается при компиляции с `field session not found`:

```powershell
& $Daslang ./derive/repros/jit_fixed_array_default.das -no-module-cache
& $Daslang ./derive/repros/jit_fixed_array_default.das -no-module-cache -jit -jit-no-cache
```

Триггер: `default<Item[1]>` в инициализаторе поля, если Item сам содержит
инициализаторы полей. Этот файл намеренно не входит в положительный scripts.json.
Отдельное AOT-исполнение минимального repro не проверялось. Однако полный
strict-тест с исходным default<PresenceUser[1]> также не собирался в AOT:
сгенерированный C++ обращался к session/__this у TDim<PresenceUser,1> (C2039).
Это тот же неверно раскрытый инициализатор, обнаруженный двумя backend. Полный strict-тест
проверяет каждый режим отдельно, а не выводит успех JIT из интерпретатора/AOT.

Обход, сохраняющий значения defaults:

```das
struct Item {session:int=42}
def default_item() {return Item()}
struct Container {items:Item[1]=fixed_array(default_item())}
```

В `tests/test_json_strict.das` используется этот приём с owning-структурой
PresenceUser; проверяются defaults, JSON strict, массивы, Option, JsonField,
накопление ошибок и освобождение памяти. Дополнительная factory нужна только
для этого сочетания инициализаторов в SDK; это не глобальное отключение JIT
и не перенос декодирования в интерпретатор.


## AOT стандартного Option с empty struct

`aot_option_empty.das` импортирует только daslib/option. Интерпретатор и JIT
исполняют some(EmptyPayload()), но сгенерированный C++ не компилируется на
SDK 0.6.5-RC2: TVariant<4,4,void,EmptyPayload> нарушает static_assert в aot.h
(variant with no payload), а вложенный TTuple также может получить неверный размер.
Сам empty struct имеет размер 0 в daScript и 1 в C++, что нарушает layout payload.
Минимальный repro проверяется генерацией C++ и компиляцией отдельного object target
без библиотечных derive-функций. В полном Patch AOT-хосте первоначальный тест
Option<EmptyPatchRoot> также воспроизвёл эту ошибку.

Repro намеренно не входит в положительный manifest. Patch выдаёт раннюю ошибку
при sizeof(root)==0 одинаково в интерпретаторе/JIT/AOT. Для своей корневой модели
добавьте реальное поле; пустой массив и None остаются поддержанными.


## AOT move_some оставляет вложенный variant в исходном struct

`aot_move_some_source.das` импортирует только стандартный Option. Интерпретатор
и JIT обнуляют source после move_some структуры с owning Option-полем.
Обычный struct с одним массивом обрабатывается корректно.
В C++ SDK 0.6.5-RC2 конструктор variant
может присвоить payload без обнуления source. Последующий delete исходника
затрагивает данные Option. Builder явно обнуляет уже переданное хранилище
через memzero, до его очистки; owning-проверки включены в строгий AOT-набор.
Repro ожидает обычный контракт move_some и не включён в положительный manifest.
