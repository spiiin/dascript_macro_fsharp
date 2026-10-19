options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var snapshot:array<int>
def print_batch(caption:string;batch:array<int>) {
    print("{caption}: [")
    for(i in range(length(batch))) {if(i>0) {print(",")};print("{batch[i]}")}
    print("]\n")
}
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope input <- rx_subject(type<int>)
    var inscope leading <- rx_clone(input) |> rx_throttle(10,clock)
    var inscope sampled <- rx_clone(input) |> rx_sample(10,clock)
    var inscope timed <- rx_clone(input) |> rx_buffer_time(10,clock)
    var inscope capped <- rx_clone(input) |> rx_buffer(2,10,clock)
    var inscope a <- rx_subscribe(leading,@(n:int) {print("throttle: {n}\n")},@(s:string) {panic(s)},@() {print("throttle done\n")})
    var inscope b <- rx_subscribe(sampled,@(n:int) {print("sample: {n}\n")},@(s:string) {panic(s)},@() {print("sample done\n")})
    var inscope c <- rx_subscribe(timed,@(batch:array<int>) {print_batch("time",batch)},@(s:string) {panic(s)},@() {print("time buffer done\n")})
    var inscope d <- rx_subscribe(capped,@(batch:array<int>) {print_batch("count or time",batch);snapshot := batch},@(s:string) {panic(s)},@() {})
    rx_subject_next(input,1);rx_subject_next(input,2)
    rx_advance_to(clock,5);rx_subject_next(input,3)
    rx_advance_to(clock,10);rx_subject_next(input,4)
    rx_subject_complete(input) // Flush sample/latest and partial batches now.
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print_batch("saved snapshot",snapshot)
    delete snapshot

    // Count-only buffering needs no scheduler. Convert a borrowed batch to a
    // copyable summary before retaining operators such as share_replay/delay.
    var inscope totals <- rx_range(1,5) |> rx_buffer(2) |> rx_filter(@(batch:array<int>) {return !empty(batch)}) |> rx_map(@(batch:array<int>) {
        var total=0
        for(n in batch) {total+=n}
        return total
    }) |> rx_take(3)
    var inscope totalsSub <- rx_subscribe(totals,@(n:int) {print("batch total: {n}\n")},@(s:string) {panic(s)},@() {})
    print("ReactiveX throttle/sample/buffer demo OK\n")
}
