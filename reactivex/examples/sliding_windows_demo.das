options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
var total=0
[export]
def main() {
    var inscope batches <- rx_range(1,5) |> rx_buffer(3,1)
    var inscope sub <- rx_subscribe(batches,@(batch:array<int>){
        print("batch:");for(n in batch){print(" {n}")};print("\n")
    },@(s:string){panic(s)},@(){})
    // Borrow each hot window during notification; clone it to return an owning
    // Observable from the selector. Inner subscriptions precede the first item.
    var inscope windows <- rx_range(1,4) |> rx_window(3,1) |> rx_flat_map(@(window:typedecl(rx_subject(type<int>))){return <- rx_clone(window)})
    var inscope flattened <- rx_subscribe(windows,@(n:int){total+=n},@(s:string){panic(s)},@(){})
    verify(total==26)
    var inscope clock <- rx_virtual_scheduler()
    var inscope input <- rx_subject(type<int>)
    var inscope timed <- rx_clone(input) |> rx_buffer_time(5,2,clock)
    var inscope timedSub <- rx_subscribe(timed,@(batch:array<int>){print("timed batch: {length(batch)} values\n")},@(s:string){panic(s)},@(){})
    rx_subject_next(input,1);rx_advance_to(clock,4);rx_subject_next(input,2)
    rx_advance_to(clock,7);rx_subject_complete(input)
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print("ReactiveX sliding windows demo OK\n")
}
