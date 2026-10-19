options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened:int[4]
var freed:int[4]
var completed=0
var errors=0
var cleanups=0
var cleanupFreed=0
var trace=""
var inCallback=false
struct Hold {
    side:int
    data:array<int>
    def finalize {if(!empty(data)) {freed[side]++;delete data}}
}
def hold(side:int) {
    opened[side]++
    return <- Hold(side=side,data <- [side,42])
}
def tracked(source:auto;side:int;fail:bool=false) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view,copy(side),copy(fail)) () {
        if(fail) {panic("source failed")}
        var resource <- hold(side)
        return <- rx_clone(view) |> rx_map(@ capture(<-resource) (n:int) {verify(resource.data[1]==42);return n} finally {delete resource})
    } finally {delete view})
}
def selector(first,second:auto;mode:int;switching:bool) {
    var a <- rx_clone(first);var b <- rx_clone(second)
    var data <- hold(3)
    return <- @ capture(<-a,<-b,<-data,copy(mode),copy(switching)) (n:int) {
        verify(data.data[1]==42)
        if(n==1) {return <- tracked(a,1)}
        verify(rx_subscriber_count(a)==(switching ? 0 : 1))
        // When the previous inner is idle, switch frees its resource before projection.
        if(switching) {verify(opened[1]==freed[1])}
        if(mode==9) {panic("source failed")}
        return <- tracked(b,2,mode==11)
    } finally {delete a;delete b;delete data}
}
def compose(var source,project:auto;tag:RxSwitchMapTag) {return <- source |> rx_switch_map(project)}
def compose(var source,project:auto;tag:RxFlatMapTag) {return <- source |> rx_flat_map(project)}
def cleanup_action(fail:bool) {
    var data:array<int>;data <- [1,2]
    return <- @ capture(<-data,copy(fail)) () {verify(length(data)==2);cleanups++;if(fail) {panic("cleanup failed")}} finally {delete data;cleanupFreed++}
}
def checks(tag:auto;switching:bool) {
    for(mode in range(13)) {
        let oldDone=completed
        let oldErrors=errors
        let oldCleanup=cleanups
        let oldCleanupFreed=cleanupFreed
        var inscope outer <- rx_subject(type<int>)
        var inscope first <- rx_subject(type<int>)
        var inscope second <- rx_subject(type<int>)
        var source <- compose(tracked(outer,0),selector(first,second,mode,switching),tag) |> rx_take(mode==10 ? 1 : 100)
        var ov <- rx_clone(outer);var av <- rx_clone(first);var bv <- rx_clone(second)
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int) {if(mode==5) {panic("next failed")}},
            @ capture(<-ov,<-av,<-bv,copy(mode)) (message:string) {
                verify(message=="source failed" || mode==9 || mode==11)
                verify(rx_subscriber_count(ov)==0 && rx_subscriber_count(av)==0 && rx_subscriber_count(bv)==0)
                errors++;if(mode==6) {panic("error callback failed")}
            } finally {delete ov;delete av;delete bv},@ capture(copy(mode)) () {completed++;if(mode==7) {panic("complete callback failed")}})
        delete source // the subscription now owns the selector and all its captures.
        rx_add_cleanup(sub,cleanup_action(mode==8 || mode==12))
        rx_add_cleanup(sub,cleanup_action(false))
        rx_subject_next(outer,1)
        rx_subject_next(outer,2)
        if(mode==9 || mode==11) {verify(rx_is_closed(sub))}
        var caught=false
        try {
            if(mode==0 || mode==7) {
                rx_subject_complete(outer);verify(opened[0]==freed[0])
                rx_subject_next(second,20);rx_subject_complete(second);rx_subject_complete(first)
            } elif(mode==1 || mode==8) {rx_unsubscribe(sub)}
            elif(mode==2) {delete sub}
            elif(mode==3) {rx_subject_error(outer,"source failed")}
            elif(mode==4 || mode==6 || mode==12) {rx_subject_error(second,"source failed")}
            elif(mode==5 || mode==10) {rx_subject_next(second,20)}
        } recover {caught=true}
        verify(caught==(mode==5 || mode==6 || mode==7 || mode==8 || mode==12))
        if(mode!=2) {verify(rx_is_closed(sub));delete sub}
        verify(rx_subscriber_count(outer)==0 && rx_subscriber_count(first)==0 && rx_subscriber_count(second)==0)
        for(i in range(4)) {verify(opened[i]==freed[i])}
        verify(completed==oldDone+((mode==0 || mode==7 || mode==10) ? 1 : 0))
        verify(errors==oldErrors+((mode==3 || mode==4 || mode==6 || mode==9 || mode==11 || mode==12) ? 1 : 0))
        verify(cleanups==oldCleanup+2 && cleanupFreed==oldCleanupFreed+2)
    }
    // Reentrant error cancels all children immediately, but waits to deliver error.
    {
        trace=""
        var inscope outer <- rx_subject(type<int>)
        var inscope first <- rx_subject(type<int>)
        var inscope second <- rx_subject(type<int>)
        var a <- rx_clone(first);var b <- rx_clone(second)
        var project <- @ capture(<-a,<-b) (n:int) {if(n==1) {return <- tracked(a,1)};return <- tracked(b,2)} finally {delete a;delete b}
        var inscope source <- compose(tracked(outer,0),project,tag)
        var ov <- rx_clone(outer);var av <- rx_clone(first);var bv <- rx_clone(second)
        var inscope sub <- rx_subscribe(source,@ capture(<-ov,<-av,<-bv,copy(switching)) (n:int) {
            verify(!inCallback);inCallback=true;trace+="next;"
            let before=freed[1]
            rx_subject_next(ov,2)
            // The old active callback remains alive after switch detaches it.
            verify(freed[1]==before && rx_subscriber_count(av)==(switching ? 0 : 1))
            rx_subject_next(bv,20);rx_subject_error(bv,"reentrant error")
            verify(trace=="next;" && rx_subscriber_count(ov)==0 && rx_subscriber_count(av)==0 && rx_subscriber_count(bv)==0)
            trace+="return;";inCallback=false
        } finally {delete ov;delete av;delete bv},@(message:string) {verify(!inCallback && message=="reentrant error");trace+="error;"},@(){panic("unexpected complete")})
        rx_subject_next(outer,1);rx_subject_next(first,10)
        verify(trace=="next;return;error;" && rx_is_closed(sub))
        for(i in range(4)) {verify(opened[i]==freed[i])}
    }
    // Large batches of synchronous inner completion must not retain child leases.
    {
        var inscope source <- compose(rx_range(1,200),@(n:int) {
            var resource <- hold(1)
            return <- rx_range(n,1) |> rx_map(@ capture(<-resource) (v:int) {return v} finally {delete resource})
        },tag)
        var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic(s)},@(){})
        verify(rx_is_closed(sub))
        for(i in range(4)) {verify(opened[i]==freed[i])}
    }
}
[export]
def main() {
    checks(RxSwitchMapTag(),true);checks(RxFlatMapTag(),false)
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks(RxSwitchMapTag(),true);checks(RxFlatMapTag(),false)}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX switch_map/flat_map lifetime checks OK\n")
}
