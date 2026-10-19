options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var done=0
var errors=0
def observe(source:auto) {return <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(message:string) {errors++},@(){done++})}
def checks() {
    {
        trace=""
        let completed=done
        var inscope source <- rx_range(1,2) |> rx_merge(rx_range(10,2))
        var inscope sub <- observe(source)
        verify(trace=="1;2;10;11;" && done==completed+1 && rx_is_closed(sub))
    }
    {
        trace=""
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
        var inscope sub <- observe(source)
        rx_subject_next(left,1);rx_subject_next(right,10);rx_subject_next(left,2)
        rx_subject_complete(left)
        verify(!rx_is_closed(sub) && rx_subscriber_count(left)==0 && rx_subscriber_count(right)==1)
        rx_subject_next(right,11);rx_subject_complete(right)
        verify(trace=="1;10;2;11;" && done==completed+1 && rx_is_closed(sub))
    }
    {
        trace=""
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_concat(rx_clone(right))
        var inscope sub <- observe(source)
        verify(rx_subscriber_count(left)==1 && rx_subscriber_count(right)==0)
        rx_subject_next(right,99);rx_subject_next(left,1)
        rx_subject_complete(left)
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==1)
        rx_subject_next(right,10);rx_subject_complete(right)
        verify(trace=="1;10;" && done==completed+1 && rx_is_closed(sub))
    }
    // Empty sources, repeated subscriptions and left-associated three-way trees.
    for(mode in range(2)) {
        trace=""
        let completed=done
        var inscope first <- rx_range(0,0)
        var inscope second <- rx_range(5,2)
        var inscope third <- rx_range(9,1)
        if(mode==0) {
            var inscope source <- first |> rx_merge(second) |> rx_merge(third) |> rx_map(@(n:int) {return n+1})
            for(i in range(2)) {var inscope sub <- observe(source)}
        } else {
            var inscope source <- first |> rx_concat(second) |> rx_concat(third)
            for(i in range(2)) {var inscope sub <- observe(source)}
        }
        verify(trace==(mode==0 ? "6;7;10;6;7;10;" : "5;6;9;5;6;9;") && done==completed+2)
    }
    // A synchronous take can stop a merge's first source and skip the second.
    for(mode in range(2)) {
        trace=""
        let completed=done
        var inscope right <- rx_defer(@() {errors++;return <- rx_range(10,10)})
        var inscope left <- rx_range(1,10)
        let oldErrors=errors
        if(mode==0) {
            var inscope source <- left |> rx_merge(right) |> rx_take(1)
            var inscope sub <- observe(source)
        } else {
            var inscope source <- left |> rx_concat(right) |> rx_take(1)
            var inscope sub <- observe(source)
        }
        verify(trace=="1;" && errors==oldErrors && done==completed+1)
    }
    // Concat starts a synchronous second source without buffering its entire
    // range: take(1) must prevent all later selector effects on that source.
    {
        trace=""
        let oldErrors=errors
        var inscope source <- rx_range(0,0) |> rx_concat(rx_range(10,10) |> rx_map(@(n:int) {errors++;return n})) |> rx_take(1)
        var inscope sub <- observe(source)
        verify(trace=="10;" && errors==oldErrors+1)
    }
    // Failure on either active merge input ends both subscriptions exactly once.
    for(side in range(2)) {
        let oldErrors=errors
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
        var inscope sub <- observe(source)
        if(side==0) {rx_subject_error(left,"left failed")} else {rx_subject_error(right,"right failed")}
        verify(errors==oldErrors+1 && done==completed && rx_is_closed(sub))
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
        rx_subject_complete(left);rx_subject_complete(right)
        verify(errors==oldErrors+1 && done==completed)
    }
    // A failed concat left never subscribes to the right factory. Errors from
    // a deferred second factory terminate once after left completion.
    for(mode in range(2)) {
        let oldErrors=errors
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_defer(@() {errors+=100;panic("right factory failed");return <- rx_range(0,0)})
        var inscope source <- rx_clone(left) |> rx_concat(right)
        var inscope sub <- observe(source)
        if(mode==0) {rx_subject_error(left,"left failed")} else {rx_subject_complete(left)}
        verify(errors==oldErrors+(mode==0 ? 1 : 101) && done==completed && rx_is_closed(sub))
        verify(rx_subscriber_count(left)==0)
    }
    // A synchronous first-source failure also prevents merge's second
    // subscription. This is fail-fast merge, not mergeDelayError.
    for(mode in range(2)) {
        let oldErrors=errors
        var inscope left <- rx_defer(@() {panic("first failed");return <- rx_range(0,0)})
        var inscope right <- rx_defer(@() {errors+=100;return <- rx_range(1,1)})
        if(mode==0) {var inscope source <- left |> rx_merge(right);var inscope sub <- observe(source)}
        else {var inscope source <- left |> rx_concat(right);var inscope sub <- observe(source)}
        verify(errors==oldErrors+1)
    }
    // The right factory observes the first subscription already detached.
    {
        trace=""
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var before <- rx_clone(left)
        var inscope right <- rx_defer(@ capture(<-before) () {
            verify(rx_subscriber_count(before)==0)
            return <- rx_range(30,3)
        } finally {delete before})
        var inscope source <- rx_clone(left) |> rx_concat(right) |> rx_take(1)
        var inscope sub <- observe(source)
        rx_subject_complete(left)
        verify(trace=="30;" && done==completed+1 && rx_is_closed(sub))
    }
    // Different descriptor kinds and type-changing map pipelines share one
    // element type. Retaining/consuming these sources must preserve deduction.
    {
        trace=""
        var inscope items:array<string>
        items <- ["x","y"]
        var inscope source <- rx_range(1,2) |> rx_map(@(n:int) {return "{n}"}) |> rx_merge(rx_from_array(items)) |> rx_map(@(value:string) {return length(value)})
        var inscope sub <- observe(source)
        verify(trace=="1;1;1;1;")
    }
    // The same owning handle cannot be consumed twice. An explicit retained
    // view is supported, including concat of an already completed Subject.
    for(mode in range(2)) {
        var source <- rx_range(1,1)
        var caught=false
        try {
            if(mode==0) {var result <- source |> rx_merge(source);delete result}
            else {var result <- source |> rx_concat(source);delete result}
        } recover {caught=true}
        verify(caught)
        delete source
    }
    {
        trace=""
        let completed=done
        var inscope subject <- rx_subject(type<int>)
        var inscope source <- rx_clone(subject) |> rx_concat(rx_clone(subject))
        var inscope sub <- observe(source)
        rx_subject_next(subject,1);rx_subject_complete(subject)
        verify(trace=="1;" && done==completed+1 && rx_is_closed(sub) && rx_subscriber_count(subject)==0)
    }
    // Explicit unsubscribe and owner destruction detach all active children,
    // and cancelling concat before left completion never starts its right side.
    for(mode in range(4)) {
        let completed=done
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<int>)
        if(mode<2) {
            var inscope source <- rx_clone(left) |> rx_merge(rx_clone(right))
            {
                var inscope sub <- observe(source)
                if(mode==0) {verify(rx_unsubscribe(sub));verify(!rx_unsubscribe(sub))}
            }
        } else {
            var inscope source <- rx_clone(left) |> rx_concat(rx_clone(right))
            {
                var inscope sub <- observe(source)
                if(mode==2) {rx_unsubscribe(sub)}
            }
            rx_subject_complete(left)
        }
        verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0 && done==completed)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX merge/concat checks OK\n")
}
