options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var errors=0
def observe(source:auto;marker:iterator<auto(T)>) {
    return <- rx_subscribe(source,@(n:T) {trace+="{n};"},@(message:string) {errors++;trace+="error;"},@(){trace+="done;"})
}
def observe(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- observe(source,source.element)}
def checks() {
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_timer(10,clock)
        var inscope sub <- observe(source)
        verify(rx_advance_to(clock,9)==0 && trace=="")
        rx_advance_to(clock,10)
        verify(trace=="0;done;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_interval(5,clock) |> rx_take(3)
        var inscope sub <- observe(source)
        verify(rx_advance_to(clock,100)==3 && trace=="0;1;2;done;" && rx_pending_count(clock)==0)
    }
    {
        trace=""
        var inscope clock <- rx_scheduler()
        var inscope source <- rx_interval(5,clock) |> rx_take(2)
        var inscope sub <- observe(source)
        rx_tick(clock,100);verify(trace=="0;")
        rx_tick(clock,100);verify(trace=="0;")
        rx_tick(clock,105);verify(trace=="0;1;done;")
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_delay(10,clock)
        var inscope sub <- observe(source)
        rx_subject_next(input,1);rx_advance_to(clock,5);rx_subject_next(input,2);rx_subject_complete(input)
        verify(trace=="" && rx_subscriber_count(input)==0)
        rx_advance_to(clock,10);verify(trace=="1;")
        rx_advance_to(clock,15);verify(trace=="1;2;done;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_debounce(10,clock)
        var inscope sub <- observe(source)
        rx_subject_next(input,1);rx_advance_to(clock,5);rx_subject_next(input,2)
        rx_advance_to(clock,14);verify(trace=="" && rx_pending_count(clock)==1)
        rx_advance_to(clock,15);verify(trace=="2;")
        rx_subject_next(input,3);rx_subject_complete(input)
        verify(trace=="2;3;done;" && rx_pending_count(clock)==0 && rx_is_closed(sub))
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_timeout(10,clock)
        var inscope sub <- observe(source)
        rx_advance_to(clock,9);rx_subject_next(input,1)
        rx_advance_to(clock,18);verify(trace=="1;" && !rx_is_closed(sub))
        rx_advance_to(clock,19);verify(trace=="1;error;" && rx_is_closed(sub) && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0)
    }
    // Error bypasses delay/debounce; timeout is removed on normal completion.
    for(mode in range(3)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        // Select the mode through a generic test helper below.
        if(mode==0) {
            var inscope source <- rx_clone(input) |> rx_delay(10,clock)
            var inscope sub <- observe(source)
            rx_subject_next(input,1);rx_subject_error(input,"failed")
            verify(trace=="error;" && rx_is_closed(sub))
        } elif(mode==1) {
            var inscope source <- rx_clone(input) |> rx_debounce(10,clock)
            var inscope sub <- observe(source)
            rx_subject_next(input,1);rx_subject_error(input,"failed")
            verify(trace=="error;" && rx_is_closed(sub))
        } else {
            var inscope source <- rx_clone(input) |> rx_timeout(10,clock)
            var inscope sub <- observe(source)
            rx_subject_next(input,1);rx_subject_complete(input)
            verify(trace=="1;done;" && rx_is_closed(sub))
        }
        verify(rx_pending_count(clock)==0)
        rx_advance_to(clock,100)
    }
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_range(1,3) |> rx_debounce(0,clock)
        var inscope sub <- observe(source)
        verify(trace=="3;done;" && rx_pending_count(clock)==0)
    }
    // Repeated subscriptions have independent counters and watchdogs.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_timer(0,clock)
        var inscope a <- observe(source);var inscope b <- observe(source)
        rx_unsubscribe(a);rx_advance_by(clock,0)
        verify(trace=="0;done;" && rx_is_closed(b) && rx_pending_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX time operators checks OK\n")
}
