options gen2
options max_infer_passes=128
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost

var allocated=0
var released=0
var opened=0
var closed=0
var advanced=0
struct Packet {data:array<int>
    def finalize {
        if(!empty(data)) {released++;delete data}
    }
}
def packet(value:int) {var result:Packet;result.data <- [value,value+1];allocated++;return <- result}
struct Feed {data:array<int>}
def acquire() {var result:Feed;result.data <- [1,2,3];opened++;return <- result}
def ce_dispose(var feed:Feed) {closed++;delete feed}
def packets(wait:int=1; fail:bool=false) {
    return <- computation(AsyncSequenceBuilder(type<Packet>)) {
        var feed & = acquire() |> use_resource
        for(i in range(length(feed.data))) {
            var value <- packet(feed.data[i])
            task_delay_ms(wait) |> bind
            if(fail) {panic("packet producer failed")}
            yield <- value
            verify(empty(value.data))
            advanced++
        }
    }
}
def consume(limit:int=10; wait:int=1; hold:int=1; failProducer:bool=false; failConsumer:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = packets(wait,failProducer) |> use_resource
        var sum=0
        var count=0
        while(true) {
            var item & = async_sequence_next(stream) |> bind
            if(item is none) {break}
            // Keep the borrowed owner alive across an additional suspension.
            task_delay_ms(hold) |> bind
            verify(length((item as some).data)==2)
            if(failConsumer) {panic("packet consumer failed")}
            sum+=(item as some).data[0]
            count++
            if(count==limit) {break}
        }
        return sum
    }
}
def check_released() {verify(allocated==released && opened==closed)}
def checks() {
    for(mode in range(2)) {
        let before=allocated
        let resumed=advanced
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(mode==0 ? 10 : 1))
        for(now in range(12)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        verify(task_value(scheduler,id)==(mode==0 ? 6 : 1))
        verify(allocated-before==(mode==0 ? 3 : 1))
        verify(advanced-resumed==(mode==0 ? 3 : 0))
        check_released()
    }
    // Cancellation before yield and while the consumer owns a delivered item.
    for(mode in range(2)) {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,task_with_cancellation(consume(10,mode==0 ? 100 : 0,100),token))
        verify(task_tick(scheduler,0)==1 && allocated==released+1)
        cancellation_cancel(token)
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        check_released()
    }
    for(mode in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,mode==0 ? 100 : 0,100),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1 && allocated==released+1)
        verify(task_tick(scheduler,5)==0 && task_timed_out(scheduler,id))
        verify(task_status(scheduler,id)==TaskStatus.Cancelled)
        check_released()
    }
    for(mode in range(2)) {
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consume(10,1,1,mode==0,mode==1))
        for(now in range(5)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,id),mode==0 ? "packet producer failed" : "packet consumer failed"))
        check_released()
    }
    // A value taken from next survives closing the stream. Clone is independent.
    {
        var stream <- packets()
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1 && task_tick(scheduler,1)==0)
        {
            var inscope copied <- task_value(scheduler,id)
            (copied as some).data[0]=99
            var inscope taken <- task_take(scheduler,id)
            verify((taken as some).data[0]==1 && (copied as some).data[0]==99)
            delete stream
            verify((taken as some).data[1]==2 && opened==closed)
            // task_value's deep clone is another independent owning Packet.
            allocated++
        }
        check_released()
    }
    // Delete the stream with an active next holding an as-yet unyielded Packet.
    {
        var stream <- packets(100)
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        delete stream
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        check_released()
    }
    // Unstarted Task and stream, and an unconsumed completed next cache.
    {
        var inscope stream <- packets()
        var pending <- async_sequence_next(stream)
        delete pending
        check_released()
    }
    {
        var inscope stream <- packets(0)
        var ready <- async_sequence_next(stream)
        var inscope scheduler <- task_scheduler(type<$Option<Packet>>)
        let id=task_spawn(scheduler,ready)
        verify(task_tick(scheduler,0)==0 && allocated==released+1)
        task_forget(scheduler,id)
        async_sequence_close(stream)
        check_released()
    }
    // Owning array binds inside a producer can be consumed by yield <- too.
    {
        var inscope stream <- computation(AsyncSequenceBuilder(type<array<int>>)) {
            var value & = task_after_polls_move(1,[7,8]) |> bind
            yield <- value
            verify(empty(value))
        }
        var inscope next <- async_sequence_next(stream)
        verify(task_poll(next)==TaskStatus.Waiting && task_poll(next)==TaskStatus.Succeeded)
        var inscope value <- task_take(next)
        verify((value as some)[0]==7 && length(value as some)==2)
        var inscope done <- async_sequence_next(stream)
        verify(task_poll(done)==TaskStatus.Succeeded)
        var inscope end <- task_take(done)
        verify(end is none)
    }
    // A Task result borrowed by the fused await adapter remains owned while
    // the continuation suspends. Close it at each stage, or move it to output.
    for(mode in range(5)) {
        var inscope stream <- computation(AsyncSequenceBuilder(type<Packet>)) {
            var value & = task_after_polls_move(1,packet(42)) |> bind
            task_after_polls(1,0) |> bind
            verify(value.data[0]==42 && value.data[1]==43)
            if(mode==3) {panic("borrowed task body failed")}
            yield <- value
            verify(empty(value.data))
        }
        var inscope request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Waiting && allocated==released+1)
        if(mode==0) {verify(task_cancel(request))}
        else {
            verify(task_poll(request)==TaskStatus.Waiting && allocated==released+1)
            if(mode==1) {async_sequence_close(stream);verify(task_poll(request)==TaskStatus.Cancelled)}
            elif(mode==2) {verify(task_cancel(request))}
            elif(mode==3) {verify(task_poll(request)==TaskStatus.Failed)}
            else {
                verify(task_poll(request)==TaskStatus.Succeeded)
                {
                    var inscope item <- task_take(request)
                    async_sequence_close(stream)
                    verify((item as some).data[0]==42 && allocated==released+1)
                }
            }
        }
        check_released()
    }
    check_released()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence move checks OK\n")
}
