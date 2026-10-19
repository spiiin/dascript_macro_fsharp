options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
require strings
require daslib/strings_boost
var trace=""
var count=0
var sum=0
var subscriptions:array<RxSubscription>
var saved:typedecl(rx_group_marker(type<int>,type<int>))
var sink:typedecl(rx_sink_marker(type<int>))
var keyText=""
struct Key {n:int}
def operator ==(a,b:Key) : bool {
    if(a.n==9 || b.n==9) {panic("key comparison failed")}
    return a.n==b.n
}

def observe(source:auto) {
    return <- rx_subscribe(source,@(g:typedecl(rx_group_marker(type<int>,type<int>))) {
        let key=rx_group_key(g);count++;trace+="g{key};"
        subscriptions |> emplace(rx_subscribe(g,@ capture(copy(key)) (n:int) {trace+="{key}:{n};";sum+=n},
            @ capture(copy(key)) (message:string) {trace+="e{key}:{message};"},
            @ capture(copy(key)) () {trace+="c{key};"}))
    },@(message:string) {trace+="error:{message};"},@(){trace+="done;"})
}

def checks() {
    trace="";count=0;sum=0
    {
        var inscope source <- rx_range(1,5) |> rx_group_by(@(n:int) {return n%2})
        var inscope sub <- observe(source)
        verify(trace=="g1;1:1;g0;0:2;1:3;0:4;1:5;c1;c0;done;" && count==2 && sum==15 && rx_is_closed(sub))
        for(s in subscriptions) {verify(rx_is_closed(s))};delete subscriptions
    }
    trace="";count=0
    {
        var inscope source <- rx_empty(type<int>) |> rx_group_by(@(n:int) {return n})
        var inscope sub <- observe(source)
        verify(trace=="done;" && count==0 && rx_is_closed(sub))
    }
    // Source and key-selector failures close groups in creation order, then outer.
    for(mode in range(3)) {
        trace="";count=0
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_group_by(@ capture(copy(mode)) (n:int) {
            if(mode==1 && n==3) {panic("bad key")};return n%2
        },mode==2 ? 2 : 0)
        var inscope sub <- observe(source)
        rx_subject_next(input,1);rx_subject_next(input,2)
        if(mode==0) {rx_subject_error(input,"")}
        elif(mode==1) {rx_subject_next(input,3)}
        else {rx_subject_next(input,4);rx_subject_complete(input)}
        if(mode==0) {verify(trace=="g1;1:1;g0;0:2;e1:;e0:;error:;")}
        elif(mode==1) {verify(count==2 && contains(trace,"e1:bad key") && contains(trace,"e0:bad key") && contains(trace,"error:bad key"))}
        else {verify(trace=="g1;1:1;g0;0:2;0:4;c1;c0;done;")}
        verify(rx_is_closed(sub) && rx_subscriber_count(input)==0);delete subscriptions
    }
    trace="";count=0
    {
        var inscope source <- rx_range(1,4) |> rx_group_by(@(n:int){return n},2)
        var inscope sub <- observe(source)
        verify(trace=="g1;1:1;g2;2:2;e1:rx_group_by: group limit exceeded;e2:rx_group_by: group limit exceeded;error:rx_group_by: group limit exceeded;" && count==2)
        delete subscriptions
    }
    // Groups do not replay values. Unsubscribing a listener does not recreate a key.
    trace="";count=0
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_group_by(@(n:int) {return 7})
        var inscope outer <- rx_subscribe(source,@(g:typedecl(saved)) {count++;saved <- rx_clone(g)},@(s:string){panic(s)},@(){})
        rx_subject_next(input,1)
        var listener <- rx_subscribe(saved,@(n:int){trace+="{n};"},@(s:string){panic(s)},@(){trace+="end;"})
        rx_subject_next(input,2);rx_unsubscribe(listener);delete listener
        rx_subject_next(input,3)
        var inscope late <- rx_subscribe(saved,@(n:int){trace+="{n};"},@(s:string){panic(s)},@(){trace+="end;"})
        rx_subject_next(input,4);rx_subject_complete(input)
        verify(trace=="2;4;end;" && count==1 && rx_is_closed(late) && rx_group_key(saved)==7)
        var inscope terminal <- rx_subscribe(saved,@(n:int){panic("no replay")},@(s:string){panic(s)},@(){trace+="late;"})
        verify(trace=="2;4;end;late;" && rx_is_closed(terminal));delete saved
    }
    // Pass-through operators and explicit flattening accept borrowed groups.
    sum=0
    {
        var inscope source <- rx_range(1,6) |> rx_group_by(@(n:int){return n%2}) |> rx_filter(@(g:typedecl(saved)){return rx_group_key(g)==1}) |> rx_flat_map(@(g:typedecl(saved)){return <- rx_clone(g)})
        var inscope sub <- rx_subscribe(source,@(n:int){sum+=n},@(s:string){panic(s)},@(){})
        verify(sum==9 && rx_is_closed(sub))
    }
    // Custom producers may reenter while announcing a new group. The first
    // value must still precede reentrant values and terminal notifications.
    for(reenter in range(2)) {
        trace="";count=0
        var inscope input <- rx_create(type<int>,@(target:typedecl(sink)){sink <- rx_sink_clone(target)})
        var inscope source <- rx_clone(input) |> rx_group_by(@ capture(copy(reenter)) (n:int){
            if(reenter==1 && n==1) {rx_sink_next(sink,3);rx_sink_next(sink,2);rx_sink_complete(sink)}
            return n%2
        })
        var inscope sub <- rx_subscribe(source,@ capture(copy(reenter)) (g:typedecl(saved)) {
            let key=rx_group_key(g);trace+="g{key};"
            subscriptions |> emplace(rx_subscribe(g,@(n:int){trace+="{n};"},@(s:string){panic(s)},@(){trace+="end;"}))
            if(key==1 && reenter==0) {rx_sink_next(sink,3);rx_sink_next(sink,2);rx_sink_complete(sink)}
        },@(s:string){panic(s)},@(){trace+="done;"})
        rx_sink_next(sink,1)
        verify(trace=="g1;1;3;g0;2;end;end;done;" && rx_is_closed(sub))
        delete subscriptions;delete sink
    }
    // Each subscription creates an independent group registry.
    trace="";count=0
    {
        var inscope source <- rx_range(1,2) |> rx_group_by(@(n:int){return n%2})
        var inscope a <- observe(source);delete subscriptions
        var inscope b <- observe(source);delete subscriptions
        verify(count==4 && rx_is_closed(a) && rx_is_closed(b))
    }
    // String keys use content equality and retain an independent snapshot.
    trace="";count=0
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_group_by(@(n:int){return keyText})
        var inscope sub <- rx_subscribe(source,@(g:typedecl(rx_group_marker(type<string>,type<int>))) {
            let key=rx_group_key(g);count++;trace+="g:{key};"
            subscriptions |> emplace(rx_subscribe(g,@ capture(copy(key)) (n:int){trace+="{key}:{n};"},@(s:string){panic(s)},@(){}))
        },@(s:string){panic(s)},@(){})
        keyText=clone_string("first");rx_subject_next(input,1)
        keyText=clone_string("second");rx_subject_next(input,2)
        keyText=clone_string("first");rx_subject_next(input,3);rx_subject_complete(input)
        verify(count==2 && trace=="g:first;first:1;g:second;second:2;first:3;" && rx_is_closed(sub))
        delete subscriptions
    }
    // A user-defined equality failure is an on_error for every group and outer.
    count=0;trace=""
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_group_by(@(n:int){return Key(n=n)})
        var inscope sub <- rx_subscribe(source,@(g:typedecl(rx_group_marker(type<Key>,type<int>))) {
            count++
            subscriptions |> emplace(rx_subscribe(g,@(n:int){},@(s:string){trace+="error;"},@(){panic("unexpected complete")}))
        },@(s:string){trace+="outer;"},@(){panic("unexpected complete")})
        rx_subject_next(input,1);rx_subject_next(input,2);rx_subject_next(input,9)
        verify(count==2 && trace=="error;error;outer;" && rx_is_closed(sub) && rx_subscriber_count(input)==0)
        delete subscriptions
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX group_by tests OK\n")
}
