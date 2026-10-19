options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var cleanups=0
var errors=0
var completed=0
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
def hold() {opened++;return <- Hold(values <- [42])}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        var data <- hold()
        return <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.values[0]==42);return n} finally {delete data})
    } finally {delete view})
}
def cleanup(fail:bool) {return <- @ capture(copy(fail)) () {cleanups++;if(fail) {panic("cleanup failed")}}}

def checks() {
    // A notifier that completes without a value releases its own resources
    // while the main source remains active.
    {
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<int>)
        var source <- tracked(input) |> rx_take_until(tracked(stop))
        var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==1)},@(s:string) {panic(s)},@() {})
        delete source
        verify(opened==freed+2)
        rx_subject_complete(stop)
        verify(opened==freed+1 && rx_subscriber_count(stop)==0 && rx_subscriber_count(input)==1 && !rx_is_closed(sub))
        rx_subject_next(input,1);rx_subject_complete(input)
        verify(opened==freed && rx_is_closed(sub))
    }
    for(mode in range(11)) {
        errors=0;completed=0
        let before=cleanups
        var inscope input <- rx_subject(type<int>)
        var inscope stop <- rx_subject(type<int>)
        var source <- tracked(input) |> rx_take_until(tracked(stop)) |> rx_take(mode==5 ? 1 : 100)
        var observerData <- hold()
        var sub <- rx_subscribe(source,@ capture(<-observerData,copy(mode)) (n:int) {
            verify(observerData.values[0]==42);if(mode==6) {panic("next failed")}
        } finally {delete observerData},@ capture(copy(mode)) (s:string) {errors++;if(mode==8) {panic("error failed")}},
            @ capture(copy(mode)) () {completed++;if(mode==7) {panic("complete failed")}})
        delete source
        verify(opened==freed+3 && rx_subscriber_count(input)==1 && rx_subscriber_count(stop)==1)
        rx_add_cleanup(sub,cleanup(mode==9));rx_add_cleanup(sub,cleanup(false))
        var caught=false
        try {
            if(mode==3 || mode==9) {rx_unsubscribe(sub)}
            elif(mode==4) {delete sub}
            else {
                rx_subject_next(input,1)
                if(mode==1 || mode==8) {rx_subject_error(input,"input failed")}
                elif(mode==2) {rx_subject_error(stop,"signal failed")}
                elif(mode==10) {rx_subject_complete(input)}
                else {rx_subject_next(stop,1)}
            }
        } recover {caught=true}
        verify(caught==(mode==6 || mode==7 || mode==8 || mode==9))
        if(mode!=4) {verify(rx_is_closed(sub));delete sub}
        verify(opened==freed && rx_subscriber_count(input)==0 && rx_subscriber_count(stop)==0 && cleanups==before+2)
        verify(errors==((mode==1 || mode==2 || mode==8) ? 1 : 0))
        verify(completed==((mode==0 || mode==5 || mode==7 || mode==10) ? 1 : 0))
    }
    // Error from either connect unwinds the other subscription and both captures.
    for(side in range(2)) {
        var inscope input <- rx_subject(type<int>)
        var data <- hold()
        var bad <- rx_create(type<int>,@ capture(<-data) (sink:typedecl(rx_sink_marker(type<int>))) {
            verify(data.values[0]==42)
            rx_sink_add_cleanup(sink,cleanup(false));panic("connect failed")
        } finally {delete data})
        var sub <- rx_subscription()
        var caught=false
        if(side==0) {
            var source <- bad |> rx_take_until(tracked(input))
            try {rx_subscribe_with(sub,source,@(n:int) {},@(s:string) {panic("unexpected on_error")},@() {})} recover {caught=true}
            delete source
        } else {
            var source <- tracked(input) |> rx_take_until(bad)
            try {rx_subscribe_with(sub,source,@(n:int) {},@(s:string) {panic("unexpected on_error")},@() {})} recover {caught=true}
            delete source
        }
        delete sub
        verify(caught && rx_subscriber_count(input)==0 && opened==freed)
    }
    // Attempt both child cleanups even if one throws. Native cleanup failures
    // propagate on completion; an existing on_error preserves its own message.
    for(error in range(2)) {
        let before=cleanups
        var inscope stop <- rx_subject(type<int>)
        var source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,cleanup(true));rx_sink_add_cleanup(sink,cleanup(false))
        }) |> rx_take_until(tracked(stop))
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {verify(s=="signal failed")},@() {panic("unexpected complete")})
        delete source
        var caught=false
        try {if(error==0) {rx_subject_next(stop,1)} else {rx_subject_error(stop,"signal failed")}} recover {caught=true}
        verify(caught==(error==0) && rx_is_closed(sub) && cleanups==before+2 && rx_subscriber_count(stop)==0 && opened==freed)
        delete sub
    }
    // A signal from synchronous on_next also waits for the producer's late
    // cleanup registration before downstream completion.
    {
        let before=cleanups
        var inscope stop <- rx_subject(type<int>)
        var source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_next(sink,1)
            rx_sink_add_cleanup(sink,cleanup(false))
        }) |> rx_take_until(rx_clone(stop))
        var view <- rx_clone(stop)
        var inscope sub <- rx_subscribe(source,@ capture(<-view) (n:int) {rx_subject_next(view,1)} finally {delete view},
            @(s:string) {panic(s)},@ capture(copy(before)) () {verify(cleanups==before+1)})
        delete source
        verify(rx_is_closed(sub) && rx_subscriber_count(stop)==0)
    }
    // Late cleanup registration after a synchronous stopping signal still runs.
    {
        let before=cleanups
        var data <- hold()
        var source <- rx_range(1,3) |> rx_take_until(rx_create(type<int>,@ capture(<-data) (sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_next(sink,1)
            rx_sink_add_cleanup(sink,cleanup(false))
        } finally {delete data}))
        var inscope sub <- rx_subscribe(source,@(n:int) {panic("source must not start")},@(s:string) {panic(s)},@() {verify(cleanups==before+1)})
        delete source
        verify(opened==freed && rx_is_closed(sub))
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX take_until lifetime checks OK\n")
}
