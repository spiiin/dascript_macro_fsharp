options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
var released=0
var applied=0
struct LevelData {items:array<int>}
def load_data() {var data:LevelData;data.items <- [1,2,3];return <- data}
def ce_dispose(var data:LevelData) {released++;delete data}
def cooldown(duration:int) {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = load_data() |> use_resource
        task_delay_ms(duration) |> bind
        applied++
        return length(data.items)
    }
}
[export]
def main() {
    var inscope group <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<int>)
    let ready=task_spawn(scheduler,cooldown(30))
    let cancelled=task_spawn(scheduler,task_with_cancellation(cooldown(100),group))
    let expired=task_spawn(scheduler,cooldown(100),TaskTimeout(after_ms=20))
    verify(task_tick(scheduler,1000)==3 && applied==0)
    cancellation_cancel(group)
    verify(task_tick(scheduler,1016)==2 && released==1)
    verify(task_tick(scheduler,1020)==1 && released==2)
    verify(task_tick(scheduler,1030)==0 && released==3 && applied==1)
    verify(task_value(scheduler,ready)==3)
    verify(task_status(scheduler,cancelled)==TaskStatus.Cancelled)
    verify(task_timed_out(scheduler,expired))
    print("Task delay demo OK\n")
}
