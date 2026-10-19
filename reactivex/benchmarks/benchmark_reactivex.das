options gen2
options max_infer_passes=512
require ../lib/reactivex.das
require daslib/rtti

var bench_total=0l
var bench_done=0
var bench_running=false

def transformed(n:int) : int {return (n*17+13)%1009}

def cached_source(behavior,timed:bool) {
    if(behavior) {return <- rx_behavior_subject(0)}
    if(timed) {
        var inscope clock <- rx_virtual_scheduler()
        return <- rx_replay_subject(type<int>,8,1000,clock)
    }
    return <- rx_replay_subject(type<int>,8)
}

// Each call owns and releases all its descriptors and subscriptions.
def workload(name:string;manual:bool;elements,batches:int) : int64 {
    bench_total=0l
    bench_done=0
    if(name=="behavior" || name=="behavior_8" || name=="replay" || name=="replay_8" || name=="replay_timed" || name=="behavior_reentrant" || name=="replay_reentrant" || name=="behavior_subscribe" || name=="replay_subscribe") {
        let behavior=name=="behavior" || name=="behavior_8" || name=="behavior_reentrant" || name=="behavior_subscribe"
        let subscribing=name=="behavior_subscribe" || name=="replay_subscribe"
        let reentrant=name=="behavior_reentrant" || name=="replay_reentrant"
        let listeners=name=="behavior" || name=="replay" || subscribing ? 1 : 8
        if(manual) {
            let repeats=subscribing ? elements*batches : listeners
            for(j in range(repeats)) {
                if(behavior) {bench_total+=int64(transformed(0))}
                else {for(n in range(1,9)) {bench_total+=int64(transformed(n))}}
            }
            if(!subscribing) {
                for(batchIndex in range(batches)) {
                    for(n in range(elements)) {for(j in range(listeners)) {bench_total+=int64(transformed(n%1009))}}
                }
            }
        } else {
            var inscope source <- cached_source(behavior,name=="replay_timed")
            if(!behavior) {for(n in range(1,9)) {rx_subject_next(source,n)}}
            var inscope pipeline <- rx_clone(source) |> rx_map(@(n:int) {return (n=n,value=transformed(n%1009))})
            if(subscribing) {
                for(j in range(elements*batches)) {
                    var inscope sub <- rx_subscribe(pipeline,@(item:tuple<n:int;value:int>) {bench_total+=int64(item.value)},@(e:string) {panic(e)},@() {bench_done++})
                }
                verify(rx_subscriber_count(source)==0 && bench_done==0)
            } else {
                bench_running=false
                var inscope subscriptions:array<RxSubscription>
                for(j in range(listeners)) {
                    var view <- rx_clone(source)
                    subscriptions |> emplace(rx_subscribe(pipeline,@ capture(<-view,copy(j),copy(reentrant),copy(elements)) (item:tuple<n:int;value:int>) {
                        bench_total+=int64(item.value)
                        if(bench_running && reentrant && j==0 && item.n<elements-1) {rx_subject_next(view,item.n+1)}
                    } finally {delete view},@(e:string) {panic(e)},@() {bench_done++}))
                }
                bench_running=true
                for(batchIndex in range(batches)) {
                    if(reentrant) {rx_subject_next(source,0)}
                    else {for(n in range(elements)) {rx_subject_next(source,n)}}
                }
                bench_running=false
                rx_subject_complete(source)
                verify(bench_done==listeners)
                for(sub in subscriptions) {verify(rx_is_closed(sub))}
            }
        }
        return bench_total
    }
    if(name=="reentrant_1" || name=="reentrant_8" || name=="reentrant_burst") {
        let listeners=name=="reentrant_1" ? 1 : 8
        let burst=name=="reentrant_burst"
        if(manual) {
            for(batchIndex in range(batches)) {
                for(n in range(elements*(burst ? 9 : 1))) {
                    for(j in range(listeners)) {bench_total+=int64(transformed(n%1009))}
                }
            }
        } else {
            var inscope source <- rx_subject(type<int>)
            var inscope pipeline <- rx_clone(source) |> rx_map(@(n:int) {return (n=n,value=transformed(n%1009))})
            var inscope subscriptions:array<RxSubscription>
            for(j in range(listeners)) {
                var view <- rx_clone(source)
                subscriptions |> emplace(rx_subscribe(pipeline,@ capture(<-view,copy(j),copy(elements),copy(burst)) (item:tuple<n:int;value:int>) {
                    bench_total+=int64(item.value)
                    if(j==0) {
                        if(burst && item.n%9==0) {
                            for(offset in range(1,9)) {rx_subject_next(view,item.n+offset)}
                        } elif(!burst && item.n<elements-1) {rx_subject_next(view,item.n+1)}
                    }
                } finally {delete view},@(e:string) {panic(e)},@() {bench_done++}))
            }
            for(batchIndex in range(batches)) {
                if(burst) {for(i in range(elements)) {rx_subject_next(source,i*9)}}
                else {rx_subject_next(source,0)}
            }
            rx_subject_complete(source)
            verify(bench_done==listeners)
            for(sub in subscriptions) {verify(rx_is_closed(sub))}
        }
        return bench_total
    }
    if(name=="construct") {
        for(i in range(elements*batches)) {
            if(manual) {
                // A manual pipeline needs only its configuration, no runtime nodes.
                bench_total+=int64(i%17+3)
            } else {
                var inscope source <- rx_range(i%17,3) |> rx_map(@(n:int) {return transformed(n)}) |> rx_filter(@(n:int) {return n%2==0})
                bench_total+=int64(i%17+3)
            }
        }
        return bench_total
    }
    if(name=="subject" || name=="subject_2" || name=="subject_8" || name=="subject_32") {
        let listeners=name=="subject_32" ? 32 : (name=="subject_8" ? 8 : (name=="subject_2" ? 2 : 1))
        if(manual) {
            for(i in range(elements*batches)) {
                for(j in range(listeners)) {bench_total+=int64(transformed(i%1009))}
            }
        } else {
            var inscope source <- rx_subject(type<int>)
            var inscope pipeline <- rx_clone(source) |> rx_map(@(n:int) {return transformed(n)})
            var inscope subscriptions:array<RxSubscription>
            for(j in range(listeners)) {
                subscriptions |> emplace(rx_subscribe(pipeline,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++}))
            }
            for(i in range(elements*batches)) {rx_subject_next(source,i%1009)}
            rx_subject_complete(source)
            verify(bench_done==listeners)
            for(sub in subscriptions) {verify(rx_is_closed(sub))}
        }
        return bench_total
    }
    if(name=="subscribe" || name=="subscribe_chain") {
        if(manual) {
            for(i in range(elements*batches)) {bench_total+=int64(name=="subscribe" ? 7 : transformed(7));bench_done++}
        } else {
            if(name=="subscribe") {
                var inscope source <- rx_range(7,1)
                for(i in range(elements*batches)) {
                    var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
                    verify(rx_is_closed(sub))
                }
            } else {
                var inscope source <- rx_range(7,1) |> rx_map(@(n:int) {return transformed(n)}) |> rx_filter(@(n:int) {return n>=0})
                for(i in range(elements*batches)) {
                    var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
                    verify(rx_is_closed(sub))
                }
            }
        }
        verify(bench_done==elements*batches)
        return bench_total
    }
    for(batchIndex in range(batches)) {
        let seed=batchIndex%17
        if(manual) {
            var accumulator=0
            for(i in range(elements)) {
                var n=i+seed
                if(name!="range") {n=transformed(n)}
                if((name=="filter" || name=="chain") && n%2!=0) {continue}
                if(name=="chain") {accumulator+=n;n=accumulator}
                bench_total+=int64(n)
            }
            bench_done++
        } else {
            if(name=="range") {
                var inscope source <- rx_range(seed,elements)
                var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
            } elif(name=="map") {
                var inscope source <- rx_range(seed,elements) |> rx_map(@(n:int) {return transformed(n)})
                var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
            } elif(name=="filter") {
                var inscope source <- rx_range(seed,elements) |> rx_map(@(n:int) {return transformed(n)}) |> rx_filter(@(n:int) {return n%2==0})
                var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
            } else {
                verify(name=="chain")
                var inscope source <- rx_range(seed,elements) |> rx_map(@(n:int) {return transformed(n)}) |> rx_filter(@(n:int) {return n%2==0}) |> rx_scan(0,@(acc,n:int) {return acc+n})
                var inscope sub <- rx_subscribe(source,@(n:int) {bench_total+=int64(n)},@(e:string) {panic(e)},@() {bench_done++})
            }
        }
    }
    verify(bench_done==batches)
    return bench_total
}

