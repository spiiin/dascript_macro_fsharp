options gen2
options max_infer_passes=256
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das

def page(first:int) {
    return <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        task_delay_ms(5) |> bind
        var row <- [first,first+1]
        yield <- row
    }
}

def pages() {
    return <- deferred(AsyncSequenceBuilder(type<array<int>>),10) $(first) {
        page(first) |> yield_from
        page(first+10) |> yield_from
        var last <- [first+20]
        yield <- last
    }
}

def total(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<variant<some:array<int>;none:bool>>)
    var now:int64=0
    var result=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
            task_tick(scheduler,now)
            now++
        }
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        var inscope item <- task_take(scheduler,id)
        if(item is none) {break}
        result+=(item as some)[0]
    }
    return result
}

[export]
def main() {
    var saved <- pages()
    var inscope first <- run_deferred(saved)
    var inscope second <- run_deferred(saved)
    delete saved
    verify(total(first)==60 && total(second)==60)
    print("Async sequence yield_from demo OK\n")
}
