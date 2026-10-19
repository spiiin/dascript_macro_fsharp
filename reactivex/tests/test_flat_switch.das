options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var done=0
var errors=0
var calls=0
var effects=0
var inCallback=false
def compose(var source,selector:auto;tag:RxSwitchMapTag) {return <- source |> rx_switch_map(selector)}
def compose(var source,selector:auto;tag:RxFlatMapTag) {return <- source |> rx_flat_map(selector)}
def choose(first,second:auto) {
    var a <- rx_clone(first);var b <- rx_clone(second)
    return <- @ capture(<-a,<-b) (n:int) {calls++;if(n==1) {return <- rx_clone(a)};return <- rx_clone(b)} finally {delete a;delete b}
}
def observe(source:auto) {
    return <- rx_subscribe(source,@(n:int) {verify(!inCallback);trace+="{n};"},
        @(message:string) {errors++;trace+="error;"},@(){verify(!inCallback);done++;trace+="done;"})
}
def checks(tag:auto;switching:bool) {
    {
        var inscope source <- compose(rx_range(1,2),@(n:int) {return <- rx_range(n*10,2)},tag)
        for(i in range(2)) {
            trace=""
            var inscope sub <- observe(source)
            verify(trace=="10;11;20;21;done;" && rx_is_closed(sub))
        }
    }
    {
        trace="";calls=0
        var inscope outer <- rx_subject(type<int>)
        var inscope first <- rx_subject(type<int>)
        var inscope second <- rx_subject(type<int>)
        var inscope source <- compose(rx_clone(outer),choose(first,second),tag)
        var inscope sub <- observe(source)
        rx_subject_next(outer,1);rx_subject_next(first,10)
        rx_subject_next(outer,2)
        verify(rx_subscriber_count(first)==(switching ? 0 : 1) && rx_subscriber_count(second)==1)
        rx_subject_next(first,11);rx_subject_next(second,20)
        rx_subject_complete(outer)
        verify(!rx_is_closed(sub) && rx_subscriber_count(outer)==0)
        rx_subject_complete(second)
        verify(rx_is_closed(sub)==switching)
        rx_subject_complete(first)
        verify(trace==(switching ? "10;20;done;" : "10;11;20;done;") && calls==2 && rx_is_closed(sub))
    }
    // Empty outer and empty inners complete exactly once.
    for(emptyOuter in range(2)) {
        calls=0;trace=""
        var inscope source <- compose(rx_range(1,emptyOuter==1 ? 0 : 3),@(n:int) {calls++;return <- rx_range(0,0)},tag)
        var inscope sub <- observe(source)
        verify(calls==(emptyOuter==1 ? 0 : 3) && trace=="done;" && rx_is_closed(sub))
    }
    for(limit in range(2)) {
        calls=0;effects=0
        var inscope source <- compose(rx_range(1,10),@(n:int) {
            calls++;return <- rx_range(n*10,10) |> rx_map(@(value:int) {effects++;return value})
        },tag) |> rx_take(limit)
        var inscope sub <- observe(source)
        verify(calls==limit && effects==limit && rx_is_closed(sub))
    }
    // Errors from outer, either inner, selector, or an inner defer factory.
    for(mode in range(6)) {
        trace=""
        let old=errors
        var inscope outer <- rx_subject(type<int>)
        var inscope first <- rx_subject(type<int>)
        var inscope second <- rx_subject(type<int>)
        var a <- rx_clone(first);var b <- rx_clone(second)
        var selector <- @ capture(<-a,<-b,copy(mode)) (n:int) {
            if(mode==3 && n==2) {panic("selector failed")}
            if(n==1) {return <- rx_clone(a)}
            return <- rx_clone(b)
        } finally {delete a;delete b}
        var inscope source <- compose(rx_clone(outer),selector,tag)
        var inscope sub <- observe(source)
        rx_subject_next(outer,1);rx_subject_next(outer,2)
        if(mode==0) {rx_subject_error(outer,"outer failed")}
        elif(mode==1) {rx_subject_error(first,"first failed")}
        elif(mode==2) {rx_subject_error(second,"second failed")}
        elif(mode==4) {rx_unsubscribe(sub)}
        elif(mode==5) {rx_subject_complete(outer);rx_subject_error(second,"after outer completed")}
        if(mode==1 && switching) {
            verify(errors==old && !rx_is_closed(sub)) // stale inner error is ignored.
            rx_subject_complete(outer);rx_subject_complete(second)
        } else {verify(errors==old+((mode==4) ? 0 : 1))}
        verify(rx_is_closed(sub))
        verify(rx_subscriber_count(outer)==0 && rx_subscriber_count(first)==0 && rx_subscriber_count(second)==0)
    }
    {
        let old=errors
        var inscope source <- compose(rx_range(1,3),@(n:int) {
            return <- rx_defer(@ capture(copy(n)) () {if(n==2) {panic("inner factory failed")};return <- rx_range(n,1)})
        },tag)
        var inscope sub <- observe(source)
        verify(errors==old+1 && rx_is_closed(sub))
    }
    // Two independent subscriptions must maintain independent inner lists.
    {
        var inscope outer <- rx_subject(type<int>)
        var inscope inner <- rx_subject(type<int>)
        var inscope source <- compose(rx_clone(outer),choose(inner,inner),tag)
        var inscope a <- observe(source)
        var inscope b <- observe(source)
        rx_subject_next(outer,1)
        verify(rx_subscriber_count(inner)==2)
        rx_unsubscribe(a)
        verify(rx_subscriber_count(inner)==1 && rx_subscriber_count(outer)==1)
        rx_subject_complete(outer);rx_subject_complete(inner)
        verify(rx_is_closed(b))
    }
    // Many live inners exercise list growth, removal, and synchronous finalization.
    {
        var inscope outer <- rx_subject(type<int>)
        var inscope inner <- rx_subject(type<int>)
        var inscope source <- compose(rx_clone(outer),choose(inner,inner),tag)
        var inscope sub <- observe(source)
        for(i in range(64)) {rx_subject_next(outer,i)}
        verify(rx_subscriber_count(inner)==(switching ? 1 : 64))
        rx_subject_complete(inner);rx_subject_complete(outer)
        verify(rx_is_closed(sub) && rx_subscriber_count(inner)==0)
    }
    // Switching also invalidates already queued notifications of the old inner.
    {
        trace=""
        var inscope outer <- rx_subject(type<int>)
        var inscope first <- rx_subject(type<int>)
        var inscope second <- rx_subject(type<int>)
        var inscope source <- compose(rx_clone(outer),choose(first,second),tag)
        var ov <- rx_clone(outer);var av <- rx_clone(first);var bv <- rx_clone(second)
        var inscope sub <- rx_subscribe(source,@ capture(<-ov,<-av,<-bv) (n:int) {
            verify(!inCallback);inCallback=true;trace+="{n};"
            if(n==1) {
                rx_subject_next(ov,2);rx_subject_next(bv,20);rx_subject_next(bv,21)
                rx_subject_next(ov,1);rx_subject_next(av,2)
                verify(trace=="1;");trace+="return;"
            }
            inCallback=false
        } finally {delete ov;delete av;delete bv},@(message:string) {panic(message)},@(){verify(!inCallback)})
        rx_subject_next(outer,1);rx_subject_next(first,1)
        verify(trace==(switching ? "1;return;2;" : "1;return;20;21;2;2;"))
        rx_unsubscribe(sub)
        verify(rx_subscriber_count(outer)==0 && rx_subscriber_count(first)==0 && rx_subscriber_count(second)==0)
    }
}
def types() {
    var inscope source <- rx_range(1,2) |> rx_flat_map(@(n:int) {return <- rx_range(n*10,2) |> rx_map(@(v:int) {return "{v}"})}) |> rx_switch_map(@(s:string) {return <- rx_range(length(s),1)}) |> rx_map(@(n:int) {return n+100}) |> rx_take(1)
    var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==102)},@(s:string) {panic(s)},@(){})
    verify(rx_is_closed(sub))
}
[export]
def main() {
    checks(RxSwitchMapTag(),true);checks(RxFlatMapTag(),false);types()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks(RxSwitchMapTag(),true);checks(RxFlatMapTag(),false);types()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX switch_map/flat_map checks OK\n")
}
