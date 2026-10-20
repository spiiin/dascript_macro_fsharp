options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_parallel.das
require daslib/rtti
var opened=0;var closed=0;var active=0;var peak=0;var attempts=0
var order=""
def tracked(n:int;waits:int=2;fail:bool=false;crash:bool=false) {
    opened++;active++;if(active>peak) {peak=active}
    order+="{n};"
    var data <- [n,n+1]
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<int;string>>> capture(copy(n),copy(waits),copy(fail),copy(crash),<-data) {
        for(i in range(waits)) {yield task_pending(type<$Result<int;string>>)}
        if(crash) {panic("native failure")}
        yield task_ready(fail ? result_error("denied {n}",type<int>) : result_ok(n));return false
    } finally {ce_sequence_finalize($ {active--;closed++;delete data})}
    return <- task_create(source)
}
def reset() {verify(active==0 && opened==closed);peak=0;order="";attempts=0}
def owned(n:int) {
    return <- computation(TaskResultBuilder(type<array<int>>)) {
        var data <- [n,n+1]
        task_after_polls(1,CeUnit()) |> bind
        return <- data
    }
}
def checks() {
    reset()
    {
        var inputs <- [0,1,2,3,4,5]
        var inscope all <- task_result_when_all_limited(inputs,2,@(n:int) {return <- tracked(n,5-n)})
        verify(opened==closed) // Factory has not run at construction.
        for(i in range(30)) {task_poll(all)}
        verify(all.status==TaskStatus.Succeeded && peak==2 && active==0)
        for(i in range(6)) {verify((all.value as ok)[i]==i)}
        verify(order=="0;1;2;3;4;5;")
    }
    reset()
    {
        var inputs <- [0,1,2,3]
        var inscope all <- task_result_when_all_limited(inputs,2,@(n:int) {return <- tracked(n,n==0 ? 0 : 99,n==0)})
        task_poll(all)
        verify(all.value is err && active==0 && order=="0;1;")
    }
    reset()
    {
        var inputs <- [0,1,2]
        var inscope all <- task_result_when_all_limited(inputs,2,@(n:int) {if(n==1) {panic("factory failed")};return <- tracked(n)})
        task_poll(all);verify(all.status==TaskStatus.Failed && active==0 && order=="0;")
    }
    reset()
    {
        var inputs <- [0,1,2]
        var inscope all <- task_result_when_all_limited(inputs,2,@(n:int) {return <- tracked(n,99)})
        task_poll(all);task_cancel(all);verify(active==0 && order=="0;1;")
    }
    reset()
    {
        var inputs <- [2,4,6]
        var inscope all <- task_result_when_all_limited(inputs,2,@(n:int) {return <- owned(n)})
        for(i in range(10)) {task_poll(all)}
        var inscope values <- task_take(all)
        verify((values as ok)[0][0]==2 && (values as ok)[2][1]==7)
    }
    {
        var inscope sem <- task_semaphore(1)
        var inscope a <- task_with_semaphore(sem,@(){return <- tracked(1,99)})
        var inscope b <- task_with_semaphore(sem,@(){return <- tracked(2,0,true)})
        task_poll(a);task_poll(b);verify(active==1 && task_channel_waiters(sem.channel)==1)
        task_cancel(a);verify(active==0)
        task_poll(b);verify(b.value is err && task_channel_count(sem.channel)==1 && active==0)
        var inscope runtime <- task_runtime()
        var inscope ticket <- task_spawn(runtime,task_with_semaphore(sem,@(){return <- tracked(3,99)}),TaskTimeout(after_ms=3))
        task_tick(runtime,100);task_tick(runtime,103)
        verify(task_status(ticket)==TaskStatus.Cancelled && active==0 && task_channel_count(sem.channel)==1)
        task_semaphore_close(sem)
        var inscope denied <- task_semaphore_acquire(sem);task_poll(denied);verify(denied.value is err)
    }
    reset()
    {
        var inscope runtime <- task_runtime()
        var inscope job <- task_spawn(runtime,task_retry(@(attempt:int) {attempts++;return <- tracked(attempt,0,attempt<3)},3,10l))
        task_tick(runtime,100);verify(attempts==1)
        task_tick(runtime,109);verify(attempts==1)
        task_tick(runtime,110);verify(attempts==2)
        task_tick(runtime,120);verify(attempts==3 && task_value(job) as ok==3 && active==0)
    }
    reset()
    {
        var inscope runtime <- task_runtime()
        var inscope job <- task_spawn(runtime,task_retry(@(attempt:int) {attempts++;return <- tracked(attempt,0,true)},5,10l),TaskTimeout(after_ms=5))
        task_tick(runtime,0);task_tick(runtime,5);task_tick(runtime,100)
        verify(attempts==1 && task_status(job)==TaskStatus.Cancelled && active==0)
    }
    reset()
    {
        var inscope retry <- task_retry(@(attempt:int) {attempts++;return <- tracked(attempt,0,false,true)},3)
        task_poll(retry);verify(retry.status==TaskStatus.Failed && attempts==1 && active==0)
    }
    reset()
    {
        var children:array<typedecl(tracked(0))>
        children |> emplace(tracked(1,0,true));children |> emplace(tracked(2,1));children |> emplace(tracked(3,99))
        var inscope first <- task_first_success(children)
        task_poll(first);task_poll(first)
        verify(first.value as ok==2 && active==0)
    }
    reset()
    {
        var children:array<typedecl(tracked(0))>
        children |> emplace(tracked(1,0,true));children |> emplace(tracked(2,0,true))
        var inscope first <- task_first_success(children);task_poll(first)
        verify(first.value is err && first.value as err=="denied 2" && active==0)
        var empty_children:array<typedecl(tracked(0))>
        var inscope empty_first <- task_first_success(empty_children);task_poll(empty_first)
        verify(empty_first.value is err)
    }
    verify(active==0 && opened==closed)
}
[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task parallel lifetime checks OK\n")
}
