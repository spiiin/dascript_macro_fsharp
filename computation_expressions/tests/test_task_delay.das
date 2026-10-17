options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_combinators.das
require daslib/rtti
require daslib/strings_boost
var effects=0
def job(duration:int64; value:int) {
    return <- computation(TaskBuilder(type<int>)) {
        task_delay_ms(duration) |> bind
        effects++
        return value
    }
}
def boundaries() {
    let before=effects
    var inscope scheduler <- task_scheduler(type<int>)
    let a=task_spawn(scheduler,job(10l,7))
    verify(task_tick(scheduler,1000)==1 && effects==before)
    verify(task_tick(scheduler,1009)==1 && effects==before)
    verify(task_tick(scheduler,1009)==1 && effects==before)
    verify(task_tick(scheduler,1010)==0 && task_value(scheduler,a)==7 && effects==before+1)
    verify(task_tick(scheduler,5000)==0 && effects==before+1)
    let zero=task_spawn(scheduler,job(0l,8))
    verify(task_tick(scheduler,5000)==0 && task_value(scheduler,zero)==8)
    var repeated <- computation(TaskBuilder(type<int>)) {
        for(i in range(3)) {task_delay_ms(10) |> bind;effects++}
        return 9
    }
    let loops=task_spawn(scheduler,repeated)
    verify(task_tick(scheduler,6000)==1)
    verify(task_tick(scheduler,7000)==1 && effects==before+3)
    // The next interval starts at 7000, not the old deadline 6010.
    verify(task_tick(scheduler,7009)==1 && effects==before+3)
    verify(task_tick(scheduler,7010)==1 && effects==before+4)
    verify(task_tick(scheduler,7020)==0 && task_value(scheduler,loops)==9 && effects==before+5)
    var inscope moved <- scheduler
    let pending=task_spawn(moved,job(5l,10))
    verify(task_tick(moved,8000)==1)
    var inscope again <- moved
    verify(task_tick(again,8005)==0 && task_value(again,pending)==10)
    let overflow=task_spawn(again,job(9223372036854775807l,0))
    verify(task_tick(again,9223372036854775807l)==1 && task_status(again,overflow)==TaskStatus.Waiting)
    task_scheduler_close(again)
}
def budgets_and_result() {
    var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=1))
    let a=task_spawn(scheduler,job(10l,1))
    let b=task_spawn(scheduler,job(10l,2))
    verify(task_tick(scheduler,0)==2)
    verify(task_tick(scheduler,100)==2) // b starts its own wait at 100.
    verify(task_tick(scheduler,109)==1 && task_value(scheduler,a)==1)
    verify(task_tick(scheduler,110)==0 && task_value(scheduler,b)==2)
    var inscope results <- task_scheduler(type<variant<ok:int;error:string>>)
    var source <- computation(TaskResultBuilder(type<int>)) {
        task_delay_ms(5) |> bind
        let n=task_after_polls(0,result_ok(6)) |> bind
        return n+1
    }
    let id=task_spawn(results,source)
    verify(task_tick(results,900)==1)
    verify(task_tick(results,905)==0)
    let result=task_value(results,id)
    verify(result is ok && result as ok==7)
    // A delay is a normal Task<Unit>, including within combinators.
    var inscope units <- task_scheduler(type<tuple<first:CeUnit;second:CeUnit>>)
    let pair=task_spawn(units,task_when_all(task_delay_ms(5),task_delay_ms(10)))
    verify(task_tick(units,10)==1 && task_tick(units,15)==1 && task_tick(units,20)==0)
    verify(task_status(units,pair)==TaskStatus.Succeeded)
}
var sharedDelay:typedecl(task_delay_ms(10))
var nested:typedecl(task_scheduler(type<int>))
def driver() {return <- task_from_poll(@(){return task_ready(int(task_poll(sharedDelay)))},@(){})}
def clocks() {
    var inscope scheduler <- task_scheduler(type<int>)
    var caught=false
    try {var inscope invalid <- task_delay_ms(-1)} recover {caught=starts_with(this_context().last_exception,"task_delay_ms: duration must be non-negative")}
    verify(caught)
    var inscope noClock <- task_delay_ms(1)
    verify(task_poll(noClock)==TaskStatus.Failed && starts_with(task_error(noClock),"task_delay_ms: polling requires task_tick"))
    sharedDelay <- task_delay_ms(10)
    let a=task_spawn(scheduler,driver())
    verify(task_tick(scheduler,0)==0 && task_value(scheduler,a)==int(TaskStatus.Waiting))
    var inscope other <- task_scheduler(type<int>)
    let b=task_spawn(other,driver())
    verify(task_tick(other,100)==0 && task_value(other,b)==int(TaskStatus.Failed))
    verify(starts_with(task_error(sharedDelay),"task_delay_ms: scheduler changed"))
    delete sharedDelay
    sharedDelay <- task_delay_ms(10)
    nested <- task_scheduler(type<int>)
    let nestedId=task_spawn(nested,job(0l,3))
    var source <- task_from_poll(@(){
        let n=task_tick(nested,10000)
        return task_ready(int(task_poll(sharedDelay)))
    },@(){})
    let outer=task_spawn(scheduler,source)
    verify(task_tick(scheduler,10)==0 && task_value(scheduler,outer)==int(TaskStatus.Waiting))
    let resumed=task_spawn(scheduler,driver())
    verify(task_tick(scheduler,20)==0 && task_value(scheduler,resumed)==int(TaskStatus.Succeeded))
    delete sharedDelay;delete nested
    var inscope after <- task_delay_ms(0)
    verify(task_poll(after)==TaskStatus.Failed) // No clock leaked out of tick.
}
[export]
def main() {
    boundaries();budgets_and_result();clocks()
    print("Task delay checks OK\n")
}
