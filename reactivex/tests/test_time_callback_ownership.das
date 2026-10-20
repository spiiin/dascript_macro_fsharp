options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var releases=0
var finalized:int[4]
var on_dispose:lambda<():void>
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {releases++;delete values}}
}
struct Payload {
    n:int
    def finalize {
        if(n>0 && n<4) {finalized[n]++}
        if(n==1 && on_dispose!=null) {
            var action <- on_dispose
            invoke(action)
            unsafe {delete action}
        }
    }
}

def timed(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;clock:RxScheduler;mode:int;limits:RxQueueOptions) {
    if(mode==0) {return <- source |> rx_observe_on(clock,limits)}
    return <- source |> rx_delay(1,clock,limits)
}

def checks() {
    // A separate scheduled action per notification preserves FIFO against
    // unrelated actions with the same deadline and the scheduler action budget.
    for(mode in range(2)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- timed(rx_clone(input),clock,mode,rx_queue(3))
        var resource=Hold(values <- [42])
        var inscope sub <- rx_subscribe(source,@ capture(<-resource) (n:int) {verify(resource.values[0]==42);trace+="{n};"} finally {delete resource},
            @(s:string) {panic(s)},@(){trace+="done;"})
        delete source
        rx_subject_next(input,1)
        var marker <- @(){trace+="other;"}
        rx_schedule(clock,mode==0 ? 0 : 1,marker)
        rx_subject_next(input,2);rx_subject_complete(input)
        verify(rx_pending_count(clock)==4)
        verify(rx_advance_to(clock,1,1)==1 && trace=="1;" && !rx_is_closed(sub))
        verify(rx_advance_to(clock,1,1)==1 && trace=="1;other;")
        rx_advance_to(clock,1)
        verify(trace=="1;other;2;done;" && rx_is_closed(sub))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // The currently executing callback outlives public handles and all other
    // cancelled callbacks. Teardown inside next must not release its capture.
    for(mode in range(2)) {
        for(fail in range(2)) {
            let before=releases
            var clock <- rx_virtual_scheduler()
            var inscope view <- rx_scheduler_clone(clock)
            var inscope input <- rx_subject(type<int>)
            var source <- timed(rx_clone(input),clock,mode,rx_queue(3))
            var sub <- rx_subscription()
            var control:RxSubscription?;var primary:RxScheduler?
            unsafe {control=addr(sub);primary=addr(clock)}
            var resource=Hold(values <- [42])
            rx_subscribe_with(sub,source,@ capture(<-resource,copy(control),copy(primary),copy(before),copy(fail)) (n:int) {
                verify(n==1 && resource.values[0]==42)
                unsafe {rx_unsubscribe(*control);delete *control;delete *primary}
                verify(resource.values[0]==42 && releases==before)
                if(fail==1) {panic("next failed")}
            } finally {delete resource},@(s:string) {panic(s)},@(){panic("unexpected completion")})
            delete source
            rx_subject_next(input,1);rx_subject_next(input,2);rx_subject_complete(input)
            var caught=false
            try {rx_advance_to(view,1)} recover {caught=true}
            verify(caught==(fail==1) && releases==before+1)
            verify(rx_subscriber_count(input)==0 && rx_pending_count(view)==0 && rx_close_listener_count(view)==0)
            delete sub;delete clock
        }
    }
    // Dropping an owning pending payload can reenter the producer. Subject
    // serializes that notification, which evicts the second pending value.
    for(mode in range(2)) {
        for(i in range(4)) {finalized[i]=0}
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var inscope source <- timed(rx_clone(input),clock,mode,rx_queue(1,RxOverflowPolicy.drop_oldest))
        var inscope sub <- rx_subscribe(source,@(p:Payload) {trace+="{p.n};"},@(s:string) {panic(s)},@(){trace+="done;"})
        var feedback <- rx_clone(input)
        on_dispose <- @ capture(<-feedback) () {rx_subject_next(feedback,Payload(n=3))} finally {delete feedback}
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2))
        verify(on_dispose==null && finalized[1]==1 && finalized[2]==1 && finalized[3]==0)
        verify(rx_pending_count(clock)==1)
        rx_subject_complete(input);rx_advance_to(clock,1)
        verify(trace=="3;done;" && rx_is_closed(sub))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline && on_dispose==null)
    print("ReactiveX timed callback ownership tests OK\n")
}
