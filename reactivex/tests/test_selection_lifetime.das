options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
require strings
var trace=""
var opened=0
var freed=0
var finished=0
var cleaned=0
var effects=0
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}

def checks() {
    // Cold finally ordering: terminal callback, upstream teardown, then finally.
    for(mode in range(4)) {
        trace=""
        let before=finished
        var inscope source <- rx_create(type<int>,@ capture(copy(mode)) (sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@() {trace+="up;";cleaned++})
            if(mode==0) {rx_sink_complete(sink)}
            elif(mode==1) {rx_sink_error(sink,"source")}
            elif(mode==2) {panic("connect failed")}
            else {rx_sink_next(sink,1)}
        }) |> rx_finally(@() {trace+="finally;";finished++}) |> rx_finally(@() {trace+="outer;"})
        var caught=false
        try {
            var sub <- rx_subscribe(source,@(n:int) {panic("observer failed")},@(s:string) {verify(s=="source");trace+="error;"},@() {trace+="done;"})
            delete sub
        } recover {caught=true}
        verify(finished==before+1 && caught==(mode>=2))
        if(mode==0) {verify(trace=="done;up;finally;outer;")}
        elif(mode==1) {verify(trace=="error;up;finally;outer;")}
        else {verify(trace=="up;finally;outer;")}
    }
    // A synchronous finally failure also releases its capture; outer cleanup runs.
    {
        trace=""
        var data <- hold()
        var source <- rx_empty(type<int>) |> rx_finally(@ capture(<-data) () {trace+="inner;";panic("sync finally")} finally {delete data}) |> rx_finally(@(){trace+="outer;"})
        var caught=false
        try {var sub <- rx_subscribe(source,@(n:int){},@(s:string){panic("unexpected error")},@(){trace+="done;"});delete sub} recover {caught=true;verify(starts_with("{this_context().last_exception}","sync finally"))}
        delete source
        verify(caught && trace=="done;inner;outer;" && opened==freed)
    }
    // One action per subscription, independent of descriptor cloning/reuse.
    {
        let before=finished
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_finally(@(){finished++})
        var inscope a <- rx_subscribe(source,@(n:int){},@(s:string){},@(){})
        var inscope b <- rx_subscribe(source,@(n:int){},@(s:string){},@(){})
        rx_unsubscribe(a);verify(finished==before+1 && rx_subscriber_count(input)==1)
        rx_subject_complete(input);verify(finished==before+2 && rx_is_closed(b))
        var inscope c <- rx_subscribe(source,@(n:int){},@(s:string){},@(){})
        verify(finished==before+3 && rx_is_closed(c))
    }
    // Deleting an unsubscribed descriptor releases the capture without running it.
    {
        let before=finished
        var data <- hold()
        var source <- rx_empty(type<int>) |> rx_finally(@ capture(<-data) () {verify(data.data[0]==42);finished++} finally {delete data})
        delete source
        verify(opened==freed && finished==before)
    }
    // Retained nodes/captures survive descriptor deletion and release on every exit.
    for(mode in range(10)) {
        let before=finished
        var inscope input <- rx_subject(type<int>)
        var a <- hold();var b <- hold();var c <- hold()
        var source <- rx_clone(input) |> rx_skip(1) |> rx_skip_while(@ capture(<-a,copy(mode)) (n:int) {
            verify(a.data[0]==42)
            if(mode==6) {panic("skip predicate failed")}
            return false
        } finally {delete a}) |> rx_take_while(@ capture(<-b,copy(mode)) (n:int) {
            verify(b.data[0]==42)
            if(mode==7) {panic("take predicate failed")}
            return mode!=5
        } finally {delete b}) |> rx_pairwise() |> rx_finally(@ capture(<-c) () {verify(c.data[0]==42);finished++} finally {delete c}) |> rx_take(mode==2 ? 1 : 100)
        var observerData <- hold()
        var sub <- rx_subscribe(source,@ capture(<-observerData,copy(mode)) (p:tuple<previous:int;current:int>) {
            verify(observerData.data[0]==42)
            if(mode==8) {panic("observer failed")}
        } finally {delete observerData},@ capture(copy(mode)) (s:string) {if(mode==9) {panic("error observer failed")}},@() {})
        delete source
        var caught=false
        try {
            if(mode==3) {rx_unsubscribe(sub)}
            elif(mode==4) {delete sub}
            else {
                rx_subject_next(input,1);rx_subject_next(input,2);rx_subject_next(input,3)
                if(mode==1 || mode==9) {rx_subject_error(input,"source")}
                else {rx_subject_complete(input)}
            }
        } recover {caught=true}
        verify(caught==(mode==8 || mode==9))
        if(mode!=4) {verify(rx_is_closed(sub));verify(!rx_unsubscribe(sub));delete sub}
        verify(finished==before+1 && rx_subscriber_count(input)==0 && opened==freed)
    }
    // Completion/error callbacks can throw; finally still executes once.
    for(mode in range(2)) {
        let before=finished
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_finally(@(){finished++})
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic("error callback")},@(){panic("done callback")})
        var caught=false
        try {if(mode==0) {rx_subject_complete(input)} else {rx_subject_error(input,"error")}} recover {caught=true}
        verify(caught && finished==before+1 && rx_is_closed(sub) && rx_subscriber_count(input)==0)
        delete sub
    }
    // Cleanup failures are native, do not become on_error, and do not stop later cleanup.
    for(mode in range(3)) {
        trace=""
        let before=finished
        var inscope input <- rx_subject(type<int>)
        var data <- hold()
        var source <- rx_clone(input) |> rx_finally(@ capture(<-data) () {
            verify(data.data[0]==42);finished++;trace+="f;";panic("finally failed")
        } finally {delete data}) |> rx_finally(@(){trace+="outer;"})
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {trace+="error;"},@() {trace+="done;"})
        delete source
        rx_add_cleanup(sub,@(){trace+="late;"})
        var caught=false
        try {
            if(mode==0) {rx_subject_complete(input)}
            elif(mode==1) {rx_subject_error(input,"source")}
            else {rx_unsubscribe(sub)}
        } recover {caught=true;verify(starts_with("{this_context().last_exception}","finally failed"))}
        verify(caught && finished==before+1 && rx_is_closed(sub) && rx_subscriber_count(input)==0 && opened==freed)
        verify(trace==(mode==0 ? "done;f;outer;late;" : (mode==1 ? "error;f;outer;late;" : "f;outer;late;")))
        delete sub
    }
    // Preserve the original connect/observer failure over a finally failure.
    {
        var inscope source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {panic("original")}) |> rx_finally(@(){finished++;panic("secondary")})
        var caught=false
        try {var sub <- rx_subscribe(source,@(n:int){},@(s:string){panic("unexpected")},@(){});delete sub} recover {caught=true;verify(starts_with("{this_context().last_exception}","original"))}
        verify(caught)
    }
    // Reentrant unsubscription is harmless: the control is closed before finally.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope control <- rx_subscription()
        var ptr:RxSubscription?
        unsafe {ptr=addr(control)}
        var inscope source <- rx_clone(input) |> rx_finally(@ capture(copy(ptr)) () {
            unsafe {verify(rx_is_closed(*ptr) && !rx_unsubscribe(*ptr))};trace+="f;"
        })
        rx_subscribe_with(control,source,@ capture(copy(ptr)) (n:int) {trace+="next;";unsafe {rx_unsubscribe(*ptr)}},@(s:string){panic(s)},@(){panic("unexpected done")})
        rx_subject_next(input,1)
        verify(trace=="next;f;" && rx_subscriber_count(input)==0)
    }
    // Downstream take(0) never connects, so no finally callback is registered.
    {
        let before=finished
        var inscope source <- rx_range(1,2) |> rx_finally(@(){finished++}) |> rx_take(0)
        var inscope sub <- rx_subscribe(source,@(n:int){panic("unexpected")},@(s:string){panic(s)},@(){})
        verify(finished==before)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(12)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX selection lifetime checks OK\n")
}
