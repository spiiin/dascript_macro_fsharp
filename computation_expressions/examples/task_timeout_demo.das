options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
var released=0
var applied=0
struct LevelData {items:array<int>}
def load_data() {var data:LevelData;data.items <- [1,2,3];return <- data}
def ce_dispose(var data:LevelData) {released++;delete data}
def prepare_level() {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = load_data() |> use_resource
        let bonus=task_after_polls(10,5) |> bind
        applied++
        return length(data.items)+bonus
    }
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=2))
    let level=task_spawn(scheduler,prepare_level(),TaskTimeout(after_ms=30))
    let quick=task_spawn(scheduler,task_after_polls(0,7),TaskTimeout(after_ms=30))
    verify(task_tick(scheduler,1000)==1) // Start timeout at the first clock sample.
    verify(task_tick(scheduler,1016)==1)
    verify(task_tick(scheduler,1030)==0) // Cancel before the next poll.
    verify(task_timed_out(scheduler,level) && task_status(scheduler,level)==TaskStatus.Cancelled)
    verify(released==1 && applied==0)
    verify(task_status(scheduler,quick)==TaskStatus.Succeeded && task_value(scheduler,quick)==7)
    verify(!task_timed_out(scheduler,quick))
    verify(task_prune(scheduler)==2)
    print("Task timeout demo OK\n")
}
