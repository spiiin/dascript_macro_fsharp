options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
require strings
var trace=""
var groups=0
var finished=0
var errors=0
var sum=0
var subscriptions:array<RxSubscription>
var saved:typedecl(rx_subject(type<int>))

def batch_observe(source:auto) {
    return <- rx_subscribe(source,@(b:array<int>){trace+="[";for(n in b){trace+="{n}"};trace+="]"},@(s:string){trace+="error;"},@(){trace+="done;"})
}

def window_observe(source:auto) {
    return <- rx_subscribe(source,@(w:typedecl(rx_subject(type<int>))) {
        groups++;let id=groups
        subscriptions |> emplace(rx_subscribe(w,@ capture(copy(id)) (n:int){trace+="w{id}:{n};";sum+=n},@ capture(copy(id)) (s:string){errors++;trace+="e{id};"},@ capture(copy(id)) (){finished++;trace+="c{id};"}))
    },@(s:string){trace+="outerError;"},@(){trace+="done;"})
}

def checks() {
    for(step in range(1,6)) {
        trace=""
        var inscope source <- rx_range(1,5) |> rx_buffer(3,step)
        var inscope sub <- batch_observe(source)
        if(step==1){verify(trace=="[123][234][345][45][5]done;")}
        elif(step==2){verify(trace=="[123][345][5]done;")}
        elif(step==3){verify(trace=="[123][45]done;")}
        elif(step==4){verify(trace=="[123][5]done;")}
        else {verify(trace=="[123]done;")}
    }
    {
        trace="";groups=0;finished=0;errors=0;sum=0
        var inscope source <- rx_range(1,3) |> rx_window(2,1)
        var inscope sub <- window_observe(source)
        verify(trace=="w1:1;w1:2;c1;w2:2;w2:3;c2;w3:3;c3;c4;done;" && groups==4 && finished==4 && sum==11)
        delete subscriptions
    }
    {
        trace="";groups=0;finished=0;errors=0;sum=0
        var inscope empty <- rx_empty(type<int>) |> rx_window(3)
        var inscope sub <- window_observe(empty)
        verify(groups==1 && finished==1 && trace=="c1;done;")
        delete subscriptions
    }
    // Map may inspect a borrowed window. flat_map clones each inner explicitly.
    {
        trace="";sum=0
        var inscope source <- rx_range(1,4) |> rx_window(3,1) |> rx_tap(@(w:typedecl(rx_subject(type<int>))){groups++}) |> rx_flat_map(@(w:typedecl(rx_subject(type<int>))){return <- rx_clone(w)})
        var inscope sub <- rx_subscribe(source,@(n:int){sum+=n},@(s:string){panic(s)},@(){trace="done"})
        verify(sum==26 && trace=="done")
    }
    // Bounded projection retains window views, not copied iterators; hot prefixes may be missed.
    {
        sum=0;trace=""
        var inscope source <- rx_range(1,4) |> rx_window(3,1) |> rx_concat_map(@(w:typedecl(rx_subject(type<int>))){return <- rx_clone(w)})
        var inscope sub <- rx_subscribe(source,@(n:int){sum+=n},@(s:string){panic(s)},@(){trace="done"})
        verify(sum==17 && trace=="done")
    }
    // Cancellation from an inner callback stops the synchronous outer source immediately.
    {
        groups=0;finished=0;sum=0
        var inscope control <- rx_subscription()
        var pointer=unsafe(addr(control))
        var inscope source <- rx_range(1,5) |> rx_tap(@(n:int){sum++}) |> rx_window(3,1)
        rx_subscribe_with(control,source,@ capture(copy(pointer)) (w:typedecl(rx_subject(type<int>))) {
            groups++
            subscriptions |> emplace(rx_subscribe(w,@ capture(copy(pointer)) (n:int){unsafe {rx_unsubscribe(*pointer)}},@(s:string){panic(s)},@(){finished++}))
        },@(s:string){panic(s)},@(){panic("outer cancellation has no terminal")})
        verify(sum==1 && groups==1 && finished==1 && rx_is_closed(control))
        delete subscriptions
    }
    // Time groups are half-open; close timers run before opens at the same due time.
    for(gap in range(2)) {
        trace=""
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_buffer_time(5,gap==0 ? 2 : 7,clock)
        var inscope sub <- batch_observe(source)
        rx_subject_next(input,1)
        rx_advance_to(clock,4);rx_subject_next(input,2)
        rx_advance_to(clock,5);rx_subject_next(input,3)
        rx_advance_to(clock,7);rx_subject_next(input,4)
        rx_subject_complete(input)
        verify(trace==(gap==0 ? "[12][23][234][4]done;" : "[12][4]done;"))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0 && rx_subscriber_count(input)==0)
    }
    {
        trace="";groups=0;finished=0;errors=0;sum=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_window_time(5,2,clock)
        var inscope sub <- window_observe(source)
        rx_subject_next(input,1);rx_advance_to(clock,4);rx_subject_next(input,2);rx_advance_to(clock,5)
        rx_subject_next(input,3);rx_subject_complete(input)
        verify(groups==3 && finished==3 && errors==0 && sum==1+2*3+3*2 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete subscriptions
    }
    // Empty timed windows exist, unlike empty buffer packets.
    {
        trace="";groups=0;finished=0;errors=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_window_time(2,clock)
        var inscope sub <- window_observe(source)
        rx_advance_to(clock,4);rx_subject_complete(input)
        verify(groups==3 && finished==3 && trace=="c1;c2;c3;done;")
        delete subscriptions
    }
    // Every open window gets the source error, buffered partials are discarded.
    for(mode in range(2)) {
        trace="";groups=0;finished=0;errors=0;sum=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_window_time(10,2,clock)
        var inscope sub <- window_observe(source)
        rx_advance_to(clock,4);rx_subject_next(input,1)
        if(mode==0) {rx_subject_error(input,"failure")} else {rx_scheduler_close(clock)}
        verify(groups==3 && errors==3 && finished==0 && ends_with(trace,"e1;e2;e3;outerError;"))
        verify(rx_is_closed(sub) && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete subscriptions
    }
    {
        trace=""
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_buffer(4,1)
        var inscope sub <- batch_observe(source)
        rx_subject_next(input,1);rx_subject_next(input,2);rx_subject_error(input,"failed")
        verify(trace=="error;" && rx_subscriber_count(input)==0)
    }
    // Explicit outer cancellation completes open windows, with no outer terminal.
    {
        trace="";groups=0;finished=0;errors=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_window_time(10,2,clock)
        var sub <- window_observe(source)
        delete source
        rx_advance_to(clock,4);rx_unsubscribe(sub)
        verify(groups==3 && finished==3 && trace=="c1;c2;c3;" && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub;delete subscriptions
    }
    // A retained window is closed with the outer, and does not keep the source alive.
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- rx_clone(input) |> rx_window(3)
        var sub <- rx_subscribe(source,@(w:typedecl(rx_subject(type<int>))){saved <- rx_clone(w)},@(s:string){panic(s)},@(){})
        rx_unsubscribe(sub);delete sub
        trace=""
        var inscope late <- rx_subscribe(saved,@(n:int){panic("no replay")},@(s:string){panic(s)},@(){trace="done"})
        verify(trace=="done" && rx_subscriber_count(input)==0)
        delete saved
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)){checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX sliding buffer/window checks OK\n")
}
