# JSON через derive

`[derive(json=true)]` генерирует сериализацию и типизированное чтение.
`[derive(json=true,validate=true)]` дополнительно проверяет загруженные данные
существующими правилами валидации. Нативный модуль и CE не нужны.

```das
options gen2
require ./lib/derive.das

[derive(json=true,validate=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int
}
[derive(json=true,validate=true)]
struct Player {
    @json_name="displayName"
    @validate_non_empty
    name:string
    stats:Stats
    @json_default=1
    level:int
    @json_skip
    session:int=42
}
[export]
def main() {
    let text="\{\"displayName\":\"Alice\",\"stats\":\{\"health\":85\}\}"
    var inscope loaded <- derive_from_json(text,type<Player>,"player")
    if(loaded.ok) {
        print("{derive_to_json(loaded.value)}\n")
    } else {
        for(issue in loaded.errors) {print("{issue.path}: {issue.message} [{issue.code}]\n")}
    }
}
```

В daScript тип передаётся вторым аргументом `type<Player>`. Результат — owning
кортеж `tuple<ok:bool;value:Player;errors:array<ValidationIssue>>`.
`var inscope` освобождает и значение с вложенными массивами, и ошибки.

## Поля и значения по умолчанию

| Аннотация | Поведение |
|---|---|
| `@json_name="displayName"` | имя при чтении и записи |
| `@json_skip` | поле не читается и не записывается; остаётся инициализатор структуры |
| `@json_required=false` | отсутствие допускается; остаётся инициализатор структуры |
| `@json_default=1` | значение отсутствующего поля; поле становится необязательным |

Без настроек все поля обязательны, даже имеющие обычный инициализатор daScript.
`json_default` принимает числовой, строковый или bool литерал, совместимый с полем;
не создаёт массивы или структуры и не вызывает функции. Явный required=true
вместе с default отклоняется. Флаг skip/required можно также задавать true/false.
Неизвестные, повторные правила, неверные типы метаданных и одинаковые JSON-имена
полей отклоняются при компиляции. JSON-метаданные требуют json=true.

По умолчанию неизвестные ключи игнорируются; строгий режим описан ниже.
`null` не равен отсутствующему полю: для обычных скаляров, структур и массивов
это ошибка типа. Для `$Option<T>` и `$JsonField<T>` предусмотрены отдельные состояния.
Пропущенные поля по-прежнему участвуют в обычной валидации своих значений.
Debug, Equality и Hash не учитывают json_skip и продолжают видеть все поля.

## Диагностика и валидация

Сначала накапливаются ошибки формы JSON в порядке полей структуры и индексов:

- `json_parse`: синтаксис JSON, лимиты, повторные ключи, лишние токены;
- `json_missing`: отсутствует обязательное поле;
- `json_unknown`: неизвестный ключ в строгом режиме;
- `json_type`: несовместимый JSON-тип;
- `json_range`: число не помещается в тип поля;
- `json_enum`: неизвестное имя enum;
- `json_variant`: неизвестный случай variant;
- `json_variant_payload`: payload у случая без данных;
- `json_length`: неверная длина фиксированного массива.

При ошибках формы валидация не запускается: нельзя проверять бизнес-правила
на частично загруженных данных. Если форма корректна, запускаются встроенные и
пользовательские проверки всех типов с validate=true. Контейнеры и JSON-типы без
validate=true рекурсивно передают проверку вложенным JSON-типам.
Если ошибок нет, ok=true и value содержит готовые данные. Иначе ok=false,
частичное значение освобождается и заменяется значением по умолчанию;
использовать value как успешно загруженные данные при !ok нельзя.

Пути используют JSON-имена: `game.players[0].displayName`. Для типов с json=true
это относится и к отдельному `derive_validate`. Пользовательский hook сам строит
путь: для переименованного поля укажите его JSON-имя в `validation_path`.
Корень по умолчанию пустой, путь элемента корневого массива — `[0].health`.

Исключения пользовательских декодеров/валидаторов и ошибки программирования
распространяются наружу, не превращаясь в ValidationIssue. Обёртка освобождает
частичный результат и JSON-дерево перед повторным выбрасыванием.
Сериализация сама не запускает валидацию: она может сохранить значения,
нарушающие бизнес-правила. При необходимости вызовите derive_validate отдельно.

## Типы и ограничения

