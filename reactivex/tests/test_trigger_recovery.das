options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
require strings
var trace=""
var effects=0
var attempts=0
var closed=0
var factories=0
struct Score {amount:int;name:string}

def observe(source:auto) {return <- rx_subscribe(source,@(n:int){trace+="{n};"},@(s:string){trace+="error:{s};"},@(){trace+="done;"})}

def checks() {
    // Secondary connects first, and its updates never trigger output.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope latest <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_with_latest_from(rx_clone(latest))
        var inscope sub <- rx_subscribe(source,@(p:tuple<first:int;second:string>){trace+="{p.first}/{p.second};"},@(s:string){panic(s)},@(){trace+="done;"})
        rx_subject_next(input,1);rx_subject_next(latest,"a");rx_subject_next(latest,"b")
        verify(trace=="")
        rx_subject_next(input,2);rx_subject_complete(latest);rx_subject_next(input,3);rx_subject_complete(input)
        verify(trace=="2/b;3/b;done;" && rx_subscriber_count(latest)==0 && rx_subscriber_count(input)==0)
    }
    {
        trace=""
        var inscope source <- rx_range(1,3) |> rx_with_latest_from(rx_just(9)) |> rx_map(@(p:tuple<first:int;second:int>){return p.first+p.second})
        var inscope sub <- observe(source)
        verify(trace=="10;11;12;done;")
    }
    for(mode in range(3)) {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope latest <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_with_latest_from(rx_clone(latest))
        var inscope sub <- rx_subscribe(source,@(p:tuple<first:int;second:int>){panic("no latest")},@(s:string){trace=s},@(){trace="done"})
        if(mode==0) {rx_subject_complete(latest);verify(!rx_is_closed(sub));rx_subject_next(input,1);rx_subject_complete(input)}
        elif(mode==1) {rx_subject_error(latest,"secondary")}
        else {rx_subject_error(input,"primary")}
        verify(trace==(mode==0 ? "done" : (mode==1 ? "secondary" : "primary")) && rx_subscriber_count(input)==0 && rx_subscriber_count(latest)==0)
    }
    // No selector call or queued request while a child is active.
    {
        trace="";factories=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var clockView <- rx_scheduler_clone(clock)
        var inscope source <- rx_clone(input) |> rx_exhaust_map(@ capture(<-clockView) (n:int) {
            factories++
            return <- rx_timer(5,clockView) |> rx_map(@ capture(copy(n)) (tick:int64){return n})
        } finally {delete clockView})
        var inscope sub <- observe(source)
        rx_subject_next(input,1);rx_subject_next(input,2)
        rx_advance_to(clock,5);verify(trace=="1;" && factories==1)
        rx_subject_next(input,3);rx_subject_complete(input)
        verify(!rx_is_closed(sub))
        rx_advance_to(clock,10)
        verify(trace=="1;3;done;" && factories==2 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Synchronous children free the slot before the next outer value.
    {
        trace=""
        var inscope source <- rx_range(1,3) |> rx_exhaust_map(@(n:int){return <- rx_just(n)})
        var inscope sub <- observe(source)
        verify(trace=="1;2;3;done;")
    }
    // Backoff 2,4,5; producer teardown precedes predicate and the next attempt.
    {
        trace="";attempts=0;closed=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            attempts++;rx_sink_add_cleanup(sink,@(){closed++;trace+="close;"})
            if(attempts<4) {rx_sink_error(sink,"transient")}
            else {rx_sink_next(sink,42);rx_sink_complete(sink)}
        }) |> rx_retry_backoff(4,2,5,clock,@(s:string;retry:int){verify(closed==attempts);trace+="retry{retry};";return s=="transient"})
        var inscope sub <- observe(source)
        rx_advance_to(clock,1);verify(attempts==1)
        rx_advance_to(clock,2);verify(attempts==2)
        rx_advance_to(clock,5);verify(attempts==2)
        rx_advance_to(clock,6);verify(attempts==3)
        rx_advance_to(clock,11)
        verify(attempts==4 && closed==4 && trace=="close;retry1;close;retry2;close;retry3;42;close;done;" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    for(mode in range(4)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_throw("original",type<int>) |> rx_retry(3,@ capture(copy(mode)) (s:string;retry:int) {
            if(mode==1) {panic("predicate failed")}
            return mode!=0
        },@ capture(copy(mode)) (retry:int) {
            if(mode==2) {panic("delay failed")}
            return -1l
        },clock)
        var inscope sub <- rx_subscribe(source,@(n:int){panic("unexpected next")},@(s:string){trace=s},@(){panic("unexpected complete")})
        verify(starts_with(trace,mode==0 ? "original" : (mode==1 ? "predicate failed" : (mode==2 ? "delay failed" : "rx_retry: negative delay"))))
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Struct seeds survive the scan construction and every repeated subscription (SDK JIT regression).
    {
        var inscope filled <- rx_range(1,2) |> rx_reduce(Score(amount=7,name="seed"),@(a:Score;n:int){return Score(amount=a.amount+n,name=a.name)})
        var inscope empty <- rx_empty(type<int>) |> rx_reduce(Score(amount=7,name="seed"),@(a:Score;n:int){return Score(amount=a.amount+n,name=a.name)})
        var inscope fallback <- rx_empty(type<Score>) |> rx_default_if_empty(Score(amount=9,name="fallback"))
        for(repeat in range(3)) {
            var inscope a <- rx_subscribe(filled,@(score:Score){verify(score.amount==10 && score.name=="seed")},@(s:string){panic(s)},@(){})
            var inscope b <- rx_subscribe(empty,@(score:Score){verify(score.amount==7 && score.name=="seed")},@(s:string){panic(s)},@(){})
            var inscope c <- rx_subscribe(fallback,@(score:Score){verify(score.amount==9 && score.name=="fallback")},@(s:string){panic(s)},@(){})
        }
    }
    // Seeded reduce changes type, emits only on successful completion.
    {
        trace=""
        var inscope source <- rx_range(1,3) |> rx_reduce("",@(a:string;n:int){return "{a}{n}"})
        var inscope sub <- rx_subscribe(source,@(s:string){trace+="{s};"},@(s:string){panic(s)},@(){trace+="done;"})
        verify(trace=="123;done;")
    }
    {
        trace=""
        var inscope source <- rx_empty(type<int>) |> rx_reduce(7,@(a:int;n:int){panic("empty reducer");return a+n})
        var inscope sub <- observe(source);verify(trace=="7;done;")
    }
    for(mode in range(2)) {
        trace="";effects=0
        var inscope input <- rx_range(1,4) |> rx_tap(@(n:int){effects++})
        if(mode==0) {
            var inscope source <- rx_clone(input) |> rx_first()
            var inscope sub <- observe(source);verify(trace=="1;done;" && effects==1)
        } else {
            var inscope source <- rx_clone(input) |> rx_last()
            var inscope sub <- observe(source);verify(trace=="4;done;" && effects==4)
        }
    }
    {
        trace=""
        var inscope a <- rx_empty(type<int>) |> rx_first()
        var inscope x <- observe(a);verify(trace=="error:rx_first: empty source;")
        trace=""
        var inscope b <- rx_empty(type<int>) |> rx_last()
        var inscope y <- observe(b);verify(trace=="error:rx_last: empty source;")
        trace=""
        var inscope c <- rx_empty(type<int>) |> rx_default_if_empty(8)
        var inscope z <- observe(c);verify(trace=="8;done;")
        trace=""
        var inscope d <- rx_range(1,3) |> rx_default_if_empty(8)
        var inscope q <- observe(d);verify(trace=="1;2;3;done;")
    }
    {
        trace="";effects=0
        var inscope source <- rx_range(1,4) |> rx_tap(@(n:int){effects++}) |> rx_reduce(0,@(a:int;n:int){if(n==2){panic("reduce failed")};return a+n})
        var inscope sub <- rx_subscribe(source,@(n:int){panic("partial reduce")},@(s:string){trace=s},@(){panic("unexpected done")})
        verify(effects==2 && starts_with(trace,"reduce failed"))
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)){checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX trigger/recovery/terminal checks OK\n")
}
