options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened:int[2]
var freed:int[2]
var completed=0
var errors=0
var cleanupRuns=0
var cleanupFreed=0
var trace=""
var inCallback=false
struct Hold {
    side:int
    data:array<int>
    def finalize {if(!empty(data)) {freed[side]++;delete data}}
}
def tracked(source:auto;side:int) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view,copy(side)) () {
        opened[side]++
        var resource:Hold
        resource.side=side;resource.data <- [side,42]
        return <- rx_clone(view) |> rx_map(@ capture(<-resource) (n:int) {verify(resource.data[1]==42);return n} finally {delete resource})
    } finally {delete view})
}
def compose(left,right:auto;tag:RxLatestTag) {return <- tracked(left,0) |> rx_combine_latest(tracked(right,1))}
def compose(left,right:auto;tag:RxZipTag) {return <- tracked(left,0) |> rx_zip(tracked(right,1))}
def cleanup_action(fail:bool) {
    var data:array<int>;data <- [1,2]
    return <- @ capture(<-data,copy(fail)) () {
        verify(length(data)==2);cleanupRuns++
        if(fail) {panic("cleanup failed")}
    } finally {delete data;cleanupFreed++}
}
def checks(tag:auto) {
    for(mode in range(11)) {
        let oldDone=completed
        let oldErrors=errors
        let oldRuns=cleanupRuns
        let oldFreed=cleanupFreed
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var source <- compose(left,right,tag)
        var av <- rx_clone(left)
        var bv <- rx_clone(right)
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (v:tuple<first:int;second:int>) {
            if(mode==5) {panic("consumer failed")}
        },@ capture(<-av,<-bv,copy(mode)) (message:string) {
            verify(rx_subscriber_count(av)==0 && rx_subscriber_count(bv)==0)
            verify(message=="source failed")
            errors++;if(mode==6) {panic("error callback failed")}
        } finally {delete av;delete bv},@ capture(copy(mode)) () {completed++;if(mode==9) {panic("complete callback failed")}})
        // The active run must survive deletion of its public descriptor.
        delete source
        rx_add_cleanup(sub,cleanup_action(mode==7))
        rx_add_cleanup(sub,cleanup_action(false))
        rx_subject_next(left,1);rx_subject_next(left,2)
        var caught=false
        try {
            if(mode==0 || mode==9) {
                rx_subject_next(right,10);rx_subject_next(right,11)
                rx_subject_complete(left);rx_subject_complete(right)
            } elif(mode==1 || mode==7) {rx_unsubscribe(sub)}
            elif(mode==2) {rx_subject_complete(left);rx_unsubscribe(sub)}
            elif(mode==3 || mode==6) {rx_subject_error(left,"source failed")}
            elif(mode==4) {rx_subject_error(right,"source failed")}
            elif(mode==5) {rx_subject_next(right,10)}
            elif(mode==8) {delete sub}
            else {
                // on_error receives the source message before a root cleanup failure.
                var extra <- cleanup_action(true)
                // Root cleanup failure must not replace on_error's source message.
                rx_add_cleanup(sub,extra)
                rx_subject_error(left,"source failed")
            }
        } recover {caught=true}
        verify(caught==(mode==5 || mode==6 || mode==7 || mode==9 || mode==10))
        if(mode!=8) {verify(rx_is_closed(sub));delete sub}
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
        verify(opened[0]==freed[0] && opened[1]==freed[1])
        verify(completed==oldDone+((mode==0 || mode==9) ? 1 : 0))
        verify(errors==oldErrors+((mode==3 || mode==4 || mode==6 || mode==10) ? 1 : 0))
        verify(cleanupRuns==oldRuns+2+(mode==10 ? 1 : 0) && cleanupFreed==oldFreed+2+(mode==10 ? 1 : 0))
    }
    // Cancellation in a callback discards queued pairs and detaches both inputs.
    {
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag) |> rx_take(1)
        var inscope sub <- rx_subscribe(source,@(v:tuple<first:int;second:int>) {},@(message:string) {panic(message)},@(){})
        rx_subject_next(a,1);rx_subject_next(b,10)
        verify(rx_is_closed(sub) && rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0)
        verify(opened[0]==freed[0] && opened[1]==freed[1])
    }
    // Cross-source errors cancel immediately, drop pending pairs, and serialize error.
    {
        trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var av <- rx_clone(a)
        var inscope sub <- rx_subscribe(source,@ capture(<-av) (v:tuple<first:int;second:int>) {
            verify(!inCallback);inCallback=true;trace+="next;"
            rx_subject_next(av,2);rx_subject_error(av,"failure")
            verify(rx_subscriber_count(av)==0 && trace=="next;")
            trace+="return;";inCallback=false
        } finally {delete av},@(message:string) {verify(!inCallback && message=="failure");trace+="error;"},@(){panic("unexpected complete")})
        rx_subject_next(a,1);rx_subject_next(b,10)
        verify(trace=="next;return;error;" && rx_is_closed(sub))
        verify(rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0)
        verify(opened[0]==freed[0] && opened[1]==freed[1])
    }
    // Empty first input prevents acquiring any resources on the second input.
    {
        let before=opened[1]
        var inscope a <- rx_range(0,0)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var inscope sub <- rx_subscribe(source,@(v:tuple<first:int;second:int>) {panic("unexpected next")},@(s:string) {panic(s)},@(){})
        verify(rx_is_closed(sub) && opened[1]==before && rx_subscriber_count(b)==0)
        verify(opened[0]==freed[0] && opened[1]==freed[1])
    }
}
[export]
def main() {
    checks(RxLatestTag());checks(RxZipTag())
    let baseline=heap_bytes_allocated()
    for(i in range(12)) {checks(RxLatestTag());checks(RxZipTag())}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX combine_latest/zip lifetime checks OK\n")
}
