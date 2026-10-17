options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_combinators.das
require daslib/async_boost
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
var effects=0
var order=""
struct Resource {items:array<int>}
def acquire() {var r:Resource;r.items <- [1,2,3];opened++;return <- r}
def ce_dispose(var r:Resource) {closed++;order+="ce;";delete r}
[async]
def native_read(request:Resource?) : int {await_next_frame();effects++;yield length(request.items)}
def read_request(fail_close:bool=false) {
    var request=new Resource(items <- [4,5,6])
    opened++
    return <- task_from_async(native_read(request),@(){
        unsafe {delete request}
        closed++;order+="async;"
        if(fail_close) {panic("close failed")}
    })
}
def job() {
    return <- computation(TaskBuilder(type<int>)) {
        var resource & = acquire() |> use_resource
        let n=read_request() |> bind
        effects++
        return n+length(resource.items)
    }
}
def local_token_task() {
    var inscope local <- cancellation_token()
    return <- task_with_cancellation(task_after_polls(1,8),local)
}
def checks() {
    let before=effects
    {
        var inscope group <- cancellation_token()
        var inscope copy <- clone(group)
        var inscope assigned:CancellationToken
        assigned := group
        assigned := assigned // Self assignment keeps one valid lease.
        var inscope moved <- copy
        var inscope scheduler <- task_scheduler(type<int>)
        let first=task_spawn(scheduler,task_with_cancellation(job(),group))
        let second=task_spawn(scheduler,task_with_cancellation(job(),assigned))
        verify(task_tick(scheduler,0)==2)
        order=""
        verify(cancellation_cancel(moved) && cancellation_requested(group) && cancellation_requested(assigned))
        verify(!cancellation_cancel(group))
        verify(task_tick(scheduler,1)==0 && effects==before && opened==closed)
        verify(order=="async;ce;async;ce;")
        verify(task_status(scheduler,first)==TaskStatus.Cancelled && task_status(scheduler,second)==TaskStatus.Cancelled)
        verify(!task_timed_out(scheduler,first))
        verify(task_prune(scheduler)==2)
    }
    {
        var inscope group <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=1))
        let a=task_spawn(scheduler,task_with_cancellation(job(),group))
        let b=task_spawn(scheduler,task_with_cancellation(read_request(),group))
        verify(task_tick(scheduler,0)==2)
        verify(cancellation_cancel(group))
        // Cancellation is observed on each task's turn, including unstarted b.
        verify(task_tick(scheduler,1)==1 && task_status(scheduler,b)==TaskStatus.Cancelled)
        verify(task_tick(scheduler,2)==0 && task_status(scheduler,a)==TaskStatus.Cancelled)
        verify(opened==closed && effects==before)
    }
    {
        var inscope group <- cancellation_token()
        var inscope first <- task_with_cancellation(read_request(),group)
        var inscope second <- task_with_cancellation(task_after_polls(0,7),group)
        verify(task_cancel(first) && !cancellation_requested(group))
        verify(task_poll(second)==TaskStatus.Succeeded && task_value(second)==7)
        verify(opened==closed)
    }
    {
        var group <- cancellation_token()
        var inscope alias <- cancellation_clone(group)
        var inscope task <- task_with_cancellation(job(),group)
        delete group
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(cancellation_cancel(alias))
        delete alias
        verify(task_poll(task)==TaskStatus.Cancelled && opened==closed)
    }
    {
        var inscope task <- local_token_task()
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==8)
    }
    {
        var inscope group <- cancellation_token()
        var source <- computation(TaskResultBuilder(type<int>)) {
            var resource & = acquire() |> use_resource
            let n=task_after_polls(10,result_ok(4)) |> bind
            effects++
            return n
        }
        var inscope task <- task_with_cancellation(source,group)
        verify(task_poll(task)==TaskStatus.Waiting)
        cancellation_cancel(group)
        verify(task_poll(task)==TaskStatus.Cancelled && opened==closed && effects==before)
    }
    {
        var inscope group <- cancellation_token()
        var inscope task <- task_with_cancellation(read_request(true),group)
        verify(task_poll(task)==TaskStatus.Waiting)
        cancellation_cancel(group)
        verify(task_poll(task)==TaskStatus.Failed && starts_with(task_error(task),"close failed"))
        verify(opened==closed)
    }
    {
        var inscope group <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(job(),group),TaskTimeout(after_ms=1))
        verify(task_tick(scheduler,0)==1)
        verify(task_tick(scheduler,1)==0 && task_timed_out(scheduler,id))
        verify(!cancellation_requested(group) && opened==closed)
    }
    {
        var inscope group <- cancellation_token()
        var owner <- task_with_cancellation(job(),group)
        var caught=false
        try {task_scope(owner,$(var task){verify(task_poll(task)==TaskStatus.Waiting);panic("host failed")})} recover {caught=starts_with(this_context().last_exception,"host failed")}
        verify(caught && !cancellation_requested(group) && opened==closed)
    }
    {
        var inscope group <- cancellation_token()
        var inscope abandoned <- task_with_cancellation(read_request(),group)
        // Dropping an unpolled wrapper also closes its preallocated handle.
    }
    verify(opened==closed && effects==before)
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==closed)
    print("Task cancellation lifetime checks OK\n")
}
