options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost
var opened=fixed_array(0,0,0)
var closed=fixed_array(0,0,0)
var polls=fixed_array(0,0,0)
var order=""
var effects=0
struct Request {remaining:int;data:array<int>}
def owned(id,waits:int; fail_native:bool=false; fail_close:bool=false) {
    opened[id]++
    var state=new Request(remaining=waits,data <- [1,2,3])
    return <- task_from_poll(@(){
        polls[id]++
        if(fail_native) {panic("child {id} failed")}
        if(state.remaining>0) {state.remaining--;return task_pending(type<int>)}
        return task_ready(id*10)
    },@(){
        closed[id]++;order+="{id};"
        unsafe {delete state}
        if(fail_close) {panic("close {id} failed")}
    })
}
def inputs(waits:int=2; fail_native:int=-1; fail_close:int=-1) {
    var tasks:array<typedecl(task_after_polls(0,0))>
    for(i in range(3)) {tasks |> emplace(owned(i,waits,i==fail_native,i==fail_close))}
    return <- tasks
}
def reset() {
    for(i in range(3)) {verify(opened[i]==closed[i]);opened[i]=0;closed[i]=0;polls[i]=0}
    order=""
}
def balanced() {for(i in range(3)) {verify(opened[i]==closed[i])}}
var running:array<typedecl(task_after_polls(0,0))>
def checks() {
    let before=effects
    reset()
    {
        var inscope task <- task_when_all(inputs())
        verify(task_cancel(task) && order=="0;1;2;" && polls[0]==0 && polls[2]==0)
        verify(task_status(task)==TaskStatus.Cancelled && !task_cancel(task))
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(inputs(fail_native=1,fail_close=1))
        verify(task_poll(task)==TaskStatus.Failed && polls[0]==1 && polls[1]==1 && polls[2]==0)
        verify(starts_with(task_error(task),"child 1 failed") && order=="1;0;2;")
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(inputs(fail_close=1))
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && order=="0;1;2;")
        verify(starts_with(task_error(task),"close 1 failed"))
    }
    balanced();reset()
    {
        var tasks <- inputs()
        verify(task_cancel(tasks[1]))
        var inscope task <- task_when_all(tasks)
        verify(task_poll(task)==TaskStatus.Cancelled && polls[0]==1 && polls[2]==0)
        verify(order=="1;0;2;" && empty(task_error(task)))
    }
    balanced();reset()
    {
        var tasks <- inputs(fail_close=0)
        verify(task_cancel(tasks[1]))
        var inscope task <- task_when_all(tasks)
        verify(task_poll(task)==TaskStatus.Failed && polls[2]==0)
        verify(starts_with(task_error(task),"close 0 failed"))
    }
    balanced();reset()
    {
        var inscope group <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<array<int>>)
        let id=task_spawn(scheduler,task_with_cancellation(task_when_all(inputs()),group))
        verify(task_tick(scheduler,0)==1)
        cancellation_cancel(group)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(!task_timed_out(scheduler,id) && task_prune(scheduler)==1)
    }
    balanced();reset()
    {
        var inscope scheduler <- task_scheduler(type<array<int>>)
        let id=task_spawn(scheduler,task_when_all(inputs(20)),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1)
        verify(task_tick(scheduler,5)==0 && task_timed_out(scheduler,id))
    }
    balanced();reset()
    {
        var inscope scheduler <- task_scheduler(type<int>)
        var source <- computation(TaskBuilder(type<int>)) {
            var results & = task_when_all(inputs(0)) |> bind
            task_delay_ms(100) |> bind
            effects++
            return results[0]
        }
        let id=task_spawn(scheduler,source)
        verify(task_tick(scheduler,0)==1)
        verify(task_cancel(scheduler,id) && effects==before)
    }
    balanced();reset()
    {
        var owner <- task_when_all(inputs())
        var caught=false
        try {task_scope(owner,$(var task){verify(task_poll(task)==TaskStatus.Waiting);panic("host failed")})} recover {caught=starts_with(this_context().last_exception,"host failed")}
        verify(caught)
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(inputs())
        verify(task_poll(task)==TaskStatus.Waiting)
    }
    balanced();reset()
    {var inscope never <- task_when_all(inputs())}
    balanced();reset()
    {
        var inscope group <- cancellation_token()
        cancellation_cancel(group)
        var inscope task <- task_with_cancellation(task_when_all(inputs()),group)
        verify(task_poll(task)==TaskStatus.Cancelled && polls[0]==0 && polls[2]==0)
    }
    balanced();reset()
    running |> emplace(task_from_poll(@(){
        var inscope rejected <- task_when_all(running)
        return task_ready(0)
    },@(){}))
    running |> emplace(owned(1,0))
    verify(task_poll(running[0])==TaskStatus.Failed && length(running)==2)
    verify(starts_with(task_error(running[0]),"task_when_all array: cannot move a task being polled"))
    delete running
    balanced()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    // A cancelled batch kept for status/error inspection must not retain its
    // result buffer or children until delete/prune.
    var big:array<typedecl(task_after_polls(0,0))>
    let before=heap_bytes_allocated()
    for(i in range(1024)) {big |> emplace(task_after_polls(2,i))}
    var inscope batch <- task_when_all(big)
    verify(task_cancel(batch) && task_status(batch)==TaskStatus.Cancelled)
    verify(heap_bytes_allocated()==before)
    print("Task array lifetime checks OK\n")
}
