options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
require daslib/async_boost

[async]
def standard_name() : string {await_next_frame();yield "Alice"}
def load_player() {
    return <- computation(TaskBuilder(type<string>)) {
        let data=task_when_all(task_from_async(standard_name()),task_after_polls(2,85)) |> bind
        return "{data.first}: health={data.second}"
    }
}
[export]
def main() {
    var inscope player <- load_player()
    var frame=0
    while(task_poll(player)==TaskStatus.Waiting) {frame++;print("Frame {frame}: loading\n")}
    print("{task_value(player)}\n")
    var inscope checked <- computation(TaskResultBuilder(type<int>)) {
        let pair=task_result_when_all(task_after_polls(1,result_ok(10)),task_after_polls(2,result_ok(20))) |> bind
        return pair.first+pair.second
    }
    while(task_poll(checked)==TaskStatus.Waiting) {}
    let result=task_value(checked)
    verify(result is ok && result as ok==30)
    var inscope race <- task_race(task_after_polls(3,"slow"),task_from_async(standard_name()))
    while(task_poll(race)==TaskStatus.Waiting) {}
    let winner=task_value(race)
    verify(winner.index==1 && winner.value=="Alice")
    print("Winner: {winner.index}, {winner.value}\nTask composition demo OK\n")
}
