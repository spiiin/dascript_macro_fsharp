# ValidationBuilder

Отдельный builder для проверки независимых полей с накоплением ошибок.
Подключается без правок `computation.das` или `computation_macro.das`:

```das
require ./lib/computation_macro.das
require ./lib/validation_builder.das

let character = computation(ValidationBuilder()) {
    let nameCheck = check_name(name)
    let levelCheck = check_level(level)
    let fields = nameCheck |> validation_zip(levelCheck) |> bind
    return Character(name=fields.first, level=fields.second)
}
```

Полный игровой пример: `validation_demo.das`.
Можно использовать и прежний фасад `require computation`, дополнительно
подключив `require validation_builder`.

## Значения и ошибки

`validation_ok(value)` возвращает `variant<valid:T;invalid:ValidationErrors>`.
`validation_error(message, type<T>)` создаёт ошибку с типом отсутствующего
значения T. `ValidationErrors` содержит `.messages` (текст, разделённый
переводами строк) и `.count` (количество исходных ошибок).

```das
if (character is invalid) {
    print("{(character as invalid).count} errors:\n{(character as invalid).messages}\n")
}
```

Это простой копируемый контейнер сообщений, без структурированных кодов
и путей полей. Count хранится отдельно: переводы строк внутри исходного
сообщения не увеличивают количество ошибок. Payload также должен быть
копируемым.

## Независимые и зависимые проверки

`left |> validation_zip(right)` объединяет два уже вычисленных результата:

| left | right | Итог |
| --- | --- | --- |
| valid A | valid B | valid tuple(first=A, second=B) |
| invalid | valid | Ошибки left |
| valid | invalid | Ошибки right |
| invalid | invalid | Все ошибки left, затем все ошибки right |

Для трёх проверок можно написать `a |> validation_zip(b) |> validation_zip(c)`.
Успешное значение будет вложенной парой: `.first.first`, `.first.second`,
`.second`. Ошибки накапливаются в исходном порядке.

Обычные `let` перед zip явно задают порядок выполнения проверок и позволяют
выполнить каждую ровно один раз. Zip не принимает отложенные функции, не
запускает потоки и не перехватывает native panic. Его аргументы должны быть
независимыми: правый результат не может использовать ещё не извлечённое
успешное значение левого.

После zip используется привычный `|> bind`. Если есть хотя бы одна ошибка,
продолжение не выполняется. Последовательные bind также останавливаются при
первой ошибке:

```das
let result = computation(ValidationBuilder()) {
    let account = lookup_account() |> bind
    let profile = check_profile(account) |> bind
    return profile
}
```

Накопление выполняется именно внутри явно объединённой группы. Циклы,
последовательные ветвления и Combine останавливаются при первой ошибке;
они не запускают пропущенный код ради сбора дополнительных сообщений.

По назначению явная группа похожа на объединение независимых источников
в applicative CE. Синтаксис F# `and!` в парсер не добавлен; этот модуль
полностью использует существующий протокол Value и обычную функцию zip.

## Остальные конструкции

Поддержаны `return`, `return_from`, bind без переменной, Zero/Combine/Delay,
ветвления, for/while, `use_resource`, `try_finally`, `try_with`.
Промежуточные scope и итерации требуют успешный payload `CeUnit`.

Ресурсы освобождаются и при invalid. `try_with` обрабатывает native panic;
значение invalid не вызывает обработчик. Handler может явно преобразовать
исключение в `validation_error(...) |> return_from`.

## Проверки

`run_computation.ps1 -Test` запускает пример, `test_validation.das` и два
отрицательных теста. Проверяются обе ошибки, каждая ошибка отдельно, успех,
разные типы payload, вложенные пары, порядок сообщений, однократное выполнение
источников, остановка следующих bind и циклов, Unit, return_from, cleanup и
TryWith. Отрицательные тесты запрещают bind обычного Result и возврат значения
вместо Unit из итерации.

Теперь внутри CE вместо `validation_zip` можно использовать общий маркер:
`left |> and_bind(right) |> bind`. ValidationBuilder реализует
`ce_merge_sources` через ту же функцию `validation_zip` и сохраняет порядок
накопления ошибок. См. [AND_BIND.md](AND_BIND.md).
