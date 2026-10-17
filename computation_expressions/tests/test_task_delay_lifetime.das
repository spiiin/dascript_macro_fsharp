options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
var finalized=0
var effects=0
struct Resource {items:array<int>}
def acquire() {var r:Resource;r.items <- [1,2,3];opened++;return <- r}
def ce_dispose(var r:Resource) {closed++;delete r}
def job(duration:int; fail:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var resource & = acquire() |> use_resource
        try_finally($ {
            task_delay_ms(duration) |> bind
            if(fail) {panic("after wait")}
            effects++
            return length(resource.items)
        },$ {finalized++})
    }
}
def checks() {
    let before=effects
    let initialOpened=opened
    let initialFinalized=finalized
    {
        var inscope scheduler <- task_scheduler(type<int>)
        for(i in range(12)) {
            let id=task_spawn(scheduler,job(100))
            verify(task_tick(scheduler,i)==1)
            verify(task_cancel(scheduler,id) && task_status(scheduler,id)==TaskStatus.Cancelled)
            verify(opened==closed && effects==before)
            verify(task_prune(scheduler)==1 && task_slot_count(scheduler)==1)
        }
        let id=task_spawn(scheduler,job(100),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,12)==1)
        verify(task_tick(scheduler,16)==0 && task_timed_out(scheduler,id))
        verify(opened==closed && effects==before)
    }
    {
        var inscope group <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,task_with_cancellation(job(100),group))
        let b=task_spawn(scheduler,task_with_cancellation(job(100),group))
        verify(task_tick(scheduler,1000)==2)
        cancellation_cancel(group)
        verify(task_tick(scheduler,1001)==0 && opened==closed && effects==before)
        verify(task_status(scheduler,a)==TaskStatus.Cancelled && task_status(scheduler,b)==TaskStatus.Cancelled)
    }
    {
        var inscope group <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<variant<ok:int;error:string>>)
        var source <- computation(TaskResultBuilder(type<int>)) {
            var resource & = acquire() |> use_resource
            task_delay_ms(100) |> bind
            effects++
            return length(resource.items)
        }
        let id=task_spawn(scheduler,task_with_cancellation(source,group))
        verify(task_tick(scheduler,0)==1)
        cancellation_cancel(group)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(opened==closed && effects==before)
    }
    for(i in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,job(100))
        verify(task_tick(scheduler,0)==1)
        break // Destructor closes an outstanding delay on a host-loop break.
    }
    verify(opened==closed)
    {
        var scheduler <- task_scheduler(type<int>)
        var caught=false
        try {task_scheduler_scope(scheduler,$(var owner){
            let id=task_spawn(owner,job(100))
            verify(task_tick(owner,0)==1)
            panic("host failed")
        })} recover {caught=starts_with(this_context().last_exception,"host failed")}
        verify(caught && opened==closed && effects==before)
    }
    {
        var inscope scheduler <- task_scheduler(type<int>)
        let bad=task_spawn(scheduler,job(-1))
        verify(task_tick(scheduler,0)==0 && task_status(scheduler,bad)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,bad),"task_delay_ms: duration must be non-negative"))
        let fail=task_spawn(scheduler,job(10,true))
        verify(task_tick(scheduler,1)==1 && task_tick(scheduler,11)==0)
        verify(task_status(scheduler,fail)==TaskStatus.Failed && starts_with(task_error(scheduler,fail),"after wait"))
        let good=task_spawn(scheduler,job(5))
        verify(task_tick(scheduler,12)==1 && task_tick(scheduler,17)==0 && task_value(scheduler,good)==3)
        verify(effects==before+1 && opened==closed)
    }
    // TaskResult's resource was outside try_finally; all other opened bodies
    // passed through that finalizer exactly once, including exceptions/break.
    verify(finalized-initialFinalized==opened-initialOpened-1)
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==closed)
    print("Task delay lifetime checks OK\n")
}
