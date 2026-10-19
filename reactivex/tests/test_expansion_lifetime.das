options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var calls=0
var groups=0
var terminals=0
var errors=0
var subscriptions:array<RxSubscription>
var drop_descriptor:lambda<():void>
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}

def checks() {
    // Retry owns both callback captures through waiting/cancellation and policy failures.
    for(mode in range(7)) {
        var inscope clock <- rx_virtual_scheduler()
        if(mode==6) {rx_scheduler_close(clock)}
        var a <- hold();var b <- hold()
        var source <- rx_throw("source",type<int>) |> rx_retry(mode==5 ? 0 : 3,
            @ capture(<-a,copy(mode)) (s:string;retry:int) {verify(a.data[0]==42);if(mode==0){panic("predicate")};return true} finally {delete a},
            @ capture(<-b,copy(mode)) (retry:int) {verify(b.data[0]==42);if(mode==1){panic("delay")};return mode==2 ? -1l : 10l} finally {delete b},clock)
        var sub <- rx_subscribe(source,@(n:int){panic("unexpected")},@(s:string){},@(){panic("unexpected done")})
        delete source
        if(mode==3) {rx_unsubscribe(sub)}
        if(mode==4) {rx_scheduler_close(clock)}
        verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub;verify(opened==freed)
    }
    // with_latest_from releases both sources and retained snapshots on all exits.
    for(mode in range(5)) {
        var inscope left <- rx_subject(type<int>)
        var inscope right <- rx_subject(type<string>)
        var a <- hold();var b <- hold()
        var source <- (rx_clone(left) |> rx_tap(@ capture(<-a) (n:int){verify(a.data[0]==42)} finally {delete a})) |> rx_with_latest_from(rx_clone(right) |> rx_tap(@ capture(<-b) (s:string){verify(b.data[0]==42)} finally {delete b}))
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (p:tuple<first:int;second:string>){if(mode==4){panic("consumer")}},@(s:string){},@(){})
        delete source
        var caught=false
        try {
            rx_subject_next(right,"snapshot");rx_subject_next(left,1)
            if(mode==0){rx_subject_complete(left)}
            elif(mode==1){rx_subject_error(right,"error")}
            elif(mode==2){rx_unsubscribe(sub)}
            elif(mode==3){delete sub}
        } recover {caught=true}
        verify(caught==(mode==4) && rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
        if(mode!=3){delete sub}
        verify(opened==freed)
    }
    // exhaust_map never allocates a resource for an ignored outer value.
    for(mode in range(6)) {
        calls=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var view <- rx_scheduler_clone(clock);var data <- hold()
        var source <- rx_clone(input) |> rx_exhaust_map(@ capture(<-view,<-data,copy(mode)) (n:int) {
            verify(data.data[0]==42);calls++
            if(mode==5){panic("selector")}
            var child <- hold()
            return <- rx_timer(5,view) |> rx_tap(@ capture(<-child) (n:int64){verify(child.data[0]==42)} finally {delete child}) |> rx_map(@(n:int64){return int(n)})
        } finally {delete data;delete view})
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (n:int){if(mode==4){panic("consumer")}},@(s:string){},@(){})
        delete source
        var caught=false
        try {
            rx_subject_next(input,1);rx_subject_next(input,2)
            if(mode==0){rx_subject_complete(input);rx_advance_to(clock,5)}
            elif(mode==1){rx_unsubscribe(sub)}
            elif(mode==2){rx_subject_error(input,"source")}
            elif(mode==3){rx_scheduler_close(clock)}
            elif(mode==4){rx_advance_to(clock,5)}
        } recover {caught=true}
        verify(caught==(mode==4) && calls==1 && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub;verify(opened==freed)
    }
    // Window resources are retained after descriptor deletion and freed on all closes.
    for(mode in range(8)) {
        groups=0;terminals=0;errors=0
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var sourceHold <- hold()
        var source <- rx_clone(input) |> rx_tap(@ capture(<-sourceHold) (n:int){verify(sourceHold.data[0]==42)} finally {delete sourceHold}) |> rx_window_time(5,2,clock)
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (w:typedecl(rx_subject(type<int>))) {
            groups++
            if(mode==5 && groups==2){panic("outer observer")}
            var data <- hold()
            subscriptions |> emplace(rx_subscribe(w,@ capture(<-data,copy(mode)) (n:int){verify(data.data[0]==42);if(mode==6){panic("inner observer")}} finally {delete data},@(s:string){errors++},@ capture(copy(mode)) (){terminals++;if(mode==7){panic("inner complete")}}))
        },@(s:string){},@(){})
        delete source
        var caught=false
        try {
            rx_advance_to(clock,4)
            rx_subject_next(input,1)
            if(mode==0){rx_subject_complete(input)}
            elif(mode==1){rx_unsubscribe(sub)}
            elif(mode==2){delete sub}
            elif(mode==3){rx_subject_error(input,"source")}
            elif(mode==4){rx_scheduler_close(clock)}
            elif(mode==7){rx_advance_to(clock,5)}
        } recover {caught=true}
        verify(caught==(mode>=5))
        verify(rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        var index=0
        while(index<length(subscriptions)){verify(rx_is_closed(subscriptions[index]));index++}
        delete subscriptions
        if(mode!=2){verify(rx_is_closed(sub));delete sub}
        verify(opened==freed)
    }
    // Borrowed arrays are released even if foreach exits through a native exception.
    for(mode in range(2)) {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        var source <- rx_clone(input) |> rx_buffer_time(5,2,clock)
        var sub <- rx_subscribe(source,@ capture(copy(mode)) (b:array<int>){for(n in b){if(mode==0){panic("batch consumer")}}},@(s:string){},@(){})
        delete source
        var caught=false
        try {rx_subject_next(input,1);rx_advance_to(clock,5)} recover {caught=true}
        if(mode==1){rx_unsubscribe(sub)}
        verify(caught==(mode==0) && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub
    }
    // A window returned through take(1) closes before source effects start.
    {
        calls=0
        var inscope source <- rx_defer(@(){calls++;return <- rx_range(1,3)}) |> rx_window(3,1) |> rx_take(1)
        var inscope sub <- rx_subscribe(source,@(w:typedecl(rx_subject(type<int>))){},@(s:string){},@(){})
        verify(calls==0 && rx_is_closed(sub))
    }
    // A native publish observer failure closes the generation without synthetic terminals.
    {
        var inscope input <- rx_subject(type<int>)
        var inscope pub <- rx_clone(input) |> rx_publish()
        var a <- rx_subscribe(pub,@(n:int){panic("observer")},@(s:string){panic("synthetic error")},@(){panic("synthetic complete")})
        var b <- rx_subscribe(pub,@(n:int){},@(s:string){panic("synthetic error")},@(){panic("synthetic complete")})
        var connection <- rx_connect(pub)
        var caught=false
        try {rx_subject_next(input,1)} recover {caught=true}
        verify(caught && rx_is_closed(a) && rx_is_closed(b) && rx_is_closed(connection) && rx_subscriber_count(input)==0)
        delete a;delete b;delete connection
    }
    // A callback may delete the public descriptor while connect/close is on stack.
    {
        var pub <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {rx_sink_next(sink,1);panic("connect failure")}) |> rx_publish()
        var pointer=unsafe(addr(pub))
        drop_descriptor <- @ capture(copy(pointer)) () {unsafe {delete *pointer}}
        var sub <- rx_subscribe(pub,@(n:int){invoke(drop_descriptor)},@(s:string){},@(){})
        var caught=false
        try {var connection <- rx_connect(pub);delete connection} recover {caught=true}
        verify(caught && empty(pub.owner) && rx_is_closed(sub))
        delete sub;unsafe {delete drop_descriptor}
    }
    {
        var hub <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@(){invoke(drop_descriptor)})
        }) |> rx_share(RxShareOptions(reset_on_refcount_zero=false))
        var pointer=unsafe(addr(hub))
        drop_descriptor <- @ capture(copy(pointer)) () {unsafe {delete *pointer}}
        var sub <- rx_subscribe(hub,@(n:int){},@(s:string){},@(){})
        rx_share_close(hub)
        verify(empty(hub.owner) && rx_is_closed(sub))
        delete sub;unsafe {delete drop_descriptor}
    }
    // Deadline overflow cannot leave a timer, lifecycle hook or source subscription.
    {
        calls=0
        var inscope clock <- rx_virtual_scheduler(9223372036854775805l)
        var source <- rx_defer(@(){calls++;return <- rx_range(1,3)}) |> rx_window_time(5,2,clock)
        var caught=false
        try {var sub <- rx_subscribe(source,@(w:typedecl(rx_subject(type<int>))){},@(s:string){},@(){});delete sub} recover {caught=true}
        delete source
        verify(caught && calls==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Invalid new constructors dispose pipeline temporaries as well.
    var inscope clock <- rx_virtual_scheduler()
    var caught=false
    try {var source <- rx_range(1,2) |> rx_buffer(0,1);delete source} recover {caught=true}
    verify(caught)
    caught=false
    try {var source <- rx_range(1,2) |> rx_window_time(-1,1,clock);delete source} recover {caught=true}
    verify(caught)
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)){checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX expansion lifetime checks OK\n")
}
