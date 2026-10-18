options gen2
options max_infer_passes=256
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var allocated=0
var released=0
var opened=0
var closed=0
var snapshots=0
var effects=0

struct Packet {data:array<int>
    def finalize {if(!empty(data)) {released++;delete data}}
}
struct Snapshot {data:array<int>;wait:int
    def finalize {if(!empty(data)) {snapshots++;delete data}}
}
struct Resource {data:array<int>}
def acquire() {opened++;var result:Resource;result.data <- [1];return <- result}
def ce_dispose(var resource:Resource) {closed++;delete resource}
def packet(value:int) {allocated++;var result:Packet;result.data <- [value];return <- result}

def child(wait:int=1;fail:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var resource & = acquire() |> use_resource
        for(i in range(3)) {
            var value <- packet(i+1)
            task_delay_ms(wait) |> bind
            if(fail) {panic("delegated producer failed")}
            yield <- value
            effects++
        }
    }
}

def outer(wait:int=1;fail:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var resource & = acquire() |> use_resource
        child(wait,fail) |> yield_from
        var value <- packet(4)
        yield <- value
    }
}

def selected_stream(wait:int;fail:bool;isDeferred:bool) {
    if(isDeferred) {
        return <- computation(AsyncSequenceBuilder(type<Packet>)) {
            replay_child(wait) |> yield_from
        }
    }
    return <- outer(wait,fail)
}

def consume(limit:int=10;wait:int=1;hold:int=1;fail:bool=false;consumerFail:bool=false;isDeferred:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = selected_stream(wait,fail,isDeferred) |> use_resource
        var sum=0
        var count=0
        while(true) {
            var item & = async_sequence_next(stream) |> bind
            if(item is none) {break}
            task_delay_ms(hold) |> bind
            if(consumerFail) {panic("delegated consumer failed")}
            sum+=(item as some).data[0]
            count++
            if(count==limit) {break}
        }
        return sum
    }
}

def balanced() {verify(allocated==released && opened==closed)}

def factory(wait:int=0) {
    var inscope seed:Snapshot
    seed.data <- [7]
    seed.wait=wait
    return <- deferred(AsyncSequenceBuilder(type<Packet>),seed) $(snapshot) {
        try_finally($ {
            child(snapshot.wait) |> yield_from
            var value <- packet(snapshot.data[0])
            snapshot.data[0]++
            yield <- value
        },$ {
            verify(length(snapshot.data)==1 && (snapshot.data[0]==7 || snapshot.data[0]==8))
        })
    }
}

def drain(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
    var now:int64=0
    var sum=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
            task_tick(scheduler,now)
            now++
        }
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        var inscope item <- task_take(scheduler,id)
        if(item is none) {break}
        sum+=(item as some).data[0]
    }
    return sum
}

def replay_child(wait:int=0) {
    var inscope saved <- factory(wait)
    return <- run_deferred(saved)
}

def cancelled_child() {
    var stream <- child()
    async_sequence_close(stream)
    return <- stream
}

def copy_replay() {
    var inscope saved <- deferred(AsyncSequenceBuilder(),4) $(value) {yield value}
    return <- run_deferred(saved)
}

def checks() {
    for(mode in range(2)) {
        let before=effects
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(mode==0 ? 10 : 1))
        for(now in range(20)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        verify(task_value(scheduler,id)==(mode==0 ? 10 : 1))
        verify(effects-before==(mode==0 ? 3 : 0))
        balanced()
    }
    for(mode in range(2)) {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,mode==0 ? 100 : 0,100),token))
        verify(task_tick(scheduler,0)==1)
        cancellation_cancel(token)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        balanced()
    }
    for(mode in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,mode==0 ? 100 : 0,100),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1)
        verify(task_tick(scheduler,5)==0 && task_timed_out(scheduler,id))
        balanced()
    }
    for(mode in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,1,1,mode==0,mode==1))
        for(now in range(5)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,id),mode==0 ? "delegated producer failed" : "delegated consumer failed"))
        balanced()
    }
    // Close the outer owner while a next lease is still pending.
    {
        var stream <- outer(100)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        delete stream
        balanced()
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
    }
    {
        var inscope stream <- outer()
        var request <- async_sequence_next(stream)
        delete request
        balanced()
    }
    // A taken owning element survives closing both the parent and child.
    {
        var stream <- outer(0)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==0)
        {
            var inscope item <- task_take(scheduler,id)
            delete stream
            verify((item as some).data[0]==1 && opened==closed)
            verify(allocated==released+1)
        }
        balanced()
    }
    // Child cancellation is control flow: no continuation after delegation.
    {
        let before=effects
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            cancelled_child() |> yield_from
            effects++
        }
        var inscope request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Cancelled && effects==before)
        balanced()
    }
    // Each deferred run owns a snapshot, even inside a delegated stream.
    {
        let before=snapshots
        var saved <- factory()
        var inscope first <- run_deferred(saved)
        var inscope second <- run_deferred(saved)
        delete saved
        verify(snapshots==before+2)
        verify(drain(first)==13 && snapshots==before+3)
        verify(drain(second)==13)
        verify(snapshots==before+4) // seed, saved frame, two run frames
        balanced()
    }
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            replay_child() |> yield_from
        }
        verify(drain(stream)==13)
        balanced()
    }
    for(mode in range(3)) {
        let before=snapshots
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(mode==0 ? 1 : 10,mode==0 ? 0 : 100,0,false,false,true),token),TaskTimeout(after_ms=5))
        if(mode==0) {
            verify(task_tick(scheduler,0)==0 && task_value(scheduler,id)==1)
        } else {
            verify(task_tick(scheduler,0)==1)
            verify(snapshots==before+2) // child suspended; working snapshot lives
            if(mode==1) {cancellation_cancel(token)}
            verify(task_tick(scheduler,mode==1 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
            verify(task_timed_out(scheduler,id)==(mode==2))
        }
        verify(snapshots==before+3) // original, saved frame, run frame
        balanced()
    }
    // Copyable elements, empty delegation, recursive delegation, continuation.
    {
        var inscope stream <- computation(AsyncSequenceBuilder()) {
            computation(AsyncSequenceBuilder()) {} |> yield_from
            computation(AsyncSequenceBuilder()) {
                computation(AsyncSequenceBuilder()) {yield 1;yield 2} |> yield_from
            } |> yield_from
            yield 3
            copy_replay() |> yield_from
        }
        for(expected in range(1,5)) {
            var inscope request <- async_sequence_next(stream)
            verify(task_poll(request)==TaskStatus.Succeeded)
            verify((task_value(request) as some)==expected)
        }
        var inscope done <- async_sequence_next(stream)
        verify(task_poll(done)==TaskStatus.Succeeded && task_value(done) is none)
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence yield_from checks OK\n")
}
