# Валидация через derive

Включается явно: `[derive(validate=true)]`. Debug, Equality и Hash продолжают
генерироваться по умолчанию. Для одной валидации используйте
`[derive(debug=false,equality=false,hash=false,validate=true)]`.

```das
require ./lib/derive.das

[derive(validate=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int
}
[derive(validate=true,check="check_player")]
struct Player {
    @validate_non_empty
    @validate_min_length=2
    name:string
    stats:Stats
}
def check_player(value:Player;path:string;var errors:array<ValidationIssue>) {
    if(value.name=="admin") {
        validation_add(errors,validation_path(path,"name"),"reserved name","reserved")
    }
}
// Внутри функции:
// var inscope errors <- derive_validate(player,"player")
// for(issue in errors) {print("{issue.path}: {issue.message}\n")}
```

## Правила полей

| Аннотация | Тип поля | Условие |
|---|---|---|
| `@validate_min=0` | числовой скаляр | значение >= границы |
| `@validate_max=100` | числовой скаляр | значение <= границы |
| `@validate_non_empty` | string, array, фиксированный массив | length > 0 |
| `@validate_min_length=2` | те же | length >= границы |
| `@validate_max_length=20` | те же | length <= границы |

Границы — литералы аннотаций. Длины — неотрицательные `int`.
`@validate_non_empty=false` отключает правило. Неизвестные и повторные правила,
неверные типы и противоречивые границы отклоняются при компиляции.
Строковая длина измеряется в байтах UTF-8. Null-строка имеет длину 0.

Целочисленные поля требуют целочисленных границ: сравнение signed/unsigned и
64-битных значений выполняется без преобразования в double. Для float/double
границы должны быть floating либо целыми до 32 бит включительно. NaN нарушает
каждое заданное min/max правило; без правил скаляр сам по себе допустим.
Векторы не поддерживают min/max.

## Вложенные данные и накопление

`derive_validate(value,root="")` возвращает owning `array<ValidationIssue>`.
У каждого элемента есть `path`, `message` и `code`. Используйте `var inscope`
или самостоятельно освободите массив. Входные owning-данные заимствуются и
не меняются. Валидация выполняется явно и не отслеживает последующие изменения.

Вложенные структуры требуют `[derive(validate=true)]` либо перегрузки
`derive_validate_into(value:MyType;path:string;var errors:array<ValidationIssue>)`.
Динамические и фиксированные массивы обходятся рекурсивно. Пример пути:
`game.players[0].stats.health`; массив в корне без имени даёт `[0].health`.

Ошибки накапливаются: поля в порядке объявления, правила поля в порядке записи,
затем вложенные значения этого поля. Все совпавшие нарушения сохраняются,
поэтому пустая строка может дать одновременно non_empty и min_length.
Встроенные коды: `min`, `max`, `non_empty`, `min_length`, `max_length`.

Низкоуровневый `derive_validate_into(value,path,errors)` добавляет к существующему
массиву. `validation_add(errors,path,message,code="custom")` добавляет ошибку,
`validation_path(parent,field)` соединяет имена через точку, обрабатывая пустой корень.
Имена полей и корней не экранируются; path — диагностическая строка, не парсер адресов.

## Пользовательские проверки

`check="check_player"` задаёт простое имя функции в модуле структуры. Функция
принимает заимствованное значение, путь и изменяемый массив ошибок и возвращает void.
Её можно объявить после структуры. Она вызывается один раз после всех полей и
вложенных проверок, даже если встроенные правила нашли ошибки. Никаких скрытых
повторных вызовов из-за `typeinfo` нет. Для чужих типов можно определить перегрузку
`derive_validate_into`, как в тесте пользовательских проверок.

Исключения пользовательских проверок распространяются как исключения, не превращаясь
в ValidationIssue. `derive_validate` освобождает частичный массив перед повторным
выбрасыванием. В `derive_validate_into` частичный массив остаётся у вызывающего кода.
Проверки должны завершаться; библиотека не ограничивает произвольный пользовательский код.

## Проверки полей, элементов и уникальности

```das
[derive(validate=true)]
struct Roster {
    @validate_check="check_title"
    title:string
    @validate_each="check_player_entry"
    @validate_unique_by="player_id"
    players:array<CheckedPlayer>
}

def check_title(value:string;path:string;var errors:array<ValidationIssue>) {
    if(value=="admin") {validation_add(errors,path,"reserved title","reserved")}
}
def check_player_entry(value:CheckedPlayer;path:string;var errors:array<ValidationIssue>) {
    if(value.id<=0) {validation_add(errors,validation_path(path,"id"),"positive id required","player_id")}
}
def player_id(value:CheckedPlayer) : int {return value.id}
```

