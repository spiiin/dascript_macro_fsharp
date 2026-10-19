options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var mapped=0
var starts=0
var saved:array<int>
def record(n:int) {trace+="{n};"}
def record(batch:array<int>) {trace+="[";for(n in batch) {trace+="{n},"};trace+="];"}
def watch_typed(source:auto;marker:iterator<auto(WatchValue)>) {
    return <- rx_subscribe(source,@(v:WatchValue) {record(v)},@(s:string) {trace+="error:{s};"},@() {trace+="done;"})
}
def watch(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- watch_typed(source,source.element)}
def boundary_checks() {
    for(producerFirst in range(2)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var action <- @ capture(<-view) () {rx_subject_next(view,7)} finally {delete view}
        var handle:RxScheduledId
        if(producerFirst==1) {handle=rx_schedule(clock,10,action)}
        var source <- rx_clone(input) |> rx_sample(10,clock)
        var sub <- watch(source);delete source
        if(producerFirst==0) {handle=rx_schedule(clock,10,action)}
        rx_advance_to(clock,10)
        verify(trace==(producerFirst==1 ? "7;" : ""))
        rx_advance_to(clock,20);verify(trace=="7;")
        delete sub
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
def checks() {
    boundary_checks()
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_throttle(10,clock)
        var sub <- watch(source);delete source
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==1)
        rx_subject_next(input,1);rx_subject_next(input,2)
        rx_advance_to(clock,9);rx_subject_next(input,3)
        rx_advance_to(clock,10);rx_subject_next(input,4);rx_subject_next(input,5)
        rx_subject_complete(input)
        verify(trace=="1;4;done;" && rx_is_closed(sub) && rx_close_listener_count(clock)==0)
        delete sub
    }
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_sample(10,clock)
        var sub <- watch(source);delete source
        rx_advance_to(clock,10);verify(trace=="")
        rx_subject_next(input,1);rx_subject_next(input,2)
        rx_advance_to(clock,20);verify(trace=="2;")
        rx_advance_to(clock,30);verify(trace=="2;")
        rx_subject_next(input,3);rx_subject_complete(input)
        verify(trace=="2;3;done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    trace=""
    {
        var source <- rx_range(1,5) |> rx_buffer(2)
        var sub <- watch(source);delete source
        verify(trace=="[1,2,];[3,4,];[5,];done;" && rx_is_closed(sub))
        delete sub
        trace=""
        var emptySource <- rx_empty(type<int>) |> rx_buffer(3)
        var emptySub <- watch(emptySource)
        verify(trace=="done;");delete emptySource;delete emptySub
    }
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_buffer_time(10,clock)
        var sub <- watch(source);delete source
        rx_subject_next(input,1);rx_subject_next(input,2)
        rx_advance_to(clock,10);verify(trace=="[1,2,];")
        rx_advance_to(clock,20);verify(trace=="[1,2,];")
        rx_subject_next(input,3);rx_subject_complete(input)
        verify(trace=="[1,2,];[3,];done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_buffer(2,10,clock)
        var sub <- watch(source);delete source
        rx_subject_next(input,1);rx_advance_to(clock,3);rx_subject_next(input,2)
        verify(trace=="[1,2,];" && rx_pending_count(clock)==1)
        rx_advance_to(clock,8);rx_subject_next(input,3)
        rx_advance_to(clock,10);verify(trace=="[1,2,];")
        rx_advance_to(clock,13);verify(trace=="[1,2,];[3,];")
        rx_subject_complete(input)
        verify(trace=="[1,2,];[3,];done;" && rx_pending_count(clock)==0)
        delete sub
    }
    // Direct batch pipelines preserve borrowed contents; explicit cloning owns
    // a snapshot after the callback, take, subscription and source are gone.
    trace="";mapped=0;delete saved
    {
        var source <- rx_range(1,7) |> rx_tap(@(n:int) {mapped++}) |> rx_buffer(2) |> rx_filter(@(b:array<int>) {return b[0]>1}) |> rx_tap(@(b:array<int>) {saved := b}) |> rx_take(1) |> rx_map(@(b:array<int>) {return b[0]+b[1]})
        var sub <- watch(source);delete source;delete sub
        verify(trace=="7;done;" && mapped==4 && length(saved)==2 && saved[0]==3 && saved[1]==4)
    }
    delete saved
    // Array events are detached before callbacks, so reentrant events cannot
    // modify or invalidate the currently delivered batch.
    trace=""
    {
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var source <- rx_clone(input) |> rx_buffer(2)
        var sub <- rx_subscribe(source,@ capture(<-view) (b:array<int>) {
            record(b)
            if(b[0]==1) {rx_subject_next(view,3);rx_subject_next(view,4);rx_subject_next(view,5);rx_subject_complete(view);verify(b[0]==1 && b[1]==2)}
        } finally {delete view},@(s:string) {panic(s)},@() {trace+="done;"})
        delete source
        rx_subject_next(input,1);rx_subject_next(input,2)
        verify(trace=="[1,2,];[3,4,];[5,];done;" && rx_is_closed(sub))
        delete sub
    }
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var source <- rx_clone(input) |> rx_sample(10,clock)
        var sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            record(n);if(n==2) {rx_subject_next(view,9);rx_subject_complete(view)}
        } finally {delete view},@(s:string) {panic(s)},@() {trace+="done;"})
        delete source
        rx_subject_next(input,2);rx_advance_to(clock,10)
        verify(trace=="2;9;done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    // Repeat and concurrent subscriptions have independent retained values.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_buffer(10,clock)
        for(iteration in range(2)) {
            var a <- watch(source);var b <- watch(source)
            verify(rx_pending_count(clock)==2)
            rx_subject_next(input,7);rx_unsubscribe(a);rx_advance_by(clock,10)
            verify(rx_pending_count(clock)==1 && rx_subscriber_count(input)==1)
            rx_unsubscribe(b);delete a;delete b
            verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        }
        verify(trace=="[7,];[7,];")
        delete source
    }
    // Manual pumping coalesces missed sample intervals, without repeating data.
    trace=""
    {
        var inscope clock <- rx_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_sample(10,clock)
        var sub <- watch(source)
        rx_subject_next(input,1);verify(rx_tick(clock,100)==1 && trace=="1;")
        rx_subject_next(input,2);verify(rx_tick(clock,109)==0);rx_tick(clock,110)
        verify(trace=="1;2;");delete sub;delete source
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX throttle/sample/buffer checks OK\n")
}
