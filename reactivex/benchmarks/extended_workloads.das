options gen2
options max_infer_passes=2048
module extended_workloads public
require ../lib/reactivex.das public
require daslib/rtti public

var extended_total=0l
var extended_effects=0l
var extended_done=0

def extended_chain(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<int>>) {
    return <- source |> rx_map(@(n:int) {return n/2}) |> rx_distinct_until_changed() |> rx_map(@(n:int) {return n+1}) |> rx_filter(@(n:int) {return n%2==0}) |> rx_scan(0,@(acc,n:int) {return acc+n}) |> rx_tap(@(n:int) {extended_effects+=int64(n)}) |> rx_skip(1) |> rx_skip_while(@(n:int) {return n<3}) |> rx_take_while(@(n:int) {return n<2147483647}) |> rx_pairwise() |> rx_map(@(p:tuple<previous:int;current:int>) {return p.previous+p.current})
}

def extended_watch(source:auto) {
    return <- rx_subscribe(source,@(n:int) {extended_total+=int64(n)},
        @(message:string) {panic(message)},@() {extended_done++})
}

def extended_manual_chain(count:int) {
    var acc=0;var previous=0;var seen=false;var skipped=false
    for(n in range(count)) {
        if(n%2!=0) {continue}
        let mapped=n/2+1
        if(mapped%2!=0) {continue}
        acc+=mapped;extended_effects+=int64(acc)
        if(!skipped) {skipped=true;continue}
        if(acc<3) {continue}
        if(seen) {extended_total+=int64(previous+acc)}
        previous=acc;seen=true
    }
    extended_done++
}

