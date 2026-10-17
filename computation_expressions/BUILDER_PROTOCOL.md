# Протокол builders

Поставка публичных модулей и минимальный внешний builder: [INTEGRATION.md](INTEGRATION.md). Специальные сообщения макросов: [DIAGNOSTICS.md](DIAGNOSTICS.md).

Таблица возможностей builders и общий контракт: [CE_SEMANTICS.md](CE_SEMANTICS.md).

Новый builder добавляется отдельным `.das`-модулем. Править `computation.das`
или регистрировать имя типа в макросе не нужно.

```das
require ./lib/computation_macro.das
require ./lib/reader_builder.das

let answer = computation(ReaderBuilder(7)) {
    let environment = reader_ask() |> bind
    return environment * 6
}
assert(answer.value == 42)
```

`computation.das` — совместимый фасад: подключает макрос и прежние стандартные
builders. Можно оставить `require computation` и дополнительно подключить свой
модуль. Для минимального набора зависимостей используйте `computation_macro`.
ReaderBuilder намеренно не включён в фасад: `reader_demo.das` показывает расширение
только через два импорта. Он требует лишь `builder_protocol`.

## Выбор стратегии

В модуле builder определите перегрузку `ce_protocol(builder)`:

| Возвращаемый тип | Раскрытие |
| --- | --- |
| `CeValueProtocol` | Синхронное вычисление с копируемым результатом; Bind/Combine решают, выполнять ли продолжение |
| `CeOwnedProtocol` | Перемещаемые результаты, consuming bind с временным заимствованием payload; см. [MOVE_CE.md](MOVE_CE.md) |
| `CeCollectProtocol` | Накопление результатов, `yield`, `yield_from`, перемещение результата и `inscope` для промежуточных коллекций |
| `ce_sequence_protocol(type<T>)` | Ленивый native generator элементов T; завершается вызовом `ce_sequence_run(builder, source)` |

Это номинальные дескрипторы из `builder_protocol`, а не совпадение строкового
имени пользовательского builder. Форма самого builder произвольна: структура
или tuple с параметрами. Значение builder вычисляется один раз. Поддержаны сохранённые локальные
переменные: `let saved = ReaderBuilder(7); computation(saved) { ... }`.
Выбор протокола откладывается, пока тип saved не перестанет быть auto.
Проверки: `test_saved_builder.das`; неизвестный протокол по-прежнему выдаёт
целевую диагностику в `test_saved_builder_missing_protocol.das`.

Макрос в два прохода сначала выводит тип вызова
`ce_protocol(default<BuilderType>)`, затем раскрывает исходный блок. Этот вызов
отсутствует в итоговой программе. Он не получает реальное значение builder;
его тело не предназначено для побочных эффектов. Тип стратегии и элемента
должен определяться типами, а не runtime-настройками. Настройки доступны
перегрузкам операций и `ce_sequence_run`.

## Операции Value и Collect

Ниже `B` — тип builder, `M<T>` — условное обозначение результата с полезным
значением T, а не буквальный синтаксис daScript. Реальные сигнатуры показаны
в `reader_builder.das` и `list_builder.das`.

| Операция | Назначение |
| --- | --- |
| `ce_return(builder, value)` | Упаковать `return value`; для Collect также `yield value` |
| `ce_return_from(builder, source)` | `source \|> return_from`; для Collect также `source \|> yield_from` |
| `ce_unwrap(builder, source) : T` | Только вывести тип переменной bind; вызов не выполняется |
| `ce_bind(builder, source, next : block<(item:T):R>) : R` | Исполнить продолжение нужное число раз или пропустить его |
| `ce_zero(builder)` | Пустой блок, отсутствующая ветка, конец блока без return |
| `ce_delay(builder, body : block<():R>) : R` | Выполнить блок; общий default синхронно вызывает body |
| `ce_combine(builder, first, next : block<():R>) : R` | Соединить вложенный scope/ветку/цикл с оставшимся кодом |
| `ce_for(builder, source, body)` | Необязательный For для одного источника; hook управляет обходом и остановкой |
| `ce_for_zip(builder, arity, traverse)` | Необязательный For с несколькими источниками; visit возвращает false для остановки всего обхода |
| `ce_while(builder, condition, body)` | Необязательный While; condition и body передаются блоками |
| `ce_loop_append(builder, accumulated, step)` | Value: вернуть результат накопления эффектов одной итерации |
| `ce_loop_failed(builder, step) : bool` | Value: остановить цикл при неуспехе |
| `ce_collect_append(builder, var accumulated, step)` | Collect: добавить результат итерации на месте |
| `ce_collect_rethrow(builder, var accumulated)` | Collect: освободить накопленный результат и повторно бросить текущее исключение |

Операции требуются только при использовании соответствующей конструкции.
Обычно промежуточные Value-блоки и итерации возвращают `M<CeUnit>`: это
ограничивается перегрузками builder, а не скрытыми проверками runtime.
`ce_bind` получает продолжение и отвечает за семантику остановки/повторения.
Не сохраняйте stack block для последующего вызова: эта стратегия синхронная.

