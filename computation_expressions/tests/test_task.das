options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/rtti
var trace=""

def make_task(n:int) {
    return <- computation(TaskBuilder(type<int>)) {
        trace+="start;"
        let a=task_after_polls(2,n) |> bind
        trace+="a;"
        let b=task_after_polls(1,a+1) |> bind
        trace+="b;"
        return b*2
    }
}
[export]
def main() {
    var inscope task <- make_task(10)
    verify(trace=="")
    verify(task_poll(task)==TaskStatus.Waiting && trace=="start;")
    verify(task_poll(task)==TaskStatus.Waiting && trace=="start;")
    verify(task_poll(task)==TaskStatus.Waiting && trace=="start;a;")
    verify(task_poll(task)==TaskStatus.Succeeded && trace=="start;a;b;")
    verify(task_value(task)==22)
    verify(task_poll(task)==TaskStatus.Succeeded && trace=="start;a;b;")
    print("Task checks OK\n")
}