def extended_workload(name:string;manual:bool;count,batches:int) : int64 {
    extended_total=0l;extended_effects=0l;extended_done=0
    if(name=="resubscribe") {
        if(manual) {for(i in range(count*batches)) {extended_manual_chain(16)}}
        else {
            var inscope source <- rx_range(0,16) |> extended_chain()
            for(i in range(count*batches)) {
                var inscope sub <- extended_watch(source)
                verify(rx_is_closed(sub))
            }
        }
        verify(extended_done==count*batches)
    } else {
        for(batch in range(batches)) {
            if(manual) {
                if(name=="long_chain") {extended_manual_chain(count);continue}
                if(name=="zip_queue" || name=="concat_queue" || name=="observe_queue" || name=="delay_queue") {
                    // A hand-written bounded batch queue; drain with a cursor.
                    var inscope queue:array<int>
                    for(n in range(count)) {queue |> push(n)}
                    let pairs=name=="zip_queue"
                    for(item,n in queue,range(count)) {extended_total+=int64(pairs ? item+n : item)}
                } else {
                    if(name=="concat_sync") {
                        for(n in range(count)) {extended_total+=int64(n)}
                    } elif(name=="concat_reuse") {
                        for(n in range(count)) {extended_total+=1l}
                    } elif(name=="scan") {
                        var acc=0
                        for(n in range(count)) {acc+=n;extended_total+=int64(acc)}
                    } elif(name=="distinct") {
                        for(n in range(count)) {if(n%2==0) {extended_total+=int64(n/2)}}
                    } elif(name=="tap") {
                        for(n in range(count)) {extended_effects+=int64(n);extended_total+=int64(n)}
                    } elif(name=="take" || name=="take_while") {
                        for(n in range(count/2)) {extended_total+=int64(n)}
                    } elif(name=="skip" || name=="skip_while") {
                        for(n in range(count/2,count)) {extended_total+=int64(n)}
                    } elif(name=="pairwise") {
                        for(n in range(1,count)) {extended_total+=int64(n+n-1)}
                    } else {
                        verify(name=="map_control")
                        for(n in range(count)) {extended_total+=int64(n+1)}
                    }
                }
                extended_done++
            } else {
                if(name=="scan") {
                    var inscope source <- rx_range(0,count) |> rx_scan(0,@(acc,n:int) {return acc+n})
                    var inscope sub <- extended_watch(source)
                } elif(name=="distinct") {
                    var inscope source <- rx_range(0,count) |> rx_map(@(n:int) {return n/2}) |> rx_distinct_until_changed()
                    var inscope sub <- extended_watch(source)
                } elif(name=="tap") {
                    var inscope source <- rx_range(0,count) |> rx_tap(@(n:int) {extended_effects+=int64(n)})
                    var inscope sub <- extended_watch(source)
                } elif(name=="take") {
                    var inscope source <- rx_range(0,count) |> rx_take(count/2)
                    var inscope sub <- extended_watch(source)
                } elif(name=="skip") {
                    var inscope source <- rx_range(0,count) |> rx_skip(count/2)
                    var inscope sub <- extended_watch(source)
                } elif(name=="take_while") {
                    var inscope source <- rx_range(0,count) |> rx_take_while(@ capture(copy(count)) (n:int) {return n<count/2})
                    var inscope sub <- extended_watch(source)
                } elif(name=="skip_while") {
                    var inscope source <- rx_range(0,count) |> rx_skip_while(@ capture(copy(count)) (n:int) {return n<count/2})
                    var inscope sub <- extended_watch(source)
                } elif(name=="pairwise") {
                    var inscope source <- rx_range(0,count) |> rx_pairwise() |> rx_map(@(p:tuple<previous:int;current:int>) {return p.previous+p.current})
                    var inscope sub <- extended_watch(source)
                } elif(name=="long_chain") {
                    var inscope source <- rx_range(0,count) |> extended_chain()
                    var inscope sub <- extended_watch(source)
                } elif(name=="concat_sync") {
                    var inscope source <- rx_range(0,count) |> rx_concat_map(@(n:int) {return <- rx_just(n)})
                    var inscope sub <- extended_watch(source)
                    verify(rx_is_closed(sub))
                } elif(name=="concat_reuse") {
                    var prepared <- rx_just(1)
                    var inscope source <- rx_range(0,count) |> rx_concat_map(@ capture(<-prepared) (n:int) {
                        return <- rx_clone(prepared)
                    } finally {delete prepared})
                    var inscope sub <- extended_watch(source)
                    verify(rx_is_closed(sub))
                } elif(name=="zip_queue") {
                    var inscope left <- rx_subject(type<int>)
                    var inscope right <- rx_subject(type<int>)
                    var inscope source <- rx_clone(left) |> rx_zip(rx_clone(right),rx_queue(count)) |> rx_map(@(p:tuple<first:int;second:int>) {return p.first+p.second})
                    var inscope sub <- extended_watch(source)
                    for(n in range(count)) {rx_subject_next(left,n)}
                    rx_subject_complete(left)
                    for(n in range(count)) {rx_subject_next(right,n)}
                    rx_subject_complete(right)
                    verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
                } elif(name=="concat_queue") {
                    var inscope clock <- rx_virtual_scheduler()
                    var keep <- rx_scheduler_clone(clock)
                    var inscope source <- rx_range(0,count) |> rx_concat_map(@ capture(<-keep) (n:int) {
                        return <- rx_just(n) |> rx_delay(1,keep)
                    } finally {delete keep},rx_queue(count))
                    var inscope sub <- extended_watch(source)
                    rx_advance_to(clock,int64(count)+1)
                    verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
                } elif(name=="observe_queue" || name=="delay_queue") {
                    var inscope clock <- rx_virtual_scheduler()
                    if(name=="observe_queue") {
                        var inscope source <- rx_range(0,count) |> rx_observe_on(clock,rx_queue(count))
                        var inscope sub <- extended_watch(source)
                        rx_advance_to(clock,0)
                        verify(rx_is_closed(sub))
                    } else {
                        var inscope source <- rx_range(0,count) |> rx_delay(1,clock,rx_queue(count))
                        var inscope sub <- extended_watch(source)
                        rx_advance_to(clock,1)
                        verify(rx_is_closed(sub))
                    }
                    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
                } else {
                    verify(name=="map_control")
                    var inscope source <- rx_range(0,count) |> rx_map(@(n:int) {return n+1})
                    var inscope sub <- extended_watch(source)
                }
            }
        }
        verify(extended_done==batches)
    }
    return extended_total+17l*extended_effects+19l*int64(extended_done)
}

