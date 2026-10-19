options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
require strings
var trace=""
var factories=0
var cleanups=0
var effects=0
var other:RxSubscription
var reconnect:RxSubscription
var late:RxSubscription
var reenter:lambda<():void>

def observe(source:auto) {return <- rx_subscribe(source,@(n:int){trace+="{n};"},@(s:string){trace+="e;"},@(){trace+="c;"})}

def checks() {
    // Expiration is half-open: age == window is expired, including after terminal.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_replay_subject(type<int>,3,5,clock)
        rx_subject_next(input,1);rx_advance_to(clock,3);rx_subject_next(input,2)
        rx_advance_to(clock,5);verify(rx_subject_buffered_count(input)==1)
        var inscope sub <- observe(input);verify(trace=="2;")
        rx_unsubscribe(sub)
        rx_advance_to(clock,8);verify(rx_subject_buffered_count(input)==0)
        rx_subject_complete(input);trace=""
        var inscope late <- observe(input);verify(trace=="c;")
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Count and time limits apply together; replay is FIFO.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_replay_subject(type<string>,2,10,clock)
        rx_subject_next(input,"a");rx_subject_next(input,"b");rx_subject_next(input,"c");rx_subject_error(input,"failure")
        var inscope sub <- rx_subscribe(input,@(s:string){trace+=s},@(s:string){trace+="e"},@(){panic("done")})
        verify(trace=="bce")
        rx_advance_to(clock,10);trace=""
        var inscope late <- rx_subscribe(input,@(s:string){trace+=s},@(s:string){trace+="e"},@(){panic("done")})
        verify(trace=="e" && rx_subject_buffered_count(input)==0)
    }
    // Every reset flag is snapshotted and works across repeated subscriptions.
    for(terminal in range(2)) {
        for(flags in range(4)) {
            let errorReset=flags==1 || flags==3
            let completeReset=flags>=2
            let reset=terminal==0 ? completeReset : errorReset
            factories=0;trace=""
            var inscope source <- rx_create(type<int>,@ capture(copy(terminal)) (sink:typedecl(rx_sink_marker(type<int>))) {
                factories++;rx_sink_next(sink,factories)
                if(terminal==0) {rx_sink_complete(sink)} else {rx_sink_error(sink,"source")}
            }) |> rx_share_replay(1,RxShareOptions(reset_on_error=errorReset,reset_on_complete=completeReset))
            for(repeat in range(2)) {var inscope sub <- observe(source)}
            verify(factories==(reset ? 2 : 1))
            if(terminal==0) {verify(trace==(reset ? "1;c;2;c;" : "1;c;1;c;"))}
            else {verify(trace==(reset ? "1;e;2;e;" : "1;e;1;e;"))}
        }
    }
    // Successful retained cache expires without reconnecting its completed source.
    {
        factories=0;trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {factories++;rx_sink_next(sink,7);rx_sink_complete(sink)}) |> rx_share_replay(2,5,clock)
        {var inscope a <- observe(source)}
        rx_advance_to(clock,5)
        {var inscope b <- observe(source)}
        verify(trace=="7;c;c;" && factories==1)
    }
    for(reset in range(2)) {
        trace="";factories=0
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope source <- rx_defer(@ capture(<-view) () {factories++;return <- rx_clone(view)} finally {delete view}) |> rx_share_replay(2,RxShareOptions(reset_on_refcount_zero=reset==1,reset_on_complete=false))
        var a <- observe(source);rx_subject_next(input,1);rx_unsubscribe(a);delete a
        verify(rx_subscriber_count(input)==(reset==1 ? 0 : 1))
        rx_subject_next(input,2)
        trace=""
        var b <- observe(source)
        verify(factories==(reset==1 ? 2 : 1) && trace==(reset==1 ? "" : "1;2;"))
        rx_unsubscribe(b);delete b
        rx_share_close(source)
        verify(rx_subscriber_count(input)==0)
        var inscope late <- observe(source);verify(rx_is_closed(late))
    }
    // Explicit close breaks keep-alive cycles and still tears down all listeners if cleanup fails.
    {
        cleanups=0
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var source <- rx_create(type<int>,@ capture(<-view) (sink:typedecl(rx_sink_marker(type<int>))) {
            var nested <- rx_subscribe(view,@(n:int){},@(s:string){},@(){})
            var cleanup <- @ capture(<-nested) () {rx_unsubscribe(nested);cleanups++;panic("upstream cleanup")} finally {delete nested}
            rx_sink_add_cleanup(sink,cleanup)
        } finally {delete view}) |> rx_share(RxShareOptions(reset_on_refcount_zero=false))
        var a <- observe(source);var b <- observe(source)
        var caught=false
        try {rx_share_close(source)} recover {caught=true;verify(starts_with("{this_context().last_exception}","upstream cleanup"))}
        verify(caught && cleanups==1 && rx_subscriber_count(input)==0 && rx_is_closed(a) && rx_is_closed(b))
        delete a;delete b;delete source
    }
    // Publish is idle until connect; any alias of the connection cancels that connection.
    {
        factories=0;trace=""
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope pub <- rx_defer(@ capture(<-view) () {factories++;return <- rx_clone(view)} finally {delete view}) |> rx_publish()
        var inscope a <- rx_subscribe(pub,@(n:int){trace+="a{n};"},@(s:string){panic(s)},@(){trace+="ac;"})
        var inscope b <- rx_subscribe(pub,@(n:int){trace+="b{n};"},@(s:string){panic(s)},@(){trace+="bc;"})
        rx_subject_next(input,0);verify(trace=="" && factories==0)
        var connection <- rx_connect(pub)
        rx_subject_next(input,1);verify(trace=="a1;b1;" && factories==1)
        var alias <- rx_connect(pub);verify(factories==1)
        delete alias;verify(rx_is_closed(connection) && rx_subscriber_count(input)==0 && !rx_is_closed(a))
        rx_subject_next(input,2);verify(trace=="a1;b1;")
        var again <- rx_connect(pub);rx_subject_next(input,3);verify(factories==2 && trace=="a1;b1;a3;b3;")
        rx_subject_complete(input);verify(rx_is_closed(again) && trace=="a1;b1;a3;b3;ac;bc;")
        delete again;delete connection
        var inscope late <- rx_connect(pub);verify(rx_is_closed(late) && factories==2)
    }
    // ref_count auto-connects, disconnects at zero, and reconnects a nonterminal publish.
    {
        factories=0;trace=""
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope source <- rx_defer(@ capture(<-view) () {factories++;return <- rx_clone(view)} finally {delete view}) |> rx_publish() |> rx_ref_count()
        var a <- observe(source);var b <- observe(source)
        verify(factories==1 && rx_subscriber_count(input)==1)
        rx_subject_next(input,1);verify(trace=="1;1;")
        rx_unsubscribe(a);verify(rx_subscriber_count(input)==1);delete a
        delete b;verify(rx_subscriber_count(input)==0)
        var c <- observe(source);verify(factories==2 && rx_subscriber_count(input)==1)
        rx_subject_next(input,2);rx_subject_complete(input);verify(trace=="1;1;2;c;")
        delete c
        var inscope late <- observe(source);verify(factories==2 && rx_is_closed(late))
    }
    // An old synchronous ref_count connect must not overwrite a newer connection.
    {
        trace="";factories=0
        var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            factories++
            rx_sink_add_cleanup(sink,@(){if(factories==1){invoke(reenter)}})
            rx_sink_next(sink,factories)
        }) |> rx_publish() |> rx_ref_count()
        var view <- rx_clone(source)
        reenter <- @ capture(<-view) () {late <- observe(view)} finally {delete view}
        var inscope control <- rx_subscription()
        var pointer=unsafe(addr(control))
        rx_subscribe_with(control,source,@ capture(copy(pointer)) (n:int){unsafe {rx_unsubscribe(*pointer)}},@(s:string){panic(s)},@(){})
        verify(factories==2 && !rx_is_closed(late) && trace=="2;")
        delete late;unsafe {delete reenter}
    }
    // A failed old generation cannot cancel a reconnect started by its cleanup.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope pub <- rx_clone(input) |> rx_publish()
        var a <- rx_subscribe(pub,@(n:int){panic("old observer")},@(s:string){},@(){})
        var b <- rx_subscribe(pub,@(n:int){trace+="b{n};"},@(s:string){},@(){})
        var connection <- rx_connect(pub)
        var view <- rx_clone(pub)
        rx_add_cleanup(connection,@ capture(<-view) () {
            late <- rx_subscribe(view,@(n:int){trace+="late{n};"},@(s:string){},@(){})
            reconnect <- rx_connect(view)
        } finally {delete view})
        var caught=false
        try {rx_subject_next(input,1)} recover {caught=true}
        verify(caught && rx_is_closed(a) && rx_is_closed(b) && !rx_is_closed(reconnect) && !rx_is_closed(late))
        rx_subject_next(input,2);verify(trace=="b1;late2;" && rx_subscriber_count(input)==1)
        delete connection;delete a;delete b;delete reconnect;delete late
        verify(rx_subscriber_count(input)==0)
    }
    // Reentrant subscribers during synchronous connect don't connect twice.
    {
        factories=0;trace=""
        var inscope source <- rx_defer(@(){factories++;return <- rx_range(1,2)}) |> rx_publish() |> rx_ref_count()
        var view <- rx_clone(source)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            trace+="a{n};"
            if(n==1) {other <- rx_subscribe(view,@(v:int){trace+="b{v};"},@(s:string){panic(s)},@(){trace+="bc;"})}
        } finally {delete view},@(s:string){panic(s)},@(){trace+="ac;"})
        verify(factories==1 && trace=="a1;a2;b2;ac;bc;" && rx_is_closed(other))
        delete other
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)){checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX connectable/cache checks OK\n")
}
