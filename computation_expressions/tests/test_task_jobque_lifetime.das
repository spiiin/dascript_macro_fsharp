options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_jobque.das
require daslib/rtti
require daslib/fio
struct Work {items:array<int>;fail:bool;delay:uint}
def worker(input:Work) {
    if(input.delay>0u) {sleep(input.delay)}
    if(input.fail) {panic("worker failure")}
    var values:array<int>;values := input.items
    values |> push(42)
    return <- values
}
def checks() {
    with_job_que() {
        var inscope queue <- task_job_queue()
        var inscope runtime <- task_runtime()
        {
            var inscope input=Work(items <- [1,2],delay=1u)
            var inscope work <- task_jobque(queue,input,@@worker)
            input.items[0]=99 // The worker receives the submitted snapshot.
            var inscope job <- task_spawn(runtime,work)
            for(i in range(10000)) {
                task_tick(runtime,i)
                if(task_status(job)==TaskStatus.Succeeded) {break}
                sleep(1u)
            }
            verify(task_status(job)==TaskStatus.Succeeded)
            var inscope value <- task_take(job)
            verify((value as ok)[0]==1 && (value as ok)[2]==42)
        }
        {
            var inscope input=Work(items <- [3],fail=true)
            var inscope job <- task_spawn(runtime,task_jobque(queue,input,@@worker))
            for(i in range(10000,20000)) {
                task_tick(runtime,i)
                if(task_status(job)==TaskStatus.Succeeded) {break}
                sleep(1u)
            }
            var inscope value <- task_take(job)
            verify(value is err && !empty(value as err))
        }
        {
            var inscope input=Work(items <- [4],delay=5u)
            var inscope job <- task_spawn(runtime,task_jobque(queue,input,@@worker))
            task_tick(runtime,20000)
            verify(task_cancel(runtime,job) && task_status(job)==TaskStatus.Cancelled)
            // Worker keeps its native channel/context after the waiter detaches.
        }
        {
            var inscope input=Work(items <- [5],delay=5u)
            var inscope job <- task_spawn(runtime,task_jobque(queue,input,@@worker),TaskTimeout(after_ms=2))
            task_tick(runtime,20001);task_tick(runtime,20003)
            verify(task_timed_out(runtime,job) && task_status(job)==TaskStatus.Cancelled)
        }
        {
            var inscope input=Work(items <- [6])
            var inscope never <- task_jobque(queue,input,@@worker)
            task_cancel(never) // Cold cancellation never submits native work.
        }
        for(i in range(10000)) {
            task_jobque_collect(queue)
            if(task_jobque_channels()==0) {break}
            sleep(1u)
        }
        verify(task_jobque_channels()==0)
    }
    verify(task_jobque_channels()==0)
}
[export]
def main() {
    {
        var inscope queue <- task_job_queue()
        var inscope input=Work(items <- [1])
        var inscope missing_pool <- task_jobque(queue,input,@@worker)
        task_poll(missing_pool)
        verify(missing_pool.status==TaskStatus.Failed && task_jobque_channels()==0)
    }
    checks();let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && task_jobque_channels()==0)
    print("Task jobque lifetime checks OK\n")
}