def extended_sample(name:string;manual:bool;size,repetition:int) : int64 {
    let live=heap_bytes_allocated();let calls=heap_allocation_count()
    let bytes=heap_allocation_stats()[0];let strings=string_heap_allocation_count()
    let stringBytes=string_heap_allocation_stats()[0];let start=ref_time_ticks()
    let checksum=extended_workload(name,manual,size,4)
    let elapsed=int64(get_time_nsec(start))
    let allocated=heap_allocation_count()-calls;let allocatedBytes=heap_allocation_stats()[0]-bytes
    let stringCalls=string_heap_allocation_count()-strings;let allocatedStrings=string_heap_allocation_stats()[0]-stringBytes
    let retained=heap_bytes_allocated()-live
    verify(retained==0)
    let implementation=manual ? "manual" : "rx"
    print("RXEXT,{name},{implementation},{size},{repetition},{elapsed},{checksum},{allocated},{allocatedBytes},{stringCalls},{allocatedStrings},{retained}\n")
    return checksum
}

struct RxExtendedPhase {ns:int64;allocations:int64;bytes:int64;live:int64}
struct RxExtendedQueueMeasurement {fill:RxExtendedPhase;drain:RxExtendedPhase}

def extended_mark() {
    return (ticks=ref_time_ticks(),allocations=heap_allocation_count(),bytes=heap_allocation_stats()[0],live=heap_bytes_allocated())
}

def extended_delta(mark:auto) {
    let elapsed=int64(get_time_nsec(mark.ticks))
    return RxExtendedPhase(ns=elapsed,allocations=int64(heap_allocation_count()-mark.allocations),
        bytes=int64(heap_allocation_stats()[0]-mark.bytes),live=int64(heap_bytes_allocated()-mark.live))
}

// Setup and teardown are excluded from phase timings; complete teardown is
// checked separately. Fill includes on_next/enqueue, drain includes delivery.
def extended_queue_phases(source:auto;input:auto;second:auto;clock:RxScheduler;name:string;count:int) {
    extended_total=0l;extended_effects=0l;extended_done=0
    var inscope sub <- extended_watch(source)
    let fillMark=extended_mark()
    for(n in range(count)) {rx_subject_next(input,n)}
    let fill=extended_delta(fillMark)
    let drainMark=extended_mark()
    rx_subject_complete(input)
    if(name=="zip_queue") {
        for(n in range(count)) {rx_subject_next(second,n)}
        rx_subject_complete(second)
    } else {rx_advance_to(clock,name=="concat_queue" ? int64(count)+1 : (name=="delay_queue" ? 1l : 0l))}
    let drain=extended_delta(drainMark)
    let expected=int64(count)*int64(count-1)/(name=="zip_queue" ? 1l : 2l)
    verify(extended_total==expected && extended_done==1 && rx_is_closed(sub))
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    return RxExtendedQueueMeasurement(fill=fill,drain=drain)
}

def extended_queue_sample(name:string;count,repetition:int) {
    let baseline=heap_bytes_allocated()
    var measured:RxExtendedQueueMeasurement
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<int>)
        if(name=="zip_queue") {
            var inscope second <- rx_subject(type<int>)
            var inscope source <- rx_clone(input) |> rx_zip(rx_clone(second),rx_queue(count)) |> rx_map(@(p:tuple<first:int;second:int>) {return p.first+p.second})
            measured=extended_queue_phases(source,input,second,clock,name,count)
            verify(rx_subscriber_count(second)==0)
        } elif(name=="concat_queue") {
            var keep <- rx_scheduler_clone(clock)
            var inscope source <- rx_clone(input) |> rx_concat_map(@ capture(<-keep) (n:int) {
                return <- rx_just(n) |> rx_delay(1,keep)
            } finally {delete keep},rx_queue(count))
            measured=extended_queue_phases(source,input,input,clock,name,count)
        } elif(name=="observe_queue") {
            var inscope source <- rx_clone(input) |> rx_observe_on(clock,rx_queue(count))
            measured=extended_queue_phases(source,input,input,clock,name,count)
        } else {
            verify(name=="delay_queue")
            var inscope source <- rx_clone(input) |> rx_delay(1,clock,rx_queue(count))
            measured=extended_queue_phases(source,input,input,clock,name,count)
        }
        verify(rx_subscriber_count(input)==0)
    }
    verify(heap_bytes_allocated()==baseline)
    let f=measured.fill;let d=measured.drain
    print("RXQUEUE,{name},{count},{repetition},{f.ns},{f.allocations},{f.bytes},{f.live},{d.ns},{d.allocations},{d.bytes},{d.live}\n")
}
