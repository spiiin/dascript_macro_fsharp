options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var lastError=""
var completed=0
var errors=0
var attempts=0
var handlers=0
var inCallback=false
def observe(source:auto) {
    return <- rx_subscribe(source,@(n:int) {verify(!inCallback);trace+="{n};"},@(message:string) {verify(!inCallback);errors++;lastError=message;trace+="error;"},@(){verify(!inCallback);completed++;trace+="done;"})
}
def failing() {
    return <- rx_defer(@(){attempts++;return <- rx_throw("failure {attempts}",type<int>)})
}
def checks() {
    {
        trace=""
        var inscope source <- rx_just(42)
        for(i in range(2)) {var inscope sub <- observe(source);verify(rx_is_closed(sub))}
        verify(trace=="42;done;42;done;")
        var inscope emptySource <- rx_empty(type<int>)
        var inscope sub <- observe(emptySource)
        verify(trace=="42;done;42;done;done;" && rx_is_closed(sub))
    }
    {
        trace="";handlers=0
        var inscope source <- rx_range(1,2) |> rx_concat(rx_throw("failed",type<int>)) |> rx_catch_error(@(message:string) {
            verify(message=="failed");handlers++;return <- rx_just(9)
        })
        var inscope sub <- observe(source)
        verify(trace=="1;2;9;done;" && handlers==1 && rx_is_closed(sub))
    }
    {
        handlers=0;trace=""
        var inscope source <- rx_empty(type<int>) |> rx_catch_error(@(s:string) {handlers++;return <- rx_just(9)})
        var inscope sub <- observe(source)
        verify(trace=="done;" && handlers==0)
    }
    for(mode in range(3)) {
        trace="";handlers=0
        let oldErrors=errors
        var inscope source <- rx_throw("first",type<int>) |> rx_catch_error(@ capture(copy(mode)) (message:string) {
            handlers++
            if(mode==1) {panic("handler failed")}
            var replacement <- rx_throw("fallback failed",type<int>)
            if(mode==2) {delete replacement}
            return <- replacement
        })
        var inscope sub <- observe(source)
        verify(errors==oldErrors+1 && handlers==1 && trace=="error;" && rx_is_closed(sub))
        if(mode==0) {verify(lastError=="fallback failed")}
    }
    {
        var inscope primary <- rx_subject(type<int>)
        var inscope backup <- rx_subject(type<int>)
        var old <- rx_clone(primary);var next <- rx_clone(backup)
        var inscope source <- rx_clone(primary) |> rx_catch_error(@ capture(<-old,<-next) (message:string) {
            verify(rx_subscriber_count(old)==0);return <- rx_clone(next)
        } finally {delete old;delete next})
        trace=""
        var inscope sub <- observe(source)
        rx_subject_next(primary,1);rx_subject_error(primary,"failed")
        verify(rx_subscriber_count(backup)==1 && !rx_is_closed(sub))
        rx_subject_next(backup,2);rx_subject_complete(backup)
        verify(trace=="1;2;done;" && rx_is_closed(sub))
    }
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_defer(@(){
            attempts++
            let attempt=attempts
            return <- rx_range(1,2) |> rx_map(@ capture(copy(attempt)) (n:int) {if(attempt<3 && n==2) {panic("failed")};return n})
        }) |> rx_retry(2,10,clock)
        for(i in range(2)) {
            trace="";attempts=0
            var inscope sub <- observe(source)
            verify(attempts==1 && trace=="1;" && rx_pending_count(clock)==1)
            rx_advance_by(clock,9);verify(attempts==1)
            rx_advance_by(clock,1);verify(attempts==2 && trace=="1;1;")
            rx_advance_by(clock,10)
            verify(attempts==3 && trace=="1;1;1;2;done;" && rx_is_closed(sub))
            verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        }
    }
    for(retries in range(4)) {
        attempts=0;trace=""
        let old=errors
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- failing() |> rx_retry(retries,0,clock)
        var inscope sub <- observe(source)
        verify(attempts==1)
        if(retries>0) {verify(!rx_is_closed(sub) && errors==old)}
        rx_advance_by(clock,0)
        verify(attempts==retries+1 && errors==old+1 && lastError=="failure {retries+1}" && rx_is_closed(sub))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Large zero-delay retry is iterative, budget-limited, and cancellable.
    {
        attempts=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- failing() |> rx_retry(5000,0,clock)
        var inscope sub <- observe(source)
        verify(rx_advance_by(clock,0,64)==64 && attempts==65 && !rx_is_closed(sub))
        rx_unsubscribe(sub);rx_advance_by(clock,0)
        verify(attempts==65 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    for(mode in range(3)) {
        attempts=0;trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- failing() |> rx_retry(3,10,clock)
        var sub <- observe(source)
        if(mode==0) {rx_unsubscribe(sub)}
        elif(mode==1) {delete sub}
        else {rx_scheduler_close(clock);verify(trace=="error;" && lastError=="rx scheduler closed")}
        if(mode!=1) {verify(rx_is_closed(sub));delete sub}
        rx_advance_by(clock,100)
        verify(attempts==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // retry resubscribes to the same descriptor; a terminal Subject stays terminal.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_retry(2,1,clock)
        var inscope sub <- observe(source)
        rx_subject_next(input,1);rx_subject_error(input,"hot failed")
        rx_advance_by(clock,2)
        verify(trace=="1;error;" && rx_is_closed(sub) && rx_subscriber_count(input)==0)
    }
    {
        trace="";attempts=0;handlers=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- failing() |> rx_retry(2,5,clock) |> rx_catch_error(@(s:string) {
            verify(s=="failure 3");handlers++;return <- rx_just(99)
        })
        var inscope sub <- observe(source)
        rx_advance_by(clock,10)
        verify(attempts==3 && handlers==1 && trace=="99;done;" && rx_is_closed(sub))
    }
    // Consumer exceptions are not source on_error and must not trigger recovery.
    {
        attempts=0;handlers=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_defer(@(){attempts++;return <- rx_just(1)}) |> rx_retry(3,0,clock) |> rx_catch_error(@(s:string) {handlers++;return <- rx_just(9)})
        var caught=false
        try {var inscope sub <- rx_subscribe(source,@(n:int) {panic("consumer failed")},@(s:string) {panic("unexpected error")},@(){})} recover {caught=true}
        verify(caught && attempts==1 && handlers==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    {
        var inscope source <- rx_just((number=7,text="seven")) |> rx_map(@(v:tuple<number:int;text:string>) {return v.text}) |> rx_catch_error(@(s:string) {return <- rx_just("fallback")}) |> rx_map(@(s:string) {return length(s)})
        trace=""
        var inscope sub <- observe(source)
        verify(trace=="5;done;")
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX recovery checks OK\n")
}
