options gen2
options max_infer_passes=512
module async_sequence_workloads public
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das

def async_bench_mix(seed,work:int) : int {
    var value=uint(seed)
    for(i in range(work)) {value=(value*1664525u+1013904223u) ^ (value >> 13)}
    return int(value & 0x7fffffffu)
}

def async_bench_feed_ce(count,seed,work,pending:int) {
    return <- computation(AsyncSequenceBuilder()) {
        for(i in range(count)) {
            let value=task_after_polls(pending,i+seed) |> bind
            yield async_bench_mix(value,work)
        }
    }
}

// Native generators use the same stream/next ownership API and primitive Tasks.
// They specialize the successful workloads, without the general CE lowering.
def async_bench_feed_manual(count,seed,work,pending:int) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:int;none:bool>>> {
        for(i in range(count)) {
            var inscope request <- task_after_polls(pending,i+seed)
            while(task_poll(request)==TaskStatus.Waiting) {yield task_pending(type<variant<some:int;none:bool>>)}
            verify(request.status==TaskStatus.Succeeded)
            yield task_ready(some(async_bench_mix(task_value(request),work)))
        }
        return false
    }
    return <- ce_sequence_run(AsyncSequenceBuilder(),events)
}

def private async_bench_for_ce(count,seed,work,pending:int) {
    return <- computation(AsyncSequenceBuilder()) {
        for(value in async_bench_feed_ce(count,seed,0,pending)) {
            yield async_bench_mix(value,work)
        }
    }
}
def private async_bench_for_manual(count,seed,work,pending:int) {
    var source <- async_bench_feed_manual(count,seed,0,pending)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:int;none:bool>>> capture(<-source) {
        while(true) {
            var inscope request <- async_sequence_next(source)
            while(task_poll(request)==TaskStatus.Waiting) {yield task_pending(type<variant<some:int;none:bool>>)}
            verify(request.status==TaskStatus.Succeeded)
            let item=task_take(request)
            if(item is none) {break}
            yield task_ready(some(async_bench_mix(item as some,work)))
        }
        return false
    } finally {ce_sequence_finalize($ {ce_dispose(source)})}
    return <- ce_sequence_run(AsyncSequenceBuilder(),events)
}

def private async_bench_zip_ce(count,seed,work,pending:int) {
    return <- computation(AsyncSequenceBuilder()) {
        for(a,b in async_bench_feed_ce(count,seed,0,pending),async_bench_feed_ce(count,seed+17,0,pending*2)) {
            yield async_bench_mix(a ^ b,work)
        }
    }
}
def private async_bench_zip_manual(count,seed,work,pending:int) {
    var left <- async_bench_feed_manual(count,seed,0,pending)
    var right <- async_bench_feed_manual(count,seed+17,0,pending*2)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:int;none:bool>>> capture(<-left,<-right) {
        while(true) {
            var inscope first <- async_sequence_next(left)
            var inscope second <- async_sequence_next(right)
            while(true) {
                task_poll(first)
                verify(first.status==TaskStatus.Succeeded || first.status==TaskStatus.Waiting)
                if(first.status==TaskStatus.Succeeded && first.value is none) {return false}
                task_poll(second)
                verify(second.status==TaskStatus.Succeeded || second.status==TaskStatus.Waiting)
                if(second.status==TaskStatus.Succeeded && second.value is none) {return false}
                if(first.status==TaskStatus.Succeeded && second.status==TaskStatus.Succeeded) {
                    yield task_ready(some(async_bench_mix((first.value as some) ^ (second.value as some),work)))
                    break
                }
                yield task_pending(type<variant<some:int;none:bool>>)
            }
        }
        return false
    } finally {ce_sequence_finalize($ {ce_dispose(left);ce_dispose(right)})}
    return <- ce_sequence_run(AsyncSequenceBuilder(),events)
}

def private async_bench_group_ce(count,seed,work,pending:int) {
    return <- computation(AsyncSequenceBuilder()) {
        for(i in range(count)) {
            let pair=task_after_polls(pending,i+seed) |> and_bind(task_after_polls(pending*2,i+seed+17)) |> bind
            yield async_bench_mix(pair.first ^ pair.second,work)
        }
    }
}
def private async_bench_group_manual(count,seed,work,pending:int) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:int;none:bool>>> {
        for(i in range(count)) {
            var inscope request <- task_when_all(task_after_polls(pending,i+seed),task_after_polls(pending*2,i+seed+17))
            while(task_poll(request)==TaskStatus.Waiting) {yield task_pending(type<variant<some:int;none:bool>>)}
            verify(request.status==TaskStatus.Succeeded)
            let pair=task_take(request)
            yield task_ready(some(async_bench_mix(pair.first ^ pair.second,work)))
        }
        return false
    }
    return <- ce_sequence_run(AsyncSequenceBuilder(),events)
}

def private async_bench_move_ce(count,seed,work,pending:int) {
    return <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        for(i in range(count)) {
            let value=task_after_polls(pending,i+seed) |> bind
            yield <- [async_bench_mix(value,work),i]
        }
    }
}
def private async_bench_move_manual(count,seed,work,pending:int) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:array<int>;none:bool>>> {
        for(i in range(count)) {
            var inscope request <- task_after_polls(pending,i+seed)
            while(task_poll(request)==TaskStatus.Waiting) {yield <- task_pending(type<variant<some:array<int>;none:bool>>)}
            verify(request.status==TaskStatus.Succeeded)
            var inscope value <- [async_bench_mix(task_value(request),work),i]
            yield <- ce_await_yield_move(AsyncSequenceBuilder(type<array<int>>),value)
        }
        return false
    }
    return <- ce_sequence_run(AsyncSequenceBuilder(type<array<int>>),events)
}

def private async_bench_drain(var source:auto) : int64 {
    var checksum=0l
    while(true) {
        var inscope request <- async_sequence_next(source)
        while(task_poll(request)==TaskStatus.Waiting) {}
        verify(request.status==TaskStatus.Succeeded)
        var inscope item <- task_take(request)
        if(item is none) {break}
        static_if(typeinfo can_copy(item as some)) {checksum+=int64(item as some)}
        else {checksum+=int64((item as some)[0])}
    }
    return checksum
}

def async_bench_run(name:string;manual:bool;count,seed,work,pending:int) : int64 {
    if(name=="next") {
        if(manual) {var inscope source <- async_bench_feed_manual(count,seed,work,pending);return async_bench_drain(source)}
        var inscope source <- async_bench_feed_ce(count,seed,work,pending);return async_bench_drain(source)
    } elif(name=="for") {
        if(manual) {var inscope source <- async_bench_for_manual(count,seed,work,pending);return async_bench_drain(source)}
        var inscope source <- async_bench_for_ce(count,seed,work,pending);return async_bench_drain(source)
    } elif(name=="zip") {
        if(manual) {var inscope source <- async_bench_zip_manual(count,seed,work,pending);return async_bench_drain(source)}
        var inscope source <- async_bench_zip_ce(count,seed,work,pending);return async_bench_drain(source)
    } elif(name=="and_bind") {
        if(manual) {var inscope source <- async_bench_group_manual(count,seed,work,pending);return async_bench_drain(source)}
        var inscope source <- async_bench_group_ce(count,seed,work,pending);return async_bench_drain(source)
    } elif(name=="move") {
        if(manual) {var inscope source <- async_bench_move_manual(count,seed,work,pending);return async_bench_drain(source)}
        var inscope source <- async_bench_move_ce(count,seed,work,pending);return async_bench_drain(source)
    }
    panic("unknown async benchmark: {name}")
    return 0l
}
