options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/async_boost

// An external async operation can be awaited without knowing about the scheduler.
[async]
def load_level() : int {await_next_frame();yield 12}
def prepare_player() {
    return <- computation(TaskBuilder(type<int>)) {
        let level=task_from_async(load_level()) |> bind
        let bonus=task_after_polls(1,3) |> bind
        return level+bonus
    }
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=1))
    let player=task_spawn(scheduler,prepare_player())
    let npc=task_spawn(scheduler,task_after_polls(1,7))
    var frame=0
    while(task_active_count(scheduler)>0) {
        let remaining=task_tick(scheduler,frame*16)
        frame++
    }
    verify(task_value(scheduler,player)==15 && task_value(scheduler,npc)==7)
    verify(task_forget(scheduler,player))
    verify(task_prune(scheduler)==1)

    var inscope requests <- task_scheduler(type<variant<ok:int;error:string>>)
    var requestTask <- computation(TaskResultBuilder(type<int>)) {
        let n=task_after_polls(1,result_ok(8)) |> bind
        return n+1
    }
    let request=task_spawn(requests,requestTask)
    verify(task_tick(requests,0)==1)
    verify(task_tick(requests,16)==0)
    let outcome=task_value(requests,request)
    verify(outcome is ok && outcome as ok==9)
    task_scheduler_close(requests)
    print("Task scheduler demo OK\n")
}
