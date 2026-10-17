# Move-only ресурсы в use_resource

`var resource & = acquire() |> use_resource` передаёт ресурс во владение CE.
Тело временно заимствует тот же экземпляр, без копирования или клонирования.
Обычная запись `let resource = ... |> use_resource` сохраняет прежний контракт
копируемого handle.

```das
struct UploadBuffer {id:int;data:array<int>}
def ce_dispose(var buffer:UploadBuffer) {
    // Здесь также закрывают внешние handles, если они есть.
    delete buffer
}

let result=computation(ResultBuilder()) {
    var buffer & = acquire_buffer(1) |> use_resource
    buffer.data |> push(99)
    return length(buffer.data)
}
```

Доступная в вызывающем модуле перегрузка `ce_dispose(var resource:T)` обязательна.
Именно она освобождает ресурс целиком, включая вложенные allocations.
Библиотека не вызывает повторный dispose или delete реального payload после неё.
`delete resource` внутри ce_dispose — простой вариант для структуры, владеющей
только памятью. Для внешнего ресурса сначала закройте его handle.

## Владение

Источник перемещается при достижении объявления. Существующая переменная
источника становится moved-from; возвращённое функцией значение не копируется.
`var resource <- ... |> use_resource`, clone и inscope-декларации отвергаются:
ресурсом должен владеть CE, а переменная тела лишь заимствует его.

Не сохраняйте ссылку/указатель на ресурс за пределами области и не перемещайте
весь ресурс наружу. Можно явно извлечь отдельное owning поле через `<-`, если
контракт вашего ce_dispose допускает его отсутствие. Например, массив данных
может перейти в результат, а handle ресурса всё равно закрыться в ce_dispose.
Компилятор daScript не обеспечивает линейное владение: это контракт API.

Проверено для Result, Option, MoveResult, MoveOption, List и Sequence.
В eager CE cleanup вызывается при обычном результате, Error/None и native panic.
Общий hook `ce_using_move(builder, var resource, body, cleanup)` можно
переопределить для стороннего builder. Он передаёт continuation изменяемое
заимствование и поддерживает копируемые и перемещаемые результаты.

## Sequence и deferred

```das
var inscope stream <- computation(SequenceBuilder()) {
    var buffer & = acquire_buffer(1) |> use_resource
    for(value in buffer.data) {yield value}
}
for(value in stream) {break}
// buffer уже освобождён.
```

Ресурс приобретается лениво, когда обход достигает use_resource. Для передачи
одного экземпляра между телом и cleanup используется одна heap-ячейка на ресурс.
При закрытии сначала завершается дочерний итератор, затем вызывается disposer.
Вложенные области закрываются в обратном порядке; ранее приобретённый ресурс
закрывается также при ошибке приобретения следующего.

Непрочитанный Sequence не приобретает ресурс. `deferred` создаёт новый ресурс
для каждого запуска при достижении объявления в теле. В snapshot по-прежнему
нельзя хранить произвольные внешние handles: приобретайте их внутри CE.

Обычное завершение, break и явное close закрывают ресурс. Для исключения
потребителя вне CE используйте `sequence_each`/`sequence_each_move` либо явный
try/recover с sequence_close. Ограничение native for на panic остаётся прежним.
Disposer должен освобождать всё владение и не бросать исключений; native
finalizer должен корректно обрабатывать moved-from значение. Ошибка disposer
не запускает его повторно. Если он бросил до освобождения данных, библиотека
не может гарантировать очистку внешнего ресурса. Для Sequence сохраняется
известное ограничение runtime при бросающих финализаторах.

Пример: `move_resources_demo.das`; фабрики: `move_resource_support.das`.
`test_move_resources.das` проверяет порядок и число dispose, результат после
извлечения поля, завершение, break, acquisition/body/consumer errors, deferred
и возврат heap к исходному уровню. Отрицательные тесты проверяют неверное
объявление владельца и отсутствие disposer.
