options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/async_boost
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
var continued=0
var order=""
struct Resource {items:array<int>}
def acquire() {var r:Resource;r.items <- [1,2,3];opened++;return <- r}
def ce_dispose(var r:Resource) {closed++;order+="ce;";delete r}
[async]
def native_read(request:Resource?) : int {
    await_next_frame()
    continued++
    yield length(request.items)
}
def read_request() {
    var request=new Resource(items <- [4,5,6])
    opened++
    return <- task_from_async(native_read(request),@(){
        unsafe {delete request}
        closed++;order+="async;"
    })
}
def game_job() {
    return <- computation(TaskBuilder(type<int>)) {
        var r & = acquire() |> use_resource
        let n=read_request() |> bind
        continued++
        return n+length(r.items)
    }
}
def checked_job() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var r & = acquire() |> use_resource
        let n=task_after_polls(20,result_ok(4)) |> bind
        continued++
        return n+length(r.items)
    }
}
var callbackScheduler:typedecl(task_scheduler(type<int>))
var callbackId:TaskId
def checks() {
    let before=continued
    order=""
    {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,game_job(),TaskTimeout(after_ms=10))
        verify(task_tick(scheduler,100)==1)
        verify(task_tick(scheduler,110)==0 && task_timed_out(scheduler,id))
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && continued==before)
        verify(order=="async;ce;" && opened==closed)
        verify(task_prune(scheduler)==1)
        // Expire an adapter before its first poll: its preallocated request
        // still belongs to the Task and must be freed exactly once.
        let never=task_spawn(scheduler,read_request(),TaskTimeout(after_ms=0))
        verify(task_tick(scheduler,110)==0 && task_timed_out(scheduler,never))
        verify(opened==closed && continued==before)
        for(i in range(12)) {
            let next=task_spawn(scheduler,game_job(),TaskTimeout(after_ms=1))
            verify(task_tick(scheduler,110+i)==1)
            verify(task_tick(scheduler,111+i)==0 && task_timed_out(scheduler,next))
            verify(task_prune(scheduler)>0 && opened==closed)
        }
        // Owner destruction closes a non-expired timer and suspended resource.
        let pending=task_spawn(scheduler,game_job(),TaskTimeout(after_ms=100))
        verify(task_tick(scheduler,123)==1)
    }
    verify(opened==closed && continued==before)
    {
        var inscope scheduler <- task_scheduler(type<$Result<int;string>>)
        let id=task_spawn(scheduler,checked_job(),TaskTimeout(after_ms=1))
        verify(task_tick(scheduler,0)==1)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(task_timed_out(scheduler,id) && opened==closed && continued==before)
    }
    {
        var owner <- task_scheduler(type<int>)
        var caught=false
        try {
            task_scheduler_scope(owner,$(var scheduler) {
                let id=task_spawn(scheduler,game_job(),TaskTimeout(after_ms=100))
                verify(task_tick(scheduler,0)==1)
                panic("host failed")
            })
        } recover {caught=starts_with(this_context().last_exception,"host failed")}
        verify(caught && opened==closed)
    }
    callbackScheduler <- task_scheduler(type<int>)
    var source <- task_from_poll(@(){return task_pending(type<int>)},@(){
        verify(task_timed_out(callbackScheduler,callbackId))
        let n=task_tick(callbackScheduler,0)
    })
    callbackId=task_spawn(callbackScheduler,source,TaskTimeout(after_ms=0))
    let other=task_spawn(callbackScheduler,read_request(),TaskTimeout(after_ms=0))
    verify(task_tick(callbackScheduler,0)==0)
    verify(task_timed_out(callbackScheduler,callbackId) && task_status(callbackScheduler,callbackId)==TaskStatus.Failed)
    verify(starts_with(task_error(callbackScheduler,callbackId),"task scheduler: mutation"))
    verify(task_status(callbackScheduler,other)==TaskStatus.Cancelled && opened==closed)
    delete callbackScheduler
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==closed)
    print("Task timeout lifetime checks OK\n")
}
