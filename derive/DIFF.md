# Диагностический Diff через derive

Включение для обычной структуры: `[derive(diff=true)]`. Операция
`derive_diff(before,after,root="")` возвращает owning `array<DiffChange>`.
Входные данные одного типа заимствуются и не меняются; Clone не требуется.
Для вложенных structs тоже нужен diff=true либо пользовательский derive_diff_into.

```das
options gen2
require ./lib/derive.das

[derive(diff=true)]
struct Stats {health:int;mana:int}
[derive(diff=true)]
struct Player {name:string;stats:Stats;items:array<int>}

[export]
def main() {
    var inscope before:Player
    before.name="Alice"
    before.stats=Stats(health=100,mana=20)
    before.items <- [1,2]
    var inscope after:Player
    after.name="Alice"
    after.stats=Stats(health=75,mana=20)
    after.items <- [1,3,4]
    var inscope changes <- derive_diff(before,after,"player")
    for(change in changes) {
        print("{change.path}: [{change.kind}] {change.before} -> {change.after}\n")
    }
}
```

```text
player.stats.health: [changed] 100 -> 75
player.items[1]: [changed] 2 -> 3
player.items[2]: [added]  -> 4
```

## Запись изменения

`DiffChange {path:string;kind:string;before:string;after:string}` содержит
диагностические снимки через derive_debug, а не ссылки на входные данные.
Результат остаётся доступным после удаления или изменения входных массивов.
Строки принадлежат runtime context daScript; результат не является независимым
от контекста сериализованным объектом.

| kind | Значение | before / after |
|---|---|---|
| changed | Изменён скаляр | Debug старого и нового значения |
| added | Добавлен хвостовой элемент массива | Пустая строка / Debug элемента |
| removed | Удалён хвостовой элемент массива | Debug элемента / пустая строка |
| state | Переход None/Some либо Missing/Null/Present | Debug всей обёртки |
| case | Смена активного случая variant | Debug обоих variant с payload |

Пустая строка в отсутствующей стороне added/removed — служебное отсутствие,
а настоящее строковое значение выводится в кавычках. Коды kind — строки API.
Каждый пользовательский обработчик может добавлять свои записи через
`diff_add(changes,path,kind,before,after)`.

Diff не является типизированным Patch, JSON Patch, алгоритмом минимального
редактирования или протоколом сохранений. Debug может округлять числа при
выводе; разные значения иногда имеют одинаковый диагностический текст.
Наличие изменения определяется значениями, а не сравнением этого текста.

## Порядок, пути и типы

- Struct: поля в порядке объявления, рекурсивный обход каждого поля до
  следующего. Пути используют реальные имена daScript, включая json_skip-поля;
  json_name не переименовывает диагностический путь. Валидация не запускается.
- Массивы: сравнение по индексам на общем участке, затем хвостовые удаления
  или добавления по возрастанию индекса. Для добавленного/удалённого объекта
  выдаётся одна запись с Debug всего объекта. Вставка в середину выглядит как
  изменения соответствующих индексов и добавление хвоста. Нет сопоставления по ID,
  поиска перестановок или LCS. Удаления не предназначены для последовательного
  применения как patch.
- Фиксированные массивы: тот же порядок, размер и тип должны совпадать.
  Поддержаны вложенные массивы и массивы owning-структур.
- Option: None/None не меняется; Some/Some сравнивает payload по тому же пути;
  None/Some и Some/None дают одну запись state, без вложенных записей.
- JsonField: Missing, Null и Present различаются. Разные состояния дают state;
  Present/Present рекурсивно сравнивает payload по тому же пути.
- Variant: разные случаи дают одну запись case. Для одинакового случая payload
  сравнивается рекурсивно по `.value`, а void-case не даёт записей. Вложенные
  variant и массивы в payload поддерживаются. Небезопасно повреждённые теги
  обычного variant приводят к исключению до доступа к payload.
- Числа, bool, string и enum используют равенство значений. Enum-алиасы с одним
  underlying value не отличаются; +0/-0 не отличаются, NaN следует обычной
  семантике equality и отличается от самого себя.

Пути вроде `game.items[2].count` — диагностические строки, без экранирования и
парсера адресов. Пустой root даёт `field` или `[0]`; изменённый корневой скаляр
имеет пустой путь. Совпадающие значения не создают записей. Повторный вызов
на неизменённых данных сохраняет порядок и содержимое при стабильных
пользовательских обработчиках.

Diff включается независимо от Clone/Validation/JSON и не требует Equality/Hash
для structs. Но diff=true требует debug=true для диагностических снимков
добавленных/удалённых объектов и смены состояния/случая. Для Diff без Equality/Hash
используйте `[derive(equality=false,hash=false,diff=true)]`. По умолчанию diff=false.

Tuple, table, указатели, native handles, closures, iterators и векторы не получают
автоматического обхода. Графы с циклами и идентичность shared-ссылок не сравниваются
автоматически. Для своего типа задайте явный протокол.

## Пользовательский протокол и исключения

```das
struct EntityId {raw:int}
def derive_debug(value:EntityId) : string {return "Entity({value.raw})"}
def derive_diff_into(before,after:EntityId;path:string;
                     var changes:array<DiffChange>) {
    if(before.raw!=after.raw) {
        diff_add(changes,path,"changed","{before.raw}","{after.raw}")
    }
}
[derive(equality=false,hash=false,diff=true)]
struct Target {id:EntityId}
```

Сгенерированный код использует `_::derive_diff_into`; overload разрешается по
типу в модуле модели. Пользовательский код сам определяет семантику, порядок
и снимки своих записей и не должен менять входные данные.

`derive_diff_into(before,after,path,var changes)` — низкоуровневое добавление
в существующий массив: оно сохраняет уже находившиеся в нём записи. При исключении
пользовательской операции/Debug частичный массив остаётся у вызывающего кода.
Высокоуровневый derive_diff освобождает свой частичный массив и повторно
выбрасывает исключение. Пользовательский обработчик отвечает за очистку собственных
временных owning-данных, если создаёт их и бросает исключение.

Реализация массивов использует индексы и не удерживает native array iterator
после исключения. Диагностика выделяет строки и массив изменений; это не бесплатная
проверка равенства. Время зависит от объёма обхода и форматирования снимков, память —
от числа записей и размера строк. Ограничения размера результата пока нет.

## Примеры и проверки

- [diff_demo.das](examples/diff_demo.das), [diff_model.das](examples/diff_model.das):
  игровой пример с десятью изменениями в определённом порядке.
- [test_diff.das](tests/test_diff.das): порядок, вложенные пути, добавления/удаления,
  JSON-метаданные, отдельное время жизни результата, повторный вызов и context heap.
- [test_diff_wrappers.das](tests/test_diff_wrappers.das): переходы Option/JsonField,
  владение payload, variant, enum, строки и числовые границы равенства.
- [test_diff_exceptions.das](tests/test_diff_exceptions.das): пользовательский
  обработчик, исключения Debug, частичное накопление и очистка context heap.

Запуск: `./derive/run.ps1 -Test`, `./derive/run.ps1 -Test -Jit`,
`./derive/run_aot.ps1`. AOT-скрипт собирает и исполняет строгий хост с проверкой
main->aot. Для собственного хоста добавьте `-aotlib lib/derive_diff.das` наряду
с остальными используемыми runtime-модулями и модулями моделей.
Проверки heap_bytes_allocated контролируют живой context heap, не string heap
и не память всего процесса. Манифесты используются также в GitHub Actions.

Типизированное создание и атомарное применение правок описано в [PATCH.md](PATCH.md).
