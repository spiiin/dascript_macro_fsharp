options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var effects=0
var predicates=0
var finalizations=0

def observe(source:auto) {
    return <- rx_subscribe(source,@(n:int) {trace+="{n};"},@(s:string) {trace+="error:{s};"},@() {trace+="done;"})
}

def checks() {
    {
        trace=""
        var inscope source <- rx_empty(type<int>) |> rx_skip(2) |> rx_take_while(@(n:int){panic("empty predicate");return true}) |> rx_skip_while(@(n:int){panic("empty predicate");return true})
        var inscope sub <- observe(source)
        verify(trace=="done;")
    }
    for(count in range(6)) {
        trace="";effects=0
        var inscope source <- rx_range(1,4) |> rx_tap(@(n:int) {effects++}) |> rx_skip(count)
        var inscope sub <- observe(source)
        verify(effects==4 && rx_is_closed(sub))
        if(count==0) {verify(trace=="1;2;3;4;done;")}
        elif(count==1) {verify(trace=="2;3;4;done;")}
        elif(count==2) {verify(trace=="3;4;done;")}
        elif(count==3) {verify(trace=="4;done;")}
        else {verify(trace=="done;")}
    }
    {
        var inscope input <- rx_range(1,2)
        var caught=false
        try {var bad <- rx_clone(input) |> rx_skip(-1);delete bad} recover {caught=true}
        verify(caught)
    }
    // The failed take predicate's item is excluded; input stops immediately.
    for(limit in range(1,7)) {
        trace="";effects=0;predicates=0
        var inscope source <- rx_range(1,4) |> rx_tap(@(n:int) {effects++}) |> rx_take_while(@ capture(copy(limit)) (n:int) {predicates++;return n<limit})
        var inscope sub <- observe(source)
        verify(predicates==(limit<4 ? limit : 4) && effects==predicates && rx_is_closed(sub))
        if(limit==1) {verify(trace=="done;")}
        if(limit==3) {verify(trace=="1;2;done;")}
        if(limit>4) {verify(trace=="1;2;3;4;done;")}
    }
    // skip_while is a latch, not a filter; the first false item is delivered.
    {
        trace="";predicates=0
        var inscope values:array<int> <- [1,2,3,1,0]
        var inscope source <- rx_from_array(values) |> rx_skip_while(@(n:int) {predicates++;return n<3})
        var inscope sub <- observe(source)
        verify(trace=="3;1;0;done;" && predicates==3)
    }
    for(mode in range(2)) {
        trace="";predicates=0
        var inscope source <- rx_range(1,3) |> rx_skip_while(@ capture(copy(mode)) (n:int) {predicates++;return mode==0})
        var inscope sub <- observe(source)
        verify(predicates==(mode==0 ? 3 : 1))
        verify(trace==(mode==0 ? "done;" : "1;2;3;done;"))
    }
    // Predicate failures become on_error, never a subsequent complete.
    for(mode in range(2)) {
        trace="";effects=0
        var inscope input <- rx_range(1,4) |> rx_tap(@(n:int) {effects++})
        if(mode==0) {
            var inscope source <- rx_clone(input) |> rx_take_while(@(n:int) {if(n==2) {panic("predicate failed")};return true})
            var inscope sub <- observe(source)
            verify(trace=="1;error:predicate failed\n;" && effects==2)
        } else {
            var inscope source <- rx_clone(input) |> rx_skip_while(@(n:int) {if(n==2) {panic("predicate failed")};return true})
            var inscope sub <- observe(source)
            verify(trace=="error:predicate failed\n;" && effects==2)
        }
    }
    // Each subscription has independent counters, latches and pair history.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_skip(1) |> rx_skip_while(@(n:int) {return n<2}) |> rx_take_while(@(n:int) {return n<5}) |> rx_pairwise()
        var inscope a <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {trace+="a{p.previous}:{p.current};"},@(s:string) {panic(s)},@() {trace+="ac;"})
        rx_subject_next(input,1);rx_subject_next(input,2)
        var inscope b <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {trace+="b{p.previous}:{p.current};"},@(s:string) {panic(s)},@() {trace+="bc;"})
        rx_subject_next(input,3);rx_subject_next(input,4);rx_subject_next(input,5)
        verify(trace=="a2:3;a3:4;ac;bc;" && rx_subscriber_count(input)==0)
        trace=""
        var inscope c <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {trace+="{p.previous}:{p.current};"},@(s:string) {panic(s)},@(){trace+="done;"})
        rx_subject_next(input,1);rx_subject_next(input,2);rx_subject_next(input,3);rx_subject_complete(input)
        verify(trace=="2:3;done;")
    }
    for(count in range(4)) {
        trace=""
        var inscope source <- rx_range(1,count) |> rx_pairwise()
        var inscope sub <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {trace+="{p.previous}:{p.current};"},@(s:string) {panic(s)},@(){trace+="done;"})
        verify(trace==(count<2 ? "done;" : (count==2 ? "1:2;done;" : "1:2;2:3;done;")))
    }
    {
        trace=""
        var inscope values:array<string> <- ["a","bb","ccc"]
        var inscope source <- rx_from_array(values) |> rx_pairwise() |> rx_map(@(p:tuple<previous:string;current:string>) {return "{p.previous}/{p.current}"})
        var inscope sub <- rx_subscribe(source,@(s:string) {trace+="{s};"},@(s:string) {panic(s)},@(){trace+="done;"})
        verify(trace=="a/bb;bb/ccc;done;")
    }
    // Reentrant input is queued; history and skip latch are committed first.
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var view <- rx_clone(input)
        var inscope source <- rx_clone(input) |> rx_skip_while(@ capture(<-view) (n:int) {if(n==1) {rx_subject_next(view,2)};return n<2} finally {delete view}) |> rx_pairwise()
        var inscope sub <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {trace+="{p.previous}:{p.current};"},@(s:string) {panic(s)},@(){})
        rx_subject_next(input,1);rx_subject_next(input,3)
        verify(trace=="2:3;")
        rx_unsubscribe(sub);verify(rx_subscriber_count(input)==0)
    }
    // Native source errors pass through every operator, preserving the prefix.
    {
        trace=""
        var inscope source <- rx_throw("source",type<int>) |> rx_skip(2) |> rx_take_while(@(n:int) {panic("unreachable");return true}) |> rx_skip_while(@(n:int) {panic("unreachable");return true}) |> rx_pairwise()
        var inscope sub <- rx_subscribe(source,@(p:tuple<previous:int;current:int>) {panic("unreachable")},@(s:string) {trace=s},@(){panic("unreachable")})
        verify(trace=="source" && rx_is_closed(sub))
    }
    // Non-retaining operators also accept borrowed buffer packets.
    {
        trace=""
        var inscope source <- rx_range(1,6) |> rx_buffer(2) |> rx_skip(1) |> rx_skip_while(@(b:array<int>) {return b[0]<3}) |> rx_take_while(@(b:array<int>) {return b[0]<5}) |> rx_finally(@(){trace+="f;"})
        var inscope sub <- rx_subscribe(source,@(b:array<int>) {trace+="{b[0]},{b[1]};"},@(s:string) {panic(s)},@(){trace+="c;"})
        verify(trace=="3,4;c;f;")
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX selection checks OK\n")
}