Поддерживаются string, bool, int8/uint8, int16/uint16, int/uint, int64/uint64,
float/double, динамические и фиксированные массивы и вложенные структуры с
json=true. Для JSON без остальных derive-операций используйте
`[derive(debug=false,equality=false,hash=false,json=true)]`.
Option и JsonField поддерживаются, включая owning-полезную нагрузку.
Enum и именованные variant имеют встроенные кодеки, описанные ниже.
Таблицы и указатели не имеют встроенного JSON кодека. Их можно обернуть пользовательским типом и определить overloads.

Целочисленные литералы JSON должны сохраняться в signed int64 DOM стандартной
библиотеки. Они не проходят через double; 9007199254740993 сохраняется точно.
`uint64` выше INT64_MAX при записи вызывает исключение, при чтении отклоняется:
эта версия не поддерживает весь unsigned 64-bit диапазон. Это ограничение DOM,
а не преобразование по модулю или молчаливая потеря точности. JSON 1.0 не
принимается в целочисленное поле; float/double принимают и целые, и дробные числа,
с обычным округлением целевого floating-типа. NaN/Infinity запрещены при записи;
переполнение floating-поля отклоняется при чтении.

Строки используют JSON escaping стандартной библиотеки. Null-строка daScript
записывается как пустая строка; различие null/empty не сохраняется.
Порядок ключей не является контрактом; сравнивайте данные после round-trip.
Для skipped-полей и явных defaults равенство исходного значения и результата
round-trip возможно лишь если исходные skipped-поля совпадают с defaults.
Сериализация сохраняет пустые массивы независимо от глобального no_empty_arrays;
настройки JSON writer восстанавливаются после вызова.

Чтение использует `read_json_bounded` из штатного `daslib/json`: строгий UTF-8,
запрет повторных ключей, trailing input, некорректных escapes и NUL. Четвёртый
аргумент — `JsonReadLimits`: по умолчанию 1 MiB, глубина 64, 65536 токенов и
65536 байтов в строковом токене. Пример:
`derive_from_json(text,type<Player>,"player",JsonReadLimits(max_bytes=4096))`.
Для расширения лимитов учитывайте расход памяти результата. Запись не ограничивает
размер массива или глубину дерева, создаваемого пользовательским кодом.

## Строгий режим

```das
var inscope loaded <- derive_from_json(text,type<Player>,"player",true)
// С собственными ограничениями парсера:
var inscope limited <- derive_from_json(text,type<Player>,"player",JsonReadLimits(max_bytes=4096),true)
```

Четвёртый bool включает strict; прежний четвёртый JsonReadLimits остаётся совместимым.
Режим по умолчанию false. Строгость передаётся явно через структуры, массивы,
фиксированные массивы, Option и JsonField. Глобальных переключателей нет;
вложенная загрузка с другими настройками не влияет на внешний вызов.

В каждом объекте неизвестные ключи возвращаются как json_unknown с вложенным
путём, в алфавитном порядке; затем проверяются объявленные поля в порядке объявления.
После @json_name разрешено только JSON-имя. Поля с json_skip не входят в допустимые
ключи: их присутствие в строгом режиме является ошибкой. Неизвестные ключи
накапливаются вместе с json_missing/json_type/json_range; валидация по-прежнему
не запускается при любых структурных ошибках. Проверка синтаксиса, повторных ключей
и лимитов выполняется до проверки схемы в обоих режимах.

## Option, null и присутствие ключа

Используется стандартный `$Option<T>` из daslib/option. Он доступен через require
derive и совместим с остальным кодом SDK. Для трёх состояний есть `$JsonField<T>`:

```das
[derive(json=true,validate=true)]
struct Profile {
    // Обязательный ключ, nullable-значение.
    nickname:$Option<string>

    // Необязательный ключ: все три состояния сохраняются при round-trip.
    @json_required=false
    @validate_min_length=2
    bio:$JsonField<string>
}
```

| Поле | Ключ отсутствует | JSON null | Значение T |
|---|---|---|---|
| T (по умолчанию required=true) | json_missing | json_type | T |
| Option<T> (required=true) | json_missing | none | some(T) |
| Option<T> с required=false | инициализатор, обычно none | none | some(T) |
| JsonField<T> с required=false | инициализатор, обычно missing | null_value | present(T) |

