options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
var released=0
var applied=0
struct LevelData {items:array<int>}
def load_data() {var data:LevelData;data.items <- [1,2,3];return <- data}
def ce_dispose(var data:LevelData) {released++;delete data}
def prepare_player() {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = load_data() |> use_resource
        let bonus=task_after_polls(10,5) |> bind
        applied++
        return length(data.items)+bonus
    }
}
[export]
def main() {
    var inscope level <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<int>)
    let player=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
    let npc=task_spawn(scheduler,task_with_cancellation(prepare_player(),level))
    let unrelated=task_spawn(scheduler,task_after_polls(1,7))
    verify(task_tick(scheduler,0)==3)
    // Leaving the level requests cancellation for both jobs, including awaits.
    verify(cancellation_cancel(level))
    verify(task_tick(scheduler,16)==0)
    verify(task_status(scheduler,player)==TaskStatus.Cancelled)
    verify(task_status(scheduler,npc)==TaskStatus.Cancelled)
    verify(task_value(scheduler,unrelated)==7 && released==2 && applied==0)
    verify(task_prune(scheduler)==3)
    print("Task cancellation demo OK\n")
}
