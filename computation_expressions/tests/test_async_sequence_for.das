options gen2
options max_infer_passes=512
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var allocated=0
var released=0
var opened=0
var closed=0
var activeChildren=0
var snapshots=0
var advanced=0
var started=0
struct Packet {data:array<int>
    def finalize {if(!empty(data)) {released++;delete data}}
}
struct Resource {data:array<int>;child:bool}
struct Snapshot {data:array<int>;wait:int
    def finalize {if(!empty(data)) {snapshots++;delete data}}
}
def acquire(child:bool) {
    opened++
    if(child) {activeChildren++}
    var result:Resource
    result.data <- [1]
    result.child=child
    return <- result
}
def ce_dispose(var resource:Resource) {
    if(resource.child) {activeChildren--} else {verify(activeChildren==0)}
    closed++
    delete resource
}
def packet(value:int) {allocated++;var result:Packet;result.data <- [value];return <- result}
def balanced() {verify(allocated==released && opened==closed && activeChildren==0)}

def child(wait:int=1;fail:bool=false) {
    started++
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var resource & = acquire(true) |> use_resource
        for(i in range(3)) {
            var value <- packet(i+1)
            task_delay_ms(wait) |> bind
            if(fail) {panic("For producer failed")}
            yield <- value
            verify(empty(value.data))
            advanced++
        }
    }
}

def saved_child(wait:int) {
    var inscope initial:Snapshot
    initial.data <- [1,2,3]
    initial.wait=wait
    return <- deferred(AsyncSequenceBuilder(type<Packet>),initial) $(snapshot) {
        try_finally($ {
            var resource & = acquire(true) |> use_resource
            for(i in range(length(snapshot.data))) {
                task_delay_ms(snapshot.wait) |> bind
                var value <- packet(snapshot.data[i])
                snapshot.data[i]++
                yield <- value
            }
        },$ {verify(length(snapshot.data)==3)})
    }
}
def replay_child(wait:int) {var inscope saved <- saved_child(wait);return <- run_deferred(saved)}
def selected_child(wait:int;fail:bool;isDeferred:bool) {
    if(isDeferred) {return <- replay_child(wait)}
    return <- child(wait,fail)
}

def transformed(wait:int=1;hold:int=1;breakAt:int=0;skip:int=0;fail:bool=false;bodyFail:bool=false;isDeferred:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var parent & = acquire(false) |> use_resource
        for(value in selected_child(wait,fail,isDeferred)) {
            // The borrowed Packet remains alive across another await and scope.
            task_delay_ms(hold) |> bind
            if(bodyFail) {panic("For body failed")}
            if(value.data[0]==breakAt) {break}
            if(value.data[0]==skip) {continue}
            yield <- value
            verify(empty(value.data))
        }
        verify(activeChildren==0) // The source is closed before continuation.
        var tail <- packet(4)
        yield <- tail
    }
}

def consume(limit:int=10;wait:int=1;hold:int=1;breakAt:int=0;skip:int=0;fail:bool=false;bodyFail:bool=false;consumerFail:bool=false;isDeferred:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = transformed(wait,hold,breakAt,skip,fail,bodyFail,isDeferred) |> use_resource
        var sum=0
        var count=0
        while(true) {
            var item & = async_sequence_next(stream) |> bind
            if(item is none) {break}
            if(consumerFail) {panic("For consumer failed")}
            sum+=(item as some).data[0]
            count++
            if(count==limit) {break}
        }
        return sum
    }
}

def drive(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
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

def saved_outer(wait:int=0) {
    var inscope initial:Snapshot
    initial.data <- [9]
    initial.wait=wait
    return <- deferred(AsyncSequenceBuilder(type<Packet>),initial) $(snapshot) {
        try_finally($ {
            for(value in replay_child(snapshot.wait)) {
                task_delay_ms(1) |> bind
                yield <- value
            }
        },$ {verify(length(snapshot.data)==1 && snapshot.data[0]==9)})
    }
}

def cancelled_child() {
    var stream <- child()
    async_sequence_close(stream)
    return <- stream
}

def numbers(first:int;count:int) {
    return <- computation(AsyncSequenceBuilder()) {
        for(i in range(count)) {yield first+i}
    }
}

def scoped_iterations(wait:int) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        for(value in child(0)) {
            var iteration & = acquire(true) |> use_resource
            try_finally($ {
                task_delay_ms(wait) |> bind
                yield <- value
            },$ {verify(length(value.data)<=1)})
        }
    }
}

