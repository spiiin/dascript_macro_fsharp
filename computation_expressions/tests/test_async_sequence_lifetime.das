options gen2
// Stress nested producer/consumer/resource macros beyond the default 50 passes.
options max_infer_passes=128
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das
require daslib/strings_boost
require daslib/rtti

var opened=0
var closed=0
var finalized=0
var produced=0
struct StreamResource {data:array<int>}
def acquire() {var resource:StreamResource;resource.data <- [10,20,30];opened++;return <- resource}
def ce_dispose(var resource:StreamResource) {closed++;delete resource}
def producer(wait:int=1; fail:bool=false) {
    return <- computation(AsyncSequenceBuilder()) {
        var resource & = acquire() |> use_resource
        try_finally($ {
            for(i in range(length(resource.data))) {
                task_delay_ms(wait) |> bind
                if(fail) {panic("producer failed")}
                produced++
                yield resource.data[i]
            }
        },$ {finalized++})
    }
}
def consumer(limit:int=10; wait:int=1; failProducer:bool=false; failConsumer:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = producer(wait,failProducer) |> use_resource
        var sum=0
        var count=0
        while(true) {
            let item=async_sequence_next(stream) |> bind
            if(item is none) {break}
            if(failConsumer) {panic("consumer failed")}
            sum+=item as some
            count++
            if(count==limit) {break}
        }
        return sum
    }
}
def check_closed() {verify(opened==closed && finalized==closed)}
def checks() {
    let initialProduced=produced
    let initialOpened=opened
    // Cold, pull-based: construction and next construction have no effects.
    {
        var inscope stream <- producer()
        var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
        var first <- async_sequence_next(stream)
        verify(opened==initialOpened && produced==initialProduced)
        let one=task_spawn(scheduler,first)
        verify(task_tick(scheduler,0)==1 && opened==initialOpened+1)
        verify(task_tick(scheduler,1)==0 && task_value(scheduler,one) as some==10)
        verify(opened==closed+1 && produced==initialProduced+1)
        // Consumer may do other work without advancing the producer.
        verify(task_tick(scheduler,10)==0 && produced==initialProduced+1)
        let two=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,11)==1 && task_tick(scheduler,12)==0)
        verify(task_value(scheduler,two) as some==20 && opened==closed+1)
        let three=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,13)==1 && task_tick(scheduler,14)==0)
        verify(task_value(scheduler,three) as some==30)
        let done=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,15)==0 && task_value(scheduler,done) is none)
        check_closed()
        let again=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,16)==0 && task_value(scheduler,again) is none)
    }
    // Full consumption and early break both close the producer exactly once.
    for(mode in range(2)) {
        let limit=mode==0 ? 10 : 1
        let before=produced
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consumer(limit))
        for(now in range(10)) {task_tick(scheduler,now)}
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        verify(task_value(scheduler,id)==(limit==1 ? 10 : 60))
        verify(produced-before==(limit==1 ? 1 : 3))
        check_closed()
    }
    // Cancelling the parent propagates through next -> producer -> awaited delay.
    {
        let before=produced
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<int>)
        let a=task_spawn(scheduler,task_with_cancellation(consumer(10,100),token))
        let b=task_spawn(scheduler,task_with_cancellation(consumer(10,100),token))
        verify(task_tick(scheduler,0)==2)
        cancellation_cancel(token)
        verify(task_tick(scheduler,1)==0)
        verify(task_status(scheduler,a)==TaskStatus.Cancelled && task_status(scheduler,b)==TaskStatus.Cancelled)
        verify(produced==before)
        check_closed()
    }
    {
        let before=produced
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consumer(10,100),TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1 && task_tick(scheduler,5)==0)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && task_timed_out(scheduler,id))
        verify(produced==before)
        check_closed()
    }
    // Panic on either side of next also closes nested resources.
    for(mode in range(2)) {
        let failProducer=mode==0
        var inscope scheduler <- task_scheduler(type<int>)
        let id=task_spawn(scheduler,consumer(10,1,failProducer,!failProducer))
        verify(task_tick(scheduler,0)==1 && task_tick(scheduler,1)==0)
        verify(task_status(scheduler,id)==TaskStatus.Failed)
        verify(starts_with(task_error(scheduler,id),failProducer ? "producer failed" : "consumer failed"))
        check_closed()
    }
    // The next Task owns stable state even after deleting the primary owner.
    {
        var stream <- producer(100)
        var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        delete stream
        check_closed()
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
    }
    // Direct next cancellation and explicit close share the same terminal path.
    for(mode in range(2)) {
        let explicitClose=mode==0
        var inscope stream <- producer(100)
        var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
        let id=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,0)==1)
        if(explicitClose) {async_sequence_close(stream)}
        else {verify(task_cancel(scheduler,id))}
        verify(task_tick(scheduler,1)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        let afterClose=task_spawn(scheduler,async_sequence_next(stream))
        verify(task_tick(scheduler,2)==0 && task_status(scheduler,afterClose)==TaskStatus.Cancelled)
        check_closed()
    }
    // Abandon an unpolled next, with and without a started producer.
    for(mode in range(2)) {
        let started=mode==0
        var inscope stream <- producer()
        if(started) {
            var inscope scheduler <- task_scheduler(type<variant<some:int;none:bool>>)
            let id=task_spawn(scheduler,async_sequence_next(stream))
            verify(task_tick(scheduler,0)==1 && task_tick(scheduler,1)==0)
        }
        var pending <- async_sequence_next(stream)
        delete pending
        check_closed()
    }
    // The single-consumer guard rejects overlapping next calls without leaks.
    {
        var inscope stream <- producer()
        var inscope first <- async_sequence_next(stream)
        var caught=false
        try {var inscope second <- async_sequence_next(stream)} recover {
            caught=starts_with(this_context().last_exception,"async sequence: only one next")
        }
        verify(caught)
        task_cancel(first)
        check_closed()
    }
    check_closed()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Async sequence lifetime checks OK\n")
}
