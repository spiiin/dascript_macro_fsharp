options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti

var sum=0l
var chainLimit=-1
var done=0
var trace=""
var late:RxSubscription
var nested:RxSubscription
var madeNested=false
var copiesFreed=0
struct FinalizedValue {
    n:int
    def finalize {if(n!=0) {copiesFreed++}}
}

def source_for(mode:int;clock:RxScheduler) {
    if(mode==0) {return <- rx_behavior_subject(0)}
    elif(mode==2) {return <- rx_replay_subject(type<int>,8,1000,clock)}
    return <- rx_replay_subject(type<int>,8)
}

def allocation_checks(mode,count:int) {
    var inscope clock <- rx_virtual_scheduler()
    var inscope source <- source_for(mode,clock)
    if(mode!=0) {for(n in range(1,9)) {rx_subject_next(source,n)}}
    var inscope pipeline <- rx_clone(source) |> rx_map(@(n:int) {return n*2})
    var inscope subscriptions:array<RxSubscription>
    chainLimit=-1
    for(j in range(count)) {
        var view <- rx_clone(source)
        subscriptions |> emplace(rx_subscribe(pipeline,@ capture(<-view,copy(j),copy(mode)) (value:int) {
            sum+=int64(value)
            let n=value/2
            if(mode==0) {verify(rx_behavior_value(view)==n)}
            if(j==0 && n<chainLimit) {rx_subject_next(view,n+1)}
        } finally {delete view},@(e:string) {panic(e)},@() {done++}))
    }
    rx_subject_next(source,10)
    var calls=heap_allocation_count()
    var bytes=heap_allocation_stats()[0]
    var before=sum
    for(n in range(1,1001)) {rx_subject_next(source,n)}
    verify(sum-before==1001000l*int64(count))
    verify(heap_allocation_count()==calls && heap_allocation_stats()[0]==bytes)
    chainLimit=3;rx_subject_next(source,0)
    calls=heap_allocation_count();bytes=heap_allocation_stats()[0];before=sum
    chainLimit=999;rx_subject_next(source,0)
    verify(sum-before==999000l*int64(count))
    verify(heap_allocation_count()==calls && heap_allocation_stats()[0]==bytes)
    chainLimit=-1
    verify(rx_subject_buffered_count(source)==(mode==0 ? 1 : 8))
    let oldDone=done
    rx_subject_complete(source)
    verify(done==oldDone+count && rx_subscriber_count(source)==0)
    for(sub in subscriptions) {verify(rx_is_closed(sub))}
}

def checks() {
    for(mode in range(3)) {for(count in fixed_array(1,8)) {allocation_checks(mode,count)}}
    // Nested subscriptions replay the frozen current history. Reentrant next
    // waits until the complete initial replay, then updates Behavior's value.
    trace="";madeNested=false
    {
        var inscope source <- rx_behavior_subject(1)
        var view <- rx_clone(source)
        var inscope first <- rx_subscribe(source,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(!madeNested) {
                madeNested=true;rx_subject_next(view,2)
                var inner <- rx_clone(view)
                late <- rx_subscribe(view,@ capture(<-inner) (v:int) {trace+="B{v};";if(v==1) {rx_subject_next(inner,3)}} finally {delete inner},@(e:string) {panic(e)},@() {})
            }
        } finally {delete view},@(e:string) {panic(e)},@() {})
        verify(trace=="A1;B1;A2;B2;A3;B3;" && rx_behavior_value(source)==3)
        rx_subject_complete(source);delete late
    }
    trace="";madeNested=false
    {
        var inscope source <- rx_replay_subject(type<int>,3)
        for(n in range(1,4)) {rx_subject_next(source,n)}
        var view <- rx_clone(source)
        var inscope first <- rx_subscribe(source,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(n==1 && !madeNested) {
                madeNested=true;rx_subject_next(view,4)
                var inner <- rx_clone(view)
                late <- rx_subscribe(view,@ capture(<-inner) (v:int) {trace+="B{v};";if(v==1) {rx_subject_next(inner,5)}} finally {delete inner},@(e:string) {panic(e)},@() {})
            } elif(n==4) {
                nested <- rx_subscribe(view,@(v:int) {trace+="C{v};"},@(e:string) {panic(e)},@() {})
            }
        } finally {delete view},@(e:string) {panic(e)},@() {})
        verify(trace=="A1;B1;B2;B3;A2;A3;A4;C2;C3;C4;B4;A5;B5;C5;")
        rx_subject_complete(source)
        trace=""
        var inscope terminal <- rx_subscribe(source,@(v:int) {trace+="{v};"},@(e:string) {panic(e)},@() {trace+="done;"})
        verify(trace=="3;4;5;done;" && rx_is_closed(terminal))
        delete late;delete nested
    }
    // Timed history may be pruned from a replay callback. Its own snapshot
    // must still deliver the original unread entries before queued next.
    trace=""
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope source <- rx_replay_subject(type<int>,3,10,clock)
        rx_subject_next(source,0);rx_advance_by(clock,5);rx_subject_next(source,1)
        rx_advance_by(clock,4);rx_subject_next(source,2)
        var view <- rx_clone(source);var time <- rx_scheduler_clone(clock)
        var inscope sub <- rx_subscribe(source,@ capture(<-view,<-time) (n:int) {
            trace+="{n};"
            if(n==0) {
                rx_advance_by(time,11)
                verify(rx_subject_buffered_count(view)==0)
                rx_subject_next(view,3)
            }
        } finally {delete view;delete time},@(e:string) {panic(e)},@() {})
        verify(trace=="0;1;2;3;" && rx_subject_buffered_count(source)==1)
        rx_subject_complete(source)
    }
    // Copy finalizers are observable: retain the old replay snapshot path.
    {
        var inscope source <- rx_replay_subject(type<FinalizedValue>,2)
        rx_subject_next(source,FinalizedValue(n=1));rx_subject_next(source,FinalizedValue(n=2))
        let before=copiesFreed
        var inscope sub <- rx_subscribe(source,@(value:FinalizedValue) {verify(value.n>0)},@(e:string) {panic(e)},@() {})
        verify(copiesFreed>before)
        rx_subject_complete(source)
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX cached Subject dispatch checks OK\n")
}
