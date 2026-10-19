options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var finalized:int[4]
var saved:array<Payload>
var trace=""
struct Payload {
    n:int
    def finalize {if(n>0 && n<4) {finalized[n]++}}
}
def reset() {delete saved;for(i in range(4)) {finalized[i]=0};trace=""}
def checks() {
    reset()
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_sample(10,clock)
        var sub <- rx_subscribe(source,@(p:Payload) {trace+="{p.n};"},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1));verify(finalized[1]==0)
        rx_subject_next(input,Payload(n=2));verify(finalized[1]==1 && finalized[2]==0)
        rx_advance_by(clock,10);verify(trace=="2;" && finalized[2]==1)
        rx_subject_next(input,Payload(n=3));rx_unsubscribe(sub)
        verify(finalized[3]==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    reset()
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_throttle(10,clock)
        var sub <- rx_subscribe(source,@(p:Payload) {trace+="{p.n};"},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2))
        verify(trace=="1;" && finalized[1]==1 && finalized[2]==0)
        rx_advance_by(clock,10);rx_subject_next(input,Payload(n=2))
        verify(trace=="1;2;" && finalized[2]==1)
        rx_unsubscribe(sub);delete sub
    }
    for(fail in range(2)) {
        reset()
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_buffer_time(10,clock)
        var sub <- rx_subscribe(source,@(b:array<Payload>) {panic("unexpected batch")},@ capture(copy(fail)) (s:string) {
            verify(s=="source failed");if(fail==1) {panic("consumer failed")}
        },@() {})
        delete source
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2))
        verify(finalized[1]==0 && finalized[2]==0)
        var caught=false
        try {rx_subject_error(input,"source failed")} recover {caught=true}
        verify(caught==(fail==1) && finalized[1]==1 && finalized[2]==1)
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0 && rx_subscriber_count(input)==0)
        delete sub
    }
    reset()
    {
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_buffer(3)
        var sub <- rx_subscribe(source,@(b:array<Payload>) {
            verify(length(b)==2 && b[0].n==1 && b[1].n==2)
            saved := b
        },@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2));rx_subject_complete(input)
        delete sub
        verify(length(saved)==2 && saved[0].n==1 && saved[1].n==2 && finalized[1]==1 && finalized[2]==1)
        delete saved;verify(finalized[1]==2 && finalized[2]==2)
    }
    // Cancelling while processing a borrowed batch cannot destroy that frame.
    reset()
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_buffer_time(10,clock)
        var sub <- rx_subscription()
        let target=unsafe(addr(sub))
        rx_subscribe_with(sub,source,@ capture(copy(target)) (b:array<Payload>) {
            verify(length(b)==2 && b[0].n==1 && b[1].n==2)
            unsafe {rx_unsubscribe(*target)}
            verify(finalized[1]==0 && finalized[2]==0 && b[0].n==1 && b[1].n==2)
        },@(s:string) {panic(s)},@() {panic("cancel does not complete")})
        delete source
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2));rx_advance_by(clock,10)
        verify(finalized[1]==1 && finalized[2]==1 && rx_is_closed(sub))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0 && rx_subscriber_count(input)==0)
        delete sub
    }
    // tap converts a callback panic to on_error. Even then, leaked native
    // foreach locks must not prevent release of the borrowed delivery frame.
    reset()
    {
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_buffer(2) |> rx_tap(@(b:array<Payload>) {
            for(p in b) {verify(p.n>0);panic("tap foreach failed")}
        })
        var sub <- rx_subscribe(source,@(b:array<Payload>) {panic("unexpected next")},@(s:string) {trace+="error;"},@() {})
        delete source
        rx_subject_next(input,Payload(n=1));rx_subject_next(input,Payload(n=2))
        verify(trace=="error;" && finalized[1]==1 && finalized[2]==1 && rx_is_closed(sub))
        verify(rx_subscriber_count(input)==0)
        delete sub
    }
    // Native exceptions while a batch is in flight release all its values.
    reset()
    {
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_buffer(2)
        var sub <- rx_subscribe(source,@(b:array<Payload>) {
            for(a in b) {for(c in b) {verify(a.n>0 && c.n>0);panic("consumer failed in nested foreach")}}
        },@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,Payload(n=1))
        var caught=false
        try {rx_subject_next(input,Payload(n=2))} recover {caught=true}
        verify(caught && finalized[1]==1 && finalized[2]==1 && rx_is_closed(sub) && rx_subscriber_count(input)==0)
        delete sub
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX throttle/sample/buffer payload checks OK\n")
}
