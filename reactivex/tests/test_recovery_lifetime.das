options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened:int[4]
var freed:int[4]
var attempts=0
var errors=0
var completed=0
var handlers=0
var cleanups=0
var trace=""
var inCallback=false
struct Hold {
    side:int
    data:array<int>
    def finalize {if(!empty(data)) {freed[side]++;delete data}}
}
def hold(side:int) {opened[side]++;return <- Hold(side=side,data <- [42])}
def tracked(source:auto;side:int) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view,copy(side)) () {
        var data <- hold(side)
        return <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.data[0]==42);return n} finally {delete data})
    } finally {delete view})
}
def cleanup(fail:bool) {return <- @ capture(copy(fail)) () {cleanups++;if(fail) {panic("cleanup failed")}}}
def catch_checks() {
    for(mode in range(11)) {
        let oldErrors=errors
        let oldDone=completed
        let oldCleanups=cleanups
        handlers=0
        var inscope first <- rx_subject(type<int>)
        var inscope backup <- rx_subject(type<int>)
        var firstView <- rx_clone(first);var next <- rx_clone(backup)
        var factoryData <- hold(2)
        var source <- tracked(first,0) |> rx_catch_error(@ capture(<-firstView,<-next,<-factoryData,copy(mode)) (message:string) {
            verify(factoryData.data[0]==42 && rx_subscriber_count(firstView)==0)
            handlers++;if(mode==9) {panic("handler failed")}
            return <- tracked(next,1)
        } finally {delete firstView;delete next;delete factoryData})
        var a <- rx_clone(first);var b <- rx_clone(backup)
        var consumerData <- hold(3)
        var sub <- rx_subscribe(source,@ capture(<-consumerData,copy(mode)) (n:int) {
            verify(consumerData.data[0]==42);if(mode==4 && n==10) {panic("consumer failed")}
        } finally {delete consumerData},@ capture(<-a,<-b,copy(mode)) (s:string) {
            verify(rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0);errors++
            if(mode==5) {panic("error callback failed")}
        } finally {delete a;delete b},@ capture(copy(mode)) () {completed++;if(mode==6) {panic("complete callback failed")}})
        delete source
        rx_add_cleanup(sub,cleanup(mode==7));rx_add_cleanup(sub,cleanup(false))
        var caught=false
        try {
            if(mode==1 || mode==7) {rx_unsubscribe(sub)}
            elif(mode==8) {delete sub}
            elif(mode==10) {rx_subject_complete(first)}
            else {
                rx_subject_next(first,1);rx_subject_error(first,"first failed")
                if(mode==2) {rx_unsubscribe(sub)}
                elif(mode==3 || mode==5) {rx_subject_error(backup,"backup failed")}
                elif(mode!=9) {rx_subject_next(backup,10);rx_subject_complete(backup)}
            }
        } recover {caught=true}
        verify(caught==(mode==4 || mode==5 || mode==6 || mode==7))
        if(mode!=8) {verify(rx_is_closed(sub));delete sub}
        verify(rx_subscriber_count(first)==0 && rx_subscriber_count(backup)==0)
        for(i in range(4)) {verify(opened[i]==freed[i])}
        verify(handlers==((mode==1 || mode==7 || mode==8 || mode==10) ? 0 : 1))
        verify(errors==oldErrors+((mode==3 || mode==5 || mode==9) ? 1 : 0))
        verify(completed==oldDone+((mode==0 || mode==6 || mode==10) ? 1 : 0) && cleanups==oldCleanups+2)
    }
    // A synchronous failed connection fully unwinds before the handler runs.
    {
        var inscope source <- rx_defer(@(){
            var data <- hold(0)
            return <- rx_just(1) |> rx_map(@ capture(<-data) (n:int) {verify(data.data[0]==42);panic("failure");return n} finally {delete data})
        }) |> rx_catch_error(@(s:string) {verify(opened[0]==freed[0]);return <- rx_just(9)})
        var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==9)},@(s:string) {panic(s)},@(){})
        verify(rx_is_closed(sub))
    }
}
def retry_checks() {
    for(mode in range(10)) {
        attempts=0
        let oldErrors=errors
        let oldDone=completed
        var inscope clock <- rx_virtual_scheduler()
        if(mode==9) {rx_scheduler_close(clock)}
        var source <- rx_defer(@ capture(copy(mode)) () {
            verify(opened[0]==freed[0]) // previous attempt's captures are gone.
            attempts++
            let attempt=attempts
            var data <- hold(0)
            return <- rx_range(1,2) |> rx_map(@ capture(<-data,copy(attempt),copy(mode)) (n:int) {
                verify(data.data[0]==42)
                if(n==2 && (attempt<3 || mode==1 || mode==6)) {panic("attempt failed")}
                return attempt*10+n
            } finally {delete data})
        }) |> rx_retry(2,5,clock)
        var sub <- rx_subscription()
        var data <- hold(3)
        var caught=false
        try {
            rx_subscribe_with(sub,source,@ capture(<-data,copy(mode)) (n:int) {verify(data.data[0]==42);if(mode==5) {panic("next failed")}} finally {delete data},
                @ capture(copy(mode)) (s:string) {errors++;if(mode==6) {panic("error callback failed")}},
                @ capture(copy(mode)) () {completed++;if(mode==7) {panic("complete callback failed")}})
            if(mode==2 || mode==8) {
                if(mode==8) {rx_add_cleanup(sub,cleanup(true));rx_add_cleanup(sub,cleanup(false))}
                rx_unsubscribe(sub)
            } elif(mode==3) {delete sub}
            elif(mode==4) {rx_scheduler_close(clock)}
            else {rx_advance_by(clock,10)}
        } recover {caught=true}
        delete source
        verify(caught==(mode==5 || mode==6 || mode==7 || mode==8))
        if(mode!=3) {verify(rx_is_closed(sub));delete sub}
        verify(attempts==((mode==9) ? 0 : ((mode==0 || mode==1 || mode==6 || mode==7) ? 3 : 1)))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        verify(errors==oldErrors+((mode==1 || mode==4 || mode==6 || mode==9) ? 1 : 0))
        verify(completed==oldDone+((mode==0 || mode==7) ? 1 : 0))
        for(i in range(4)) {verify(opened[i]==freed[i])}
    }
    // Shutdown while an on_next is active is delivered as a serialized error.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_just(1) |> rx_retry(2,0,clock)
        var view <- rx_scheduler_clone(clock)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(!inCallback);inCallback=true;trace+="next;"
            rx_scheduler_close(view);verify(trace=="next;")
            trace+="return;";inCallback=false
        } finally {delete view},@(s:string) {verify(!inCallback && s=="rx scheduler closed");trace+="error;"},@(){panic("unexpected complete")})
        verify(trace=="next;return;error;" && rx_is_closed(sub) && rx_close_listener_count(clock)==0)
    }
    // A teardown exception is not a new on_error: both cleanup actions run,
    // the connection closes, and neither retry nor fallback is invoked.
    {
        handlers=0
        let before=cleanups
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,cleanup(true))
            rx_sink_add_cleanup(sink,cleanup(false))
            rx_sink_error(sink,"source failed")
        }) |> rx_retry(2,0,clock) |> rx_catch_error(@(s:string) {handlers++;return <- rx_just(1)})
        var caught=false
        try {var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic("unexpected on_error")},@(){})} recover {caught=true}
        verify(caught && handlers==0 && cleanups==before+2 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    catch_checks();retry_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {catch_checks();retry_checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX recovery lifetime checks OK\n")
}
