options gen2
options max_infer_passes=512
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var opened=fixed_array(0,0)
var closed=fixed_array(0,0)
var polls=fixed_array(0,0)
var continued=0
var recovered=0
var trace=""
var allocated=0
var released=0
struct PollState {remaining:int;data:array<int>}
def finalize(var state:PollState) {delete state.data}
struct Packet {data:array<int>
    def finalize {if(!empty(data)) {released++;delete data}}
}
def packet(value:int) {allocated++;var result:Packet;result.data <- [value];return <- result}

def child(id:int;waits:int;value:int=1;fail:bool=false;badClose:bool=false) {
    trace+="{id}:create;"
    opened[id]++
    var state=new PollState(remaining=waits,data <- [value])
    return <- task_from_poll(@() {
        polls[id]++
        trace+="{id}:poll;"
        if(fail) {panic("child {id} failed")}
        if(state.remaining>0) {state.remaining--;return task_pending(type<int>)}
        return task_ready(state.data[0])
    },@() {
        trace+="{id}:close;"
        closed[id]++
        unsafe {delete state}
        if(badClose) {panic("close {id} failed")}
    })
}
def factory_failure() {panic("and_bind factory failed");return <- task_after_polls(0,1)}
def cancelled_child() {var value <- child(0,100);task_cancel(value);return <- value}
def reset() {
    verify(opened[0]==closed[0] && opened[1]==closed[1] && allocated==released)
    for(n in opened) {n=0};for(n in closed) {n=0};for(n in polls) {n=0}
    continued=0;recovered=0;trace=""
}
def stream(waitA:int=1;waitB:int=2;fail:int=0;badClose:bool=false) {
    return <- computation(AsyncSequenceBuilder()) {
        let pair=child(0,waitA,10,fail==1,badClose) |> and_bind(child(1,waitB,20,fail==2)) |> bind
        continued++
        yield pair.first+pair.second
        continued++
    }
}
def consume(limit:int=10) {
    return <- computation(TaskBuilder(type<int>)) {
        var source & = stream() |> use_resource
        var sum=0
        var count=0
        while(true) {
            let item=async_sequence_next(source) |> bind
            if(item is none) {break}
            sum+=item as some
            count++
            if(count==limit) {break}
        }
        return sum
    }
}
def owning_task(value:int;wait:int) {
    return <- computation(TaskBuilder(type<Packet>)) {
        var item <- packet(value)
        task_delay_ms(wait) |> bind
        return <- item
    }
}
def owning_stream(waitA:int=3;waitB:int=5;hold:int=2;failBody:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var pair & = owning_task(10,waitA) |> and_bind(owning_task(20,waitB)) |> bind
        task_delay_ms(hold) |> bind
        if(failBody) {panic("owning group body failed")}
        continued++
        yield <- pair.first
        verify(empty(pair.first.data))
        yield <- pair.second
        verify(empty(pair.second.data))
    }
}
def saved() {
    return <- deferred(AsyncSequenceBuilder(type<Packet>),10) $(first) {
        var pair & = owning_task(first,1) |> and_bind(owning_task(first+10,2)) |> bind
        yield <- pair.first
        yield <- pair.second
        first++
    }
}
def drain(var source:auto) {
    var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
    var now:int64=0
    var sum=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(source))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {task_tick(scheduler,now);now++}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        var inscope item <- task_take(scheduler,id)
        if(item is none) {break}
        sum+=(item as some).data[0]
    }
    return sum
}

