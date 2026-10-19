options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var finalized:int[4]
var trace=""
struct Payload {
    n:int
    def finalize {if(n>0 && n<4) {finalized[n]++}}
}
def reset() {for(i in range(4)) {finalized[i]=0};trace=""}
def checks() {
    // Destruction of an evicted delayed capture happens immediately, before
    // its deadline, and unsubscribe releases the remaining capture.
    reset()
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_delay(10,clock,rx_queue(1,RxOverflowPolicy.drop_oldest))
        var sub <- rx_subscribe(source,@(p:Payload) {trace+="{p.n};"},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1));verify(finalized[1]==0)
        rx_subject_next(input,Payload(n=2));verify(finalized[1]==1 && finalized[2]==0 && rx_pending_count(clock)==1)
        rx_unsubscribe(sub)
        verify(finalized[2]==1 && trace=="" && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    // A delivered owning value is finalized both in the delivery frame and
    // in the timer capture, including when the downstream callback throws.
    for(mode in range(2)) {
        reset()
        var inscope clock <- rx_virtual_scheduler()
        var source <- rx_just(Payload(n=1)) |> rx_delay(1,clock,rx_queue(1))
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (p:Payload) {trace+="{p.n};";if(mode==1) {panic("consumer failed")}},@(s:string) {panic(s)},@() {})
        delete source
        let before=finalized[1]
        var caught=false
        try {rx_advance_by(clock,1)} recover {caught=true}
        verify(caught==(mode==1) && trace=="1;" && finalized[1]>=before+2)
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    reset()
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var view <- rx_scheduler_clone(clock)
        var source <- rx_clone(input) |> rx_concat_map(@ capture(<-view) (p:Payload) {
            let id=p.n
            return <- rx_timer(1,view) |> rx_map(@ capture(copy(id)) (tick:int64) {return id})
        } finally {delete view},rx_queue(1,RxOverflowPolicy.drop_oldest))
        var sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1))
        rx_subject_next(input,Payload(n=2));verify(finalized[2]==0)
        rx_subject_next(input,Payload(n=3));verify(finalized[2]==1 && finalized[3]==0)
        rx_subject_complete(input);rx_advance_by(clock,10)
        verify(trace=="1;3;" && finalized[3]>=1 && rx_is_closed(sub) && rx_pending_count(clock)==0)
        delete sub
    }
    reset()
    {
        var inscope left <- rx_subject(type<Payload>)
        var inscope right <- rx_subject(type<Payload>)
        var source <- rx_clone(left) |> rx_zip(rx_clone(right),rx_queue(1,RxOverflowPolicy.drop_oldest))
        var sub <- rx_subscribe(source,@(p:tuple<first:Payload;second:Payload>) {trace+="{p.first.n}:{p.second.n};"},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(left,Payload(n=1));rx_subject_next(left,Payload(n=2))
        verify(finalized[1]==1 && finalized[2]==0)
        rx_subject_next(right,Payload(n=3))
        verify(trace=="2:3;" && finalized[2]>=2 && finalized[3]>=2)
        rx_unsubscribe(sub);delete sub
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX bounded queue payload lifetime checks OK\n")
}
