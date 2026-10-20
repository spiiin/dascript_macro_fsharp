# Derive JSON Schema

```das
require ./lib/derive.das

[derive(json=true,validate=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int=100
}
[derive(json=true,validate=true)]
struct Player {
    @json_name="displayName"
    @validate_non_empty
    name:string
    stats:Stats=Stats()
    @json_required=false
    alias:$Option<string>
}

let strict=derive_json_schema(type<Player>)
let loose=derive_json_schema(type<Player>,false)
```

`derive_json_schema(type<T>,strict=true)` — call macro, возвращающий строку JSON
Schema [Draft 2020-12](https://json-schema.org/draft/2020-12/json-schema-validation).
Дополнительного флага `[derive(schema=true)]` нет: схема берёт уже существующий
контракт `[derive(json=true)]`. Все вложенные структуры также требуют json=true.
Поддержаны скаляры, enum, массивы, фиксированные массивы, Option, JsonField и
variant в корне. Custom JSON codecs требуют своей схемы: её представление нельзя
угадать по layout структуры.

Схема целиком строится при компиляции и попадает в программу как строковая
константа. Модели и их defaults не создаются, callbacks не вызываются. При
исполнении не нужны AST/reflection или новый нативный модуль. `strict` — bool
literal; переменная здесь даст диагностику на строке вызова макроса.

## Представление и правила

| Контракт daScript | JSON Schema |
|---|---|
| Структура | object с properties, required, additionalProperties |
| Повторные/рекурсивные структуры | Общие `$defs` и `$ref` по `module::Type` |
| string / bool | string / boolean |
| Целочисленный скаляр | integer с границами разрядности; uint64 ограничен signed JSON int64 |
| float / double | number; конечность и округление дополнительно проверяет загрузчик |
| enum | string, enum всех имён, включая aliases |
| array | array с items |
| T[N] | array с items, minItems=N, maxItems=N; измерения сохраняют порядок |
| Option / JsonField | anyOf: null или схема payload; missing регулирует required поля |
| variant | oneOf: объект с case=const и обязательным value для non-void |
| void case | value запрещён, в том числе в loose-режиме |
| validate_min / validate_max | minimum / maximum для целых и double; float32 отмечен x-das-minimum/x-das-maximum |
| Длина массива / non_empty | minItems / maxItems |
| non_empty строки | minLength=1 |

В strict-режиме неизвестные поля запрещены на всех уровнях, включая payload
variant. В loose-режиме разрешены, как у derive_from_json(...,false).
`json_name` меняет имя свойства, `json_skip` исключает его. Поэтому strict JSON
не может содержать даже native-имя переименованного или пропущенного поля.

`required` повторяет правила **JSON-загрузчика**, независимо от Builder:
`json_required` по умолчанию true; `json_default` разрешает пропуск.
Option/JsonField сами по себе не делают поле необязательным. Native default
не отменяет json_required. `builder_required` сохраняется лишь в метаданных
`x-das-builder-required`: он относится к другому этапу.

`default` — аннотация, не операция заполнения данных в JSON Schema.
Генерируются scalar json_default и распознаваемые нативные scalar literals/enum.
JSON default имеет приоритет. Нативные factory calls, составные initializer и
прочие выражения не вычисляются: они отмечены x-das-native-default=true.
Отсутствие default в схеме не отменяет обычного default daScript.

## Границы точности

Схема полезна для редактора/автодополнения и структурных проверок, но не заменяет
JSON-парсер и derive_validate.

- Произвольные check, validate_check, validate_each, validate_unique_by остаются
  требованиями daScript, отмеченными x-das-check / x-das-validate_*. В частности,
  уникальность по ключу не заменяется uniqueItems: это разные условия.
- length(string) в текущей библиотеке считает UTF-8 **байты**. Стандартный
  minLength/maxLength считает Unicode-символы. Поэтому байтовые пределы записаны
  как x-das-byteMinLength/x-das-byteMaxLength; minLength=1 сохраняет требование
  непустой строки при любом положительном байтовом минимуме. Для N>1 схема не отвергает корректный
  Unicode из-за смешения единиц; точную проверку выполняет derive_validate.
- Границы float32 отмечены x-das-minimum/x-das-maximum. Например, float(0.1)
  сравнивается с округлённой float-границей; стандартный minimum по её точному
  double-представлению отверг бы исходный JSON 0.1. Точную проверку делает
  загрузчик с derive_validate; стандартная схема ограничивает здесь только type.
- JSON Schema integer описывает математическое число: 1.0 может пройти внешний
  validator, хотя загрузчик требует целочисленный JSON token. Размеры/лимиты
  парсера, float overflow, строки с NUL и округление проверяются загрузчиком.
- Любые внешние side effects, native constructor exceptions и откат состояния
  не являются свойствами JSON Schema.

Общие типы не раскрываются бесконечно: рекурсия через массивы даёт ref.
Защитные пределы макроса: 256 разных структур и 96 шагов обхода типового графа.
Неподдержанные таблицы, указатели, векторы и custom codecs дают compile error.

## Примеры и проверки

- [schema_demo.das](examples/schema_demo.das): strict/loose, рекурсия, enum,
  tagged variant, Option/JsonField и фиксированные массивы.
- [workflow_model.das](examples/workflow_model.das) и
  [workflow_demo.das](examples/workflow_demo.das): Builder → validate → JSON →
  strict load → Clone → Diff → Patch. Конфликты и validation failure сохраняют
  исходник; независимые изменения сохраняются. Owning snapshots живут после
  удаления inputs/draft.
- test_schema.das и test_workflow.das входят в interpreter/JIT/strict AOT manifest,
  с 32 повторами проверки heap после прогрева.

```powershell
./derive/run.ps1 -Test
./derive/run.ps1 -Test -Jit
./derive/run_aot.ps1
# Дополнительный независимый validator, только для тестов:
python -m pip install jsonschema==4.23.0
python ./derive/tests/test_schema_jsonschema.py
python ./derive/tests/test_schema_jsonschema.py --jit
python ./derive/tests/test_schema_jsonschema.py --output-log ./derive/.work/aot-runtime/schema_demo.runtime.log --workflow-output-log ./derive/.work/aot-runtime/workflow_demo.runtime.log
```

Независимая проверка проверяет 14 схем по meta-schema и 89 instance cases, включая
сериализованные данные сквозного примера. Проверяются также **допустимые для
схемы**, но отклоняемые custom callbacks/key uniqueness/byte-length условия:
это явно зафиксированные ограничения, а не скрытое обещание полной эквивалентности.
Для самой библиотеки и примеров Python/jsonschema не нужны.

Для AOT-хоста macro-модуль derive_schema.das не требует -aotlib. Добавляйте
обычные runtime-модули derive и модули приложения с generated функциями, как
описано в README. CI проверяет схемы независимым validator отдельно для
интерпретатора, JIT и текстов, полученных из собранного AOT-хоста.