def checks() {
    reset()
    {
        var inscope source <- stream()
        var inscope request <- async_sequence_next(source)
        verify(trace=="")
        verify(task_poll(request)==TaskStatus.Waiting && continued==0)
        verify(trace=="0:create;1:create;0:poll;1:poll;")
        verify(task_poll(request)==TaskStatus.Waiting && polls[0]==2 && polls[1]==2)
        verify(task_poll(request)==TaskStatus.Succeeded && (task_value(request) as some)==30)
        verify(continued==1 && polls[0]==2 && polls[1]==3 && closed[0]==1 && closed[1]==1)
        let before=trace
        verify(task_poll(request)==TaskStatus.Succeeded && trace==before)
        var inscope end <- async_sequence_next(source)
        verify(task_poll(end)==TaskStatus.Succeeded && task_value(end) is none && continued==2)
    }
    reset()
    // Chained and nested groups, heterogeneous payloads, Unit and Result-as-data.
    {
        var inscope source <- computation(AsyncSequenceBuilder()) {
            let a=task_after_polls(0,1) |> and_bind(task_after_polls(0,2)) |> and_bind(task_after_polls(0,3)) |> bind
            let b=task_after_polls(0,4) |> and_bind(task_after_polls(0,"ab") |> and_bind(task_after_polls(0,6))) |> bind
            task_after_polls(0,CeUnit()) |> and_bind(task_after_polls(0,CeUnit())) |> bind
            let data=task_after_polls(0,result_error("data",type<int>)) |> and_bind(task_after_polls(0,9)) |> bind
            verify(data.first is error && data.first as error=="data")
            yield a.first.first+a.first.second+a.second+b.first+length(b.second.first)+b.second.second+data.second
        }
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Succeeded && (task_value(request) as some)==27)
    }
    reset()
    for(mode in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(mode==0 ? 10 : 1))
        for(now in range(4)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded && task_value(scheduler,id)==30)
        verify(continued==(mode==0 ? 2 : 1))
        reset()
    }
    for(mode in range(2)) {
        var inscope source <- stream(mode==0 ? 0 : 100,mode==1 ? 0 : 100,mode+1)
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Failed && continued==0)
        verify(starts_with(task_error(request),"child {mode} failed"))
        verify(closed[0]==1 && closed[1]==1)
        if(mode==0) {verify(polls[1]==0)}
        reset()
    }
    // A cleanup failure does not replace the original poll/factory error.
    {
        var inscope source <- stream(100,0,2,true)
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Failed && starts_with(task_error(request),"child 1 failed"))
    }
    reset()
    {
        var inscope source <- computation(AsyncSequenceBuilder()) {
            let pair=child(0,100,1,false,true) |> and_bind(factory_failure()) |> bind
            continued++;yield pair.first
        }
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Failed && starts_with(task_error(request),"and_bind factory failed"))
        verify(polls[0]==0 && continued==0)
    }
    reset()
    {
        var inscope source <- computation(AsyncSequenceBuilder()) {
            try_with($ {
                let pair=child(0,0,1,true) |> and_bind(child(1,100,2)) |> bind
                continued++;yield pair.first
            },$(message:string) {verify(starts_with(message,"child 0 failed"));recovered++;yield 99})
        }
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Succeeded && (task_value(request) as some)==99 && continued==0 && recovered==1)
    }
    reset()
    {
        var inscope source <- computation(AsyncSequenceBuilder()) {
            try_with($ {
                let pair=cancelled_child() |> and_bind(child(1,100,2)) |> bind
                continued++;yield pair.first
            },$(message:string) {recovered++;yield 99})
        }
        var inscope request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Cancelled && continued==0 && recovered==0 && polls[1]==0)
    }
    reset()
    // Direct cancel, deletion, and group token close every pending child.
    for(mode in range(3)) {
        var inscope source <- stream(100,100)
        var request <- async_sequence_next(source)
        verify(task_poll(request)==TaskStatus.Waiting)
        if(mode==0) {verify(task_cancel(request))}
        elif(mode==1) {async_sequence_close(source)}
        else {delete request}
        if(mode!=2) {delete request}
        verify(continued==0)
        reset()
    }
    {
        var inscope token <- cancellation_token()
        var inscope source <- stream(100,100)
        var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
        let id=task_spawn(scheduler,task_with_cancellation(async_sequence_next(source),token))
        verify(task_tick(scheduler,0)==1)
        cancellation_cancel(token)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled && continued==0)
        reset()
    }
    // Owning grouped results: complete, early close with the second value held,
    // pending children, partial ready on either side, and body suspension.
    {
        var inscope source <- owning_stream()
        verify(drain(source)==30)
    }
    reset()
    {
        var inscope source <- owning_stream(1,2,1,true)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(source))
        for(now in range(5)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Failed && starts_with(task_error(scheduler,id),"owning group body failed"))
    }
    reset()
    {
        var source <- owning_stream(0,0,0)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(source))
        verify(task_tick(scheduler,0)==0)
        {
            var inscope item <- task_take(scheduler,id)
            delete source
            verify((item as some).data[0]==10 && allocated==released+1)
        }
    }
    reset()
    for(mode in range(8)) {
        let phase=mode%4
        var inscope token <- cancellation_token()
        var inscope source <- owning_stream((phase==0 || phase==3) ? 100 : 0,(phase==0 || phase==2) ? 100 : 0,100)
        var inscope scheduler <- task_scheduler(type<variant<some:Packet;none:bool>>)
        let id=task_spawn(scheduler,task_with_cancellation(async_sequence_next(source),token),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1 && allocated==released+2)
        if(mode<4) {cancellation_cancel(token)}
        verify(task_tick(scheduler,mode<4 ? 1 : 5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(task_timed_out(scheduler,id)==(mode>=4) && allocated==released)
        reset()
    }
    {
        var saved <- saved()
        var inscope first <- run_deferred(saved)
        var inscope second <- run_deferred(saved)
        delete saved
        verify(drain(first)==30 && drain(second)==30)
    }
    reset()
    {
        var inscope source <- stream(100,100)
        var request <- async_sequence_next(source)
        delete request
        verify(opened[0]==0 && opened[1]==0 && continued==0)
    }
    reset()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence and_bind checks OK\n")
}
