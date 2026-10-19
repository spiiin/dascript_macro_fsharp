options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
require ../../computation_expressions/lib/task_scheduler.das
require daslib/rtti
var trace=""
var starts=0
var produced=0
var errors=0
var completed=0
var input:typedecl(rx_subject(type<int>))
def consume(mode:int) {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = rx_clone(input) |> rx_to_async_sequence(rx_queue(2)) |> use_resource
        var total=0
        while(true) {
            let item=async_sequence_next(stream) |> bind
            if(item is none) {break}
            let n=item as some
            total+=n
            if(mode==1) {panic("consumer failed")}
            if(mode==0 && total>=3) {break}
        }
        return total
    }
}
def readings(fail:bool=false) {
    return <- computation(AsyncSequenceBuilder()) {
        for(n in range(1,4)) {
            task_delay_ms(2) |> bind
            if(fail && n==2) {panic("producer failed")}
            produced++
            yield n*10
        }
    }
}
def checks() {
    for(policyId in range(3)) {
        let policy=policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest)
        trace=""
        var stream <- rx_range(1,6) |> rx_to_async_sequence(rx_queue(2,policy))
        var request <- async_sequence_next(stream)
        let status=task_poll(request)
        if(policyId==0) {verify(status==TaskStatus.Failed && !empty(task_error(request)));delete request}
        else {
            verify(status==TaskStatus.Succeeded)
            var item <- task_take(request);verify(item is some);trace+="{item as some};"
            while(true) {
                var next <- async_sequence_next(stream)
                verify(task_poll(next)==TaskStatus.Succeeded)
                var value <- task_take(next)
                if(value is none) {break}
                trace+="{value as some};"
            }
            verify(trace==(policyId==1 ? "5;6;" : "1;2;"))
        }
        delete stream
    }
    // Construction, including an unopened next, is cold.
    starts=0
    {
        var source <- rx_defer(@() {starts++;return <- rx_range(1,2)})
        var stream <- source |> rx_to_async_sequence(2)
        var request <- async_sequence_next(stream)
        verify(starts==0)
        delete request;delete stream
        verify(starts==0)
    }
    for(mode in range(5)) {
        input <- rx_subject(type<int>)
        var job <- consume(mode)
        verify(rx_subscriber_count(input)==0 && task_poll(job)==TaskStatus.Waiting && rx_subscriber_count(input)==1)
        if(mode==3) {task_cancel(job);verify(task_status(job)==TaskStatus.Cancelled)}
        elif(mode==4) {
            rx_subject_next(input,1);rx_subject_error(input,"source failed")
            verify(rx_subscriber_count(input)==0 && task_poll(job)==TaskStatus.Failed)
        } else {
            rx_subject_next(input,1);rx_subject_next(input,2)
            if(mode==2) {rx_subject_complete(input)}
            verify(task_poll(job)==(mode==1 ? TaskStatus.Failed : TaskStatus.Succeeded))
            if(mode!=1) {verify(task_value(job)==3)}
        }
        verify(rx_subscriber_count(input)==0)
        delete job;delete input
    }
    // Cancellation tokens and scheduler timeouts propagate through next.
    for(mode in range(2)) {
        input <- rx_subject(type<int>)
        var inscope scheduler <- task_scheduler(type<int>)
        var inscope token <- cancellation_token()
        var job <- task_with_cancellation(consume(0),token)
        let id=task_spawn(scheduler,job,TaskTimeout(after_ms=5))
        task_tick(scheduler,0);verify(rx_subscriber_count(input)==1)
        if(mode==0) {cancellation_cancel(token)}
        task_tick(scheduler,5)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && rx_subscriber_count(input)==0)
        delete input
    }
    // Each Rx subscription creates an independent stream; one next is polled
    // per clock turn and task_delay_ms observes the Rx clock.
    starts=0;trace="";produced=0;completed=0
    {
        var inscope clock <- rx_virtual_scheduler()
        var source <- @() {starts++;return <- readings()} |> rx_from_async_sequence(clock)
        verify(starts==0)
        var a <- rx_subscribe(source,@(n:int) {trace+="A{n};"},@(s:string) {panic(s)},@() {completed++})
        var b <- rx_subscribe(source,@(n:int) {trace+="B{n};"},@(s:string) {panic(s)},@() {completed++})
        delete source
        verify(starts==2 && produced==0 && rx_pending_count(clock)==2)
        rx_advance_to(clock,2);verify(trace=="A10;B10;")
        rx_unsubscribe(a)
        rx_advance_to(clock,20)
        verify(trace=="A10;B10;B20;B30;" && completed==1 && produced==4)
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete a;delete b
    }
    for(mode in range(3)) {
        trace="";errors=0;completed=0
        var inscope clock <- rx_virtual_scheduler()
        var source <- @ capture(copy(mode)) () {return <- readings(mode==1)} |> rx_from_async_sequence(clock) |> rx_take(mode==2 ? 1 : 10)
        var sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {errors++},@() {completed++})
        delete source
        rx_advance_to(clock,20)
        verify(trace==(mode==0 ? "10;20;30;" : "10;"))
        verify(errors==(mode==1 ? 1 : 0) && completed==(mode==1 ? 0 : 1))
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    starts=0;errors=0
    {
        var inscope clock <- rx_virtual_scheduler()
        rx_scheduler_close(clock)
        var source <- @() {starts++;return <- readings()} |> rx_from_async_sequence(clock)
        var sub <- rx_subscribe(source,@(n:int) {panic("unexpected")},@(s:string) {verify(s=="rx scheduler closed");errors++},@() {})
        verify(starts==0 && errors==1 && rx_is_closed(sub));delete source;delete sub
    }
    // Round-trip: synchronous source -> bounded pull -> scheduled Rx delivery.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var source <- @() {return <- rx_range(1,4) |> rx_to_async_sequence(4)} |> rx_from_async_sequence(clock)
        var sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
        delete source;rx_advance_to(clock,10)
        verify(trace=="1;2;3;4;done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX AsyncSequence adapters checks OK\n")
}
