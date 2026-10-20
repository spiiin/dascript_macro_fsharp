options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_parallel.das
require ../lib/task_jobque.das
require daslib/fio

var queue:typedecl(task_job_queue())

// Runs in a cloned jobque context; input and output cross through SDK channels.
def decode_asset(asset:int) {var checksum=0;for(i in range(asset*1000)) {checksum+=i%17};return checksum}
def load(asset:int) {
    return <- computation(TaskResultBuilder(type<int>)) {
        let checksum=task_jobque(queue,asset,@@decode_asset) |> bind
        return checksum
    }
}
[export]
def main() {
    with_job_que() {
        queue <- task_job_queue()
        var inscope runtime <- task_runtime()
        var assets <- [1,2,3,4]
        // At most two cold factories run at once; results retain input order.
        var inscope loading <- task_spawn(runtime,task_result_when_all_limited(assets,2,
            @(asset:int) {return <- load(asset)}),TaskTimeout(after_ms=5000))
        var inscope caption <- task_spawn(runtime,task_retry(@(attempt:int) {
            return <- task_after_polls(0,attempt<3 ? result_error("offline",type<string>) : result_ok("ready"))
        },3,10l))
        var candidates:array<typedecl(task_after_polls(0,result_ok(1)))>
        candidates |> emplace(task_after_polls(0,result_error("mirror unavailable",type<int>)))
        candidates |> emplace(task_after_polls(2,result_ok(7)))
        var inscope mirror <- task_spawn(runtime,task_first_success(candidates))
        for(now_ms in range(5001)) {
            let active=task_tick(runtime,now_ms)
            task_jobque_collect(queue) // Non-blocking reclamation of completed/detached jobs.
            if(active==0) {break}
            sleep(1u) // Demo event loop only; a real application advances once per frame.
        }
        verify(task_status(loading)==TaskStatus.Succeeded)
        var inscope values <- task_take(loading)
        verify(values is ok && length(values as ok)==4)
        verify(task_value(caption) as ok=="ready" && task_value(mirror) as ok==7)
        // Independent operations can share a semaphore too.
        var inscope semaphore <- task_semaphore(1)
        var inscope protected <- task_with_semaphore(semaphore,@(){return <- task_after_polls(0,42)})
        task_poll(protected);verify(protected.value==42)
        delete queue
    }
    verify(task_jobque_channels()==0)
    print("Task parallel jobque demo OK\n")
}
