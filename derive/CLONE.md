# Глубокое копирование через derive

Clone включается явно: `[derive(clone=true)]`. Операция `derive_clone(value)`
возвращает новый экземпляр того же типа, заимствуя оригинал. Для owning-результата
используйте `var inscope copy <- derive_clone(original)`.

```das
options gen2
require ./lib/derive.das

[derive(clone=true)]
struct Item {name:string;mods:array<int>}
[derive(clone=true)]
struct Inventory {items:array<Item>;selected:$Option<Item>}

[export]
def main() {
    var inscope original:Inventory
    var item:Item
    item.name="sword"
    item.mods |> push(3)
    original.items |> emplace(item)

    var inscope copy <- derive_clone(original)
    copy.items[0].mods[0]=100
    verify(original.items[0].mods[0]==3)
    delete original
    verify(copy.items[0].mods[0]==100)
}
```

## Поддержка и семантика

- Plain structs: все поля рекурсивно клонируются в порядке объявления.
  Вложенным structs тоже нужен `clone=true` либо пользовательский overload.
- Динамические массивы: отдельное хранилище и глубокая копия каждого элемента.
  Массивы массивов обходятся рекурсивно. Ёмкость может отличаться от оригинала.
- Фиксированные массивы: сохраняются размер и порядок, элементы клонируются рекурсивно.
- Option: сохраняются None/Some, payload Some клонируется.
- JsonField: сохраняются Missing/Null/Present, payload Present клонируется.
- Variant: сохраняется активный случай, клонируется только его payload;
  void-case не создаёт payload. Поддержаны вложенные variant и owning-payload.
- Числовые скаляры, bool и enum копируются по значению, включая enum без нулевого
  члена. Строки неизменяемые и принадлежат string heap контекста daScript:
  копируется строковое значение без обязательного выделения нового буфера.
  Результат нельзя переносить в другой runtime context как независимый от него объект.

Копия и оригинал владеют разными массивами. Удаление или изменение одного
не меняет другого; новые ресурсы и память освобождает соответствующий владелец.
Clone не запускает валидацию и не учитывает json_skip/json_name/default:
он копирует все реальные поля и сохраняет исходные значения, даже невалидные.
Нативные инициализаторы полей при клонировании повторно не выполняются.

Clone не изменяет стандартные `clone`, `clone_to_move`, `:=` или `<-`.
Это отдельный протокол `_::derive_clone`, позволяющий использовать собственные
правила копирования вложенных типов. Debug/Equality/Hash не требуются для Clone:
`[derive(debug=false,equality=false,hash=false,clone=true)]` включает только его.
По умолчанию clone=false, поэтому существующие `[derive]` не получают новую операцию.

Tuple, table, указатели, smart pointers, native handles, closures, iterators и
векторы не клонируются автоматически. Для собственных типов определите перегрузку.
Clone не решает сохранение идентичности узлов графа, общих ссылок и циклов и не
дублирует соединения, файлы и другие внешние ресурсы.

## Пользовательский тип и исключения

```das
struct External {values:array<int>}

def derive_clone(value:External) : External {
    var result:External
    result.values <- _::derive_clone(value.values)
    return <- result
}

[derive(debug=false,equality=false,hash=false,clone=true)]
struct Envelope {external:External}
```

Операции разрешаются в модуле модели; перегрузки могут быть объявлены после
структуры. Функция должна вернуть новый экземпляр того же типа и не перемещать
данные из заимствованного оригинала. Для ресурсов с особым временем жизни
автор перегрузки отвечает за корректное владение и освобождение своей копии.

Если вложенная операция бросает исключение, сгенерированные struct и array
клоны освобождают уже созданные поля/элементы и повторно выбрасывают исключение.
Variant конструирует только выбранный payload, поэтому не оставляет других
частично созданных случаев. Оригинал остаётся у вызывающего кода.
Пользовательская перегрузка отвечает за очистку своего незавершённого результата
до выбрасывания; библиотека не может очистить её локальные переменные.

Генерация struct и реализация fixed-array используют тот же приём zeroed storage
в `unsafe`, что и стандартный `clone_to_move`: сначала пустое хранилище без
инициализаторов, затем заполнение полей. Публичный вызов `derive_clone` не требует
unsafe. Автоматический протокол предназначен для перечисленных выше типов данных;
специальные resource wrappers требуют явной перегрузки.

## Примеры и проверки

- [clone_demo.das](examples/clone_demo.das): независимость копии игрового состояния.
- [clone_model.das](examples/clone_model.das): структуры, массивы, Option, JsonField,
  variant и нативные инициализаторы.
- [test_clone.das](tests/test_clone.das): состояния обёрток/variant, фиксированные
  массивы, повторное клонирование, удаление оригинала, отсутствие повторных
  инициализаторов и контроль context heap.
- [test_clone_exceptions.das](tests/test_clone_exceptions.das): пользовательский
  overload, исключения после частичного копирования, сохранность оригинала
  и освобождение context heap.

Запуск из корня репозитория: `./derive/run.ps1 -Test`, затем `-Test -Jit` и
`./derive/run_aot.ps1`. Последний действительно собирает и запускает AOT-хост
с обязательной AOT-компиляцией main. Манифесты используются также в CI.
Проверки heap_bytes_allocated измеряют живой context heap, а не string heap
или память всего процесса. Известный дефект SDK для default<T[N]> внутри
инициализатора поля описан в [repros/README.md](repros/README.md);
пример Clone использует fixed_array(factory()) при создании исходного значения.
