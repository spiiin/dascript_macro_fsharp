options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var opened=0
var disposed=0
def checks() {
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_range(1,3) |> rx_observe_on(clock,rx_queue(3))
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@(){trace+="done;"})
        verify(trace=="" && rx_pending_count(clock)==4)
        rx_advance_to(clock,0,1);verify(trace=="1;" && !rx_is_closed(sub))
        rx_advance_to(clock,0);verify(trace=="1;2;3;done;" && rx_is_closed(sub))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    for(policyId in range(3)) {
        let policy=policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest)
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_range(1,4) |> rx_observe_on(clock,rx_queue(2,policy))
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {verify(s=="rx_observe_on: queue overflow");trace+="error;"},@(){trace+="done;"})
        verify(trace=="" && rx_pending_count(clock)<=3)
        rx_advance_to(clock,0)
        verify(trace==(policy==RxOverflowPolicy.error ? "error;" : (policy==RxOverflowPolicy.drop_oldest ? "3;4;done;" : "1;2;done;")))
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Error, including an empty message, follows previously accepted values.
    for(errorId in range(2)) {
        let message=errorId==0 ? "failure" : ""
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_range(1,2) |> rx_concat(rx_throw(message,type<int>)) |> rx_observe_on(clock)
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {trace+="error:{s};"},@(){panic("unexpected complete")})
        verify(trace=="");rx_advance_to(clock,0)
        verify(trace=="1;2;error:{message};" && rx_is_closed(sub))
    }
    // Pending connection can be cancelled without opening the source.
    for(stage in range(3)) {
        let before=opened
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope source <- rx_defer(@ capture(<-view) () {opened++;return <- rx_clone(view)} finally {delete view}) |> rx_subscribe_on(clock)
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {verify(s=="rx scheduler closed")},@(){})
        verify(opened==before && rx_subscriber_count(input)==0)
        if(stage==0) {rx_unsubscribe(sub)}
        elif(stage==1) {delete sub}
        else {rx_scheduler_close(clock)}
        rx_advance_to(clock,0)
        verify(opened==before && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    // Once connected, delivery is synchronous without observe_on; disposal is immediate.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_finally(@(){disposed++}) |> rx_subscribe_on(clock)
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@(){})
        rx_subject_next(input,1);verify(trace=="")
        rx_advance_to(clock,0);verify(rx_subscriber_count(input)==1)
        rx_subject_next(input,2);verify(trace=="2;")
        let before=disposed;rx_unsubscribe(sub)
        verify(disposed==before+1 && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Reentrant producer notifications remain behind the active callback.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_observe_on(clock)
        var view <- rx_clone(input)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            trace+="start{n};"
            if(n==1) {rx_subject_next(view,2);rx_subject_complete(view)}
            trace+="end{n};"
        } finally {delete view},@(s:string) {panic(s)},@(){trace+="done;"})
        rx_subject_next(input,1);rx_advance_to(clock,0)
        verify(trace=="start1;end1;start2;end2;done;" && rx_is_closed(sub))
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX scheduling tests OK\n")
}
