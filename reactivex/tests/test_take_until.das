options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var started=0
var signals=0
var cleaned=0
var inCallback=false

def checks() {
    // A string source retains its type across a differently typed notifier
    // and can be transformed again after take_until.
    {
        var inscope source <- rx_just("hello") |> rx_take_until(rx_empty(type<int>)) |> rx_map(@(s:string) {return length(s)})
        var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==5)},@(s:string) {panic(s)},@() {})
        verify(rx_is_closed(sub))
    }
    // Any notifier payload type; only its first next stops the source.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_take_until(rx_clone(stop))
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
        rx_subject_next(input,1);rx_subject_next(input,2)
        rx_subject_next(stop,"stop");rx_subject_next(input,3);rx_subject_next(stop,"again")
        verify(trace=="1;2;done;" && rx_is_closed(sub))
        verify(rx_subscriber_count(input)==0 && rx_subscriber_count(stop)==0)
    }
    // Notifier completion alone is ignored; both source terminals forward.
    for(mode in range(4)) {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_take_until(rx_clone(stop))
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {trace+="error:{s};"},@() {trace+="done;"})
        if(mode<2) {rx_subject_complete(stop);verify(!rx_is_closed(sub) && rx_subscriber_count(input)==1)}
        rx_subject_next(input,1)
        if(mode==0 || mode==2) {rx_subject_complete(input)}
        elif(mode==1) {rx_subject_error(input,"input failed")}
        else {rx_subject_error(stop,"signal failed")}
        verify(trace==((mode==0 || mode==2) ? "1;done;" : (mode==1 ? "1;error:input failed;" : "1;error:signal failed;")))
        verify(rx_is_closed(sub) && rx_subscriber_count(input)==0 && rx_subscriber_count(stop)==0)
    }
    // Connect notifier first; synchronous next/error must prevent source factory.
    for(mode in range(4)) {
        started=0;signals=0;trace=""
        var inscope source <- rx_defer(@() {started++;trace+="input;";return <- rx_range(1,2)}) |> rx_take_until(rx_defer(@ capture(copy(mode)) () {
            signals++;trace+="signal;"
            return <- rx_create(type<string>,@ capture(copy(mode)) (sink:typedecl(rx_sink_marker(type<string>))) {
                if(mode==0) {rx_sink_next(sink,"stop")}
                elif(mode==1) {rx_sink_error(sink,"failed")}
                elif(mode==2) {rx_sink_complete(sink)}
            })
        }))
        for(i in range(2)) {
            trace=""
            var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {trace+="error;"},@() {trace+="done;"})
            verify(rx_is_closed(sub))
            verify(trace==((mode==0) ? "signal;done;" : (mode==1 ? "signal;error;" : "signal;input;1;2;done;")))
        }
        verify(signals==2 && started==(mode<2 ? 0 : 2))
    }
    // Already completed notifier is harmless; take(0) connects neither input.
    {
        started=0;signals=0
        var inscope stop <- rx_subject(type<int>)
        rx_subject_complete(stop)
        var inscope source <- rx_range(1,2) |> rx_take_until(rx_clone(stop))
        trace=""
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="1;2;")
        var inscope zero <- rx_defer(@() {started++;return <- rx_just(1)}) |> rx_take_until(rx_defer(@() {signals++;return <- rx_just("stop")})) |> rx_take(0)
        var inscope none <- rx_subscribe(zero,@(n:int) {panic("unexpected next")},@(s:string) {panic(s)},@() {})
        verify(started==0 && signals==0)
    }
    // The signal can be triggered from on_next; terminal waits for its return.
    for(error in range(2)) {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_take_until(rx_clone(stop))
        var view <- rx_clone(stop);var inputView <- rx_clone(input)
        var inscope sub <- rx_subscribe(source,@ capture(<-view,<-inputView,copy(error)) (n:int) {
            verify(!inCallback);inCallback=true;trace+="next;"
            if(error==0) {rx_subject_next(view,"stop")} else {rx_subject_error(view,"failed")}
            verify(rx_subscriber_count(view)==0 && rx_subscriber_count(inputView)==0)
            rx_subject_next(inputView,9)
            trace+="return;";inCallback=false
        } finally {delete view;delete inputView},@(s:string) {verify(!inCallback && s=="failed");trace+="error;"},@() {verify(!inCallback);trace+="done;"})
        rx_subject_next(input,1)
        verify(trace==(error==0 ? "next;return;done;" : "next;return;error;"))
    }
    // Same subject on both inputs: notifier wins because it subscribed first.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_take_until(rx_clone(input))
        var inscope sub <- rx_subscribe(source,@(n:int) {panic("signal should win")},@(s:string) {panic(s)},@() {trace="done"})
        verify(rx_subscriber_count(input)==2)
        rx_subject_next(input,1)
        verify(trace=="done" && rx_subscriber_count(input)==0)
    }
    // Runs have independent controls; a past non-terminal signal is not replayed.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_take_until(rx_clone(stop))
        var inscope a <- rx_subscribe(source,@(n:int) {trace+="a{n};"},@(s:string) {panic(s)},@() {})
        var inscope b <- rx_subscribe(source,@(n:int) {trace+="b{n};"},@(s:string) {panic(s)},@() {})
        rx_unsubscribe(a);rx_subject_next(input,1);rx_subject_next(stop,"stop")
        var inscope c <- rx_subscribe(source,@(n:int) {trace+="c{n};"},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,2);rx_subject_complete(input)
        verify(trace=="b1;c2;" && rx_subscriber_count(stop)==0)
    }
    // Downstream take stops synchronous source effects and unregisters notifier.
    {
        started=0
        var inscope stop <- rx_subject(type<string>)
        var inscope source <- rx_range(1,10) |> rx_tap(@(n:int) {started++}) |> rx_take_until(rx_clone(stop)) |> rx_take(1)
        var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==1)},@(s:string) {panic(s)},@() {})
        verify(started==1 && rx_is_closed(sub) && rx_subscriber_count(stop)==0)
    }
    // A synchronous source must stop immediately when an upstream tap signals.
    {
        started=0;trace=""
        var inscope stop <- rx_subject(type<int>)
        var view <- rx_clone(stop)
        var inscope source <- rx_range(1,10) |> rx_tap(@ capture(<-view) (n:int) {started++;rx_subject_next(view,n)} finally {delete view}) |> rx_take_until(rx_clone(stop))
        var inscope sub <- rx_subscribe(source,@(n:int) {panic("signal precedes next")},@(s:string) {panic(s)},@() {trace="done"})
        verify(started==1 && trace=="done" && rx_subscriber_count(stop)==0)
    }
    // Virtual clock: cancel the interval and its pending timer at the signal.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_interval(5,clock) |> rx_take_until(rx_timer(12,clock))
        var inscope sub <- rx_subscribe(source,@(n:int64) {trace+="{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
        rx_advance_by(clock,100)
        verify(trace=="0;1;done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_interval(5,clock) |> rx_take_until(rx_timer(5,clock))
        var inscope sub <- rx_subscribe(source,@(n:int64) {panic("notifier wins deadline tie")},@(s:string) {panic(s)},@() {})
        rx_advance_by(clock,5)
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX take_until checks OK\n")
}
