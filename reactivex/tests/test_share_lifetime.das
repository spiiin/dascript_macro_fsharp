options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var starts=0
var stops=0
var active=0
var trace=""
var inCallback=false
var again:RxSubscription
var onStop:lambda<():void>
var repeatControls:array<RxSubscription>
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
def hold() {opened++;return <- Hold(values <- [42])}
def share_view(var source:auto;replay:bool) {
    if(replay) {return <- source |> rx_share_replay(2)}
    return <- source |> rx_share()
}
def owning_source(input:auto;failCleanup:bool=false) {
    var view <- rx_clone(input)
    return <- rx_defer(@ capture(<-view,copy(failCleanup)) () {
        var data <- hold()
        var mapped <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.values[0]==42);return n} finally {delete data})
        return <- rx_create(type<int>,@ capture(<-mapped,copy(failCleanup)) (sink:typedecl(rx_sink_marker(type<int>))) {
            starts++;active++
            rx_sink_add_cleanup(sink,@ capture(copy(failCleanup)) () {stops++;active--;if(failCleanup) {panic("producer cleanup failed")}})
            rx_connect(mapped,sink)
        } finally {delete mapped})
    } finally {delete view})
}
def resubscribe(hub:auto) : void {
    let index=starts
    var view <- rx_clone(hub)
    rx_subscribe_with(repeatControls[index],hub,@(n:int) {},@(s:string) {panic(s)},@ capture(<-view) () {
        if(starts<64) {resubscribe(view)}
    } finally {delete view})
}
def checks() {
    for(replay in range(2)) {
        for(mode in range(9)) {
            starts=0;stops=0;active=0;trace=""
            var inscope input <- rx_subject(type<int>)
            var hub <- share_view(owning_source(input,mode==8),replay==1)
            var aData <- hold();var bData <- hold()
            var aSource <- rx_clone(hub) |> rx_take(mode==4 ? 1 : 100)
            var bSource <- rx_clone(hub) |> rx_take(mode==4 ? 1 : 100)
            var a <- rx_subscribe(aSource,@ capture(<-aData,copy(mode)) (n:int) {
                verify(aData.values[0]==42);trace+="a;";if(mode==5) {panic("observer failed")}
            } finally {delete aData},@ capture(copy(mode)) (s:string) {trace+="aError;";if(mode==6) {panic("error observer failed")}},
                @ capture(copy(mode)) () {trace+="aDone;";if(mode==7) {panic("complete observer failed")}})
            var b <- rx_subscribe(bSource,@ capture(<-bData) (n:int) {verify(bData.values[0]==42);trace+="b;"} finally {delete bData},
                @(s:string) {trace+="bError;"},@() {trace+="bDone;"})
            delete aSource;delete bSource;delete hub
            verify(starts==1 && active==1 && rx_subscriber_count(input)==1)
            var caught=false
            try {
                if(mode==2 || mode==8) {rx_unsubscribe(a);verify(active==1);rx_unsubscribe(b)}
                elif(mode==3) {delete a;verify(active==1);delete b}
                else {
                    rx_subject_next(input,1)
                    if(mode==1 || mode==6) {rx_subject_error(input,"failed")}
                    elif(mode!=4) {rx_subject_complete(input)}
                }
            } recover {caught=true}
            verify(caught==(mode==5 || mode==6 || mode==7 || mode==8))
            if(mode!=3) {verify(rx_is_closed(a) && rx_is_closed(b));delete a;delete b}
            verify(active==0 && stops==1 && rx_subscriber_count(input)==0 && opened==freed)
            if(mode==5) {verify(trace=="a;b;")} // fan-out finishes, then the failed generation closes.
        }
    }
    // A failure while replaying affects only the new subscriber, not the live
    // connection or its other consumers. Its captures are released immediately.
    {
        starts=0;stops=0;active=0
        var inscope input <- rx_subject(type<int>)
        var inscope hub <- owning_source(input) |> rx_share_replay(2)
        var inscope good <- rx_subscribe(hub,@(n:int) {},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,1)
        let before=freed
        var data <- hold();var bad <- rx_subscription();var caught=false
        try {
            rx_subscribe_with(bad,hub,@ capture(<-data) (n:int) {verify(data.values[0]==42);panic("replay observer failed")} finally {delete data},@(s:string) {},@() {})
        } recover {caught=true}
        delete bad
        verify(caught && freed==before+1 && active==1 && starts==1 && !rx_is_closed(good))
        rx_subject_next(input,2);rx_unsubscribe(good)
        verify(active==0 && stops==1 && opened==freed)
    }
    // A failure while reading a completed cache leaves that successful cache
    // available to other late subscribers, including terminal callback errors.
    for(stage in range(2)) {
        starts=0;trace=""
        var inscope hub <- rx_defer(@() {starts++;return <- rx_just(starts)}) |> rx_share_replay(1)
        {var inscope warm <- rx_subscribe(hub,@(n:int) {},@(s:string) {panic(s)},@() {})}
        var data <- hold();var bad <- rx_subscription();var caught=false
        try {
            rx_subscribe_with(bad,hub,@ capture(<-data,copy(stage)) (n:int) {
                verify(data.values[0]==42);if(stage==0) {panic("cached next failed")}
            } finally {delete data},@(s:string) {},@() {panic("cached complete failed")})
        } recover {caught=true}
        delete bad
        var inscope good <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(caught && starts==1 && trace=="1;" && opened==freed)
    }
    // Native failure in the live terminal fan-out invalidates the generation
    // consistently for synchronous and asynchronous producers.
    for(sync in range(2)) {
        starts=0;trace=""
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope hub <- rx_defer(@ capture(<-view,copy(sync)) () {
            starts++;let attempt=starts;var inner <- rx_clone(view)
            return <- rx_create(type<int>,@ capture(<-inner,copy(sync),copy(attempt)) (sink:typedecl(rx_sink_marker(type<int>))) {
                if(sync==1) {rx_sink_next(sink,attempt);rx_sink_complete(sink)} else {rx_connect(inner,sink)}
            } finally {delete inner})
        } finally {delete view}) |> rx_share_replay(1)
        var bad <- rx_subscription();var caught=false
        try {
            rx_subscribe_with(bad,hub,@(n:int) {},@(s:string) {panic(s)},@() {panic("live complete failed")})
            if(sync==0) {rx_subject_next(input,7);rx_subject_complete(input)}
        } recover {caught=true}
        delete bad
        var inscope good <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(caught && starts==2 && trace==(sync==1 ? "2;" : ""))
    }
    // Reentrant completion/error subscriptions wait for late synchronous
    // producer cleanup before starting the next generation.
    for(error in range(2)) {
        starts=0;stops=0;active=0;trace="";again <- rx_subscription()
        var inscope hub <- rx_create(type<int>,@ capture(copy(error)) (sink:typedecl(rx_sink_marker(type<int>))) {
            verify(active==0);starts++;active++
            rx_sink_next(sink,starts)
            if(error==1) {rx_sink_error(sink,"failed")} else {rx_sink_complete(sink)}
            rx_sink_add_cleanup(sink,@() {active--;stops++}) // deliberately late
        }) |> rx_share()
        var completeView <- rx_clone(hub);var errorView <- rx_clone(hub)
        var inscope sub <- rx_subscribe(hub,@(n:int) {trace+="{n};"},@ capture(<-errorView) (s:string) {
            rx_subscribe_with(again,errorView,@(n:int) {trace+="{n};"},@(s:string) {},@() {})
        } finally {delete errorView},@ capture(<-completeView) () {
            rx_subscribe_with(again,completeView,@(n:int) {trace+="{n};"},@(s:string) {},@() {})
        } finally {delete completeView})
        verify(starts==2 && stops==2 && active==0 && trace=="1;2;" && rx_is_closed(again))
        delete again
    }
    // Native connect failure closes all attached consumers and allows a fresh
    // attempt. A reentrant consumer attached during the first next cannot hang.
    {
        starts=0;trace="";again <- rx_subscription()
        var hub <- rx_defer(@() {
            starts++;let attempt=starts;var data <- hold()
            return <- rx_create(type<int>,@ capture(<-data,copy(attempt)) (sink:typedecl(rx_sink_marker(type<int>))) {
                verify(data.values[0]==42);rx_sink_next(sink,attempt)
                if(attempt==1) {panic("native connect failed")}
                rx_sink_complete(sink)
            } finally {delete data})
        }) |> rx_share_replay(1)
        var view <- rx_clone(hub);var first <- rx_subscription();var caught=false
        try {
            rx_subscribe_with(first,hub,@ capture(<-view) (n:int) {
                rx_subscribe_with(again,view,@(v:int) {trace+="b{v};"},@(s:string) {},@() {})
            } finally {delete view},@(s:string) {panic("native failure is not on_error")},@() {})
        } recover {caught=true}
        verify(caught && rx_is_closed(first) && rx_is_closed(again) && opened==freed)
        delete first;delete again
        var inscope nextRun <- rx_subscribe(hub,@(n:int) {trace+="c{n};"},@(s:string) {panic(s)},@() {})
        verify(starts==2 && trace=="b1;c2;" && opened==freed)
        delete hub
    }
    // Reentrant synchronous resubscriptions drain iteratively, without stacking
    // another source connect before the previous late cleanup has returned.
    {
        starts=0;stops=0;active=0
        for(i in range(64)) {repeatControls |> emplace(rx_subscription())}
        var inscope hub <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            verify(active==0);starts++;active++
            rx_sink_complete(sink)
            rx_sink_add_cleanup(sink,@() {stops++;active--})
        }) |> rx_share()
        resubscribe(hub)
        verify(starts==64 && stops==64 && active==0)
        for(control in repeatControls) {verify(rx_is_closed(control))}
        delete repeatControls
    }
    // A new generation requested from on_next must not deliver its first
    // synchronous value inside the previous generation's active callback.
    {
        starts=0;trace="";again <- rx_subscription()
        var inscope input <- rx_subject(type<int>)
        var inner <- rx_clone(input)
        var inscope hub <- rx_create(type<int>,@ capture(<-inner) (sink:typedecl(rx_sink_marker(type<int>))) {
            starts++
            if(starts==2) {rx_sink_next(sink,20)}
            rx_connect(inner,sink)
        } finally {delete inner}) |> rx_share()
        var first <- rx_subscription();var control:RxSubscription?
        unsafe {control=addr(first)}
        var view <- rx_clone(hub)
        rx_subscribe_with(first,hub,@ capture(<-view,copy(control)) (n:int) {
            inCallback=true;trace+="a{n};"
            unsafe {rx_unsubscribe(*control)}
            rx_subscribe_with(again,view,@(v:int) {verify(!inCallback);trace+="b{v};"},@(s:string) {panic(s)},@() {})
            trace+="return;";inCallback=false
        } finally {delete view},@(s:string) {panic(s)},@() {})
        rx_subject_next(input,1)
        verify(starts==2 && trace=="a1;return;b20;" && rx_subscriber_count(input)==1)
        delete first;delete again
        verify(rx_subscriber_count(input)==0)
    }
    // Refcount-zero teardown can subscribe again; it must finish removing the
    // previous upstream observer before the new connect begins.
    {
        starts=0;stops=0;active=0;again <- rx_subscription()
        var inscope input <- rx_subject(type<int>)
        var inputView <- rx_clone(input)
        var hub <- rx_create(type<int>,@ capture(<-inputView) (sink:typedecl(rx_sink_marker(type<int>))) {
            verify(active==0 && rx_subscriber_count(inputView)==0)
            starts++;active++
            rx_sink_add_cleanup(sink,@() {active--;stops++;if(starts==1) {invoke(onStop)}})
            rx_connect(inputView,sink)
        } finally {delete inputView}) |> rx_share_replay(1)
        var view <- rx_clone(hub)
        onStop <- @ capture(<-view) () {
            rx_subscribe_with(again,view,@(n:int) {},@(s:string) {panic(s)},@() {})
        } finally {delete view}
        var first <- rx_subscribe(hub,@(n:int) {},@(s:string) {panic(s)},@() {})
        rx_unsubscribe(first)
        verify(starts==2 && stops==1 && active==1 && rx_subscriber_count(input)==1)
        delete first;delete hub;unsafe {delete onStop};delete again
        verify(stops==2 && active==0 && rx_subscriber_count(input)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(6)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX share/share_replay lifetime checks OK\n")
}
