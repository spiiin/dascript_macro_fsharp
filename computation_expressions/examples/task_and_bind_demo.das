options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
var continued=false

[export]
def main() {
    var inscope turn <- computation(TaskBuilder(type<string>)) {
        let player=task_after_polls(1,"Mage") |> and_bind(task_after_polls(2,100)) |> bind
        return "{player.first}: health={player.second}"
    }
    verify(task_poll(turn)==TaskStatus.Waiting)
    verify(task_poll(turn)==TaskStatus.Waiting)
    verify(task_poll(turn)==TaskStatus.Succeeded)
    print("{task_value(turn)}\n")

    var inscope purchase <- computation(TaskResultBuilder(type<int>)) {
        let checks=task_after_polls(0,result_error("Out of stock",type<int>)) |> and_bind(task_after_polls(3,result_ok(50))) |> bind
        continued=true
        return checks.first+checks.second
    }
    verify(task_poll(purchase)==TaskStatus.Succeeded && !continued)
    let result=task_value(purchase)
    verify(result is err && result as err=="Out of stock")
    print("Task and_bind demo OK\n")
}
