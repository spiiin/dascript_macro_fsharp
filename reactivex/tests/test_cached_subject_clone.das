options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
require strings

var clones=0
var reject=false
var trace=""
var hook:lambda<():void>
var hookEnabled=false
var hooked=false
var nestedCaught=false
var arrayClones=0
var rejectArray=false

def clone(var dst:array<int>;src:array<int>) {
    arrayClones++
    verify(empty(dst))
    resize(dst,length(src))
    for(i in range(length(src))) {dst[i]=src[i]+100}
    if(rejectArray) {panic("cached array clone failed")}
}

// Non-POD payload cloning is observable even without a payload finalizer.
def clone(var dst:string&;src:string) {
    clones++
    if(reject) {panic("cached replay clone failed")}
    if(hookEnabled) {invoke(hook)}
    dst="cloned:{src}"
}

def checks() {
    // Reusing POD storage must still invoke a user override of array clone.
    // The destination is logically empty on every call, including after failure.
    {
        var inscope subject <- rx_replay_subject(type<int>,2)
        rx_subject_next(subject,1);rx_subject_next(subject,2)
        let before=arrayClones
        for(i in range(4)) {
            trace=""
            var inscope sub <- rx_subscribe(subject,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
            verify(trace=="101;102;" && arrayClones==before+i+1)
        }
        var broken <- rx_subscription()
        var caught=false
        rejectArray=true
        try {rx_subscribe_with(broken,subject,@(n:int) {panic("must fail in array clone")},@(s:string) {panic(s)},@() {})} recover {caught=find(string(this_context().last_exception),"cached array clone failed")>=0}
        rejectArray=false
        verify(caught && rx_is_closed(broken) && rx_subscriber_count(subject)==0)
        delete broken
        trace=""
        var inscope good <- rx_subscribe(subject,@(n:int) {trace+="{n};"},@(s:string) {panic(s)},@() {})
        verify(trace=="101;102;" && arrayClones==before+6)
        rx_subject_complete(subject)
    }
    trace=""
    {
        var inscope subject <- rx_replay_subject(type<string>,2)
        rx_subject_next(subject,"one");rx_subject_next(subject,"two")
        let before=clones
        var inscope sub <- rx_subscribe(subject,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
        verify(trace=="cloned:one;cloned:two;" && clones==before+2)
        rx_subject_next(subject,"three")
        verify(trace=="cloned:one;cloned:two;three;")
        rx_subject_complete(subject)
    }
    trace=""
    {
        var inscope subject <- rx_behavior_subject("health")
        let before=clones
        var inscope sub <- rx_subscribe(subject,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
        verify(trace=="cloned:health;" && clones==before+1 && rx_behavior_value(subject)=="health")
        rx_subject_complete(subject)
    }
    // A failing clone unregisters the connecting listener, restores dispatch
    // and keeps both history and an already active subscriber usable.
    trace=""
    {
        var inscope subject <- rx_replay_subject(type<string>,2)
        rx_subject_next(subject,"one")
        var inscope good <- rx_subscribe(subject,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
        var broken <- rx_subscription()
        var caught=false
        reject=true
        try {rx_subscribe_with(broken,subject,@(s:string) {panic("must fail before delivery")},@(s:string) {panic(s)},@() {})} recover {caught=find(string(this_context().last_exception),"cached replay clone failed")>=0}
        reject=false
        verify(caught && rx_is_closed(broken) && rx_subscriber_count(subject)==1)
        delete broken
        rx_subject_next(subject,"two")
        verify(trace=="cloned:one;two;")
        rx_subject_complete(subject)
    }
    // An inner failed replay must preserve the lock owned by an outer array
    // clone, while releasing the additional locks left by its own failure.
    trace="";hooked=false;nestedCaught=false
    {
        var inscope subject <- rx_replay_subject(type<string>,2)
        rx_subject_next(subject,"one");rx_subject_next(subject,"two")
        var view <- rx_clone(subject)
        hook <- @ capture(<-view) () {
            if(!hooked) {
                hooked=true;reject=true
                var control <- rx_subscription()
                try {rx_subscribe_with(control,view,@(s:string) {panic("nested clone must fail")},@(s:string) {panic(s)},@() {})} recover {nestedCaught=find(string(this_context().last_exception),"cached replay clone failed")>=0}
                reject=false
                verify(nestedCaught && rx_is_closed(control) && rx_subscriber_count(view)==1)
                delete control
            }
        } finally {delete view}
        hookEnabled=true
        var inscope sub <- rx_subscribe(subject,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@() {})
        hookEnabled=false
        unsafe {delete hook}
        verify(hooked && nestedCaught && trace=="cloned:one;cloned:two;")
        rx_subject_next(subject,"three")
        rx_subject_complete(subject)
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX cached Subject clone checks OK\n")
}
