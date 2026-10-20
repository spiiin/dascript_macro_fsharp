options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require daslib/rtti
var polled=0;var closed=0

def owned_job(n:int) {
    var values <- [n,n+1]
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:array<int>>> capture(<-values) {
        polled++;yield <- task_pending(type<array<int>>)
        polled++;yield <- task_ready_move(values);return false
    } finally {ce_sequence_finalize($ {closed++;delete values})}
    return <- task_create(source)
}
def checks() {
    let before=closed;let polls=polled
    {
        var inscope runtime <- task_runtime(TaskSchedulerConfig(max_polls_per_tick=1))
        var inscope a <- task_spawn(runtime,owned_job(4))
        var inscope b <- task_spawn(runtime,task_after_polls(0,"name"))
        var inscope observer <- task_await(a)
        task_poll(observer);verify(polled==polls) // Observing never executes work.
        task_tick(runtime,0);verify(polled==polls+1)
        task_tick(runtime,1);verify(task_value(b)=="name")
        task_tick(runtime,2);verify(task_status(a)==TaskStatus.Succeeded)
        task_poll(observer);verify(observer.value[0]==4)
        var caught=false
        // A second observer keeps the original result alive; take must reject it.
        var inscope retained <- task_shared_clone(a.handle)
        try {var inscope invalid <- task_take(a)} recover {caught=true}
        verify(caught);delete retained
        var inscope data <- task_take(a);verify(data[1]==5)
        verify(task_forget(runtime,a) && task_prune(runtime)==1 && task_count(runtime)==0)
    }
    verify(closed==before+1)
    {
        var inscope runtime <- task_runtime()
        var inscope a <- task_spawn(runtime,owned_job(8),TaskTimeout(after_ms=5))
        var inscope observer <- task_await(a)
        task_poll(observer);task_cancel(observer)
        verify(task_status(a)==TaskStatus.Created)
        task_tick(runtime,10);task_tick(runtime,15)
        verify(task_status(a)==TaskStatus.Cancelled && task_timed_out(runtime,a))
    }
    {
        var inscope runtime <- task_runtime()
        var inscope a <- task_spawn(runtime,owned_job(12))
        delete runtime
        verify(task_status(a)==TaskStatus.Cancelled)
    }
}
[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task runtime lifetime checks OK\n")
}
