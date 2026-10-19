options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var errors=0
var completed=0
var cleanups=0
var nexts=0
struct CountBuffer {_marker:uint8}
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}
def tracked(input:auto) {
    var view <- rx_clone(input)
    return <- rx_defer(@ capture(<-view) () {
        var data <- hold()
        return <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.data[0]==42);return n} finally {delete data})
    } finally {delete view})
}
def build(input:auto;clock:RxScheduler;policy:RxThrottleTag) {return <- tracked(input) |> rx_throttle(10,clock)}
def build(input:auto;clock:RxScheduler;policy:RxSampleTag) {return <- tracked(input) |> rx_sample(10,clock)}
def build(input:auto;clock:RxScheduler;policy:RxBufferTag) {return <- tracked(input) |> rx_buffer(3,10,clock)}
def build(input:auto;clock:RxScheduler;policy:CountBuffer) {return <- tracked(input) |> rx_buffer(3)}
def timed(policy:RxThrottleTag|RxSampleTag|RxBufferTag) : bool {return true}
def timed(policy:CountBuffer) : bool {return false}
def touch(n:int) {verify(n>0)}
def touch(batch:array<int>) {verify(!empty(batch));for(n in batch) {verify(n>0)}}
def observe(source:auto;marker:iterator<auto(ObservedValue)>;mode:int;input:auto) {
    var a <- hold();var b <- hold();var c <- hold();var view <- rx_clone(input)
    return <- rx_subscribe(source,@ capture(<-a,copy(mode)) (v:ObservedValue) {
        verify(a.data[0]==42);touch(v);nexts++;if(mode==5) {panic("consumer failed")}
    } finally {delete a},@ capture(<-b,<-view,copy(mode)) (s:string) {
        verify(b.data[0]==42 && rx_subscriber_count(view)==0)
        verify(s=="source failed" || s=="rx scheduler closed");errors++
        if(mode==4) {panic("error callback failed")}
    } finally {delete b;delete view},@ capture(<-c,copy(mode)) () {
        verify(c.data[0]==42);completed++;if(mode==6) {panic("complete callback failed")}
    } finally {delete c})
}
def matrix(policy:auto) {
    for(mode in range(10)) {
        let oldErrors=errors;let oldDone=completed;let oldCleanup=cleanups
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- build(input,clock,policy) |> rx_take(mode==9 ? 1 : 100)
        var sub <- observe(source,source.element,mode,input)
        delete source
        rx_add_cleanup(sub,@ capture(copy(mode)) () {cleanups++;if(mode==8) {panic("cleanup failed")}})
        rx_add_cleanup(sub,@() {cleanups++})
        var caught=false
        try {
            rx_subject_next(input,1);rx_subject_next(input,2)
            if(mode==1 || mode==8) {rx_unsubscribe(sub)}
            elif(mode==2) {delete sub}
            elif(mode==3 || mode==4) {rx_subject_error(input,"source failed")}
            elif(mode==7) {rx_scheduler_close(clock);if(!timed(policy)) {rx_unsubscribe(sub)}}
            elif(mode==5 || mode==9) {rx_subject_next(input,3);rx_advance_by(clock,10)}
            else {rx_subject_complete(input)}
        } recover {caught=true}
        verify(caught==(mode==4 || mode==5 || mode==6 || mode==8))
        if(mode!=2) {verify(rx_is_closed(sub));delete sub}
        verify(rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        verify(cleanups==oldCleanup+2 && opened==freed)
        verify(errors==oldErrors+((mode==3 || mode==4 || (mode==7 && timed(policy))) ? 1 : 0))
        verify(completed==oldDone+((mode==0 || mode==6 || mode==9) ? 1 : 0))
    }
    // Closing before subscribe skips the source factory; count-only buffers
    // do not depend on a scheduler at all.
    if(timed(policy)) {
        var inscope clock <- rx_virtual_scheduler()
        rx_scheduler_close(clock)
        var inscope input <- rx_subject(type<int>)
        var source <- build(input,clock,policy)
        let before=opened
        var sub <- observe(source,source.element,0,input)
        verify(opened==before+3 && rx_is_closed(sub) && rx_subscriber_count(input)==0)
        delete sub;delete source;verify(opened==freed)
    }
    // A throwing upstream teardown still runs later teardown actions and
    // releases retained values/timers, both on completion and unsubscribe.
    for(stage in range(3)) {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var upstream <- rx_create(type<int>,@ capture(<-view) (sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@() {cleanups++;panic("upstream cleanup failed")})
            rx_sink_add_cleanup(sink,@() {cleanups++})
            rx_connect(view,sink)
        } finally {delete view})
        var source <- build(upstream,clock,policy)
        var sub <- observe(source,source.element,0,input)
        delete source;delete upstream
        rx_subject_next(input,1)
        let before=cleanups;let beforeErrors=errors
        var caught=false
        try {
            if(stage==0) {rx_unsubscribe(sub)}
            elif(stage==1) {rx_subject_complete(input)}
            else {rx_subject_error(input,"source failed")}
        } recover {caught=true}
        verify(caught==(stage!=2) && cleanups==before+2 && rx_is_closed(sub))
        verify(errors==beforeErrors+(stage==2 ? 1 : 0))
        verify(rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub;verify(opened==freed)
    }
    // Native connect panic must unwind already installed timers and callbacks.
    {
        var inscope clock <- rx_virtual_scheduler()
        var source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@() {cleanups++})
            panic("connect failed")
        })
        var view <- rx_subject(type<int>)
        var selected <- build(source,clock,policy)
        var caught=false
        try {var inscope sub <- observe(selected,selected.element,0,view)} recover {caught=true}
        verify(caught && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete selected;delete source;delete view;verify(opened==freed)
    }
}
def checks() {matrix(RxThrottleTag());matrix(RxSampleTag());matrix(RxBufferTag());matrix(CountBuffer())}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX throttle/sample/buffer lifetime checks OK\n")
}
