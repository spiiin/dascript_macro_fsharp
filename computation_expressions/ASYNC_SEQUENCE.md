# Асинхронная последовательность

`require ./lib/async_sequence_builder.das` добавляет `AsyncSequenceBuilder(type<T>)`.
Производитель ожидает Task через `|> bind` и выдаёт элементы через `yield`.
`async_sequence_next(stream)` возвращает холодную `Task<Option<T>>`: `some` —
один элемент, `none` — конец последовательности. Ожидать её можно в TaskBuilder.
Это не TaskResult-источник: Option не превращается автоматически в Result.

```das
options gen2
require ./lib/computation_macro.das
require ./lib/async_sequence_builder.das
require ./lib/task_scheduler.das

def readings() {
    return <- computation(AsyncSequenceBuilder(type<int>)) {
        for(i in range(3)) {
            task_delay_ms(10) |> bind
            yield 20+i
        }
    }
}

def consume() {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = readings() |> use_resource
        var sum=0
        while(true) {
            let item=async_sequence_next(stream) |> bind
            if(item is none) {break}
            sum+=item as some
            if(sum>=41) {break} // Закрытие Task закрывает и оставшийся stream.
        }
        return sum
    }
}
```

Задачу `consume()` запускают через обычный scheduler. Для задержек нужен
`task_tick(scheduler, now_ms)`; простой `task_poll` не задаёт часы.
Полный запускаемый пример: [async_sequence_demo.das](examples/async_sequence_demo.das).

## Владение и остановка

- Конструирование stream и next не запускает тело. Первый poll next начинает
  производство, следующий элемент не запрашивается заранее. Между next сохраняются
  локальные данные, вложенные ожидания и ресурсы производителя.
- Один stream допускает только один незавершённый next. Повторный вызов до
  завершения/закрытия предыдущего вызывает panic; предыдущий next остаётся владельцем.
- Успех next с some оставляет производителя открытым. Конец тела или bare
  `return` даёт none и закрывает его; последующие next также возвращают none.
- Отмена/таймаут next или потребителя закрывает всю последовательность, включая
  ожидаемый дочерний Task, `use_resource` и `try_finally`. Продолжить отменённый
  stream нельзя: следующий next будет Cancelled, а не успешным none.
- `async_sequence_close(stream)` явно закрывает stream. В CE используйте
  `var stream & = ... |> use_resource`; снаружи — `var inscope stream <- ...`.
  Обычный break сам по себе не закрывает владельца, оставленного во внешней области.
- Next удерживает отдельный lease на heap-состояние. Удаление исходного владельца
  закрывает производителя сразу; ожидающий next безопасно увидит Cancelled при poll.
  Если next просто удалить до завершения, производитель также закрывается.
- Исключение производителя даёт Failed у next. Исключение потребителя закрывает
  stream при выходе из ресурсной области. Синхронные cleanup должны быть небросающими,
  как у остальных CE. Поле Error внутри выданного значения остаётся данными.

## Move-only элементы

`AsyncSequenceBuilder(type<array<int>>)` и владеющие структуры используют тот же
API next. Производитель передаёт элемент через `yield <- value`; обычный yield
для move-only значения отклоняется с указанием строки пользователя.
Потребитель заимствует Option из владеющей задачи через пайповый bind:

```das
var item & = async_sequence_next(stream) |> bind
if(item is some) {
    var data <- item as some
    // Владение теперь у data; прежний payload пуст.
    verify(empty(item as some))
}
```

Заимствование живёт до конца продолжения bind, включая следующие ожидания.
Сохранять ссылку за пределами владельца нельзя. Чтобы оставить элемент у себя,
переместите payload либо весь Option в собственного владельца. В driving-коде
`task_take(nextTask)` переносит Option и потребляет nextTask; взятое значение
остаётся действительным после закрытия stream. `task_value(nextTask)` создаёт
независимый deep clone, как у остальных owning Task; для передачи без клонирования
используйте bind по ссылке или task_take.

Невыданный элемент освобождается при закрытии производителя. Выданный элемент
принадлежит next-Task, затем потребителю при переносе. Отмена, таймаут и ранний
выход освобождают оставшихся владельцев ровно один раз. Пример:
[async_sequence_move_demo.das](examples/async_sequence_move_demo.das).

## Deferred и повторные запуски

Подключите `./lib/deferred_computation.das` вместе с AsyncSequenceBuilder.
`deferred` клонирует исходные данные при создании фабрики; каждый `run_deferred`
клонирует сохранённый снимок и создаёт новый холодный stream. Поддержаны как
копируемые, так и move-only элементы:

