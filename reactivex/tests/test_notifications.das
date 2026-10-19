options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var effects=0
var sink:typedecl(rx_sink_marker(type<int>))
var notificationSink:typedecl(rx_sink_marker(type<typedecl(rx_notification(type<int>))>))

def observe_values(source:auto) {
    return <- rx_subscribe(source,@(n:int){trace+="{n};"},@(s:string){trace+="error:{s};"},@(){trace+="done;"})
}
def observe_notifications(source:auto) {
    return <- rx_subscribe(source,@(e:typedecl(rx_notification(type<int>))) {
        if(e is next) {trace+="n{e as next};"}
        elif(e is error) {trace+="e:{e as error};"}
        else {trace+="c;"}
    },@(s:string){panic("unexpected on_error")},@(){trace+="done;"})
}
def checks() {
    verify(rx_notification(type<int>) is complete)
    verify(rx_notification_complete(type<int>) is complete)
    verify(rx_notification_next(42) as next==42)
    verify(rx_notification_error("",type<int>) is error)
    trace=""
    {
        var inscope source <- rx_range(1,2) |> rx_materialize()
        var inscope sub <- observe_notifications(source)
        verify(trace=="n1;n2;c;done;" && rx_is_closed(sub))
    }
    for(mode in range(3)) {
        trace=""
        var inscope source <- rx_empty(type<int>) |> rx_concat(rx_throw(mode==0 ? "failure" : "",type<int>)) |> rx_take(mode==2 ? 0 : 100) |> rx_materialize()
        var inscope sub <- observe_notifications(source)
        verify(trace==(mode==0 ? "e:failure;done;" : (mode==1 ? "e:;done;" : "c;done;")) && rx_is_closed(sub))
    }
    // Round-trip restores the source's values and terminal, for each subscription.
    for(mode in range(2)) {
        var inscope source <- rx_range(1,3) |> rx_concat(rx_throw("failure",type<int>)) |> rx_take(mode==0 ? 3 : 100) |> rx_materialize() |> rx_dematerialize()
        for(run in range(2)) {
            trace=""
            var inscope sub <- observe_values(source)
            verify(trace==(mode==0 ? "1;2;3;done;" : "1;2;3;error:failure;") && rx_is_closed(sub))
        }
    }
    // A terminal notification stops the synchronous source, without waiting for
    // its real complete. No values/effects after the terminal may be observed.
    for(mode in range(2)) {
        trace="";effects=0
        var inscope source <- rx_range(1,5) |> rx_tap(@(n:int){effects++}) |> rx_map(@ capture(copy(mode)) (n:int) {
            if(n==2) {
                if(mode==0) {return rx_notification_complete(type<int>)}
                return rx_notification_error("encoded",type<int>)
            }
            return rx_notification_next(n)
        }) |> rx_dematerialize()
        var inscope sub <- observe_values(source)
        verify(effects==2 && trace==(mode==0 ? "1;done;" : "1;error:encoded;") && rx_is_closed(sub))
    }
    // Real upstream terminals remain terminals even if no encoded one exists.
    for(mode in range(2)) {
        trace=""
        var inscope source <- rx_empty(type<typedecl(rx_notification(type<int>))>) |> rx_concat(rx_throw("upstream",type<typedecl(rx_notification(type<int>))>)) |> rx_take(mode==0 ? 0 : 100) |> rx_dematerialize()
        var inscope sub <- observe_values(source)
        verify(trace==(mode==0 ? "done;" : "error:upstream;") && rx_is_closed(sub))
    }
    // Reentrant custom producers cannot nest callbacks or overtake terminal data.
    trace=""
    {
        var inscope input <- rx_create(type<int>,@(s:typedecl(sink)){sink <- rx_sink_clone(s)})
        var inscope source <- rx_clone(input) |> rx_materialize()
        var inscope sub <- rx_subscribe(source,@(e:typedecl(rx_notification(type<int>))) {
            if(e is next) {
                trace+="start{e as next};"
                if(e as next==1) {rx_sink_next(sink,2);rx_sink_error(sink,"reentrant")}
                trace+="end{e as next};"
            } else {verify(e is error && e as error=="reentrant");trace+="encoded;"}
        },@(s:string){panic(s)},@(){trace+="done;"})
        rx_sink_next(sink,1)
        verify(trace=="start1;end1;start2;end2;encoded;done;" && rx_is_closed(sub));delete sink
    }
    trace=""
    {
        var inscope input <- rx_create(type<typedecl(rx_notification(type<int>))>,@(s:typedecl(notificationSink)){notificationSink <- rx_sink_clone(s)})
        var inscope source <- rx_clone(input) |> rx_dematerialize()
        var inscope sub <- rx_subscribe(source,@(n:int){trace+="start;";rx_sink_next(notificationSink,rx_notification_complete(type<int>));rx_sink_next(notificationSink,rx_notification_next(99));trace+="end;"},@(s:string){panic(s)},@(){trace+="done;"})
        rx_sink_next(notificationSink,rx_notification_next(1))
        verify(trace=="start;end;done;" && rx_is_closed(sub));delete notificationSink
    }
    // Notifications can be stored/delayed like ordinary owning values.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_materialize() |> rx_observe_on(clock) |> rx_dematerialize()
        var inscope sub <- rx_subscribe(source,@(s:string){trace+="{s};"},@(s:string){trace+="error:{s};"},@(){trace+="done;"})
        var text=clone_string("original")
        rx_subject_next(input,text);text="changed";rx_subject_error(input,"offline")
        verify(trace=="");rx_advance_to(clock,0)
        verify(trace=="original;error:offline;" && rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX notification tests OK\n")
}
