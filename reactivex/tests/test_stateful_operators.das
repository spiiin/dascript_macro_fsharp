options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var effects=0
var factories=0
var errors=0
var completed=0

def checks() {
    trace=""
    {
        var inscope source <- rx_range(1,3) |> rx_tap(@(n:int) {trace+="tap{n};"},@(s:string) {panic(s)},@() {trace+="tapDone;"}) |> rx_scan(10,@(sum:int;n:int) {trace+="sum{n};";return sum+n}) |> rx_start_with(10)
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="next{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
        verify(trace=="next10;tap1;sum1;next11;tap2;sum2;next13;tap3;sum3;next16;tapDone;done;")
    }
    // Prefix delivery can stop before the cold source is even connected.
    for(mode in range(3)) {
        factories=0;trace=""
        var inscope source <- rx_defer(@() {factories++;return <- rx_range(1,2)}) |> rx_start_with(9) |> rx_take(mode==0 ? 1 : 10)
        var inscope control <- rx_subscription()
        var caught=false
        try {
            var ptr:RxSubscription?
            unsafe {ptr=addr(control)}
            rx_subscribe_with(control,source,@ capture(copy(ptr),copy(mode)) (n:int) {
                trace+="{n};"
                if(mode==1) {unsafe {rx_unsubscribe(*ptr)}}
                if(mode==2) {panic("prefix consumer failed")}
            },@(s:string) {panic("unexpected error")},@() {})
        } recover {caught=true}
        verify(factories==0 && trace=="9;" && rx_is_closed(control) && caught==(mode==2))
    }
    // Independent histories for simultaneous and repeated subscriptions.
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_scan(0,@(sum:int;n:int) {return sum+n}) |> rx_distinct_until_changed()
        trace=""
        var inscope a <- rx_subscribe(source,@(n:int) {trace+="a{n};"},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,1)
        var inscope b <- rx_subscribe(source,@(n:int) {trace+="b{n};"},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,0);rx_subject_next(input,2)
        verify(trace=="a1;b0;a3;b2;")
        rx_unsubscribe(a);rx_unsubscribe(b)
        var inscope c <- rx_subscribe(source,@(n:int) {trace+="c{n};"},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,1);rx_subject_complete(input)
        verify(trace=="a1;b0;a3;b2;c1;" && rx_subscriber_count(input)==0)
    }
    {
        var inscope values:array<int> <- [1,1,2,2,1]
        var inscope source <- rx_from_array(values) |> rx_distinct_until_changed()
        for(i in range(2)) {
            trace=""
            var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
            verify(trace=="1;2;1;")
        }
        // Non-transitive comparator: retain the last emitted, not suppressed value.
        var inscope custom <- rx_range(1,5) |> rx_distinct_until_changed(@(previous:int;current:int) {return current-previous<2})
        trace=""
        var inscope sub <- rx_subscribe(custom,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="1;3;5;")
    }
    // Heterogeneous scan + nested aliases + owning string history.
    {
        var inscope source <- rx_range(1,3) |> rx_scan("",@(text:string;n:int) {return "{text}{n}"}) |> rx_distinct_until_changed() |> rx_map(@(s:string) {return length(s)}) |> rx_scan(0,@(sum:int;n:int) {return sum+n}) |> rx_tap(@(n:int) {effects++})
        trace=""
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="1;3;6;")
    }
    // Empty scan does not emit its seed; prefix still precedes an error.
    {
        trace=""
        var inscope empty <- rx_empty(type<int>) |> rx_scan(10,@(a:int;b:int) {panic("empty reducer");return a+b})
        var inscope sub <- rx_subscribe(empty,@(n:int) {panic("empty next")},@(s:string) {panic(s)},@() {trace+="done;"})
        verify(trace=="done;")
        trace=""
        var inscope failed <- rx_throw("source error",type<int>) |> rx_start_with(0) |> rx_tap(@(n:int) {},@(s:string) {verify(s=="source error");trace+="tapError;"},@() {panic("unexpected done")})
        var inscope err <- rx_subscribe(failed,@(n:int) {trace+="{n};"},@(s:string) {verify(s=="source error");trace+="error;"},@() {panic("unexpected done")})
        verify(trace=="0;tapError;error;")
    }
    // Each operator's callback failure becomes one error, stops input effects.
    for(mode in range(3)) {
        effects=0;errors=0;completed=0;trace=""
        var inscope source <- rx_range(1,5) |> rx_tap(@(n:int) {effects++}) |> rx_tap(@ capture(copy(mode)) (n:int) {if(mode==0 && n==2) {panic("tap failed")}}) |> rx_scan(0,@ capture(copy(mode)) (a:int;n:int) {if(mode==1 && n==2) {panic("scan failed")};return n}) |> rx_distinct_until_changed(@ capture(copy(mode)) (a:int;b:int) {if(mode==2) {panic("compare failed")};return a==b})
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {errors++},@() {completed++})
        verify(trace=="1;" && effects==2 && errors==1 && completed==0 && rx_is_closed(sub))
    }
    for(mode in range(2)) {
        trace=""
        var inscope source <- rx_range(1,1) |> rx_tap(@(n:int) {},@ capture(copy(mode)) (s:string) {if(mode==1) {panic("tap error failed")}},@ capture(copy(mode)) () {if(mode==0) {panic("tap complete failed")}})
        var inscope input <- rx_throw("original",type<int>) |> rx_tap(@(n:int) {},@(s:string) {panic("replacement")},@() {})
        if(mode==0) {
            var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {trace=s},@() {panic("unexpected done")})
            verify(trace=="tap complete failed\n")
        } else {
            var inscope sub <- rx_subscribe(input,@(n:int) {},@(s:string) {trace=s},@() {panic("unexpected done")})
            verify(trace=="replacement\n")
        }
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX stateful operator checks OK\n")
}
