options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var done=0
var errors=0
var started=0
var effects=0
var inCallback=false
def compose(left,right:auto;tag:RxLatestTag) {return <- rx_clone(left) |> rx_combine_latest(rx_clone(right))}
def compose(left,right:auto;tag:RxZipTag) {return <- rx_clone(left) |> rx_zip(rx_clone(right))}
def observe(source:auto) {
    return <- rx_subscribe(source,@(v:tuple<first:int;second:int>) {trace+="{v.first}:{v.second};"},
        @(message:string) {errors++},@(){verify(!inCallback);done++;trace+="done;"})
}
def checks(tag:auto;zip:bool) {
    {
        var inscope a <- rx_range(1,3)
        var inscope b <- rx_range(10,2)
        var inscope source <- compose(a,b,tag)
        for(i in range(2)) {
            trace=""
            var inscope sub <- observe(source)
            verify(trace==(zip ? "1:10;2:11;done;" : "3:10;3:11;done;"))
            verify(rx_is_closed(sub))
        }
    }
    {
        trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var inscope sub <- observe(source)
        rx_subject_next(a,1);rx_subject_next(a,2)
        verify(trace=="")
        rx_subject_next(b,10);rx_subject_next(b,11)
        verify(trace==(zip ? "1:10;2:11;" : "2:10;2:11;"))
        rx_subject_complete(a)
        if(zip) {verify(rx_is_closed(sub) && trace=="1:10;2:11;done;")}
        else {
            verify(!rx_is_closed(sub))
            rx_subject_next(b,12);rx_subject_complete(b)
            verify(trace=="2:10;2:11;2:12;done;")
        }
        verify(rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0)
    }
    // Either empty input completes immediately, including before right connects.
    for(side in range(2)) {
        trace="";started=0
        var inscope a <- rx_range(0,side==0 ? 0 : 2)
        var inscope b <- rx_defer(@ capture(copy(side)) () {started++;return <- rx_range(10,side==1 ? 0 : 2)})
        var inscope source <- compose(a,b,tag)
        var inscope sub <- observe(source)
        verify(trace=="done;" && started==(side==0 ? 0 : 1) && rx_is_closed(sub))
    }
    // Completed zip input keeps unmatched values until consumed, in either direction.
    for(side in range(2)) {
        trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var inscope sub <- observe(source)
        if(side==0) {
            rx_subject_next(a,1);rx_subject_next(a,2);rx_subject_complete(a)
            verify(!rx_is_closed(sub))
            rx_subject_next(b,10);rx_subject_next(b,11);rx_subject_next(b,12)
            if(!zip) {rx_subject_complete(b)}
            verify(trace==(zip ? "1:10;2:11;done;" : "2:10;2:11;2:12;done;"))
        } else {
            rx_subject_next(b,10);rx_subject_next(b,11);rx_subject_complete(b)
            verify(!rx_is_closed(sub))
            rx_subject_next(a,1);rx_subject_next(a,2);rx_subject_next(a,3)
            if(!zip) {rx_subject_complete(a)}
            verify(trace==(zip ? "1:10;2:11;done;" : "1:11;2:11;3:11;done;"))
        }
        verify(rx_is_closed(sub))
    }
    for(side in range(2)) {
        let old=errors
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var inscope sub <- observe(source)
        rx_subject_next(a,1)
        if(side==0) {rx_subject_error(a,"first failed")} else {rx_subject_error(b,"second failed")}
        verify(errors==old+1 && rx_is_closed(sub))
        verify(rx_subscriber_count(a)==0 && rx_subscriber_count(b)==0)
    }
    // A synchronous error skips the second factory; a right factory error closes left.
    for(side in range(2)) {
        started=0
        let old=errors
        var inscope a <- rx_defer(@ capture(copy(side)) () {if(side==0) {panic("first factory")};return <- rx_range(0,1)})
        var inscope b <- rx_defer(@ capture(copy(side)) () {started++;if(side==1) {panic("second factory")};return <- rx_range(0,1)})
        var inscope source <- compose(a,b,tag)
        var inscope sub <- observe(source)
        verify(errors==old+1 && started==side && rx_is_closed(sub))
    }
    // Delivery remains synchronous: take(1) prevents the rest of right's effects.
    {
        effects=0
        var inscope a <- rx_range(1,3)
        var inscope b <- rx_range(10,5) |> rx_map(@(n:int) {effects++;return n})
        var inscope source <- compose(a,b,tag) |> rx_take(1)
        var inscope sub <- observe(source)
        verify(effects==1 && rx_is_closed(sub))
    }
    // Reentrant notifications snapshot pairs and finish after the active callback.
    {
        trace=""
        var inscope a <- rx_subject(type<int>)
        var inscope b <- rx_subject(type<int>)
        var inscope source <- compose(a,b,tag)
        var av <- rx_clone(a)
        var bv <- rx_clone(b)
        var inscope sub <- rx_subscribe(source,@ capture(<-av,<-bv) (v:tuple<first:int;second:int>) {
            verify(!inCallback);inCallback=true;trace+="{v.first}:{v.second};"
            if(v.first==1 && v.second==10) {
                rx_subject_next(av,2);rx_subject_next(bv,11);rx_subject_complete(av);rx_subject_complete(bv)
                verify(trace=="1:10;")
            }
            inCallback=false
        } finally {delete av;delete bv},@(message:string) {panic(message)},@(){verify(!inCallback);trace+="done;"})
        rx_subject_next(a,1);rx_subject_next(b,10)
        verify(trace==(zip ? "1:10;2:11;done;" : "1:10;2:10;2:11;done;"))
        verify(rx_is_closed(sub))
    }
}
def types() {
    // Heterogeneous, nested and type-changing pipelines must retain their types.
    var inscope numbers <- rx_range(1,2)
    var words:array<string>;words <- ["a","b"]
    var inscope text <- rx_from_array(words)
    delete words
    var inscope source <- rx_clone(numbers) |> rx_zip(rx_clone(text)) |> rx_combine_latest(rx_range(100,1)) |> rx_map(@(v:tuple<first:tuple<first:int;second:string>;second:int>) {return "{v.first.first}{v.first.second}:{v.second}"}) |> rx_take(1)
    var inscope sub <- rx_subscribe(source,@(s:string) {verify(s=="2b:100")},@(s:string) {panic(s)},@(){})
    verify(rx_is_closed(sub))
}
[export]
def main() {
    checks(RxLatestTag(),false);checks(RxZipTag(),true);types()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks(RxLatestTag(),false);checks(RxZipTag(),true);types()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX combine_latest/zip checks OK\n")
}
