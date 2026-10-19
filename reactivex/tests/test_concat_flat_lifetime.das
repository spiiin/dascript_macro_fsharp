options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var calls=0
var cleanups=0
var trace=""
var selected=""
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
def hold() {opened++;return <- Hold(values <- [42])}

def checks() {
    for(capacity in range(1,3)) {
        for(mode in range(10)) {
            calls=0;trace=""
            var inscope clock <- rx_virtual_scheduler()
            var view <- rx_scheduler_clone(clock)
            var selectorData <- hold()
            var source <- rx_range(1,5) |> rx_flat_map(@ capture(<-view,<-selectorData,copy(mode)) (n:int) {
                verify(selectorData.values[0]==42);calls++
                if(mode==9 && n==3) {panic("selector failed")}
                var data <- hold()
                return <- rx_timer(1,view) |> rx_map(@ capture(<-data,copy(mode),copy(n)) (tick:int64) {
                    verify(data.values[0]==42)
                    if(mode==4 || mode==6) {panic("inner failed")}
                    return n
                } finally {delete data})
            } finally {delete view;delete selectorData},capacity) |> rx_take(mode==3 ? 1 : 100)
            var observerData <- hold()
            var sub <- rx_subscribe(source,@ capture(<-observerData,copy(mode)) (n:int) {
                verify(observerData.values[0]==42);trace+="next;"
                if(mode==5) {panic("next failed")}
            } finally {delete observerData},@ capture(copy(mode)) (s:string) {trace+="error;";if(mode==6) {panic("error observer failed")}},
                @ capture(copy(mode)) () {trace+="done;";if(mode==7) {panic("complete observer failed")}})
            delete source
            verify(calls==capacity && rx_pending_count(clock)==capacity)
            if(mode==8) {
                rx_add_cleanup(sub,@() {cleanups++;panic("cleanup failed")})
                rx_add_cleanup(sub,@() {cleanups++})
            }
            let before=cleanups
            var caught=false
            try {
                if(mode==1 || mode==8) {rx_unsubscribe(sub)}
                elif(mode==2) {delete sub}
                else {rx_advance_by(clock,10)}
            } recover {caught=true}
            verify(caught==(mode==5 || mode==6 || mode==7 || mode==8))
            if(mode!=2) {verify(rx_is_closed(sub));delete sub}
            verify(opened==freed && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
            verify(calls==((mode==0 || mode==7) ? 5 : (mode==9 ? 3 : capacity)))
            if(mode==1 || mode==2 || mode==8) {verify(trace=="")}
            elif(mode==4 || mode==6) {verify(trace=="error;")}
            elif(mode==5) {verify(trace=="next;")}
            elif(mode==3) {verify(trace=="next;done;")}
            elif(mode==9) {verify(trace==(capacity==1 ? "next;next;error;" : "next;error;"))}
            else {verify(trace=="next;next;next;next;next;done;")}
            verify(cleanups==before+(mode==8 ? 2 : 0))
        }
    }
    // A slot stays reserved through reentrant selector and child teardown.
    // Cleanup runs before the next selector; reentrant outer values join FIFO.
    {
        selected="";cleanups=0
        var inscope outer <- rx_subject(type<int>)
        var inscope gate <- rx_subject(type<int>)
        var a <- rx_clone(outer);var b <- rx_clone(gate)
        var source <- rx_clone(outer) |> rx_concat_map(@ capture(<-a,<-b) (n:int) {
            selected+="{n};"
            if(n==1) {rx_subject_next(a,2)}
            if(n==2) {verify(cleanups==1)}
            var parent <- rx_clone(a);var inner <- rx_clone(b)
            return <- rx_create(type<int>,@ capture(<-parent,<-inner,copy(n)) (sink:typedecl(rx_sink_marker(type<int>))) {
                var reenter <- rx_clone(parent)
                rx_sink_add_cleanup(sink,@ capture(<-reenter,copy(n)) () {
                    cleanups++
                    if(n==1) {rx_subject_next(reenter,3)}
                } finally {delete reenter})
                if(n==1) {rx_connect(inner,sink)} else {rx_sink_complete(sink)}
            } finally {delete parent;delete inner})
        } finally {delete a;delete b})
        var inscope sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic(s)},@() {})
        delete source
        rx_subject_next(outer,1)
        verify(selected=="1;" && rx_subscriber_count(gate)==1)
        rx_subject_complete(gate)
        verify(selected=="1;2;3;" && cleanups==3)
        rx_subject_complete(outer)
        verify(rx_is_closed(sub) && rx_subscriber_count(outer)==0)
    }
    // A synchronous native connect failure in a queued job clears the rest,
    // cancels outer/active inputs, and unwinds the pump without leaking.
    {
        calls=0
        var inscope gate <- rx_subject(type<int>)
        var view <- rx_clone(gate)
        var source <- rx_range(1,4) |> rx_concat_map(@ capture(<-view) (n:int) {
            calls++
            var inner <- rx_clone(view);var data <- hold()
            return <- rx_create(type<int>,@ capture(<-inner,<-data,copy(n)) (sink:typedecl(rx_sink_marker(type<int>))) {
                verify(data.values[0]==42)
                if(n==2) {panic("native connect failed")}
                rx_connect(inner,sink)
            } finally {delete inner;delete data})
        } finally {delete view})
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic("unexpected on_error")},@() {})
        delete source
        var caught=false
        try {rx_subject_complete(gate)} recover {caught=true}
        verify(caught && calls==2 && rx_is_closed(sub) && rx_subscriber_count(gate)==0 && opened==freed)
        delete sub
    }
    // A throwing teardown abandons the queued jobs and still runs all cleanup.
    {
        calls=0;cleanups=0
        var inscope gate <- rx_subject(type<int>)
        var view <- rx_clone(gate)
        var source <- rx_range(1,3) |> rx_concat_map(@ capture(<-view) (n:int) {
            calls++
            var inner <- rx_clone(view)
            return <- rx_create(type<int>,@ capture(<-inner) (sink:typedecl(rx_sink_marker(type<int>))) {
                rx_sink_add_cleanup(sink,@() {cleanups++;panic("cleanup failed")})
                rx_sink_add_cleanup(sink,@() {cleanups++})
                rx_connect(inner,sink)
            } finally {delete inner})
        } finally {delete view})
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {panic("unexpected error")},@() {panic("unexpected complete")})
        delete source
        var caught=false
        try {rx_subject_complete(gate)} recover {caught=true}
        verify(caught && calls==1 && cleanups==2 && rx_is_closed(sub) && rx_subscriber_count(gate)==0)
        delete sub
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(4)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX concat_map/bounded flat_map lifetime checks OK\n")
}
