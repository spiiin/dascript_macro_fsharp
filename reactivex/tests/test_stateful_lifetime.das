options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var cleanups=0
var errors=0
var completed=0
var calls=0
var trace=""
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
def hold() {opened++;return <- Hold(values <- [42])}

def checks() {
    // All three tap callbacks own their captures, including callbacks that
    // are never called (normal completion/error and explicit cancellation).
    for(mode in range(3)) {
        var inscope input <- rx_subject(type<int>)
        var nextData <- hold();var errorData <- hold();var doneData <- hold()
        var source <- rx_clone(input) |> rx_tap(
            @ capture(<-nextData) (n:int) {verify(nextData.values[0]==42)} finally {delete nextData},
            @ capture(<-errorData) (s:string) {verify(errorData.values[0]==42)} finally {delete errorData},
            @ capture(<-doneData) () {verify(doneData.values[0]==42)} finally {delete doneData})
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {},@() {})
        delete source
        rx_subject_next(input,1)
        if(mode==0) {rx_subject_complete(input)}
        elif(mode==1) {rx_subject_error(input,"error")}
        else {rx_unsubscribe(sub)}
        delete sub
        verify(opened==freed && rx_subscriber_count(input)==0)
    }
    // Retained callbacks survive deletion of all descriptors, and are freed
    // on complete/error/take/unsubscribe/RAII and observer/operator exceptions.
    for(mode in range(10)) {
        errors=0;completed=0;calls=0
        let before=cleanups
        var inscope input <- rx_subject(type<int>)
        var tapData <- hold();var scanData <- hold();var equalData <- hold()
        var source <- rx_clone(input) |> rx_tap(@ capture(<-tapData,copy(mode)) (n:int) {
            verify(tapData.values[0]==42);calls++
            if(mode==5) {panic("tap failed")}
        } finally {delete tapData}) |> rx_scan(0,@ capture(<-scanData,copy(mode)) (a:int;n:int) {
            verify(scanData.values[0]==42)
            if(mode==6) {panic("reducer failed")}
            return a+n
        } finally {delete scanData}) |> rx_distinct_until_changed(@ capture(<-equalData,copy(mode)) (a:int;b:int) {
            verify(equalData.values[0]==42)
            if(mode==7) {panic("comparator failed")}
            return a==b
        } finally {delete equalData}) |> rx_take(mode==2 ? 1 : 100)
        var observerData <- hold()
        var sub <- rx_subscribe(source,@ capture(<-observerData,copy(mode)) (n:int) {
            verify(observerData.values[0]==42)
            if(mode==8) {panic("observer failed")}
        } finally {delete observerData},@ capture(copy(mode)) (s:string) {errors++;if(mode==9) {panic("error observer failed")}},@() {completed++})
        delete source
        verify(opened==freed+4 && rx_subscriber_count(input)==1)
        rx_add_cleanup(sub,@() {cleanups++})
        var caught=false
        try {
            if(mode==3) {rx_unsubscribe(sub)}
            elif(mode==4) {delete sub}
            else {
                rx_subject_next(input,1)
                if(mode==7) {rx_subject_next(input,2)}
                elif(mode==1 || mode==9) {rx_subject_error(input,"source failed")}
                else {rx_subject_complete(input)}
            }
        } recover {caught=true}
        verify(caught==(mode==8 || mode==9))
        if(mode!=4) {verify(rx_is_closed(sub));delete sub}
        verify(opened==freed && rx_subscriber_count(input)==0 && cleanups==before+1)
        verify(errors==((mode==1 || mode==5 || mode==6 || mode==7 || mode==9) ? 1 : 0))
        verify(completed==((mode==0 || mode==2) ? 1 : 0))
        verify(calls==((mode==3 || mode==4) ? 0 : ((mode==7) ? 2 : 1)))
    }
    // Native callback failure unwinds synchronous connect frames too.
    for(mode in range(3)) {
        var tapHold <- hold();var scanHold <- hold();var equalHold <- hold()
        var source <- rx_range(1,3) |> rx_tap(@ capture(<-tapHold) (n:int) {verify(tapHold.values[0]==42)} finally {delete tapHold}) |> rx_scan(0,@ capture(<-scanHold) (a:int;n:int) {verify(scanHold.values[0]==42);return a+n} finally {delete scanHold}) |> rx_distinct_until_changed(@ capture(<-equalHold) (a:int;b:int) {verify(equalHold.values[0]==42);return a==b} finally {delete equalHold}) |> rx_start_with(0)
        var caught=false
        try {
            var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int) {if(mode==0 && n==1) {panic("consumer failed")}},
                @(s:string) {panic("must not convert consumer failure")},@ capture(copy(mode)) () {if(mode==1) {panic("complete failed")}})
            delete sub
        } recover {caught=true}
        delete source
        verify(caught==(mode!=2) && opened==freed)
    }
    // Cleanup failure still releases later callbacks and the entire chain.
    {
        let before=cleanups
        var inscope input <- rx_subject(type<int>)
        var data <- hold()
        var source <- rx_clone(input) |> rx_scan(0,@ capture(<-data) (a:int;n:int) {return a+n} finally {delete data}) |> rx_distinct_until_changed()
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {},@() {})
        delete source
        rx_add_cleanup(sub,@() {cleanups++;panic("cleanup failed")})
        rx_add_cleanup(sub,@() {cleanups++})
        var caught=false
        try {rx_subject_complete(input)} recover {caught=true}
        verify(caught && cleanups==before+2 && rx_subscriber_count(input)==0 && opened==freed)
        delete sub
    }
    // State is committed before a consumer reenters the same Subject.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_scan(0,@(a:int;n:int) {return a+n}) |> rx_distinct_until_changed()
        var view <- rx_clone(input)
        var sub <- rx_subscribe(source,@ capture(<-view) (n:int) {trace+="{n};";if(n==1) {rx_subject_next(view,0);rx_subject_next(view,2)}} finally {delete view},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(input,1)
        verify(trace=="1;3;")
        delete sub
        verify(rx_subscriber_count(input)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX stateful lifetime checks OK\n")
}
