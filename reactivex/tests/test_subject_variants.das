options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var busy=false
var late:RxSubscription

def checks() {
    {
        trace=""
        var inscope subject <- rx_behavior_subject(10)
        verify(rx_behavior_value(subject)==10 && rx_subject_buffered_count(subject)==1)
        var inscope a <- rx_subscribe(subject,@(n:int) {trace+="a{n};"},@(s:string) {panic(s)},@() {trace+="aDone;"})
        rx_subject_next(subject,20)
        var inscope b <- rx_subscribe(subject,@(n:int) {trace+="b{n};"},@(s:string) {panic(s)},@() {trace+="bDone;"})
        verify(trace=="a10;a20;b20;" && rx_behavior_value(subject)==20)
        rx_subject_complete(subject)
        var inscope c <- rx_subscribe(subject,@(n:int) {panic("completed Behavior replays no value")},@(s:string) {panic(s)},@() {trace+="lateDone;"})
        rx_subject_next(subject,99)
        verify(trace=="a10;a20;b20;aDone;bDone;lateDone;" && rx_behavior_value(subject)==20 && rx_subscriber_count(subject)==0)
    }
    {
        trace=""
        var inscope subject <- rx_behavior_subject("seed")
        rx_subject_next(subject,"current");rx_subject_error(subject,"failed")
        var inscope sub <- rx_subscribe(subject,@(s:string) {panic("errored Behavior replays no value")},@(s:string) {verify(s=="failed");trace="error"},@() {panic("unexpected done")})
        var caught=false
        try {let value=rx_behavior_value(subject)} recover {caught=true}
        verify(caught && trace=="error" && rx_is_closed(sub))
    }
    for(error in range(2)) {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,3)
        verify(rx_subject_buffered_count(subject)==0)
        rx_subject_next(subject,1)
        var inscope a <- rx_subscribe(subject,@(n:int) {trace+="a{n};"},@(s:string) {trace+="aError;"},@() {trace+="aDone;"})
        for(n in range(2,6)) {rx_subject_next(subject,n);verify(rx_subject_buffered_count(subject)<=3)}
        var inscope b <- rx_subscribe(subject,@(n:int) {trace+="b{n};"},@(s:string) {trace+="bError;"},@() {trace+="bDone;"})
        verify(trace=="a1;a2;a3;a4;a5;b3;b4;b5;")
        if(error==0) {rx_subject_complete(subject)} else {rx_subject_error(subject,"failed")}
        trace=""
        rx_subject_next(subject,99)
        var inscope c <- rx_subscribe(subject,@(n:int) {trace+="{n};"},@(s:string) {verify(s=="failed");trace+="error;"},@() {trace+="done;"})
        verify(trace==(error==0 ? "3;4;5;done;" : "3;4;5;error;"))
        verify(rx_is_closed(c) && rx_subject_buffered_count(subject)==3 && rx_subscriber_count(subject)==0)
    }
    // Replay has no initial value, even with capacity one.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,1)
        var inscope sub <- rx_subscribe(subject,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="" && !rx_is_closed(sub))
        rx_subject_next(subject,1);rx_subject_next(subject,2)
        var inscope clone <- rx_clone(subject)
        var inscope other <- rx_subscribe(clone,@(n:int) {trace+="late{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="1;2;late2;" && rx_subject_buffered_count(clone)==1)
    }
    // Replay is atomic with respect to live notifications on the same Subject.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,2)
        rx_subject_next(subject,1);rx_subject_next(subject,2)
        var inscope a <- rx_subscribe(subject,@(n:int) {verify(!busy);trace+="a{n};"},@(s:string) {panic(s)},@() {verify(!busy);trace+="aDone;"})
        trace=""
        var view <- rx_clone(subject)
        var inscope b <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            verify(!busy);busy=true;trace+="b{n};"
            if(n==1) {rx_subject_next(view,3);rx_subject_complete(view)}
            busy=false
        } finally {delete view},@(s:string) {panic(s)},@() {verify(!busy);trace+="bDone;"})
        verify(trace=="b1;b2;a3;b3;aDone;bDone;" && rx_is_closed(a) && rx_is_closed(b))
    }
    // Subscribe during a broadcast after queuing next+complete: no duplicate
    // current value, no lost queued next, and terminal follows every value.
    for(behavior in range(2)) {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,2)
        if(behavior==1) {delete subject;subject <- rx_behavior_subject(0)}
        else {rx_subject_next(subject,0)}
        late <- rx_subscription()
        var view <- rx_clone(subject)
        var inscope a <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            trace+="a{n};"
            if(n==1) {
                rx_subject_next(view,2);rx_subject_complete(view)
                rx_subscribe_with(late,view,@(v:int) {trace+="b{v};"},@(s:string) {panic(s)},@() {trace+="bDone;"})
            }
        } finally {delete view},@(s:string) {panic(s)},@() {trace+="aDone;"})
        trace=""
        rx_subject_next(subject,1)
        verify(trace==(behavior==1 ? "a1;b1;a2;b2;aDone;bDone;" : "a1;b0;b1;a2;b2;aDone;bDone;"))
        verify(rx_is_closed(a) && rx_is_closed(late) && rx_subscriber_count(subject)==0)
        delete late
    }
    // Downstream take stops replay and unregisters immediately.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,4)
        for(n in range(1,5)) {rx_subject_next(subject,n)}
        var inscope source <- rx_clone(subject) |> rx_take(1)
        var inscope sub <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {trace+="done;"})
        verify(trace=="1;done;" && rx_is_closed(sub) && rx_subscriber_count(subject)==0 && rx_subject_buffered_count(subject)==4)
    }
    // Bounded storage stays bounded after many evictions; owning strings replay.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<string>,2)
        for(n in range(1000)) {rx_subject_next(subject,"value{n}");verify(rx_subject_buffered_count(subject)<=2)}
        var inscope sub <- rx_subscribe(subject,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
        verify(trace=="value998;value999;")
    }
    // Native callbacks may reuse their character buffer after returning.
    // Initial/current values and the cached error must own their string data.
    {
        trace=""
        var bytes:uint8[4]
        bytes[0]=101u8;bytes[1]=114u8;bytes[2]=114u8;bytes[3]=0u8
        var borrowed:string
        unsafe {borrowed=reinterpret<string>(addr(bytes[0]))}
        var inscope behavior <- rx_behavior_subject(borrowed)
        bytes[0]=120u8
        verify(rx_behavior_value(behavior)=="err")
        rx_subject_next(behavior,borrowed)
        bytes[0]=121u8
        verify(rx_behavior_value(behavior)=="xrr")
        var inscope replay <- rx_replay_subject(type<string>,1)
        rx_subject_next(replay,borrowed)
        bytes[0]=122u8
        rx_subject_error(replay,borrowed)
        bytes[0]=119u8
        var inscope sub <- rx_subscribe(replay,@(s:string) {trace+="{s};"},@(s:string) {trace+="{s};"},@() {panic("unexpected complete")})
        verify(trace=="yrr;zrr;")
    }
    for(size in range(-1,1)) {
        var caught=false
        try {var result <- rx_replay_subject(type<int>,size);delete result} recover {caught=true}
        verify(caught)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX BehaviorSubject/ReplaySubject checks OK\n")
}
