options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_task.das
require ../../computation_expressions/lib/task_scheduler.das
require ../../computation_expressions/lib/computation_macro.das
require daslib/rtti
var trace=""
var closed=0
var polled=0
var factories=0
var effects=0
var afterWait=0
var actions:typedecl(rx_subject(type<int>))
def wait_action() {
    return <- computation(TaskResultBuilder(type<int>)) {
        let value=rx_first_task(actions) |> bind
        afterWait++
        return value+1
    }
}
def work(count:int;fail:bool=false) {
    var remaining=count
    return <- task_from_poll(@ capture(copy(remaining),copy(fail)) () {
        polled++
        if(fail) {panic("operation failed")}
        if(remaining>0) {remaining--;return task_pending(type<int>)}
        return task_ready(77)
    },@(){closed++})
}
def observe(source:auto) {
    return <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(message:string) {trace+="error;"},@(){trace+="done;"})
}
def checks() {
    // String deduction must not leave const inside the Result variant in AOT.
    for(mode in range(4)) {
        var inscope source <- rx_subject(type<string>)
        var inscope task <- rx_first_task(source)
        verify(task_poll(task)==TaskStatus.Waiting && rx_subscriber_count(source)==1)
        if(mode==0) {
            task_cancel(task)
            verify(task_status(task)==TaskStatus.Cancelled && rx_subscriber_count(source)==0)
            continue
        }
        if(mode==1) {rx_subject_next(source,"confirmed")}
        elif(mode==2) {rx_subject_complete(source)}
        else {rx_subject_error(source,"string failure")}
        verify(task_poll(task)==TaskStatus.Succeeded && rx_subscriber_count(source)==0)
        let result=task_value(task)
        if(mode==1) {verify(result is ok && result as ok=="confirmed")}
        elif(mode==2) {verify(result is err && result as err=="rx: source completed without value")}
        else {verify(result is err && result as err=="string failure")}
    }
    {
        effects=0
        var inscope source <- rx_range(1,3) |> rx_map(@(n:int) {effects++;return n})
        var inscope task <- rx_first_task(source)
        verify(effects==0 && task_poll(task)==TaskStatus.Succeeded && effects==1)
        let value=task_value(task)
        verify(value is ok && value as ok==1)
    }
    for(mode in range(4)) {
        var inscope source <- rx_subject(type<int>)
        var inscope task <- rx_first_task(source)
        if(mode==0) {task_cancel(task);verify(rx_subscriber_count(source)==0);continue}
        verify(task_poll(task)==TaskStatus.Waiting && rx_subscriber_count(source)==1)
        if(mode==1) {
            rx_subject_next(source,42)
            verify(rx_subscriber_count(source)==0 && task_status(task)==TaskStatus.Waiting)
        } elif(mode==2) {rx_subject_complete(source)}
        else {rx_subject_error(source,"input failed")}
        verify(task_poll(task)==TaskStatus.Succeeded && rx_subscriber_count(source)==0)
        let result=task_value(task)
        if(mode==1) {verify(result is ok && result as ok==42)}
        else {verify(result is err)}
    }
    {
        var inscope source <- rx_subject(type<int>)
        var inscope token <- cancellation_token()
        var inscope task <- task_with_cancellation(rx_first_task(source),token)
        verify(task_poll(task)==TaskStatus.Waiting && rx_subscriber_count(source)==1)
        cancellation_cancel(token)
        verify(task_poll(task)==TaskStatus.Cancelled && rx_subscriber_count(source)==0)
    }
    {
        var inscope source <- rx_subject(type<int>)
        var inscope scheduler <- task_scheduler(type<$Result<int;string>>)
        let id=task_spawn(scheduler,rx_first_task(source),TaskTimeout(after_ms=3))
        task_tick(scheduler,0);verify(rx_subscriber_count(source)==1)
        task_tick(scheduler,3)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && task_timed_out(scheduler,id) && rx_subscriber_count(source)==0)
    }
    {
        actions <- rx_subject(type<int>)
        var inscope task <- wait_action()
        verify(task_poll(task)==TaskStatus.Waiting)
        rx_subject_next(actions,42)
        verify(task_poll(task)==TaskStatus.Succeeded)
        let result=task_value(task)
        verify(result is ok && result as ok==43)
        delete actions
    }
    {
        actions <- rx_subject(type<int>)
        let before=afterWait
        var inscope task <- wait_action()
        task_poll(task);rx_subject_error(actions,"failed")
        verify(task_poll(task)==TaskStatus.Succeeded && afterWait==before)
        let result=task_value(task)
        verify(result is err && result as err=="failed")
        delete actions
    }
    {
        trace=""
        let before=closed
        let start=factories
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task(@(){factories++;return <- work(2)},clock)
        for(i in range(2)) {
            var inscope sub <- observe(source)
            rx_advance_by(clock,2)
            verify(rx_is_closed(sub))
        }
        verify(trace=="77;done;77;done;" && closed==before+2 && factories==start+2 && rx_pending_count(clock)==0)
    }
    for(mode in range(5)) {
        trace=""
        let before=closed
        let beforePoll=polled
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task(@ capture(copy(mode)) () {return <- work(100,mode==1)},clock) |> rx_timeout(mode==4 ? 0 : 3,clock)
        var inscope sub <- observe(source)
        if(mode==0) {rx_advance_to(clock,0);rx_unsubscribe(sub)}
        elif(mode==2) {rx_scheduler_close(clock)}
        else {rx_advance_to(clock,10)}
        verify(rx_is_closed(sub) && closed==before+1 && rx_pending_count(clock)==0)
        verify(trace==(mode==0 ? "" : "error;"))
        if(mode==3) {verify(polled==beforePoll+3)}
        if(mode==4) {verify(polled==beforePoll)}
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope token <- cancellation_token()
        var lease <- cancellation_clone(token)
        var inscope source <- rx_from_task(@ capture(<-lease) () {return <- task_with_cancellation(work(100),lease)} finally {delete lease},clock)
        var inscope sub <- observe(source)
        rx_advance_to(clock,0);cancellation_cancel(token);rx_advance_to(clock,1)
        verify(trace=="error;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    // Raw Task<Result> emits the variant; the result adapter unwraps it.
    for(fail in range(2)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task_result(@ capture(copy(fail)) () {
            return <- task_after_polls(1,fail==0 ? result_ok(7) : result_error("domain failed",type<int>))
        },clock,2)
        var inscope sub <- observe(source)
        rx_advance_to(clock,2)
        verify(trace==(fail==0 ? "7;done;" : "error;") && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task(@(){return <- task_after_polls(0,result_ok(9))},clock)
        var inscope sub <- rx_subscribe(source,@(v:$Result<int;string>) {verify(v is ok && v as ok==9);trace+="raw;"},@(s:string) {panic(s)},@(){trace+="done;"})
        rx_advance_to(clock,0)
        verify(trace=="raw;done;" && rx_is_closed(sub))
    }
    // task_delay_ms is driven by the Rx scheduler's clock, including replay.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task(@(){return <- computation(TaskBuilder(type<int>)) {
            task_delay_ms(5) |> bind
            return 11
        }},clock)
        var inscope sub <- observe(source)
        rx_advance_to(clock,4);verify(trace=="")
        rx_advance_to(clock,5);verify(trace=="11;done;" && rx_is_closed(sub))
    }
    // A completed producer has removed its shutdown handler before on_next:
    // closing the scheduler inside the consumer cannot reenter it with error.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_from_task(@(){return <- task_after_polls(0,42)},clock)
        var view <- rx_scheduler_clone(clock)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(rx_close_listener_count(view)==0 && n==42)
            trace+="next;";rx_scheduler_close(view);verify(trace=="next;")
        } finally {delete view},@(s:string) {panic("unexpected nested error")},@(){trace+="done;"})
        rx_advance_to(clock,0)
        verify(trace=="next;done;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX Task adapters checks OK\n")
}
