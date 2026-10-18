options gen2
options max_infer_passes=1024
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var allocated=0
var released=0
var opened=0
var closed=0
var active=0
var snapshots=0
var factories:array<int>
struct Packet {data:array<int>
    def finalize {if(!empty(data)) {released++;delete data}}
}
struct Resource {data:array<int>}
struct Snapshot {data:array<int>;wait:int
    def finalize {if(!empty(data)) {snapshots++;delete data}}
}
def packet(value:int) {allocated++;var result:Packet;result.data <- [value];return <- result}
def acquire() {opened++;active++;var result:Resource;result.data <- [1];return <- result}
def ce_dispose(var resource:Resource) {closed++;active--;delete resource}
def balanced() {verify(allocated==released && opened==closed && active==0)}

def feed(id:int;wait:int=1;count:int=3;fail:bool=false) {
    factories |> push(id)
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var resource & = acquire() |> use_resource
        for(i in range(count)) {
            var value <- packet(id*10+i)
            task_delay_ms(wait) |> bind
            if(fail) {panic("zip source {id} failed")}
            yield <- value
            verify(empty(value.data))
        }
    }
}
def cancelled_feed(id:int) {
    var stream <- feed(id)
    async_sequence_close(stream)
    return <- stream
}
def saved_feed(id:int;wait:int=1) {
    var inscope initial:Snapshot
    initial.data <- [id*10,id*10+1]
    initial.wait=wait
    return <- deferred(AsyncSequenceBuilder(type<Packet>),initial) $(snapshot) {
        try_finally($ {
            var resource & = acquire() |> use_resource
            for(i in range(length(snapshot.data))) {
                task_delay_ms(snapshot.wait) |> bind
                var value <- packet(snapshot.data[i])
                snapshot.data[i]++
                yield <- value
            }
        },$ {verify(length(snapshot.data)==2)})
    }
}
def replay(id:int;wait:int) {var inscope saved <- saved_feed(id,wait);return <- run_deferred(saved)}
def selected(id:int;wait:int;count:int;fail:bool;isDeferred:bool) {
    if(isDeferred) {return <- replay(id,wait)}
    return <- feed(id,wait,count,fail)
}

def zipped(waitA:int=3;waitB:int=5;hold:int=1;stop:int=0;skip:int=0;fail:int=0;bodyFail:bool=false;isDeferred:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        for(a,b in selected(1,waitA,3,fail==1,isDeferred),selected(2,waitB,2,fail==2,isDeferred)) {
            var iteration & = acquire() |> use_resource
            task_delay_ms(hold) |> bind
            if(bodyFail) {panic("zip body failed")}
            if(a.data[0]==stop) {break}
            if(a.data[0]==skip) {continue}
            a.data[0]+=b.data[0]
            yield <- a
            verify(empty(a.data) && length(b.data)==1)
        }
        verify(active==0)
        var tail <- packet(100)
        yield <- tail
    }
}
def consume(limit:int=10;waitA:int=3;waitB:int=5;hold:int=1;stop:int=0;skip:int=0;fail:int=0;bodyFail:bool=false;consumerFail:bool=false;isDeferred:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = zipped(waitA,waitB,hold,stop,skip,fail,bodyFail,isDeferred) |> use_resource
        var result=0
        var count=0
        while(true) {
            var value & = async_sequence_next(stream) |> bind
            if(value is none) {break}
            if(consumerFail) {panic("zip consumer failed")}
            result+=(value as some).data[0]
            count++
            if(count==limit) {break}
        }
        return result
    }
}
def drive(var stream:auto) {
    var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
    var now:int64=0
    var sum=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {task_tick(scheduler,now);now++}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        var inscope value <- task_take(scheduler,id)
        if(value is none) {break}
        sum+=(value as some).data[0]
    }
    return sum
}
def numbers(first:int;count:int=2) {
    return <- computation(AsyncSequenceBuilder()) {for(i in range(count)) {yield first+i}}
}
def saved_outer(wait:int=1) {
    var inscope initial:Snapshot
    initial.data <- [1,2]
    initial.wait=wait
    return <- deferred(AsyncSequenceBuilder(type<Packet>),initial) $(snapshot) {
        try_finally($ {
            for(a,b in replay(snapshot.data[0],snapshot.wait),replay(snapshot.data[1],snapshot.wait)) {
                task_delay_ms(1) |> bind
                a.data[0]+=b.data[0]
                yield <- a
            }
        },$ {verify(length(snapshot.data)==2)})
    }
}
def throwing_factory() {
    panic("second factory failed")
    return <- feed(2)
}

