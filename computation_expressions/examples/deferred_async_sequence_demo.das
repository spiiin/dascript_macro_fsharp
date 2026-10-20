options gen2
options max_infer_passes=128
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das

def batches() {
    var inscope initial <- [10,20]
    return <- deferred(AsyncSequenceBuilder(type<array<int>>),initial) $(snapshot) {
        for(i in range(length(snapshot))) {
            task_delay_ms(5) |> bind
            var data <- [snapshot[i],snapshot[i]+1]
            snapshot[i]++ // Each run changes only its own snapshot.
            yield <- data
        }
    }
}
def sum_stream(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<$Option<array<int>>>)
    var sum=0
    var now:int64=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
            task_tick(scheduler,now)
            now++
        }
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        var inscope item <- task_take(scheduler,id)
        if(item is none) {break}
        sum+=(item as some)[0]
    }
    return sum
}
[export]
def main() {
    var saved <- batches()
    var inscope first <- run_deferred(saved)
    var inscope second <- run_deferred(saved)
    delete saved // Both streams retain their independent snapshots.
    let a=sum_stream(first)
    let b=sum_stream(second)
    verify(a==30 && b==30)
    print("Repeated runs: {a}, {b}\n")
    print("Deferred async sequence demo OK\n")
}
