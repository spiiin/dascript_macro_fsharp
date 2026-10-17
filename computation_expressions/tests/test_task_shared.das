options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/rtti
require strings
var polls=0
var closed=0
def producer() {return <- task_from_poll(@(){polls++;return polls<3 ? task_pending(type<int>) : task_ready(42)},@(){closed++})}
def checks() {
    polls=0;closed=0
    {
        var inscope handle <- task_share(producer())
        var inscope token <- cancellation_token()
        var firstLease <- task_shared_clone(handle)
        var secondLease <- task_shared_clone(handle)
        unsafe {
        var first <- computation(TaskBuilder(type<int>)) {let n=firstLease |> bind;return n+1}
        var inscope cancelled <- task_with_cancellation(first,token)
        var inscope second <- computation(TaskBuilder(type<int>)) {let n=secondLease |> bind;return n+2}
        verify(task_poll(cancelled)==TaskStatus.Waiting)
        cancellation_cancel(token)
        verify(task_poll(cancelled)==TaskStatus.Cancelled && task_status(handle)==TaskStatus.Waiting && closed==0)
        verify(task_poll(second)==TaskStatus.Waiting)
        verify(task_poll(second)==TaskStatus.Succeeded && task_value(second)==44 && closed==1)
        verify(task_value(handle)==42 && task_poll(handle)==TaskStatus.Succeeded && polls==3)
        }
    }
    polls=0;closed=0
    {
        var inscope handle <- task_share(producer())
        var inscope copy <- task_shared_clone(handle)
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,handle)
        let b=task_spawn(scheduler,copy)
        while(task_tick(scheduler,0)!=0) {}
        verify(task_value(scheduler,a)==42 && task_value(scheduler,b)==42 && polls==3 && closed==1)
    }
    polls=0;closed=0
    {
        var inscope handle <- task_share(producer())
        var inscope waiter <- task_from_shared(task_shared_clone(handle))
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,waiter,TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,100)==1 && polls==1)
        verify(task_tick(scheduler,105)==0 && task_timed_out(scheduler,id))
        verify(closed==0 && task_status(handle)==TaskStatus.Waiting)
        verify(task_cancel(handle) && closed==1)
        verify(task_status(handle)==TaskStatus.Cancelled)
    }
    closed=0
    {
        var failed <- task_from_poll(@(){panic("shared failure");return task_ready(0)},@(){closed++})
        var inscope handle <- task_share(failed)
        var inscope a <- task_from_shared(task_shared_clone(handle))
        var inscope b <- task_from_shared(task_shared_clone(handle))
        verify(task_poll(a)==TaskStatus.Failed && task_poll(b)==TaskStatus.Failed)
        verify(starts_with(task_error(a),"shared failure") && starts_with(task_error(b),"shared failure") && closed==1)
    }
    polls=0;closed=0
    {
        var handle <- task_share(producer())
        var other <- task_shared_clone(handle)
        delete handle
        verify(closed==0)
        delete other
        verify(closed==1 && polls==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task shared checks OK\n")
}
