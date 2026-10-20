options gen2
require ../lib/deferred_computation.das
require ../lib/task_scheduler.das
[export]
def main() {
    var inscope saved <- deferred(TaskResultBuilder(type<array<int>>),[10,20,30]) $(snapshot) {
        var data <- clone(snapshot)
        task_delay_ms(5) |> bind
        for(i in range(length(data))) {
            if(i==1) {continue}
            data[i]+=1
        }
        return <- data
    }
    var inscope handle <- task_share(run_deferred(saved))
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<$Result<array<int>;string>>)
    let cancelled=task_spawn(scheduler,task_with_cancellation(ce_task_source(handle),token))
    let completed=task_spawn(scheduler,handle)
    verify(task_tick(scheduler,0)==2)
    cancellation_cancel(token)
    verify(task_tick(scheduler,1)==1 && task_status(scheduler,cancelled)==TaskStatus.Cancelled)
    verify(task_tick(scheduler,5)==0)
    var inscope value <- task_take(scheduler,completed)
    verify(value is ok && (value as ok)[0]==11 && (value as ok)[1]==20 && (value as ok)[2]==31)
    // A fresh run has its own cloned snapshot and state.
    var inscope again <- run_deferred(saved)
    task_cancel(again)
    print("Task extended demo OK\n")
}
