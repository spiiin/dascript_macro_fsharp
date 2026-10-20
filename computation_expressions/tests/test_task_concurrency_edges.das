options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_parallel.das
require daslib/rtti
var factories=0

def array_job(n:int;fail:bool=false) {
    return <- computation(TaskResultBuilder(type<array<int>>)) {
        var data <- [n,n+1]
        task_after_polls(1,CeUnit()) |> bind
        if(fail) {task_after_polls(0,result_error("no",type<CeUnit>)) |> bind}
        return <- data
    }
}
def checks() {
    {
        var children:array<typedecl(array_job(0))>
        children |> emplace(array_job(1,true));children |> emplace(array_job(2))
        var inscope first <- task_first_success(children)
        task_poll(first);task_poll(first)
        var inscope data <- task_take(first)
        verify((data as ok)[1]==3)
    }
    {
        var inscope retry <- task_retry(@(attempt:int) {return <- array_job(attempt,attempt<2)},2)
        for(i in range(6)) {task_poll(retry)}
        var inscope data <- task_take(retry);verify((data as ok)[0]==2)
        var inscope denied <- task_retry(@(attempt:int) {return <- array_job(attempt,true)},2)
        for(i in range(6)) {task_poll(denied)}
        verify(denied.value is err)
    }
    {
        var inputs <- [1,2]
        var inscope all <- task_when_all_limited(inputs,1,@(i:int) {factories++;return <- array_job(i)})
        task_cancel(all)
        verify(factories==0)
        var empty_inputs:array<int>
        var inscope empty_all <- task_when_all_limited(empty_inputs,1,@(i:int) {factories++;return <- array_job(i)})
        task_poll(empty_all);verify(empty_all.status==TaskStatus.Succeeded && empty(empty_all.value) && factories==0)
    }
    {
        var children:array<typedecl(array_job(0))>
        var child <- array_job(1);task_cancel(child);children |> emplace(child)
        children |> emplace(array_job(2))
        var inscope first <- task_first_success(children);task_poll(first)
        verify(first.status==TaskStatus.Cancelled)
    }
    {
        var inscope sem <- task_semaphore(1)
        var inscope busy <- task_semaphore_acquire(sem);task_poll(busy)
        var inscope waiting <- task_with_semaphore(sem,@(){factories++;return <- array_job(9)})
        task_poll(waiting);verify(task_channel_waiters(sem.channel)==1)
        task_cancel(waiting);verify(task_channel_waiters(sem.channel)==0 && factories==0)
        task_semaphore_release(sem)
    }
    {
        var inscope retry <- task_retry(@(attempt:int) {return <- task_after_polls(0,result_error("again",type<int>))},2,1l)
        task_poll(retry) // A nonzero delay requires the scheduler clock.
        verify(retry.status==TaskStatus.Failed)
    }
    {
        var inscope sem <- task_semaphore(1)
        var inscope protected <- task_with_semaphore(sem,@() {
            return <- task_from_poll(@(){return task_pending(type<int>)},@(){panic("cleanup failed")})
        })
        task_poll(protected);task_cancel(protected)
        verify(protected.status==TaskStatus.Failed && task_channel_count(sem.channel)==1)
        var inscope retry <- task_retry(@(attempt:int) {
            return <- task_from_poll(@(){return task_pending(type<$Result<int;string>>)},@(){panic("cleanup failed")})
        },2)
        task_poll(retry);task_cancel(retry);verify(retry.status==TaskStatus.Failed)
    }
    {
        var inscope ch <- task_channel(type<string>,1)
        unsafe {
            var inscope bytes <- [uint8('o'),uint8('k'),uint8(0)]
            let borrowed=reinterpret<string#>(addr(bytes[0]))
            var inscope send <- task_channel_send(ch,borrowed)
            bytes[0]=uint8('x');delete bytes
            task_poll(send)
            var inscope receive <- task_channel_receive(ch);task_poll(receive)
            verify((receive.value as ok) as some=="ok")
        }
    }
    {
        var inscope runtime <- task_runtime()
        var inscope channel <- task_channel(type<int>,1)
        var inscope token <- cancellation_token()
        var inscope a <- task_spawn(runtime,task_with_cancellation(task_channel_receive(channel),token))
        var inscope b <- task_spawn(runtime,task_with_cancellation(task_after_polls(99,"waiting"),token))
        task_tick(runtime,0);verify(task_channel_waiters(channel)==1)
        cancellation_cancel(token);task_tick(runtime,1)
        verify(task_status(a)==TaskStatus.Cancelled && task_status(b)==TaskStatus.Cancelled)
        verify(task_channel_waiters(channel)==0 && task_active_count(runtime)==0)
    }
}
[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task concurrency edge checks OK\n")
}
