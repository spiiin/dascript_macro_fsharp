# Derive Builder

`[derive(builder=true,validate=true)]` генерирует типизированные setters и
`derive_build`. Нативный модуль и CE не нужны. Пайп передаёт изменяемый draft
первым аргументом; каждый setter — отдельный statement, возвращающий void.

```das
options gen2
require ./lib/derive.das

[derive(builder=true,validate=true)]
struct Player {
    @builder_required
    @validate_non_empty
    name:string
    @validate_min=0
    @validate_max=100
    health:int=100
    inventory:array<int>
}
[export]
def main() {
    var inscope draft <- derive_builder(type<Player>)
    draft |> builder_name("Alice")
    var inscope inventory <- [1,2]
    draft |> builder_move_inventory(inventory)
    var inscope result <- derive_build(draft,"player")
    verify(result.ok && (result.value as some).health==100)
    // inventory пуст; draft и result владеют независимыми массивами.
}
```

## API и порядок выполнения

- `derive_builder(type<Model>)`: owning `$DerivedBuilder<Model>`, без запуска
  инициализаторов модели. `var inscope` освобождает его при обычном выходе.
- `draft |> builder_<field>(value)`: заимствует input, сохраняет глубокую копию.
  Повторный setter освобождает старое поле. Для вложенной структуры нужна её
  `derive_clone` (например, `clone=true`), либо пользовательская перегрузка.
  Для самого корневого Model включать clone=true не требуется.
- `draft |> builder_move_<field>(value)`: принимает изменяемый input, перемещает
  owning-значение; копируемые значения копирует. Input после move нельзя считать
  прежним значением. Не передавайте в move-setter поле самого draft.
- `derive_build(draft,root="")`: заимствует draft, возвращает owning tuple
  `(ok:bool,value:Option<Model>,errors:array<ValidationIssue>)`.

1. Собирает все пропущенные `@builder_required` в порядке объявления полей,
   code=`builder_required`, native path=`root.field`. При пропуске сразу возвращает
   None: defaults и validation не исполняются.
2. Заполняет zeroed-хранилище модели по полям её обычными нативными defaults
   внутри блока очистки при исключении. Все нативные инициализаторы
   выполняются один раз на попытку, включая поля, которые затем заменят setters.
   Без initializer действует обычное значение по умолчанию daScript.
3. В порядке полей копирует переданные значения, освобождая заменённые defaults.
4. Один раз выполняет полную derive-валидацию: правила полей, вложенные проверки,
   пользовательский check. При ошибках возвращает None и все validation errors;
   временный кандидат освобождается. Пути валидации следуют обычным правилам
   derive, включая json_name при включённом JSON.
5. При успехе передаёт кандидата в Some. Draft остаётся пригодным для исправления
   и повторной сборки. Разные результаты не делят owning-массивы с draft/inputs.

Required — проверка присутствия во время сборки, а не compile-time typestate.
Нативный default не отменяет `@builder_required`; явно переданные `""`, `0`,
`None`, `JsonField.missing` считаются присутствующими и затем проходят валидацию.
`@builder_required=false` отменяет требование. Отдельного `builder_default` нет:
источник defaults — сама структура; JSON defaults здесь не применяются.
`builder=true` требует `validate=true`; остальные derive-флаги независимы.

## Владение, ошибки и ограничения

Исключения из копирования и валидации не превращаются в ValidationIssue:
кандидат (включая defaults ранее созданных полей) и накопленные ошибки освобождаются, исходный draft сохраняется,
исключение передаётся вызывающему коду. Пользовательский `derive_clone` обязан
сам освобождать свои частичные результаты до panic. Нативные initializer-функции
также должны освобождать свои собственные частичные результаты до panic:
Builder может освободить только значения, которые уже переданы его полям. Откат внешних
эффектов callbacks/initializers не выполняется. Низкоуровневые поля `data` и
`supplied` — внутреннее представление, изменять их напрямую не следует.

Не давайте draft выйти за время жизни его daScript context: строки принадлежат
context. Контроль heap в тестах проверяет живую память owning-массивов/таблиц,
а не string heap или память процесса. Builder хранит Model и таблицу присутствия;
build копирует заданные поля и запускает defaults/validation. Это осознанная
дополнительная работа по сравнению с прямым конструктором.

Корень sizeof(Model)==0 отвергается при генерации derive_build из-за
[дефекта SDK Option AOT](repros/README.md). Добавьте корню реальное поле.
Переданный в Some кандидат явно обнуляется: это обход SDK AOT move_some,
который иначе может оставить старый payload в исходнике (см. repros/README.md).
Обычные ограничения Clone/Validation для вложенных типов сохраняются.
Смотрите [пример](examples/builder_demo.das), [тесты](tests/test_builder.das)
и [исключения](tests/test_builder_exceptions.das).