Для Collect результат должен поддерживать перемещение и `inscope`/удаление.
Это не стратегия для обычного `int`-аккумулятора: для такого вычисления
используйте Value. Переопределите `ce_delay` и остальные операции, возвращающие
владеющий результат, с `return <-`. Восстановление после native panic требует
явного освобождения накопленных данных, как в `list_builder.das`.

## Ресурсы и исключения

`builder_protocol` публично подключает `computation_resources` с defaults:

- `ce_using(builder, resource, body, cleanup)`;
- `ce_try_finally(builder, body, cleanup)`;
- `ce_try_with(builder, body, handler)`.

Они подходят для копируемых Value-результатов. Владеющие Collect-результаты
требуют перегрузок с перемещением и очисткой при исключениях. `ce_dispose`
для конкретного ресурса виден в модуле вызывающего кода. Cleanup должен
возвращать void, обработчик исключения — тот же тип результата, что тело.

## Sequence

```das
struct MySequenceBuilder {}
def ce_protocol(builder : MySequenceBuilder) {
    return ce_sequence_protocol(type<int>)
}
def ce_sequence_run(builder : MySequenceBuilder; var source : iterator<int>) : iterator<int> {
    return <- ce_sequence_protect(source)
}
```

Подключите `sequence_runtime public` в модуле такого builder.
`ce_sequence_run` вызывается ровно один раз при создании CE, до обхода, и
принимает владение сгенерированным итератором. Можно обернуть его с учётом
настроек builder. Обёртка обязана закрывать источник при завершении, отмене
и исключениях; готовый `ce_sequence_protect` обеспечивает это для обычного
итератора. Возвращаемое значение перемещается наружу.

Bind, yield и resource scopes здесь реализованы общим generator backend;
перегрузки `ce_bind`/`ce_return` Value-стратегии не вызываются. Ограничения
однопроходности, захвата переменных и cleanup описаны в `SEQUENCE.md`.
Новый builder внутри этих четырёх стратегий не требует правок ядра. Новая
стратегия исполнения (например, настоящий async scheduler), новый синтаксис
или произвольное переопределение раскрытия AST всё ещё требуют расширения ядра.

## ReaderBuilder

`ReaderBuilder(environment)` предоставляет окружение только для чтения:
`reader_ask() |> bind` получает его, `reader_value(value)` оборачивает обычное
значение, а результат CE имеет поле `.value`. Окружение и результаты должны
быть копируемыми; изменение данных через содержащиеся в них указатели не
запрещается автоматически. Вычисление выполняется сразу: это не отложенная
функция `Environment -> T`. Повторный запуск — новый вызов функции с окружением.
Игровой пример и передача результата между функциями: `reader_demo.das`.

## Проверки

`run_computation.ps1 -Test` включает прежние тесты и новые:

- `test_reader.das`: bind, bind без переменной, return_from, Unit, циклы,
  ветвление, cleanup, TryWith, однократное создание builder;
- `test_builder_protocol.das`: независимый Collect-модуль, независимый
  Sequence-модуль с другим типом builder, ленивость, завершение, break,
  исключение и отсутствие runtime-вызовов ce_protocol;
- отрицательные примеры: нет ce_protocol, неправильный дескриптор,
  отсутствующая операция, несовместимый результат итерации.

`protocol_collect_fixture.das` — независимая тестовая реализация коллекции,
не требующая ListBuilder. Она намеренно повторяет операции списка, чтобы
проверка не могла пройти за счёт импорта встроенного builder.

Для кода с явно квалифицированными именами: `CeUnit` теперь объявлен в
`builder_protocol`, поэтому его полное имя — `builder_protocol::CeUnit`.
Обычное неквалифицированное использование через `require computation`
сохраняется благодаря публичному импорту.

Ещё один независимый модуль — `validation_builder.das`: накопление ошибок
через `validation_zip`, затем обычный bind. Использует только Value-протокол
без изменений фасада или макроса. Пример и контракт: [VALIDATION.md](VALIDATION.md).

## Групповой bind

`left |> and_bind(right) |> bind` раскрывается через необязательную перегрузку
`ce_merge_sources(builder, left, right)`. Поддержан стратегиями Value/Collect;
перегрузки добавлены для Result, Option, Validation и List. Источники группы
вычисляются слева направо ровно один раз, даже при неуспешном значении слева.
Контракт, порядок и владение: [AND_BIND.md](AND_BIND.md).

## BindReturn

Необязательный `ce_bind_return(builder, source, mapper)` объединяет Bind и
Return. Макрос распознаёт соседнюю завершающую пару, сохраняя пайповый синтаксис.
Без специализированной перегрузки остаётся исходное раскрытие; типовой fallback
не исполняется. Контракт и ограничения: [BIND_RETURN.md](BIND_RETURN.md).

## Bind2Return

Необязательная перегрузка `ce_bind2_return(builder, left, right, mapper)`
оптимизирует внешнюю группу and_bind перед return. Mapper принимает одну
пару first/second. При отсутствии перегрузки сохраняется прежнее раскрытие;
типовой fallback не выполняется. Контракт: [BIND2_RETURN.md](BIND2_RETURN.md).

