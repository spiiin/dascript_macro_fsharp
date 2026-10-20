# Типизированный Patch через derive

Patch создаёт типизированные собственные снимки, проверяет конфликты изменяемых
полей, применяет правки к глубокой копии и валидирует результат. Оригинал меняется
только при явном успешном `derive_apply_patch_to`.

```das
options gen2
require ./lib/derive.das

[derive(clone=true,validate=true,patch=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int
    mana:int
}
[derive(clone=true,validate=true,patch=true)]
struct Game {stats:Stats;items:array<int>;revision:int}

[export]
def main() {
    var inscope before:Game
    before.stats=Stats(health=100,mana=20)
    before.items <- [1,2]
    var inscope after <- derive_clone(before)
    after.stats.health=75
    after.items |> push(3)
    var inscope patch <- derive_make_patch(before,after)

    var inscope current <- derive_clone(before)
    current.stats.mana=25
    current.revision=7
    var inscope applied <- derive_apply_patch(current,patch,"game")
    verify(applied.ok)
    verify((applied.value as some).stats.health==75)
    verify((applied.value as some).stats.mana==25)
    verify((applied.value as some).revision==7)
    verify(current.stats.health==100)

    // Commit only after the candidate has passed all checks.
    var inscope errors <- derive_apply_patch_to(current,patch,"game")
    verify(length(errors)==0 && current.stats.health==75)
}
```

## API и владение

- `[derive(clone=true,validate=true,patch=true)]` генерирует typed
  `derive_patch_into` для всех полей. Patch требует clone=true, equality=true
  и validate=true. Equality по умолчанию включена; Debug, Hash, JSON и Diff
  для Patch не требуются. Для одной связки операций без Debug/Hash используйте
  `[derive(debug=false,hash=false,clone=true,validate=true,patch=true)]`.
- `derive_make_patch(expected,desired)` возвращает `$TypedPatch<T>`:
  структурный named tuple `expected:T;desired:T`. Оба снимка глубоко клонируются,
  источники не перемещаются. Изменение/удаление источников не меняет Patch.
  Функция не валидирует снимки: невалидное желаемое состояние можно подготовить,
  но применение будет отклонено. Snapshot-инициализаторы повторно не выполняются.
- `derive_apply_patch(current,patch,root="")` возвращает owning named tuple
  `ok:bool;value:$Option<T>;errors:array<ValidationIssue>`. На успехе value=Some
  новой независимой копии. При конфликте/нарушении правил value=None: тип T не
  конструируется заново ради фиктивного значения ошибки. errors содержит все
  конфликты либо все ошибки последующей валидации.
- `derive_apply_patch_to(var current,patch,root="")` возвращает owning
  `array<ValidationIssue>`. Пустой массив означает успешную замену current
  проверенной копией. При ошибках current остаётся прежним.

Для owning-результатов и Patch с owning-полями используйте `var inscope` и `<-`.
Для скалярного Patch можно использовать `let patch=derive_make_patch(1,2)`.
API применения заимствует Patch: его можно использовать многократно для разных
подходящих состояний, а результаты не делят с ним owning-массивы. Поля снимков
публичны и типизированы; API их не изменяет, но язык не запрещает автору вручную
редактировать mutable Patch. Такой автор отвечает за новые preconditions.

Это первая версия представления: два полных типизированных снимка, а не
компактный набор операций. Создание стоит двух глубоких копий; применение —
копии current плюс клонирования заменяемых значений. Для просмотра можно вызвать
`derive_diff(patch.expected,patch.desired,"game")`, если модели включают diff=true.
Диагностические записи Diff не используются как данные Patch.

## Конфликты и объединение

Обход полей — в порядке объявления, рекурсивно. Если expected==desired для
изменяемой единицы, Patch её не трогает и не требует совпадения current с expected.
Так сохраняются независимые изменения в current. Для изменяемой единицы
current должен совпадать с expected; иначе добавляется `ValidationIssue`
с кодом `patch_conflict`, путём и сообщением. Все конфликтующие поля собираются
за один проход. Результат не принимает частично применённую копию.

- Struct: независимая обработка полей, вложенные пути вроде `game.stats.health`.
  Вложенному struct нужен patch=true либо пользовательский derive_patch_into.
- Динамические и фиксированные массивы: атомарная замена целиком. Конфликт
  указывает `game.items` или `game.fixed`; изменение любого элемента current
  блокирует замену массива. Пустые массивы, добавление/удаление элементов и
  вложенные owning-значения поддержаны через полный новый массив.
- Option и JsonField: при одинаковом состоянии payload сравнивается/применяется
  рекурсивно по тому же пути. При смене None/Some либо Missing/Null/Present вся
  обёртка заменяется атомарно и сравнивается с expected целиком.
- Variant: одинаковый случай обрабатывает payload рекурсивно по `.value`.
  Смена случая заменяет весь variant атомарно с полным сравнением expected.
  Если current уже сменил ожидаемый случай, конфликт находится на пути variant.
  Void-case и owning-payload поддержаны.
- Скаляры, строки и enum заменяются по значению. Enum без нулевого члена
  поддержан. Равенство имеет обычную семантику derive_equal: +0/-0 совпадают,
  NaN не совпадает даже с собой и может не удовлетворить precondition.

