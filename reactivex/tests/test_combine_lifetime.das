options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened:int[2]
var closed:int[2]
var completed=0
var errors=0
var cleanupRuns=0
var cleanupFreed=0
var inCallback=false
var trace=""
struct Hold {
    side:int
    data:array<int>
    def finalize {if(!empty(data)) {closed[side]++;delete data}}
}
def tracked(source:auto;side:int) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view,copy(side)) () {
        opened[side]++
        var resource:Hold
        resource.side=side;resource.data <- [side,42]
        var selector <- @ capture(<-resource) (n:int) {verify(resource.data[1]==42);return n} finally {delete resource}
        return <- rx_clone(view) |> rx_map(selector)
    } finally {delete view})
}
def cleanup_action(fail:bool=false) {
    var data:array<int>
    data <- [1,2]
    return <- @ capture(<-data,copy(fail)) () {
        verify(length(data)==2);cleanupRuns++
        if(fail) {panic("parent cleanup failed")}
    } finally {delete data;cleanupFreed++}
}
def pair_checks(source:auto;left,right:auto;mode:int;concat:bool) {
    let done=completed
    let failed=errors
    let frees=cleanupFreed
    let runs=cleanupRuns
    let leftOpened=opened[0]
    let rightOpened=opened[1]
    var leftView <- rx_clone(left)
    var rightView <- rx_clone(right)
    var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int) {if(mode==5) {panic("consumer failed")}},
        @ capture(copy(mode),<-leftView,<-rightView) (message:string) {
            verify(rx_subscriber_count(leftView)==0 && rx_subscriber_count(rightView)==0)
            errors++;if(mode==6) {panic("error observer failed")}
        } finally {delete leftView;delete rightView},@(){completed++})
    rx_add_cleanup(sub,cleanup_action(mode==7))
    rx_add_cleanup(sub,cleanup_action())
    verify(opened[0]==leftOpened+1 && opened[1]==rightOpened+(concat ? 0 : 1))
    if(mode==0) {rx_subject_complete(left);verify(closed[0]==opened[0]);rx_subject_complete(right)}
    elif(mode==1) {rx_unsubscribe(sub)}
    elif(mode==2) {rx_subject_complete(left);verify(closed[0]==opened[0]);rx_unsubscribe(sub)}
    elif(mode==3) {rx_subject_error(left,"left failed")}
    elif(mode==4) {rx_subject_complete(left);rx_subject_error(right,"right failed")}
    elif(mode==5 || mode==6 || mode==7) {
        var caught=false
        try {
            if(mode==5) {rx_subject_next(left,1)}
            elif(mode==6) {rx_subject_error(left,"left failed")}
            else {rx_unsubscribe(sub)}
        } recover {caught=true}
        verify(caught)
    } else {delete sub}
    if(mode!=8) {verify(rx_is_closed(sub));delete sub}
    verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
    verify(opened[0]==closed[0] && opened[1]==closed[1])
    verify(completed==done+(mode==0 ? 1 : 0))
    verify(errors==failed+((mode==3 || mode==4 || mode==6) ? 1 : 0))
    verify(cleanupFreed==frees+2 && cleanupRuns==runs+2)
    if(concat && (mode==1 || mode==3 || mode==5 || mode==6 || mode==7 || mode==8)) {verify(opened[1]==rightOpened)}
}
def checks() {
    for(mode in range(9)) {
        for(kind in range(2)) {
            var inscope left <- rx_subject(type<int>)
            var inscope right <- rx_subject(type<int>)
            if(kind==0) {
                var inscope source <- tracked(left,0) |> rx_merge(tracked(right,1))
                pair_checks(source,left,right,mode,false)
            } else {
                var inscope source <- tracked(left,0) |> rx_concat(tracked(right,1))
                pair_checks(source,left,right,mode,true)
            }
        }
    }
    // Cross-source reentrancy is serialized by the join, not just each Subject.
    {
        trace=""
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
        var view <- rx_clone(right)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(!inCallback);inCallback=true
            trace+="{n};"
            if(n==1) {rx_subject_next(view,2);verify(trace=="1;")}
            inCallback=false
        } finally {delete view},@(message:string) {errors++},@(){completed++})
        rx_subject_next(left,1)
        verify(trace=="1;2;")
        rx_unsubscribe(sub)
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
    }
    // An already queued value precedes completion; neither terminal callback
    // can reenter the downstream observer while its on_next is executing.
    {
        trace=""
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
        var leftView <- rx_clone(left)
        var rightView <- rx_clone(right)
        var inscope sub <- rx_subscribe(source,@ capture(<-leftView,<-rightView) (n:int) {
            verify(!inCallback);inCallback=true;trace+="{n};"
            if(n==1) {rx_subject_next(rightView,2);rx_subject_complete(leftView);rx_subject_complete(rightView)}
            inCallback=false
        } finally {delete leftView;delete rightView},@(message:string) {panic(message)},@(){verify(!inCallback);trace+="done;"})
        rx_subject_next(left,1)
        verify(trace=="1;2;done;" && rx_is_closed(sub))
    }
    // Downstream take detaches hot inputs too, including a concat second source
    // which has not yet been connected.
    for(kind in range(2)) {
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        if(kind==0) {
            var inscope source <- tracked(left,0) |> rx_merge(tracked(right,1)) |> rx_take(1)
            var inscope sub <- rx_subscribe(source,@(n:int) {},@(message:string) {panic(message)},@(){})
            rx_subject_next(left,1)
            verify(rx_is_closed(sub))
        } else {
            var inscope source <- tracked(left,0) |> rx_concat(tracked(right,1)) |> rx_take(1)
            var inscope sub <- rx_subscribe(source,@(n:int) {},@(message:string) {panic(message)},@(){})
            rx_subject_next(left,1)
            verify(rx_is_closed(sub))
        }
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
        verify(opened[0]==closed[0] && opened[1]==closed[1])
    }
    // A reentrant error cancels both sources immediately, drops queued values,
    // then notifies on_error after the current on_next has returned.
    {
        trace=""
        let failed=errors
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
        var view <- rx_clone(right)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(!inCallback);inCallback=true;trace+="n;"
            rx_subject_next(view,2)
            rx_subject_error(view,"reentrant failure")
            verify(errors==failed && rx_subscriber_count(view)==0)
            trace+="return;";inCallback=false
        } finally {delete view},@(message:string) {verify(!inCallback);errors++;trace+="error;"},@(){panic("unexpected complete")})
        rx_subject_next(left,1)
        verify(trace=="n;return;error;" && errors==failed+1 && rx_is_closed(sub))
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(12)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX merge/concat lifetime checks OK\n")
}