## Bind2

Группы and_bind с произвольным продолжением используют необязательный
`ce_bind2` для Result, Option, Validation и List. Синтаксис прежний;
старые builders сохраняют fallback через MergeSources и Bind.
См. [контракт и ограничения](BIND2.md) и `bind2_demo.das`.

## Общий Run и отчёты

Необязательный `ce_run(builder, outcome)` завершает Value/Collect/Sequence CE
и может менять публичный тип результата. Старые builders сохраняют прежний
результат. Отдельный `report_builder.das` превращает Result в отчёт об операции;
пример — `run_demo.das`. Контракт, владение, диагностика и проверки: [RUN.md](RUN.md).

## Отложенное выполнение

Отдельный модуль `deferred_computation` добавляет `deferred(builder, data) $(snapshot) { ... }` и `run_deferred(task)`. Снимки владеют данными, каждый
запуск получает независимую копию builder/data. Обычный computation остаётся
немедленным. Пример — `deferred_demo.das`; контракт и ограничения — [DEFERRED.md](DEFERRED.md).

## Отложенный Sequence

Каждый запуск deferred Sequence создаёт отдельный итератор, владеющий снимком
до закрытия. Ресурсы тела закрываются перед удалением снимка. Пример —
`deferred_sequence_demo.das`; контракт и обход с исключениями — [DEFERRED_SEQUENCE.md](DEFERRED_SEQUENCE.md).

## Переопределение циклов

Подробный контракт, владение источниками и границы: [LOOP_PROTOCOL.md](LOOP_PROTOCOL.md).
Пример отдельного модуля — `bounded_result_builder.das`. Если hook не определён,
сохраняется прежний fallback через loop/collect append. Для нескольких источников
есть отдельный `ce_for_zip`: [ZIP_FOR.md](ZIP_FOR.md). Генераторная стратегия
Sequence сохраняет native loops.

Путь `ce_for_zip` использует явные курсоры и закрывает источники при native panic
производителя или потребителя. Контракт операции не изменён; подробности и
границы — [ZIP_CLEANUP.md](ZIP_CLEANUP.md).

Одиночный `For` Result/Option также закрывает iterator-источник при исключении
производителя или тела: [SINGLE_FOR_CLEANUP.md](SINGLE_FOR_CLEANUP.md).

Стандартный eager For без hooks также закрывает источники при исключениях:
[FALLBACK_CLEANUP.md](FALLBACK_CLEANUP.md). Пример: `fallback_cleanup_demo.das`.

Общий необязательный `ce_source(builder,input)` адаптирует источники bind, For,
return_from и yield_from до обычных операций и оптимизаций. Контракт:
[SOURCE_PROTOCOL.md](SOURCE_PROTOCOL.md). Отдельный builder: `game_source_builder.das`;
пример: `source_demo.das`.

## Коллекции с владением

Move-only List применяет `CeOwnedProtocol`; mutable-reference bind copyable
collection использует `ce_unwrap_borrow` и consuming `ce_bind`. Move-only
Sequence выдаёт временную ссылку из owning-slot iterator. Подробности и
ограничения: [MOVE_COLLECTIONS.md](MOVE_COLLECTIONS.md).

## Перемещаемый ресурс

Явное `var r & = source |> use_resource` вызывает `ce_using_move` для eager CE.
Доступна общая реализация с временным mutable borrow и обязательным cleanup;
Sequence удерживает ресурс в heap-ячейке до закрытия дочернего итератора.
Контракт disposer и владения: [MOVE_RESOURCES.md](MOVE_RESOURCES.md).

## ReaderResultBuilder

`reader_result_builder.das` объединяет ReaderAsk и обычный Result через
CeValueProtocol. Реализует базовые операции, MergeSources и BindReturn;
For/While используют общий fallback. Изменения ядра или фасада не требуются.
Контракт и пример: [READER_RESULT.md](READER_RESULT.md).

## StateWriterResultBuilder

`state_writer_result_builder.das` объединяет состояние, строковый журнал и Result
через CeValueProtocol. Откат относится к начальному состоянию всего CE; журнал
не откатывается. Циклы и BindReturn используют общий fallback, ресурсные операции
— общий протокол. Подробности: [STATE_WRITER_RESULT.md](STATE_WRITER_RESULT.md).

## CoroutineBuilder

`coroutine_builder.das` использует CeSequenceProtocol с CoroutineWait.
`ce_sequence_run` преобразует запросы ожидания в iterator<CoroutineFrame>,
`ce_source` адаптирует дочерние корутины для yield_from. Основной макрос
и фасад остаются прежними. Контракт: [COROUTINE.md](COROUTINE.md).

## Необязательное накопление List в одном массиве

`ce_collect_sink(builder)` по умолчанию возвращает `CeCollectSinkFallback`.
ListBuilder выбирает `ce_collect_sink_protocol(type<T>)`, разрешая оптимизацию
линейных bind/return-цепочек. Дескриптор сам по себе не заменяет операции
накопления и владения. Полный контракт и ограничения: [LIST_OPTIMIZATION.md](LIST_OPTIMIZATION.md).