def checks() {
    // Complete consumption, consumer break, source break, source continue.
    for(mode in range(4)) {
        let before=advanced
        let sourceCount=started
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(mode==1 ? 1 : 10,1,1,mode==2 ? 1 : 0,mode==3 ? 2 : 0))
        for(now in range(20)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        verify(task_value(scheduler,id)==(mode==1 ? 1 : (mode==2 ? 4 : (mode==3 ? 8 : 10))))
        verify(started==sourceCount+1)
        verify(advanced-before==((mode==1 || mode==2) ? 0 : 3))
        balanced()
    }
    // Cancellation/timeout in next and in the body holding a borrowed Packet.
    for(mode in range(4)) {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,mode%2==0 ? 100 : 0,100),token),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1 && activeChildren==1 && allocated==released+1)
        if(mode<2) {cancellation_cancel(token)}
        verify(task_tick(scheduler,mode<2 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(task_timed_out(scheduler,id)==(mode>=2))
        balanced()
    }
    for(mode in range(3)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,1,1,0,0,mode==0,mode==1,mode==2))
        for(now in range(6)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,id),mode==0 ? "For producer failed" : (mode==1 ? "For body failed" : "For consumer failed")))
        balanced()
    }
    // Primary owner closes the loop's source despite an outstanding next lease.
    {
        var stream <- transformed(100)
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        delete stream
        balanced()
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
    }
    // A value moved out of the For body remains owned by the consumer.
    {
        var stream <- transformed(0,0)
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
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
    {
        let before=started
        var inscope stream <- transformed()
        var pending <- async_sequence_next(stream)
        delete pending
        verify(started==before) // Source factory is cold and not evaluated by type probes.
        balanced()
    }
    // Consuming a named resource leaves safe cleanup of the moved-from owner.
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            var source & = child(0) |> use_resource
            for(value in source) {
                yield <- value
                break
            }
        }
        verify(drive(stream)==1)
        balanced()
    }
    // Deferred input: complete, break, cancellation, timeout; snapshot cleanup.
    for(mode in range(4)) {
        let before=snapshots
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,mode<2 ? 0 : 100,0,mode==1 ? 1 : 0,0,false,false,false,true),token),TaskTimeout(after_ms=5))
        if(mode<2) {
            verify(task_tick(scheduler,0)==0 && task_value(scheduler,id)==(mode==0 ? 10 : 4))
        } else {
            verify(task_tick(scheduler,0)==1 && snapshots==before+2)
            if(mode==2) {cancellation_cancel(token)}
            verify(task_tick(scheduler,mode==2 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        }
        verify(snapshots==before+3)
        balanced()
    }
    {
        let before=snapshots
        var saved <- saved_outer()
        var inscope first <- run_deferred(saved)
        var inscope second <- run_deferred(saved)
        delete saved
        verify(drive(first)==6 && drive(second)==6)
        verify(snapshots==before+10)
        balanced()
    }
    {
        let before=snapshots
        var saved <- saved_outer(100)
        var stream <- run_deferred(saved)
        delete saved
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1 && snapshots==before+4)
        delete stream
        verify(snapshots==before+6)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        balanced()
    }
    // Copyable inputs, different output type, nested asynchronous loops,
    // empty source, native loops and lexically scoped break/continue.
    {
        var inscope stream <- scoped_iterations(0)
        verify(drive(stream)==6)
        balanced()
    }
    {
        var inscope stream <- scoped_iterations(100)
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1 && activeChildren==2)
        verify(task_cancel(scheduler,id) && task_status(scheduler,id)==TaskStatus.Cancelled)
        balanced()
    }
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<string>)) {
            for(emptyValue in numbers(0,0)) {panic("empty body")}
            for(i in numbers(1,2)) {
                for(j in numbers(3,2)) {
                    if(j==3) {continue}
                    yield "{i}:{j}"
                    break
                }
            }
        }
        for(i in range(1,3)) {
            var inscope request <- async_sequence_next(stream)
            verify(task_poll(request)==TaskStatus.Succeeded && (task_value(request) as some)=="{i}:4")
        }
        var inscope done <- async_sequence_next(stream)
        verify(task_poll(done)==TaskStatus.Succeeded && task_value(done) is none)
    }
    {
        let before=started
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(value in cancelled_child()) {panic("cancelled body")}
            child() |> yield_from
        }
        var inscope request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Cancelled && started==before+1)
        balanced()
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence For checks OK\n")
}