JsonField по умолчанию тоже required=true: для разрешения отсутствия укажите
@json_required=false. Optional-поля сохраняют обычный инициализатор структуры.
Например, `note:$Option<string> = some("guest")`: отсутствие оставит Some("guest"),
явный null заменит его на None. json_default по-прежнему задаёт скалярный литерал;
для Option/JsonField используйте обычный типизированный инициализатор.

При записи Option.none становится null. JsonField.missing пропускает ключ объекта,
null_value записывает null, present записывает payload. Missing в корне или элементе
массива не имеет JSON-представления и вызывает исключение; используйте null_value
для явного null. Сериализация не проверяет required: Missing в required-поле
будет опущен, и такой JSON не пройдёт последующую загрузку.

Проверка состояний: `value is missing`, `value is null_value`, `value is present`,
`value as present`; для Option — `is none`, `is some`, `as some`.
Конструкторы: `json_missing(type<T>)`, `json_null(type<T>)`, `json_present(value)`
и `json_move_present(varValue)`. Первый present копирует/clones payload;
move_present передаёт владение и опустошает источник. Для Option доступны штатные
some/move_some/none. Пустой JsonNull — служебный marker для состояния null_value.

Debug, Equality, Hash и валидация поддерживают обе обёртки. Правила min/max,
non_empty и ограничения длины применяются только к Some/Present. None, Missing
и Null пропускаются; если нужно запретить null, используйте обычный T или свой hook.
Вложенные проверки payload сохраняют путь поля, без служебных .some/.present.

Для трёх состояний используйте ровно один JsonField над ненулевым T. Вложенные
nullable-обёртки не создают дополнительных JSON-состояний: например, Some(None)
и None записываются одинаковым null, поэтому их произвольный round-trip не обратим.
JsonField<Option<T>> имеет ту же неоднозначность для Present(None) и Null.

См. examples/json_presence_demo.das, tests/test_json_presence.das,
tests/test_json_strict.das и tests/test_json_presence_owned.das.

## Enum и tagged variant

Обычным enum и variant не нужна аннотация derive: кодеки доступны автоматически.
Аннотация остаётся у содержащей структуры и у структур payload.

```das
enum Role {
    Warrior
    Mage
}
[derive(json=true,validate=true)]
struct Move {
    @validate_min=0
    x:int
    y:int
}
variant Action {idle;move:Move;text:string;items:array<int>}
[derive(json=true,validate=true)]
struct Player {role:Role;action:Action}
```

Пример JSON:

```json
{"role":"Mage","action":{"case":"move","value":{"x":3,"y":4}}}
```

Enum читается только точным строковым именем (учитывается регистр), без номера,
полного имени типа или сочетаний флагов. Неизвестное имя даёт json_enum, число/null —
json_type. Записываются только значения с объявленным именем; необъявленное
underlying-значение вызывает исключение. Все aliases принимаются при чтении;
при записи выбирается первое объявленное имя этого значения. RTTI-значение
переносится с сохранением битов backing-типа, включая signed/unsigned 64-bit:
для enum это строковый протокол без ограничения signed int64 JSON-чисел.

Enum без члена 0 поддерживается в корне, массивах, Option/JsonField и payload.
Временное начальное значение корневого enum — первый объявленный член.
Если сам daScript требует инициализатора enum-поля структуры без 0, объявите его:
`role:Role=Role.Warrior`. JSON обязательность поля от этого не меняется.

Случай variant без payload записывается как `{"case":"idle"}`. Случай с payload
обязательно содержит value — в том числе для допустимого null:
`{"case":"nullable","value":null}` при payload Option<T>.
Payload может быть скаляром, enum, структурой, массивом, вложенным variant или
Option/JsonField; для неподдержанного типа нужен пользовательский кодек.

Отсутствующая case/value даёт json_missing по соответствующему пути; case не
строкового типа — json_type; неизвестный случай — json_variant. value у void-случая
даёт json_variant_payload, даже если это null и strict=false. Лишние ключи объекта
variant и его payload проверяются рекурсивно в strict-режиме. Порядок объявления
случаев не кодируется числом: wire-метка — имя случая.

