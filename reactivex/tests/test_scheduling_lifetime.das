options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var allocated=0
var freed=0
var errors=0
var done=0
var finalized:int[4]
var trace=""
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
struct Payload {
    n:int
    def finalize {if(n>0 && n<4) {finalized[n]++}}
}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        allocated++
        var resource=Hold();resource.data <- [42]
        return <- rx_clone(view) |> rx_map(@ capture(<-resource) (n:int) {verify(resource.data[0]==42);return n} finally {delete resource})
    } finally {delete view})
}
def checks() {
    // Unsubscribe/delete/take/observer exceptions/clock shutdown all release
    // the upstream capture, pending notifications and observer captures.
    for(caseId in range(11)) {
            var inscope clock <- rx_virtual_scheduler()
            var inscope input <- rx_subject(type<int>)
            var source <- tracked(input) |> rx_subscribe_on(clock) |> rx_observe_on(clock) |> rx_take(caseId==8 ? 1 : 100)
            let oldErrors=errors;let oldDone=done
            var sub <- rx_subscription()
            var control:RxSubscription?
            unsafe {control=addr(sub)}
            rx_subscribe_with(sub,source,@ capture(copy(caseId),copy(control)) (n:int) {
                if(caseId==4) {panic("next failed")}
                if(caseId==10) {unsafe {rx_unsubscribe(*control)}}
            },
                @ capture(copy(caseId)) (message:string) {errors++;if(caseId==5) {panic("error failed")}},
                @ capture(copy(caseId)) () {done++;if(caseId==6) {panic("complete failed")}})
            delete source
            rx_advance_to(clock,0) // connect only; the hot source has no events yet
            verify(rx_subscriber_count(input)==1)
            var caught=false
            try {
                rx_subject_next(input,1)
                if(caseId==1) {rx_unsubscribe(sub)}
                elif(caseId==2) {delete sub}
                elif(caseId==3 || caseId==5) {rx_subject_error(input,"failure")}
                elif(caseId==7) {rx_scheduler_close(clock)}
                elif(caseId==9) {delete clock}
                elif(caseId==0 || caseId==6) {rx_subject_complete(input)}
                if(caseId!=9) {rx_advance_to(clock,0)}
            } recover {caught=true}
            verify(caught==(caseId==4 || caseId==5 || caseId==6))
            if(caseId!=2) {verify(rx_is_closed(sub))}
            delete sub
            verify(rx_subscriber_count(input)==0 && allocated==freed)
            if(caseId!=9) {verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)}
            verify(errors==oldErrors+((caseId==3 || caseId==5 || caseId==7 || caseId==9) ? 1 : 0))
            verify(done==oldDone+((caseId==0 || caseId==6 || caseId==8) ? 1 : 0))
    }
    // Pending values are independent owning snapshots. Eviction/cancellation
    // destroy them immediately, without needing another scheduler tick.
    for(policy in range(3)) {
        for(i in range(4)) {finalized[i]=0}
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        let overflow=policy==0 ? RxOverflowPolicy.error : (policy==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest)
        var inscope source <- rx_clone(input) |> rx_observe_on(clock,rx_queue(1,overflow))
        var inscope sub <- rx_subscribe(source,@(p:Payload) {},@(s:string) {},@(){})
        rx_subject_next(input,Payload(n=1));verify(finalized[1]==0)
        rx_subject_next(input,Payload(n=2))
        if(policy!=2) {verify(finalized[1]==1)}
        rx_unsubscribe(sub)
        verify(finalized[1]==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        verify(finalized[2]==(policy==1 ? 1 : 0))
    }
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<string>)
        var inscope source <- rx_clone(input) |> rx_observe_on(clock)
        var inscope sub <- rx_subscribe(source,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@(){})
        var text=clone_string("original")
        rx_subject_next(input,text);text="changed"
        rx_subject_complete(input);rx_advance_to(clock,0)
        verify(trace=="original;" && rx_is_closed(sub))
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline && allocated==freed)
    print("ReactiveX scheduling lifetime tests OK\n")
}
