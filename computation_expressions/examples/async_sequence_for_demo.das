options gen2
options max_infer_passes=256
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das

def pages(first:int) {
    return <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        for(i in range(2)) {
            task_delay_ms(5) |> bind
            yield <- [first+i*10,first+i*10+1]
        }
    }
}

def totals() {
    return <- deferred(AsyncSequenceBuilder(),10) $(first) {
        // row borrows the owning array until this iteration ends, including bind.
        for(row in pages(first)) {
            task_delay_ms(2) |> bind
            yield row[0]+row[1]
        }
        first++ // Every run has its own working snapshot.
    }
}

def sum_stream(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
    var now:int64=0
    var result=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
            task_tick(scheduler,now)
            now++
        }
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        let item=task_take(scheduler,id)
        if(item is none) {break}
        result+=item as some
    }
    return result
}

[export]
def main() {
    var saved <- totals()
    var inscope first <- run_deferred(saved)
    var inscope second <- run_deferred(saved)
    delete saved
    verify(sum_stream(first)==62 && sum_stream(second)==62)
    print("Async sequence For demo OK\n")
}