Ошибки структур и бизнес-правил payload имеют путь вроде
`game.commands[2].value.x`; элементы payload-массива — `.value[0].x`.
Обрабатывается только выбранный payload; неактивные случаи не читаются и не
валидируются во время выполнения. Все типы случаев должны компилироваться.
При смене случая освобождается прежний owning-payload. Высокоуровневый loader
сохраняет атомарность; низкоуровневый derive_json_read может изменить случай
до обнаружения ошибки payload. Исключения кодеков и hooks распространяются с
очисткой частично построенного результата.

Встроенные Debug, Equality, Hash и валидация также поддерживают variant,
сравнивая/обходя только активный случай. Void-случаи не вызывают payload-код.
Для JSON payload проверяется после успешного структурного чтения всего документа.

Option и JsonField сохраняют свой прежний компактный JSON-формат, а не tagged
object. daScript использует structural variants: тип, структурно совпадающий
с Option (none/some) или JsonField (missing/null_value/present), получает те же
специализированные кодеки, даже если объявлен под другим именем. Для отдельного
протокола используйте другие имена случаев или собственный codec.

Tagged-кодеки генерируют безопасное создание известного случая, а не устанавливают
произвольный числовой tag из JSON. Имена enum берутся из RTTI; выбор payload
разворачивается макросом при компиляции. Глобальных регистраций моделей нет.
Для собственного wire-формата variant определите derive_json_encode и
контекстный derive_json_read со strict, как для пользовательских типов ниже.

Пример: examples/json_enum_variant_demo.das. Проверки:
tests/test_json_enum_variant.das и tests/test_json_enum_variant_owned.das —
широкие/отрицательные enum, aliases, варианты без данных, owning payload,
вложенность, strict, накопление, исключения и освобождение памяти.

## Пользовательские типы

Определите в модуле модели обе функции:

```das
struct External {text:string}
def derive_json_encode(value:External) : JsonValue? {return JV(value.text)}
def derive_json_decode(node:JsonValue?;var value:External;
                       path:string;var errors:array<ValidationIssue>) {
    derive_json_decode(node,value.text,path,errors)
}
```

Encoder возвращает новое JSON-дерево с уникальным владением, которое получает
вызывающий код. Decoder заимствует node, заполняет value и добавляет ошибки через
`derive_json_error(errors,path,message,code="json_type")`. Он не освобождает и не
сохраняет указатель node. Пользовательский код отвечает за очистку собственных
промежуточных ресурсов перед исключением. Для кодека, который оборачивает вложенную модель и должен передавать strict,
определите `derive_json_read(node;var value:MyType;path;var errors;strict:bool)`.
В нём вызывайте derive_json_read для дочерних значений, передавая strict. Старый
четырёхаргументный derive_json_decode остаётся совместимым; его внутреннее
представление считается непрозрачным, и проверять неизвестные ключи внутри
собственного JSON-формата должен сам кодек. Обёртка strict не угадывает эту схему.
Низкоуровневый decoder может частично
изменить переданное значение; атомарность обеспечивает derive_from_json.
Для пользовательской валидации такого типа можно определить derive_json_validate.

## Запуск и AOT

- `examples/json_demo.das`: имена, defaults и пользовательская проверка.
- `examples/json_game_demo.das`: owning-массив игроков, round-trip, накопление ошибок.
- `tests/test_json.das`: вложенные пути, фазы, optional, память.
- `tests/test_json_numbers.das`: границы, строгий парсер, лимиты.
- `tests/test_json_custom.das`: custom codecs, исключения и освобождение владения.

Все сценарии входят в `scripts.json` и существующий derive CI.
Запуск: `./derive/run.ps1 -Test`, `./derive/run.ps1 -Test -Jit`,
`./derive/run_aot.ps1`. AOT-хост собирается и запускает сценарии с fail_on_no_aot,
а не только генерирует C++. Для собственного хоста нужны aotlib модулей derive
runtime, моделей приложения и стандартных json/json_boost/strings_boost/utf8_utils
(см. aot_host/CMakeLists.txt).

Счётчик heap_bytes_allocated в тестах проверяет живые массивы и JSON-узлы после
прогрева, но не общую память процесса и не string heap. Результат не хранит
JSON-указателей; его строки и массивы можно использовать после удаления дерева.
Экспорт standalone включает все шесть модулей, JSON.md и примеры.

Ограничение SDK JIT/AOT для default фиксированных массивов с default-полями и проверенный обход: [repros/README.md](repros/README.md).
