options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var calls=""
var errors=0
var completed=0
var opened=0
var freed=0
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        var data <- hold()
        return <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.data[0]==42);return n} finally {delete data})
    } finally {delete view})
}
def flatten(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var selector:lambda<(value:T):auto>;parallel:bool;policy:RxOverflowPolicy) {
    if(parallel) {return <- source |> rx_flat_map(selector,2,rx_queue(2,policy))}
    return <- source |> rx_concat_map(selector,rx_queue(2,policy))
}
def flat_checks() {
    for(parallelId in range(2)) {
        let parallel=parallelId==1
        for(policyId in range(3)) {
            let policy=(policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest))
            for(mode in range(5)) {
                trace="";calls="";errors=0;completed=0
                var inscope clock <- rx_virtual_scheduler()
                var inscope input <- rx_subject(type<int>)
                var view <- rx_scheduler_clone(clock)
                var source <- flatten(tracked(input),@ capture(<-view) (n:int) {
                    calls+="{n};"
                    var data <- hold()
                    return <- rx_timer(1,view) |> rx_map(@ capture(<-data,copy(n)) (tick:int64) {verify(data.data[0]==42);return n} finally {delete data})
                } finally {delete view},parallel,policy)
                var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int) {trace+="{n};";if(mode==3) {panic("consumer failed")}},
                    @ capture(copy(mode)) (s:string) {verify(s=="rx_flat_map: queue overflow" || s=="source failed");errors++;if(mode==4) {panic("error callback failed")}},@() {completed++})
                delete source
                var caught=false
                try {
                    for(n in range(1,7)) {rx_subject_next(input,n)}
                    if(mode==1) {rx_unsubscribe(sub)}
                    elif(mode==2) {rx_subject_error(input,"source failed")}
                    else {rx_subject_complete(input);rx_advance_by(clock,10)}
                } recover {caught=true}
                verify(caught==((policy==RxOverflowPolicy.error && mode==4) || (policy!=RxOverflowPolicy.error && (mode==3))))
                verify(rx_is_closed(sub) && rx_subscriber_count(input)==0)
                verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
                if(policy==RxOverflowPolicy.error) {verify(errors==1 && trace=="" && calls==(parallel ? "1;2;" : "1;"))}
                elif(mode==0 || mode==4) {
                    let expected=policy==RxOverflowPolicy.drop_oldest ? (parallel ? "1;2;5;6;" : "1;5;6;") : (parallel ? "1;2;3;4;" : "1;2;3;")
                    verify(trace==expected && calls==expected && completed==1 && errors==0)
                } elif(mode==1 || mode==2) {verify(trace=="" && errors==(mode==2 ? 1 : 0))}
                delete sub
                verify(opened==freed)
            }
        }
    }
}
def zip_checks() {
    for(sideId in range(2)) {
        let leftFast=sideId==0
        for(policyId in range(3)) {
            let policy=(policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest))
            for(mode in range(4)) {
                trace="";errors=0;completed=0
                var inscope left <- rx_subject(type<int>)
                var inscope right <- rx_subject(type<int>)
                var source <- tracked(left) |> rx_zip(tracked(right),rx_queue(2,policy))
                var sub <- rx_subscribe(source,@ capture(copy(mode)) (v:tuple<first:int;second:int>) {trace+="{v.first}:{v.second};";if(mode==3) {panic("consumer failed")}},
                    @(s:string) {verify(s=="rx_zip: queue overflow" || s=="source failed");errors++},@() {completed++})
                delete source
                var caught=false
                try {
                    for(n in range(1,5)) {if(leftFast) {rx_subject_next(left,n)} else {rx_subject_next(right,n)}}
                    if(mode==1) {rx_unsubscribe(sub)}
                    elif(mode==2) {rx_subject_error(right,"source failed")}
                    else {
                        for(n in range(10,12)) {if(leftFast) {rx_subject_next(right,n)} else {rx_subject_next(left,n)}}
                        rx_subject_complete(left);rx_subject_complete(right)
                    }
                } recover {caught=true}
                verify(caught==(policy!=RxOverflowPolicy.error && mode==3))
                if(policy==RxOverflowPolicy.error) {verify(errors==1 && trace=="")}
                elif(mode==0) {
                    let expected=policy==RxOverflowPolicy.drop_oldest ? (leftFast ? "3:10;4:11;" : "10:3;11:4;") : (leftFast ? "1:10;2:11;" : "10:1;11:2;")
                    verify(trace==expected && completed==1)
                }
                verify(rx_is_closed(sub) && rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
                delete sub;verify(opened==freed)
            }
        }
    }
    // Synchronous overflow must not start the second source at all.
    calls="";errors=0
    var source <- rx_range(0,5) |> rx_zip(rx_defer(@() {calls+="right;";return <- rx_just(1)}),rx_queue(1))
    var sub <- rx_subscribe(source,@(v:tuple<first:int;second:int>) {panic("unexpected")},@(s:string) {errors++},@() {})
    verify(calls=="" && errors==1 && rx_is_closed(sub))
    delete sub;delete source
}
def delay_checks() {
    for(policyId in range(3)) {
            let policy=(policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest))
        for(mode in range(7)) {
            trace="";errors=0;completed=0
            var inscope clock <- rx_virtual_scheduler()
            var inscope input <- rx_subject(type<int>)
            var source <- tracked(input) |> rx_delay(10,clock,rx_queue(2,policy))
            var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int) {trace+="{n};";if(mode==3) {panic("consumer failed")}},
                @ capture(copy(mode)) (s:string) {verify(s=="rx_delay: queue overflow" || s=="source failed" || s=="rx scheduler closed");errors++;if(mode==4) {panic("error callback failed")}},@() {completed++})
            delete source
            var caught=false
            try {
                for(n in range(1,5)) {rx_subject_next(input,n);verify(rx_pending_count(clock)<=2)}
                if(mode==1) {rx_unsubscribe(sub)}
                elif(mode==2 || mode==4) {rx_subject_error(input,"source failed")}
                elif(mode==5) {rx_scheduler_close(clock)}
                else {
                    rx_subject_complete(input)
                    verify(rx_pending_count(clock)==(policy==RxOverflowPolicy.error ? 0 : 3)) // two values + terminal
                    if(mode==6) {rx_unsubscribe(sub)} else {rx_advance_by(clock,10)}
                }
            } recover {caught=true}
            verify(caught==(mode==4 || (policy!=RxOverflowPolicy.error && mode==3)))
            if(policy==RxOverflowPolicy.error) {verify(errors==1 && trace=="")}
            elif(mode==0) {verify(trace==(policy==RxOverflowPolicy.drop_oldest ? "3;4;" : "1;2;") && completed==1)}
            verify(rx_is_closed(sub) && rx_subscriber_count(input)==0)
            verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
            delete sub;verify(opened==freed)
        }
    }
    // Delivery releases the budget; same-deadline FIFO retains next before complete.
    trace="";completed=0
    var inscope clock <- rx_virtual_scheduler()
    var inscope input <- rx_subject(type<int>)
    var source <- rx_clone(input) |> rx_delay(1,clock,rx_queue(1))
    var sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {completed++})
    rx_subject_next(input,1);rx_advance_by(clock,1)
    rx_subject_next(input,2);rx_subject_complete(input);rx_advance_by(clock,1)
    verify(trace=="1;2;" && completed==1 && rx_pending_count(clock)==0)
    delete source;delete sub
}
def edge_checks() {
    // Independent buffers for simultaneous subscriptions; cancellation of one
    // must not drop the second subscription's delayed values.
    trace="";completed=0
    var inscope clock <- rx_virtual_scheduler()
    var inscope input <- rx_subject(type<int>)
    var source <- rx_clone(input) |> rx_delay(1,clock,rx_queue(1,RxOverflowPolicy.drop_oldest))
    var first <- rx_subscribe(source,@(n:int) {panic("cancelled subscription delivered")},@(s:string) {panic(s)},@() {})
    var second <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {completed++})
    delete source
    for(n in range(100)) {rx_subject_next(input,n);verify(rx_pending_count(clock)==2)}
    rx_unsubscribe(first);verify(rx_pending_count(clock)==1 && rx_subscriber_count(input)==1)
    rx_subject_complete(input);rx_advance_by(clock,1)
    verify(trace=="99;" && completed==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    delete first;delete second
    // Overflow tears down every resource even when one cleanup throws.
    errors=0
    var inscope outer <- rx_subject(type<int>)
    var inscope inner <- rx_subject(type<int>)
    var keep <- rx_clone(inner)
    var jobs <- rx_clone(outer) |> rx_concat_map(@ capture(<-keep) (n:int) {
        var view <- rx_clone(keep)
        return <- rx_create(type<int>,@ capture(<-view) (sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@() {completed++;panic("cleanup failed")})
            rx_sink_add_cleanup(sink,@() {completed++})
            rx_connect(view,sink)
        } finally {delete view})
    } finally {delete keep},rx_queue(1))
    var sub <- rx_subscribe(jobs,@(n:int) {},@(s:string) {verify(s=="rx_flat_map: queue overflow");errors++},@() {})
    delete jobs
    let before=completed
    rx_subject_next(outer,1);rx_subject_next(outer,2);rx_subject_next(outer,3)
    verify(errors==1 && completed==before+2 && rx_is_closed(sub))
    verify(rx_subscriber_count(inner)==0 && rx_subscriber_count(outer)==0)
    delete sub
}
def repeat_checks() {
    // Regression: native tuple initialization must copy the queue settings,
    // never move them out of a descriptor used by another subscription.
    errors=0
    var inscope left <- rx_subject(type<int>)
    var inscope right <- rx_subject(type<int>)
    let limits=rx_queue(1)
    var pairs <- rx_clone(left) |> rx_zip(rx_clone(right),limits)
    for(runId in range(2)) {
        var a <- rx_subscribe(pairs,@(p:tuple<first:int;second:int>) {},@(s:string) {errors++},@() {})
        var b <- rx_subscribe(pairs,@(p:tuple<first:int;second:int>) {},@(s:string) {errors++},@() {})
        rx_subject_next(left,1);rx_subject_next(left,2)
        verify(errors==2*(runId+1) && rx_is_closed(a) && rx_is_closed(b))
        delete a;delete b
    }
    delete pairs
    for(parallelId in range(2)) {
        errors=0
        var keep <- rx_clone(right)
        var jobs <- flatten(rx_clone(left),@ capture(<-keep) (n:int) {return <- rx_clone(keep)} finally {delete keep},parallelId==1,RxOverflowPolicy.error)
        for(runId in range(2)) {
            var a <- rx_subscribe(jobs,@(n:int) {},@(s:string) {errors++},@() {})
            var b <- rx_subscribe(jobs,@(n:int) {},@(s:string) {errors++},@() {})
            for(n in range(6)) {rx_subject_next(left,n)}
            verify(errors==2*(runId+1) && rx_is_closed(a) && rx_is_closed(b))
            verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
            delete a;delete b
        }
        delete jobs
    }
    verify(limits.capacity==1 && limits.policy==RxOverflowPolicy.error)
}
def checks() {flat_checks();zip_checks();delay_checks();edge_checks();repeat_checks()}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX bounded queues checks OK\n")
}


