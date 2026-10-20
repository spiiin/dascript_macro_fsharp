options gen2
options max_infer_passes=256
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var snapshotsFreed=0
var cleaned=0
var produced=0
def release_saved(var saved:auto) {delete saved}
struct Snapshot {
    rows:array<array<int>>
    marker:int
    wait:int
    fail:bool
    def finalize {
        if(marker==17) {snapshotsFreed++;marker=0}
        delete rows
    }
}
def initial(wait:int=1;fail:bool=false) {
    var value:Snapshot
    value.rows |> emplace([10,11])
    value.rows |> emplace([20,21])
    value.rows |> emplace([30,31])
    value.marker=17;value.wait=wait;value.fail=fail
    return <- value
}
def saved_copy() {
    var inscope data <- initial()
    return <- deferred(AsyncSequenceBuilder(),data) $(snapshot) {
        try_finally($ {
            for(i in range(length(snapshot.rows))) {
                task_delay_ms(snapshot.wait) |> bind
                snapshot.rows[i][0]++
                produced++
                yield snapshot.rows[i][0]
            }
        },$ {
            verify(snapshot.marker==17 && length(snapshot.rows)==3)
            cleaned++
        })
    }
}
def saved_move(wait:int=1;fail:bool=false) {
    var inscope data <- initial(wait,fail)
    return <- deferred(AsyncSequenceBuilder(type<array<int>>),data) $(snapshot) {
        try_finally($ {
            for(i in range(length(snapshot.rows))) {
                task_delay_ms(snapshot.wait) |> bind
                if(snapshot.fail) {panic("deferred producer failed")}
                snapshot.rows[i] |> push(100+i)
                produced++
                yield <- snapshot.rows[i]
                verify(empty(snapshot.rows[i]))
            }
        },$ {
            // The run frame must outlive all producer finalizers.
            verify(snapshot.marker==17 && length(snapshot.rows)==3)
            cleaned++
        })
    }
}
def move_consumer(limit:int=10;wait:int=1;hold:int=1;failProducer:bool=false;failConsumer:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var saved <- saved_move(wait,failProducer)
        var stream & = run_deferred(saved) |> use_resource
        release_saved(saved)
        var count=0
        var sum=0
        while(true) {
            var item & = async_sequence_next(stream) |> bind
            if(item is none) {break}
            task_delay_ms(hold) |> bind
            if(failConsumer) {panic("deferred consumer failed")}
            verify(length(item as some)==3)
            sum+=(item as some)[0]
            count++
            if(count==limit) {break}
        }
        return sum
    }
}
def copy_consumer(limit:int=10) {
    return <- computation(TaskBuilder(type<int>)) {
        var saved <- saved_copy()
        var stream & = run_deferred(saved) |> use_resource
        release_saved(saved)
        var count=0
        var sum=0
        while(true) {
            let item=async_sequence_next(stream) |> bind
            if(item is none) {break}
            sum+=item as some
            count++
            if(count==limit) {break}
        }
        return sum
    }
}
def repeated_copy() {
    let freed=snapshotsFreed
    var saved <- saved_copy()
    verify(snapshotsFreed==freed+1)
    for(round in range(3)) {
        var inscope stream <- run_deferred(saved)
        var inscope scheduler <- task_scheduler(type<$Option<int>>)
        var sum=0
        var now:int64=0
        while(true) {
            let id=task_spawn(scheduler,async_sequence_next(stream))
            while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {task_tick(scheduler,now);now++}
            verify(task_status(scheduler,id)==TaskStatus.Succeeded)
            let item=task_value(scheduler,id)
            task_forget(scheduler,id)
            if(item is none) {break}
            sum+=item as some
        }
        verify(sum==63 && snapshotsFreed==freed+round+2)
    }
    delete saved
    verify(snapshotsFreed==freed+5)
}
def independent_move() {
    let freed=snapshotsFreed
    let finishes=cleaned
    var data <- initial()
    var saved <- deferred(AsyncSequenceBuilder(type<array<int>>),data) $(snapshot) {
        try_finally($ {
            task_delay_ms(snapshot.wait) |> bind
            yield <- snapshot.rows[0]
        },$ {verify(snapshot.marker==17 && length(snapshot.rows)==3);cleaned++})
    }
    data.rows[0][0]=999
    var first <- run_deferred(saved)
    var second <- saved |> run_deferred
    delete data
    delete saved
    verify(snapshotsFreed==freed+2)
    var inscope scheduler <- task_scheduler(type<$Option<array<int>>>)
    let a=task_spawn(scheduler,async_sequence_next(first))
    let b=task_spawn(scheduler,async_sequence_next(second))
    verify(task_tick(scheduler,0)==2 && snapshotsFreed==freed+2)
    verify(task_tick(scheduler,1)==0 && snapshotsFreed==freed+2)
    var inscope left <- task_take(scheduler,a)
    var inscope right <- task_take(scheduler,b)
    verify((left as some)[0]==10 && (right as some)[0]==10)
    (left as some)[0]=777
    verify((right as some)[0]==10)
    delete first
    verify(snapshotsFreed==freed+3 && cleaned==finishes+1)
    delete second
    verify(snapshotsFreed==freed+4 && cleaned==finishes+2)
    verify((left as some)[1]==11 && (right as some)[1]==11)
}
def consumer_checks() {
    for(mode in range(2)) {
        let freed=snapshotsFreed
        let finishes=cleaned
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,move_consumer(mode==0 ? 10 : 1))
        let b=task_spawn(scheduler,copy_consumer(mode==0 ? 10 : 1))
        for(now in range(12)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,a)==TaskStatus.Succeeded && task_status(scheduler,b)==TaskStatus.Succeeded)
        verify(task_value(scheduler,a)==(mode==0 ? 60 : 10) && task_value(scheduler,b)==(mode==0 ? 63 : 11))
        verify(snapshotsFreed==freed+6 && cleaned==finishes+2)
    }
    // Cancel while producing, and after a move-only element has been delivered.
    for(mode in range(2)) {
        let freed=snapshotsFreed
        let finishes=cleaned
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,task_with_cancellation(move_consumer(10,mode==0 ? 100 : 0,100),token))
        verify(task_tick(scheduler,0)==1 && snapshotsFreed==freed+2)
        cancellation_cancel(token)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,a)==TaskStatus.Cancelled)
        verify(snapshotsFreed==freed+3 && cleaned==finishes+1)
    }
    {
        let freed=snapshotsFreed
        let finishes=cleaned
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,move_consumer(10,100),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1 && task_tick(scheduler,5)==0)
        verify(task_status(scheduler,a)==TaskStatus.Cancelled && task_timed_out(scheduler,a))
        verify(snapshotsFreed==freed+3 && cleaned==finishes+1)
    }
    for(mode in range(2)) {
        let freed=snapshotsFreed
        let finishes=cleaned
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,move_consumer(10,1,1,mode==0,mode==1))
        for(now in range(5)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,a)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,a),mode==0 ? "deferred producer failed" : "deferred consumer failed"))
        verify(snapshotsFreed==freed+3 && cleaned==finishes+1)
    }
}
def unopened_and_pending() {
    for(mode in range(3)) {
        let freed=snapshotsFreed
        let finishes=cleaned
        var saved <- saved_move(100)
        var stream <- run_deferred(saved)
        delete saved
        verify(snapshotsFreed==freed+2)
        if(mode==0) {
            delete stream
            verify(cleaned==finishes)
        } else {
            var inscope scheduler <- task_scheduler(type<$Option<array<int>>>)
            let a=task_spawn(scheduler,async_sequence_next(stream))
            if(mode==2) {verify(task_tick(scheduler,0)==1)}
            delete stream
            verify(snapshotsFreed==freed+3)
            verify(task_tick(scheduler,1)==0 && task_status(scheduler,a)==TaskStatus.Cancelled)
            verify(cleaned==finishes+(mode==2 ? 1 : 0))
        }
        verify(snapshotsFreed==freed+3)
    }
    // No-snapshot spelling and rejection of non-null phantom descriptors.
    {
        var inscope saved <- deferred(AsyncSequenceBuilder(type<array<int>>)) {yield <- [5,6]}
        var inscope stream <- run_deferred(saved)
        var inscope next <- async_sequence_next(stream)
        verify(task_poll(next)==TaskStatus.Succeeded)
        var inscope item <- task_take(next)
        verify((item as some)[0]==5)
    }
    {
        var number=7
        var builder=AsyncSequenceBuilder()
        unsafe {builder.element=addr(number)}
        var caught=false
        try {var inscope invalid <- deferred(builder) {yield 1}} recover {
            caught=starts_with(this_context().last_exception,"deferred: move-only builder type marker must be null")
        }
        verify(caught)
    }
}
def checks() {repeated_copy();independent_move();consumer_checks();unopened_and_pending()}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Deferred async sequence checks OK\n")
}
