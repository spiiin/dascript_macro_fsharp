options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var starts=0
var stops=0
var active=0
var effects=0
var trace=""
var late:RxSubscription

def share_view(var source:auto;replay:bool) {
    if(replay) {return <- source |> rx_share_replay(2)}
    return <- source |> rx_share()
}
def counted(input:auto) {
    var view <- rx_clone(input)
    return <- rx_defer(@ capture(<-view) () {
        var inner <- rx_clone(view)
        return <- rx_create(type<int>,@ capture(<-inner) (sink:typedecl(rx_sink_marker(type<int>))) {
            starts++;active++
            rx_sink_add_cleanup(sink,@() {stops++;active--})
            rx_connect(inner,sink)
        } finally {delete inner})
    } finally {delete view})
}
def checks() {
    for(replay in range(2)) {
        starts=0;stops=0;active=0;trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope hub <- share_view(counted(input),replay==1)
        var inscope a <- rx_subscribe(hub,@(n:int) {trace+="a{n};"},@(s:string) {panic(s)},@() {trace+="aDone;"})
        rx_subject_next(input,1)
        var inscope clone <- rx_clone(hub)
        var inscope b <- rx_subscribe(clone,@(n:int) {trace+="b{n};"},@(s:string) {panic(s)},@() {trace+="bDone;"})
        verify(starts==1 && active==1 && rx_subscriber_count(input)==1)
        rx_subject_next(input,2);rx_unsubscribe(a);rx_subject_next(input,3)
        verify(trace==(replay==1 ? "a1;b1;a2;b2;b3;" : "a1;a2;b2;b3;"))
        rx_unsubscribe(b)
        verify(stops==1 && active==0 && rx_subscriber_count(input)==0)
        trace=""
        var inscope c <- rx_subscribe(hub,@(n:int) {trace+="c{n};"},@(s:string) {panic(s)},@() {trace+="cDone;"})
        verify(starts==2 && trace=="") // refcount zero discarded even replay cache.
        rx_subject_next(input,4);rx_subject_complete(input)
        verify(trace=="c4;cDone;" && active==0 && stops==2)
        trace=""
        var inscope d <- rx_subscribe(hub,@(n:int) {trace+="d{n};"},@(s:string) {panic(s)},@() {trace+="dDone;"})
        verify(trace==(replay==1 ? "d4;dDone;" : "dDone;"))
        verify(starts==(replay==1 ? 2 : 3) && active==0 && rx_is_closed(d))
    }
    // Synchronous completion: share reruns; share_replay caches only the last N.
    for(replay in range(2)) {
        starts=0;trace=""
        var inscope hub <- share_view(rx_defer(@() {starts++;return <- rx_range(starts*10,3)}),replay==1)
        for(i in range(2)) {
            var inscope sub <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
            verify(rx_is_closed(sub))
        }
        verify(trace==(replay==1 ? "10;11;12;done;11;12;done;" : "10;11;12;done;20;21;22;done;"))
        verify(starts==(replay==1 ? 1 : 2))
    }
    // Both variants reset on error; no cached first-attempt value on retry.
    for(replay in range(2)) {
        starts=0;trace=""
        var inscope hub <- share_view(rx_defer(@() {
            starts++;let attempt=starts
            return <- rx_range(1,2) |> rx_map(@ capture(copy(attempt)) (n:int) {
                if(attempt==1 && n==2) {panic("source failed")}
                return attempt*10+n
            })
        }),replay==1)
        for(i in range(2)) {var inscope sub <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@(s:string) {trace+="error;"},@() {trace+="done;"})}
        verify(starts==2 && trace=="11;error;21;22;done;")
    }
    // Error fan-out reaches all subscribers, then a new subscription reconnects.
    for(replay in range(2)) {
        starts=0;stops=0;active=0;trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope hub <- share_view(counted(input),replay==1)
        var inscope a <- rx_subscribe(hub,@(n:int) {},@(s:string) {verify(s=="failed");trace+="aError;"},@() {})
        var inscope b <- rx_subscribe(hub,@(n:int) {},@(s:string) {verify(s=="failed");trace+="bError;"},@() {})
        rx_subject_next(input,9);rx_subject_error(input,"failed")
        verify(trace=="aError;bError;" && stops==1 && active==0 && rx_is_closed(a) && rx_is_closed(b))
        trace=""
        var inscope c <- rx_subscribe(hub,@(n:int) {panic("old cache must be gone")},@(s:string) {trace+="error;"},@() {})
        verify(starts==2 && trace=="error;" && active==0)
    }
    // First-value cancellation stops a synchronous firehose and resets replay.
    for(replay in range(2)) {
        starts=0;effects=0;trace=""
        var inscope hub <- share_view(rx_defer(@() {
            starts++;let attempt=starts
            return <- rx_range(1,10) |> rx_map(@ capture(copy(attempt)) (n:int) {effects++;return attempt*100+n})
        }),replay==1)
        for(i in range(2)) {
            var inscope source <- rx_clone(hub) |> rx_take(1)
            var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        }
        verify(starts==2 && effects==2 && trace=="101;201;")
    }
    // A subscriber added from on_next shares the existing sync connection.
    for(replay in range(2)) {
        starts=0;trace="";late <- rx_subscription()
        var inscope hub <- share_view(rx_defer(@() {starts++;return <- rx_range(1,2)}),replay==1)
        var view <- rx_clone(hub)
        var inscope a <- rx_subscribe(hub,@ capture(<-view) (n:int) {
            trace+="a{n};"
            if(n==1) {rx_subscribe_with(late,view,@(v:int) {trace+="b{v};"},@(s:string) {panic(s)},@() {trace+="bDone;"})}
        } finally {delete view},@(s:string) {panic(s)},@() {trace+="aDone;"})
        verify(starts==1 && rx_is_closed(late))
        verify(trace==(replay==1 ? "a1;b1;a2;b2;aDone;bDone;" : "a1;a2;b2;aDone;bDone;"))
        delete late
    }
    // Distinct share calls create distinct groups, even for the same descriptor.
    {
        starts=0;stops=0;active=0
        var inscope input <- rx_subject(type<int>)
        var inscope source <- counted(input)
        var inscope left <- rx_clone(source) |> rx_share()
        var inscope right <- rx_clone(source) |> rx_share()
        var inscope a <- rx_subscribe(left,@(n:int) {},@(s:string) {panic(s)},@() {})
        var inscope b <- rx_subscribe(right,@(n:int) {},@(s:string) {panic(s)},@() {})
        verify(starts==2 && active==2 && rx_subscriber_count(input)==2)
        rx_unsubscribe(a);rx_unsubscribe(b)
        verify(active==0 && stops==2)
    }
    // Repeated type-changing pipelines preserve the actual element type.
    {
        trace=""
        var inscope hub <- rx_range(1,3) |> rx_map(@(n:int) {return "v{n}"}) |> rx_share_replay() |> rx_map(@(s:string) {return length(s)}) |> rx_share()
        var inscope sub <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="2;2;2;")
    }
    for(size in range(-1,1)) {
        var source <- rx_range(1,1);var caught=false
        try {var hub <- source |> rx_share_replay(size);delete hub} recover {caught=true}
        delete source;verify(caught)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX share/share_replay checks OK\n")
}
