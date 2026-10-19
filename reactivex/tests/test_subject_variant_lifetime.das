options gen2
options gc
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var cleanups=0
var trace=""
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
def hold() {opened++;return <- Hold(values <- [42])}
def make_subject(behavior:bool) {
    if(behavior) {return <- rx_behavior_subject(5)}
    var result <- rx_replay_subject(type<int>,3)
    for(n in range(1,4)) {rx_subject_next(result,n)}
    return <- result
}

// Native backends cannot walk owning iterator locals at heap_collect; only
// this explicit collection helper stays interpreted. Other checks use JIT/AOT.
[no_jit, no_aot]
def gc_checks() {
    let baseline=heap_bytes_allocated()
    var behavior <- rx_behavior_subject("health {75}")
    var replay <- rx_replay_subject(type<string>,2)
    for(i in range(100)) {rx_subject_next(replay,"message {i}")}
    unsafe {heap_collect(true,false)} // collect strings, retain the live history
    verify(rx_behavior_value(behavior)=="health 75")
    trace=""
    var sub <- rx_subscribe(replay,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
    verify(trace=="message 98;message 99;")
    delete sub;delete behavior;delete replay
    unsafe {heap_collect(true,false)}
    verify(heap_bytes_allocated()==baseline)
}

def checks() {
    for(behavior in range(2)) {
        for(mode in range(10)) {
            var inscope subject <- make_subject(behavior==1)
            var source <- rx_clone(subject) |> rx_take(mode==4 ? 1 : 100)
            var sub <- rx_subscription()
            var nextData <- hold();var errorData <- hold();var doneData <- hold()
            var caught=false
            try {
                rx_subscribe_with(sub,source,@ capture(<-nextData,copy(mode)) (n:int) {
                    verify(nextData.values[0]==42)
                    if(mode==5 || (mode==9 && n==99)) {panic("next failed")}
                } finally {delete nextData},@ capture(<-errorData,copy(mode)) (s:string) {
                    verify(errorData.values[0]==42);if(mode==6) {panic("error callback failed")}
                } finally {delete errorData},@ capture(<-doneData,copy(mode)) () {
                    verify(doneData.values[0]==42);if(mode==7) {panic("complete callback failed")}
                } finally {delete doneData})
                if(mode==8) {
                    rx_add_cleanup(sub,@() {cleanups++;panic("cleanup failed")})
                    rx_add_cleanup(sub,@() {cleanups++})
                }
                if(mode==2 || mode==8) {rx_unsubscribe(sub)}
                elif(mode==3) {delete sub}
                elif(mode==1 || mode==6) {rx_subject_error(subject,"source failed")}
                elif(mode==9) {rx_subject_next(subject,99)}
                else {rx_subject_complete(subject)}
            } recover {caught=true}
            delete source
            verify(caught==(mode==5 || mode==6 || mode==7 || mode==8 || mode==9))
            if(mode!=3) {verify(rx_is_closed(sub));delete sub}
            verify(rx_subscriber_count(subject)==0 && opened==freed)
            verify(rx_subject_buffered_count(subject)==(behavior==1 ? 1 : 3))
        }
    }
    // A failed replay callback unregisters only itself. Queued notifications
    // still reach the existing subscriber, and dispatch remains usable.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,2)
        rx_subject_next(subject,1);rx_subject_next(subject,2)
        var inscope good <- rx_subscribe(subject,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        trace=""
        var view <- rx_clone(subject);var data <- hold()
        var sub <- rx_subscription()
        var caught=false
        try {
            rx_subscribe_with(sub,subject,@ capture(<-view,<-data) (n:int) {
                verify(data.values[0]==42);rx_subject_next(view,3);panic("replay failed")
            } finally {delete view;delete data},@(s:string) {panic("must not convert consumer exception")},@() {})
        } recover {caught=true}
        delete sub
        verify(caught && opened==freed && trace=="3;" && rx_subscriber_count(subject)==1)
        rx_subject_next(subject,4)
        verify(trace=="3;4;")
        rx_subject_complete(subject)
    }
    // Late replay before a cached terminal also unwinds owning callbacks when
    // either replay or the terminal observer throws.
    for(error in range(2)) {
        for(stage in range(2)) {
            var inscope subject <- rx_replay_subject(type<int>,2)
            rx_subject_next(subject,1);rx_subject_next(subject,2)
            if(error==0) {rx_subject_complete(subject)} else {rx_subject_error(subject,"failed")}
            var data <- hold();var sub <- rx_subscription()
            var caught=false
            try {
                rx_subscribe_with(sub,subject,@ capture(<-data,copy(stage)) (n:int) {
                    verify(data.values[0]==42);if(stage==0) {panic("late replay failed")}
                } finally {delete data},@(s:string) {panic("late error callback failed")},@() {panic("late complete callback failed")})
            } recover {caught=true}
            delete sub
            verify(caught && opened==freed && rx_subscriber_count(subject)==0 && rx_subject_buffered_count(subject)==2)
        }
    }
    // Delete the original descriptor from a replay callback: the connecting
    // subscription retains source storage, including its complete snapshot.
    {
        trace=""
        var subject <- rx_replay_subject(type<string>,2)
        rx_subject_next(subject,"one");rx_subject_next(subject,"two")
        var ptr:typedecl(subject)?
        unsafe {ptr=addr(subject)}
        var inscope sub <- rx_subscribe(subject,@ capture(copy(ptr)) (s:string) {
            trace+="{s};"
            if(s=="one") {unsafe {delete *ptr}}
        },@(s:string) {panic(s)},@() {})
        verify(trace=="one;two;" && empty(subject.owner))
        rx_unsubscribe(sub)
    }
    // Deleting the primary subscription inside initial replay stops the rest.
    {
        trace=""
        var inscope subject <- rx_replay_subject(type<int>,3)
        for(n in range(1,4)) {rx_subject_next(subject,n)}
        var sub <- rx_subscription()
        var ptr:RxSubscription?
        unsafe {ptr=addr(sub)}
        rx_subscribe_with(sub,subject,@ capture(copy(ptr)) (n:int) {
            trace+="{n};";unsafe {delete *ptr}
        },@(s:string) {panic(s)},@() {panic("unsubscribe does not complete")})
        verify(trace=="1;" && empty(sub.owner) && rx_subscriber_count(subject)==0)
        rx_subject_next(subject,4)
        verify(trace=="1;")
    }
}
[export, unsafe_heap_collect]
def main() {
    checks();gc_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    gc_checks()
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX BehaviorSubject/ReplaySubject lifetime checks OK\n")
}
