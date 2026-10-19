options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var errors=0
var completed=0
var cleanups=0
var callbacksFreed=0
var inCallback=false
var trace=""
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        opened++
        var resource=Hold();resource.data <- [42]
        return <- rx_clone(view) |> rx_map(@ capture(<-resource) (n:int) {verify(resource.data[0]==42);return n} finally {delete resource})
    } finally {delete view})
}
def timed(source:auto;mode:int;clock:RxScheduler) {
    if(mode==0) {return <- tracked(source) |> rx_delay(10,clock)}
    if(mode==1) {return <- tracked(source) |> rx_debounce(10,clock)}
    return <- tracked(source) |> rx_timeout(10,clock)
}
def cleanup_action(fail:bool) {return <- @ capture(copy(fail)) () {cleanups++;if(fail) {panic("cleanup failed")}}}
def checks() {
    for(mode in range(3)) {
        for(caseId in range(10)) {
            let oldErrors=errors
            let oldDone=completed
            let oldCleanups=cleanups
            var inscope clock <- rx_virtual_scheduler()
            var inscope input <- rx_subject(type<int>)
            var source <- timed(input,mode,clock) |> rx_take(caseId==8 ? 1 : 100)
            var view <- rx_clone(input)
            var sub <- rx_subscribe(source,@ capture(copy(caseId)) (n:int) {if(caseId==4) {panic("next callback failed")}},
                @ capture(<-view,copy(caseId)) (message:string) {verify(rx_subscriber_count(view)==0);errors++;if(caseId==5) {panic("error callback failed")}} finally {delete view},
                @ capture(copy(caseId)) () {completed++;if(caseId==6) {panic("complete callback failed")}})
            delete source
            rx_add_cleanup(sub,cleanup_action(caseId==9))
            rx_add_cleanup(sub,cleanup_action(false))
            var caught=false
            try {
                if(caseId==1 || caseId==9) {rx_subject_next(input,1);rx_unsubscribe(sub)}
                elif(caseId==2) {rx_subject_next(input,1);delete sub}
                elif(caseId==3 || caseId==5) {rx_subject_error(input,"source failed")}
                elif(caseId==7) {rx_subject_next(input,1);rx_scheduler_close(clock)}
                else {
                    rx_subject_next(input,1)
                    if(caseId==0 || caseId==6) {rx_subject_complete(input)}
                    rx_advance_to(clock,10)
                }
            } recover {caught=true}
            verify(caught==(caseId==4 || caseId==5 || caseId==6 || caseId==9))
            if(caseId!=2) {verify(rx_is_closed(sub));delete sub}
            verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0 && rx_subscriber_count(input)==0 && opened==freed)
            verify(errors==oldErrors+((caseId==3 || caseId==5 || caseId==7) ? 1 : 0))
            verify(completed==oldDone+((caseId==0 || caseId==6 || caseId==8) ? 1 : 0))
            verify(cleanups==oldCleanups+2)
        }
    }
    // An observer exception releases the timer's owning callbacks immediately.
    for(kind in range(2)) {
        var inscope clock <- rx_virtual_scheduler()
        var source <- rx_timer(1,clock)
        if(kind==1) {delete source;source <- rx_interval(1,clock)}
        var data:array<int>;data <- [42]
        let before=callbacksFreed
        var inscope sub <- rx_subscribe(source,@ capture(<-data) (n:int64) {verify(data[0]==42);panic("timer callback failed")} finally {delete data;callbacksFreed++},
            @(s:string) {panic(s)},@(){})
        var caught=false
        try {rx_advance_to(clock,1)} recover {caught=true}
        verify(caught && rx_is_closed(sub) && rx_pending_count(clock)==0 && callbacksFreed==before+1)
        delete source
    }
    // Completion flushing debounce is serialized with the active timeout next.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_timeout(10,clock)
        var view <- rx_clone(input)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(!inCallback);inCallback=true;trace+="next;"
            rx_subject_complete(view);trace+="return;";inCallback=false
        } finally {delete view},@(s:string) {panic(s)},@(){verify(!inCallback);trace+="done;"})
        rx_subject_next(input,1)
        verify(trace=="next;return;done;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    // Deleting the scheduler's primary owner closes active timed subscriptions.
    {
        var clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_timeout(10,clock)
        var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {verify(s=="rx scheduler closed")},@(){})
        delete clock
        verify(rx_is_closed(sub) && rx_subscriber_count(input)==0)
    }
    // Idle delay/debounce still subscribe to scheduler shutdown, without a timer.
    for(mode in range(2)) {
        for(stage in range(2)) {
            var clock <- rx_virtual_scheduler()
            var inscope clockView <- rx_scheduler_clone(clock)
            var inscope input <- rx_subject(type<int>)
            var inscope source <- timed(input,mode,clock)
            let before=errors
            var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {verify(s=="rx scheduler closed");errors++},@(){})
            if(stage==1) {rx_subject_next(input,1);rx_advance_to(clock,10)}
            verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==1 && rx_subscriber_count(input)==1)
            delete clock
            verify(errors==before+1 && rx_is_closed(sub) && rx_subscriber_count(input)==0 && opened==freed)
            verify(rx_close_listener_count(clockView)==0 && rx_pending_count(clockView)==0)
        }
    }
    for(fail in range(2)) {
        var inscope clock <- rx_virtual_scheduler()
        rx_scheduler_close(clock)
        var inscope source <- rx_timer(1,clock)
        var caught=false
        try {
            var inscope sub <- rx_subscribe(source,@(n:int64) {panic("unexpected next")},@ capture(copy(fail)) (s:string) {
                verify(s=="rx scheduler closed");if(fail==1) {panic("closed callback failed")}
            },@(){panic("unexpected complete")})
            verify(rx_is_closed(sub))
        } recover {caught=true}
        verify(caught==(fail==1) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX timed lifetime checks OK\n")
}