def sample(name:string;manual:bool;size,repetition:int) : int64 {
    let retainedBefore=heap_bytes_allocated()
    let callsBefore=heap_allocation_count()
    let bytesBefore=heap_allocation_stats()[0]
    let stringsBefore=string_heap_allocation_count()
    let stringBytesBefore=string_heap_allocation_stats()[0]
    let start=ref_time_ticks()
    let checksum=workload(name,manual,size,4)
    let elapsed=int64(get_time_nsec(start))
    let calls=heap_allocation_count()-callsBefore
    let bytes=heap_allocation_stats()[0]-bytesBefore
    let strings=string_heap_allocation_count()-stringsBefore
    let stringBytes=string_heap_allocation_stats()[0]-stringBytesBefore
    let retained=heap_bytes_allocated()-retainedBefore
    verify(retained==0)
    let implementation=manual ? "manual" : "rx"
    print("RXBENCH,{name},{implementation},{size},{repetition},{elapsed},{checksum},{calls},{bytes},{strings},{stringBytes},{retained}\n")
    return checksum
}

[export]
def main() {
    for(name in fixed_array("range","map","filter","chain","subscribe","subscribe_chain","construct","subject","subject_2","subject_8","subject_32","reentrant_1","reentrant_8","reentrant_burst","behavior","behavior_8","replay","replay_8","replay_timed","behavior_reentrant","replay_reentrant","behavior_subscribe","replay_subscribe")) {
        verify(workload(name,true,7,2)==workload(name,false,7,2))
        for(size in fixed_array(32,512,4096)) {
            for(repetition in range(5)) {
                var manual=0l
                var reactive=0l
                if(repetition%2==0) {
                    manual=sample(name,true,size,repetition)
                    reactive=sample(name,false,size,repetition)
                } else {
                    reactive=sample(name,false,size,repetition)
                    manual=sample(name,true,size,repetition)
                }
                verify(manual==reactive)
            }
        }
    }
    print("ReactiveX benchmarks OK\n")
}
