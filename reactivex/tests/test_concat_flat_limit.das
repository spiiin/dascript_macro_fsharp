options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var projected=""
var calls=0
var errors=0
var completed=0

def compose(var source,selector:auto;limit:int;concat:bool) {
    // Both paths have the same descriptor type and semantics at limit one.
    if(concat) {return <- source |> rx_concat_map(selector)}
    return <- source |> rx_flat_map(selector,limit)
}
def select_inner(a,b,c:auto) {
    var first <- rx_clone(a);var second <- rx_clone(b);var third <- rx_clone(c)
    return <- @ capture(<-first,<-second,<-third) (n:int) {
        calls++;projected+="{n};"
        if(n==1) {return <- rx_clone(first)}
        if(n==2) {return <- rx_clone(second)}
        return <- rx_clone(third)
    } finally {delete first;delete second;delete third}
}
def observe(source:auto) {
    return <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {errors++;trace+="error;"},@() {completed++;trace+="done;"})
}
def checks() {
    for(limit in range(1,4)) {
        calls=0;projected="";trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope c <- rx_subject(type<int>)
        var inscope source <- compose(rx_range(1,3),select_inner(a,b,c),limit,limit==1)
        var inscope sub <- observe(source)
        verify(calls==limit && !rx_is_closed(sub))
        verify(rx_subscriber_count(a)==1 && rx_subscriber_count(b)==(limit>=2 ? 1 : 0) && rx_subscriber_count(c)==(limit==3 ? 1 : 0))
        if(limit>=2) {rx_subject_next(b,20)}
        rx_subject_next(a,10)
        rx_subject_complete(a)
        verify(calls==(limit==1 ? 2 : 3))
        rx_subject_next(b,21);rx_subject_complete(b)
        verify(calls==3 && !rx_is_closed(sub))
        rx_subject_next(c,30);rx_subject_complete(c)
        verify(trace==(limit==1 ? "10;21;30;done;" : "20;10;21;30;done;"))
        verify(projected=="1;2;3;" && rx_is_closed(sub))
        verify(rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0 && rx_subscriber_count(c)==0)
    }
    // The next waiting job starts as soon as any slot opens, not in batches.
    {
        calls=0;projected="";trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope c <- rx_subject(type<int>)
        var inscope source <- rx_range(1,3) |> rx_flat_map(select_inner(a,b,c),2)
        var inscope sub <- observe(source)
        rx_subject_complete(b)
        verify(calls==3 && rx_subscriber_count(a)==1 && rx_subscriber_count(c)==1)
        rx_subject_next(c,30);rx_subject_complete(c);rx_subject_next(a,10);rx_subject_complete(a)
        verify(trace=="30;10;done;" && projected=="1;2;3;")
    }
    // Concurrent subscriptions have independent controls and waiting queues.
    {
        calls=0;projected="";trace=""
        var inscope outer <- rx_subject(type<int>)
        var inscope inner <- rx_subject(type<int>)
        var inscope source <- rx_clone(outer) |> rx_flat_map(select_inner(inner,inner,inner),1)
        var inscope a <- observe(source)
        var inscope b <- observe(source)
        rx_subject_next(outer,1);rx_subject_next(outer,2)
        verify(calls==2 && rx_subscriber_count(inner)==2)
        rx_unsubscribe(a)
        verify(rx_subscriber_count(inner)==1)
        rx_subject_next(inner,7);rx_subject_complete(inner)
        verify(calls==3 && trace=="7;" && !rx_is_closed(b))
        rx_subject_complete(outer)
        verify(rx_is_closed(b) && trace=="7;done;" && rx_subscriber_count(outer)==0)
    }
    // Reentrant outer complete inside selector must wait for its new child.
    {
        trace=""
        var inscope outer <- rx_subject(type<int>)
        var inscope inner <- rx_subject(type<int>)
        var a <- rx_clone(outer);var b <- rx_clone(inner)
        var inscope source <- rx_clone(outer) |> rx_concat_map(@ capture(<-a,<-b) (n:int) {
            rx_subject_complete(a)
            return <- rx_clone(b)
        } finally {delete a;delete b})
        var inscope sub <- observe(source)
        rx_subject_next(outer,1)
        verify(!rx_is_closed(sub) && rx_subscriber_count(inner)==1)
        rx_subject_next(inner,9);rx_subject_complete(inner)
        verify(trace=="9;done;" && rx_is_closed(sub))
    }
    // Errors from outer/inner/queued selector/factory abandon all queued values.
    for(mode in range(4)) {
        calls=0;trace="";errors=0
        var inscope outer <- rx_subject(type<int>)
        var inscope inner <- rx_subject(type<int>)
        var view <- rx_clone(inner)
        var source <- rx_clone(outer) |> rx_concat_map(@ capture(<-view,copy(mode)) (n:int) {
            calls++
            if(mode==2 && n==2) {panic("selector failed")}
            var child <- rx_clone(view)
            return <- rx_defer(@ capture(<-child,copy(mode),copy(n)) () {
                if(mode==3 && n==2) {panic("factory failed")}
                return <- rx_clone(child)
            } finally {delete child})
        } finally {delete view})
        var inscope sub <- observe(source)
        delete source
        rx_subject_next(outer,1);rx_subject_next(outer,2);rx_subject_next(outer,3)
        verify(calls==1)
        if(mode==0) {rx_subject_error(outer,"outer failed")}
        elif(mode==1) {rx_subject_error(inner,"inner failed")}
        else {rx_subject_complete(inner)}
        verify(calls==(mode<2 ? 1 : 2) && errors==1 && trace=="error;" && rx_is_closed(sub))
        verify(rx_subscriber_count(outer)==0 && rx_subscriber_count(inner)==0)
    }
    // Hot values emitted before an inner is subscribed are not replayed.
    {
        trace="";calls=0;projected=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- rx_range(1,2) |> rx_concat_map(select_inner(a,b,b))
        var inscope sub <- observe(source)
        rx_subject_next(b,99);rx_subject_next(a,10);rx_subject_complete(a)
        rx_subject_next(b,20);rx_subject_complete(b)
        verify(trace=="10;20;done;")
    }
    // Large backlog of synchronous empty inners drains iteratively.
    {
        calls=0
        var inscope gate <- rx_subject(type<int>)
        var view <- rx_clone(gate)
        var inscope source <- rx_range(0,2048) |> rx_concat_map(@ capture(<-view) (n:int) {
            calls++
            var child <- rx_clone(view)
            return <- rx_defer(@ capture(<-child,copy(n)) () {
                if(n!=0) {rx_subject_complete(child)}
                return <- rx_clone(child)
            } finally {delete child})
        } finally {delete view})
        var inscope sub <- observe(source)
        verify(calls==1)
        rx_subject_complete(gate)
        verify(calls==2048 && rx_is_closed(sub))
    }
    // Type-changing chains and separately owned string values in the FIFO.
    {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var view <- rx_scheduler_clone(clock)
        var inscope source <- rx_range(1,3) |> rx_map(@(n:int) {return "v{n}"}) |> rx_concat_map(@ capture(<-view) (s:string) {return <- rx_just(s) |> rx_delay(1,view)} finally {delete view}) |> rx_map(@(s:string) {return "{s};"})
        var inscope sub <- rx_subscribe(source,@(s:string) {trace+=s},@(s:string) {panic(s)},@() {})
        rx_advance_by(clock,3)
        verify(trace=="v1;v2;v3;" && rx_is_closed(sub) && rx_pending_count(clock)==0)
    }
    for(limit in range(-1,1)) {
        var source <- rx_range(1,1)
        var selector <- @(n:int) {return <- rx_just(n)}
        var caught=false
        try {var result <- rx_flat_map(source,selector,limit);delete result} recover {caught=true}
        delete source;unsafe {delete selector}
        verify(caught)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(4)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX concat_map/bounded flat_map checks OK\n")
}