```das
var inscope saved <- deferred(AsyncSequenceBuilder(type<array<int>>),[10,20]) $(snapshot) {
    for(i in range(length(snapshot))) {
        task_delay_ms(5) |> bind
        yield <- [snapshot[i],snapshot[i]+1]
    }
}
var inscope first <- run_deferred(saved)
var inscope second <- run_deferred(saved)
delete saved
// Оба stream продолжают владеть своими независимыми снимками.
```

Снимок запуска сохраняется между next и до закрытия производителя. Его ресурсные
финализаторы выполняются перед удалением снимка и могут читать его поля.
Завершение, отмена, таймаут, ранний выход, исключение и удаление неопрошенного
stream освобождают снимок. При удалении stream с активным next снимок освобождается
сразу после закрытия производителя; lease next удерживает только безопасное
служебное состояние. Переданные через yield <- элементы сохраняют собственное
владение и могут пережить stream и его снимок.

Снимки по-прежнему должны владеть данными: произвольные указатели, заимствования,
handles и исполняемые captures в них не допускаются. Вариант без явных данных
`deferred(AsyncSequenceBuilder()) { ... }` также поддержан.
Полный пример двух запусков: [deferred_async_sequence_demo.das](examples/deferred_async_sequence_demo.das).

## Делегирование через yield_from

`child() |> yield_from` последовательно выдаёт элементы другого AsyncSequence
с тем же типом элементов. Это consuming-операция: делегирование получает владение
дочерним stream. Можно передать результат фабрики или `run_deferred(saved)`.

```das
def combined() {
    return <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        page(10) |> yield_from
        page(20) |> yield_from
        yield <- [30]
    }
}
```

Элементы, включая move-only структуры и массивы, передаются перемещением без
клонирования. Дочерний stream опрашивается только по запросу следующего элемента;
его pending не превращается в элемент. После дочернего none внешний производитель
продолжает выполнение. Отмена дочернего next распространяется как Cancelled,
исключение — как Failed; в обоих случаях продолжение не выполняется.

При завершении, отмене, таймауте, раннем выходе или удалении внешнего владельца
закрываются активный дочерний next и сам stream. Его deferred-снимок освобождается
после финализаторов дочернего производителя. Уже переданный элемент остаётся
собственностью потребителя. Неактивные последующие источники не создаются.
`yield_from` принимает AsyncSequence, а не Task, обычный iterator или массив.
Полный пример с move-only элементами и двумя deferred-запусками:
[async_sequence_yield_from_demo.das](examples/async_sequence_yield_from_demo.das).

## Границы

Элементы должны владеть своими данными; указатели, ссылки и исполняемые
captures отклоняются. Поддержаны копируемые и move-only значения. Внутри производителя доступны owning
локальные данные и ресурсы, а также заимствующий bind move-only Task через `var x &`.
Поддержаны обычные циклы с break/continue, ветвления и ресурсные блоки общего
resumable-протокола. Отдельные and_bind и асинхронный cleanup
для этого builder пока не добавлены. Для нового обхода вызывайте фабрику stream заново.
Конструктор без типа выбирает int. `return value` отклоняется: элементы выдаются yield.
Потоки и фоновый executor не создаются; синхронный код может блокировать poll.

## Проверки

```powershell
./run_computation.ps1 -Test
& $env:DASLANG_EXE ./tests/test_async_sequence_lifetime.das -no-module-cache -jit -jit-no-cache
```

`test_async_sequence` проверяет порядок, пустой stream и return.
`test_async_sequence_lifetime` проверяет окончание, ранний break, групповую отмену,
таймаут, исключения с обеих сторон, удаление владельца при активном next,
неопрошенный next, запрет одновременных next и стабильный heap после прогрева.
Для глубоко вложенного стресс-теста увеличен бюджет вывода типов
`max_infer_passes`; запускаемый пример использует обычный бюджет SDK.
`test_async_sequence_move` проверяет перенос массивов и структур с финализатором,
заимствующий bind через следующее ожидание, очистку при завершении, отмене,
таймауте, раннем выходе и исключениях, независимость clone/take и стабильный heap.
Для owning-примера также увеличен бюджет вывода типов из-за вложенных ресурсных областей.
`test_async_sequence_deferred` проверяет повторные запуски, независимые снимки,
время их жизни между next, чтение снимка из финализатора, освобождение при
завершении/отмене/таймауте/раннем выходе/ошибке, неопрошенные stream и next,
а также стабильный heap после прогрева и 16 повторений.
`test_async_sequence_yield_from` проверяет вложенное делегирование, порядок,
пустой источник и продолжение после него, copyable/move-only payload, отмену с
обеих сторон, таймаут, ранний выход, исключения, удаление владельца при pending,
deferred-снимки и стабильный heap после прогрева и 16 повторений.