def checks() {
    // Concurrent clocks: the first pair waits max(3,5)+2, not 3+5+2.
    {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(1,3,5,2))
        verify(task_tick(scheduler,0)==1 && active==2)
        verify(task_tick(scheduler,3)==1)
        verify(task_tick(scheduler,5)==1 && active==3)
        verify(task_tick(scheduler,7)==0 && task_value(scheduler,id)==30)
        balanced()
    }
    for(mode in range(3)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,1,1,1,mode==1 ? 10 : 0,mode==2 ? 11 : 0))
        for(now in range(20)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        verify(task_value(scheduler,id)==(mode==1 ? 100 : (mode==2 ? 130 : 162)))
        balanced()
    }
    // Stop promptly even when the other next cannot yet complete. Both orders.
    for(mode in range(2)) {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b in feed(1,mode==0 ? 0 : 100,mode==0 ? 0 : 3),feed(2,mode==1 ? 0 : 100,mode==1 ? 0 : 3)) {
                panic("shortest input body")
            }
        }
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==0 && task_value(scheduler,id) is none)
        balanced()
    }
    // Shortest input in a nested merge must not wait for either earlier source.
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b,c in feed(1,100),feed(2,100),feed(3,0,0)) {yield <- a}
        }
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==0 && task_value(scheduler,id) is none)
        balanced()
    }
    // Cancellation/timeout with no values, a complete row in the body, or
    // a partial row cached on either side while the sibling is still waiting.
    for(mode in range(8)) {
        let phase=mode%4
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,(phase==0 || phase==3) ? 100 : 0,(phase==0 || phase==2) ? 100 : 0,100),token),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1)
        if(mode<4) {cancellation_cancel(token)}
        verify(task_tick(scheduler,mode<4 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(task_timed_out(scheduler,id)==(mode>=4))
        balanced()
    }
    // One source fails while its sibling is still waiting; body and consumer.
    for(mode in range(4)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,mode==1 ? 100 : 1,mode==0 ? 100 : 1,1,0,0,mode<2 ? mode+1 : 0,mode==2,mode==3))
        for(now in range(5)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,id),mode<2 ? "zip source {mode+1} failed" : (mode==2 ? "zip body failed" : "zip consumer failed")))
        balanced()
    }
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b in selected(1,100,3,false,false),selected(2,100,3,false,false)) {
                yield <- a
            }
        }
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        async_sequence_close(stream)
        balanced()
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
    }
    {
        var stream <- zipped(0,0,0)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==0)
        {
            var inscope item <- task_take(scheduler,id)
            delete stream
            verify((item as some).data[0]==30 && active==0)
            verify(allocated==released+1)
        }
        balanced()
    }
    // Every source expression is evaluated once, left-to-right. Four inputs,
    // mixed element types, and shadowing inside the body are supported.
    {
        delete factories
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b,c,d in feed(1,0,1),feed(2,0,1),feed(3,0,1),numbers(4,1)) {
                task_delay_ms(0) |> bind
                a.data[0]+=b.data[0]+c.data[0]+d
                {let a=99;verify(a==99)}
                yield <- a
            }
        }
        verify(drive(stream)==64)
        verify(length(factories)==3 && factories[0]==1 && factories[1]==2 && factories[2]==3)
        balanced()
    }
    // A later factory exception releases an earlier acquired deferred snapshot.
    {
        let before=snapshots
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b in replay(1,0),throwing_factory()) {yield <- a}
        }
        var inscope request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Failed && starts_with(task_error(request),"second factory failed"))
        verify(snapshots==before+3)
        balanced()
    }
    // Named sources registered for disposal remain safe after consuming zip.
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            var left & = feed(1,0,1) |> use_resource
            var right & = feed(2,0,1) |> use_resource
            for(a,b in left,right) {a.data[0]+=b.data[0];yield <- a;break}
        }
        verify(drive(stream)==30)
        balanced()
    }
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            var source & = feed(1,0,1) |> use_resource
            for(a,b in source,source) {yield <- a}
        }
        var inscope request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Failed)
        verify(starts_with(task_error(request),"async sequence: owner has been moved or deleted"))
        balanced()
    }
    // Nested zip, copyable payloads and shadowed iterator names/source expressions.
    {
        var inscope stream <- computation(AsyncSequenceBuilder()) {
            for(a,b in numbers(1),numbers(10)) {
                for(a,b in numbers(a,1),numbers(b,1)) {yield a+b;break}
            }
        }
        for(index in range(2)) {
            let expected=11+index*2
            var inscope request <- async_sequence_next(stream)
            verify(task_poll(request)==TaskStatus.Succeeded && (task_value(request) as some)==expected)
        }
        var inscope done <- async_sequence_next(stream)
        verify(task_poll(done)==TaskStatus.Succeeded && task_value(done) is none)
    }
    for(mode in range(2)) {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            for(a,b in mode==0 ? cancelled_feed(1) : feed(1,100),mode==1 ? cancelled_feed(2) : feed(2,100)) {yield <- a}
            panic("cancelled zip continuation")
        }
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        balanced()
    }
    // Deferred sources: success, source break, cancellation and timeout.
    for(mode in range(4)) {
        let before=snapshots
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,mode<2 ? 0 : 100,mode<2 ? 0 : 100,0,mode==1 ? 10 : 0,0,0,false,false,true),token),TaskTimeout(after_ms=5))
        if(mode<2) {
            verify(task_tick(scheduler,0)==0 && task_value(scheduler,id)==(mode==0 ? 162 : 100))
        } else {
            verify(task_tick(scheduler,0)==1 && snapshots==before+4)
            if(mode==2) {cancellation_cancel(token)}
            verify(task_tick(scheduler,mode==2 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        }
        verify(snapshots==before+6)
        balanced()
    }
    {
        let before=snapshots
        var saved <- saved_outer()
        var inscope first <- run_deferred(saved)
        var inscope second <- run_deferred(saved)
        delete saved
        verify(drive(first)==62 && drive(second)==62)
        verify(snapshots==before+16)
        balanced()
    }
    {
        let before=snapshots
        var saved <- saved_outer(100)
        var stream <- run_deferred(saved)
        delete saved
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1 && snapshots==before+6)
        delete stream
        verify(snapshots==before+9)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        balanced()
    }
    {
        let before=length(factories)
        var inscope stream <- zipped()
        var pending <- async_sequence_next(stream)
        delete pending
        verify(length(factories)==before)
        balanced()
    }
    delete factories
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence zip checks OK\n")
}