Замена не идемпотентна: повторное применение к уже изменённому объекту обычно
даёт конфликт, даже если он уже содержит desired. Пустой Patch ничего не меняет,
но всё равно проверяет валидность результирующей копии.

Конфликтные пути используют реальные имена daScript, включая json_skip-поля.
JSON-метаданные не исключают поля из Patch. Строковые пути не парсятся и не
экранируются; пустой root допустим. Для массива/скаляра в корне конфликт может
иметь пустой путь. Это не JSON Patch, не формат сериализации и не трёхстороннее
объединение по идентификаторам элементов. Поэлементные команды массивов с ID,
вставками и удалениями не представлены в этой версии.

## Валидация и атомарность

Сначала клонируется current, затем проверяются preconditions и изменяется копия.
Только если конфликтов нет, запускается один полный `derive_validate_into`
для кандидата. Поэтому сохраняются правила полей, проверки коллекций,
вложенные ошибки и общие бизнес-правила. Валидационные пути следуют существующей
семантике валидатора, включая json_name, если модель включает JSON.
При наличии конфликтов валидация частично изменённой копии не запускается.

Даже если current и desired валидны по отдельности, их объединение может нарушить
межполевой инвариант: такой кандидат отклоняется. Результат всегда содержит
None на неуспехе, а не наполовину исправленный объект.

Если Clone, Equality, пользовательский Patch или Validation бросает исключение,
частичный Patch/кандидат/массив ошибок очищается и исключение распространяется.
Проверки освобождения памяти покрывают сбой второго снимка, первого клонирования
кандидата, замены поля после других правок, сравнения, применения и валидации.
Пользовательский обработчик отвечает за свои локальные owning-данные.
Атомарность касается данных current и владения, но не откатывает внешние эффекты
пользовательских функций, изменения globals, файлы или сеть.

## Ограничение SDK для пустого корневого типа

SDK 0.6.5-RC2 генерирует некорректный C++ для стандартного Option<T>, когда
sizeof(T)==0: TVariant/TTuple завершаются static_assert в aot.h. Минимальный
[repro](repros/aot_option_empty.das) не импортирует derive. Он работает в
интерпретаторе и JIT, но не компилируется как C++ AOT.

Чтобы API одинаково работал в трёх режимах, make/apply отклоняют нулевой размер
корневого типа при компиляции с понятной ошибкой. Добавьте реальное поле в
корневую модель. Это не ограничение пустых динамических массивов или None:
их типы имеют ненулевой размер и проходят обычные проверки. Отдельная отрицательная
проверка фиксирует это ограничение, а SDK-repro исключён из положительного manifest.

## Пользовательский протокол

Для внешнего типа предоставьте все используемые операции:
`derive_clone`, `derive_equal`, `derive_validate_into` и
`derive_patch_into(var current:MyType;expected,desired:MyType;path:string;var errors:array<ValidationIssue>)`.
Обработчик должен менять только предоставленную candidate-копию, не expected,
desired или глобальную ссылку на исходный current.

Для атомарного поля можно делегировать
`derive_patch_replace(current,expected,desired,path,errors)`. Он пропускает
неизменяемые значения, проверяет expected и глубоко клонирует desired перед заменой.
`derive_patch_conflict(path,errors)` добавляет стандартную запись конфликта.
Пример находится в [test_patch_exceptions.das](tests/test_patch_exceptions.das).

Низкоуровневый `derive_patch_into` сам по себе НЕ атомарен: меняет переданный
объект, добавляет к существующим errors и оставляет частичные изменения/ошибки
при исключении. Он не запускает полную валидацию. Используйте высокоуровневые
apply/apply_to для гарантии атомарности; низкий уровень нужен для протокола.

Нативные ресурсы, указатели, графы с циклами, shared-идентичность, closures,
iterators, tables и векторы не получают неявной поддержки. Специальные типы
требуют корректных пользовательских Clone/Equality/Validation/Patch и правил
владения. Строки используют неизменяемый string heap того же runtime context,
как в Clone. Patch и результат не предназначены для переноса в другой context.

## Примеры и проверки

- [patch_demo.das](examples/patch_demo.das), [patch_model.das](examples/patch_model.das):
  игровое состояние, сохранение независимых изменений, конфликт, commit и validation.
- [test_patch.das](tests/test_patch.das): конфликты и порядок, откат кандидата,
  повторные запуски, владение снимками, накопление ошибок и межполевые инварианты.
- [test_patch_wrappers.das](tests/test_patch_wrappers.das): переходы Option/JsonField,
  variant, полная замена dynamic/fixed arrays, enum, native initializers и context heap.
- [test_patch_exceptions.das](tests/test_patch_exceptions.das): cleanup всех этапов,
  пользовательский протокол и явная неатомарность низкого уровня.

Запуск из корня репозитория: `./derive/run.ps1 -Test`, `./derive/run.ps1 -Test -Jit`,
`./derive/run_aot.ps1`. Для своего AOT-хоста добавьте `-aotlib lib/derive_patch.das`
и используемые runtime-модули/модели. Проверки `heap_bytes_allocated` измеряют
живой context heap, не string heap и не память всего процесса. Все сценарии
подключены к общим манифестам CI.
