# Общая отмена Task

`CancellationToken` — общий однопоточный флаг запроса отмены. Несколько задач
удерживают ссылки на одно состояние; `cancellation_cancel(token)` устанавливает
его один раз. Запрос не запускает задачи и не вызывает cleanup из вызывающего кода.

```das
var inscope level <- cancellation_token()
var inscope scheduler <- task_scheduler(type<int>)
let player=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
let npc=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
let running=task_tick(scheduler,0)
verify(cancellation_cancel(level))
verify(task_tick(scheduler,16)==0)
verify(task_status(scheduler,player)==TaskStatus.Cancelled)
verify(task_status(scheduler,npc)==TaskStatus.Cancelled)
```

Полный [пример выхода с игрового уровня](examples/task_cancellation_demo.das)
показывает пайповый bind, освобождение данных и отдельную задачу без токена.
Функция prepare_player возвращает обычную Task; обёртка не меняет её код:

```das
return <- computation(TaskBuilder(type<int>)) {
    var data & = load_data() |> use_resource
    let bonus=task_after_polls(10,5) |> bind
    return length(data.items)+bonus
}
```

## API и владение

Модуль `cancellation_token.das` автоматически подключён через task_builder.das,
task_combinators.das и task_scheduler.das.

| Операция | Поведение |
|---|---|
| `cancellation_token()` | Новый неотменённый владелец CancellationToken |
| `cancellation_clone(token)` | Новый handle того же состояния |
| `clone(token)`, `destination := token` | Также разделяют состояние, включая безопасное самоприсваивание |
| `cancellation_requested(token)` | Запрошена ли отмена |
| `cancellation_cancel(token)` | Запрос; true только при первом установлении флага |
| `task_with_cancellation(task,token)` | Потребляет Task, удерживает собственный handle, возвращает Task того же T |

Используйте `var inscope` или явный delete для владельцев. Обычное копирование
через `=` запрещено; перенос через `<-` опустошает исходный handle. Пустой,
перемещённый или удалённый handle вызывает panic при запросах/клонировании.
Неверный handle проверяется до потребления Task. Задачу в процессе poll передавать
в task_with_cancellation нельзя; отказ также происходит до перемещения.
Внутреннее поле owners не является API.

Удаление исходного handle не запрашивает отмену. Обёртки продолжают владеть
состоянием, даже если исходная переменная уже вышла из области видимости.
Состояние освобождается после удаления последнего handle. У каждой обёртки
есть собственный handle; delete неотменённой обёртки всё равно закрывает её Task.
Сброса флага нет: для следующей группы создайте новый токен.
Все handles могут запросить отмену; разделения на read-only token и source пока нет.

## Границы наблюдения

Обёртка действует без планировщика, через обычный task_poll. Во время её опроса
токен виден всем вложенным вызовам task_poll, включая bind и комбинаторы.
Вложенные обёртки добавляют свои токены: достаточно запроса любого из них.
Проверки происходят до опроса активного генератора, после его шага и до передачи
результата ребёнка продолжению bind. Даже если callback запросил отмену перед
возвратом Ready, продолжение не получит значение. Запрос из cleanup готового
ребёнка также замечается до продолжения родителя.

Код после cancellation_cancel в самом синхронном callback не прерывается.
Длительный/блокирующий callback удерживает управление до возврата. Токены не
добавляют потоки, атомики или поддержку нескольких context; обращения должны
происходить из одного потока и context.

В scheduler группа замечает отмену **по очереди опроса**. При бюджете 1 за tick
отменится не более одной ещё не опрошенной корневой обёртки; остальные закроются
на следующих tick. Это отличается от очереди таймаутов, которая закрывает все
истёкшие записи до poll независимо от его бюджета. Совпавший таймаут обрабатывается
первым; task_timed_out=true. Отмена через токен сама по себе этот флаг не ставит.
Ручная отмена/таймаут отдельной Task не меняют общий токен.

## Cancelled, Error и исключения

Cancelled ожидаемого ребёнка передаётся вверх через любое число bind, без panic
и без выполнения последующих шагов. Это действует для TaskBuilder и
TaskResultBuilder даже без токена. TryWith не перехватывает отмену, а области
use_resource и try_finally закрываются. TaskResult не превращает её в Result.error.
task_value доступен только при Succeeded, task_error при обычной отмене пуст.

Task WhenAll/ResultWhenAll/Race также передают наблюдённый Cancelled и закрывают
оставшихся детей. Порядок наблюдения слева направо сохраняется: в гонке уже
наблюдённый успешный левый результат выигрывает без опроса правого.

Native exception, наблюдённый во время poll, остаётся Failed, даже если callback
также запросил отмену. Ошибка cleanup при отмене также даёт Failed и диагностику;
остальные владельцы освобождаются. Отмена не распознаётся по тексту исключения:
это отдельный внутренний сигнал текущего poll. Завершённые внешние Task не
меняют статус при последующем запросе токена.

Обёртка над task_from_async закрывает стандартный iterator и его close-callback.
Если внешняя операция требует собственного cancel/unregister, сделайте это в
close-callback. Ограничения native finally и inscope из [TASKS.md](TASKS.md)
остаются в силе. Для panic внешнего driving-кода используйте task_scope или
task_scheduler_scope.

## Проверки и расходы

- [test_task_cancellation.das](tests/test_task_cancellation.das): вложенные bind,
  TaskResult, try_with, запрос перед Ready, ошибки и отсутствие утечки контекста отмены.
- [test_task_cancellation_lifetime.das](tests/test_task_cancellation_lifetime.das):
  группа, бюджет scheduler, native async, clone/move, время жизни handles,
  cleanup с ошибкой, таймаут, panic хоста и 32 повторения со стабильным heap.

Токен выделяет общее состояние и небольшой массив handle; клонирование выделяет
только новый handle, состояние остаётся общим. Task-обёртка добавляет генератор.
Вложенные poll используют приватный стек заимствованных handles только на время
синхронного вызова, без сохранения адресов стека через yield. Буферы стеков
наблюдения и cleanup сохраняют максимальную достигнутую ёмкость до удаления
context; повторения после прогрева не увеличивают её. Проверка токенов стоит
O(D) при D активных вложенных обёртках; без обёртки стек пуст.