`CheckedPlayer` и полный запускаемый пример находятся в
[collection_validation_demo.das](examples/collection_validation_demo.das) и его model-модуле.

- `@validate_check="function"`: один вызов с самим полем, его путём и массивом
  ошибок. Функция возвращает void и может добавить любое число ошибок.
  Получает точный тип поля, включая Option/JsonField: пользователь сам решает,
  как проверять None/Missing/Null. Это отличается от встроенных payload-правил.
- `@validate_each="function"`: тот же контракт для каждого непосредственного
  элемента динамического или фиксированного массива. Путь содержит индекс,
  например `game.players[2]`; проверка может добавить `.id`. Для массива массивов
  функция получает целую строку, а не каждый скаляр. Пустой массив не вызывает функцию.
- `@validate_unique_by="function"`: selector принимает заимствованный элемент и
  возвращает ключ. Он вызывается ровно один раз на элемент слева направо; typeinfo
  не вызывает его во время выполнения. Ключи сравниваются через `derive_equal`;
  Hash не требуется. Поддержаны строки, числа и собственные ключи с derive_equal,
  включая возвращаемые owning-массивы. Не возвращайте ресурсный handle без
  соответствующих правил равенства и владения.

Each и unique_by требуют непосредственно массив, не Option/JsonField-массив;
для обёрнутых коллекций используйте validate_check. Имена callback — простые
имена функций в модуле модели; определения могут следовать за структурой.
Перегрузки разрешаются по типу аргумента. Пользовательский код не должен менять
валидируемую коллекцию через внешнюю ссылку. Selector и равенство должны быть
стабильными для одного значения.

Для каждого повторного ключа создаётся одна ошибка `code="unique"` на пути
повторного элемента; сообщение содержит путь первого совпадения. Три одинаковых
ключа дают две ошибки. Сравнения занимают O(n²) в худшем случае, временные ключи —
O(n) памяти. Ключи освобождаются и при нормальном завершении, и при исключении
selector/равенства. Не владеющие указатели в пользовательском ключе остаются
ответственностью автора selector.

Правила выполняются в порядке аннотаций. Каждое each/unique_by полностью обходит
массив до следующего правила; затем запускается обычная вложенная валидация.
Ошибка не прекращает последующие проверки; исключение прекращает и распространяется.
Пути учитывают JSON-имена так же, как встроенные правила. При загрузке JSON эти
проверки запускаются после успешного структурного чтения вместе с остальной валидацией.

## Примеры и проверки

- `examples/validation_demo.das`: минимальная вложенная структура.
- `examples/game_validation_demo.das`: массив игроков, шесть ошибок и бизнес-правило.
- `tests/test_validation.das`: вложенные массивы, пути, накопление, независимое время жизни ошибок.
- `tests/test_validation_numbers.das`: точные 64-битные границы, NaN, UTF-8, длины.
- `examples/collection_validation_demo.das`: поля, элементы, повторные идентификаторы.
- `tests/test_validation_collections.das`: порядок и накопление ошибок, вложенные пути, JSON, fixed arrays, owning-ключи, исключения и память.
- `tests/test_validation_custom.das`: перегрузки, порядок, исключения и освобождение массивов.

Запуск: `./derive/run.ps1 -Test`, затем `-Test -Jit` и `./derive/run_aot.ps1`.
Все новые сценарии входят в manifests и существующие derive-шаги GitHub Actions.
Для собственного AOT-хоста требуется также `-aotlib lib/derive_validation.das`.
Проверки памяти измеряют живой context heap массивов после прогрева; string heap
и общую память процесса этот счётчик не измеряет.

Для типов с `[derive(json=true)]` встроенные пути учитывают `@json_name`.
Загрузка с валидацией и разделение ошибок описаны в [JSON.md](JSON.md).

Встроенные правила для Option и JsonField проверяют только Some/Present. None/Missing/Null пропускаются;
числовые и строковые правила относятся к payload, а не к обёртке.

Variant валидирует активный payload с путём .value; случаи без данных
не вызывают проверок payload. Enum из JSON проверяется на известное имя при чтении.
