options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    // Two running jobs and only the two newest waiting jobs survive a burst.
    var view <- rx_scheduler_clone(clock)
    var jobs <- rx_range(1,6) |> rx_flat_map(@ capture(<-view) (n:int) {
        print("start {n}\n")
        return <- rx_timer(1,view) |> rx_map(@ capture(copy(n)) (tick:int64) {return n})
    } finally {delete view},2,rx_queue(2,RxOverflowPolicy.drop_oldest))
    var inscope jobsSub <- rx_subscribe(jobs,@(n:int) {print("job {n}\n")},@(s:string) {panic(s)},@() {print("jobs done\n")})
    delete jobs
    rx_advance_by(clock,10) // 1,2,5,6; selectors 3 and 4 never run.

    var serialClock <- rx_scheduler_clone(clock)
    var serialJobs <- rx_range(1,4) |> rx_concat_map(@ capture(<-serialClock) (n:int) {
        return <- rx_timer(1,serialClock) |> rx_map(@ capture(copy(n)) (tick:int64) {return n})
    } finally {delete serialClock},rx_queue(1,RxOverflowPolicy.drop_latest))
    var inscope serialSub <- rx_subscribe(serialJobs,@(n:int) {print("serial {n}\n")},@(s:string) {panic(s)},@() {})
    delete serialJobs
    rx_advance_by(clock,10) // 1,2.

    var pairs <- rx_range(1,4) |> rx_zip(rx_range(10,2),rx_queue(2,RxOverflowPolicy.drop_oldest))
    var inscope pairSub <- rx_subscribe(pairs,@(p:tuple<first:int;second:int>) {print("pair {p.first}:{p.second}\n")},@(s:string) {panic(s)},@() {})
    delete pairs // 3:10,4:11.

    var delayed <- rx_range(1,4) |> rx_delay(5,clock,rx_queue(2,RxOverflowPolicy.drop_latest))
    var inscope delaySub <- rx_subscribe(delayed,@(n:int) {print("delayed {n}\n")},@(s:string) {panic(s)},@() {print("delay done\n")})
    delete delayed
    verify(rx_pending_count(clock)==3) // Two values and a non-droppable completion.
    rx_advance_by(clock,5) // 1,2,complete.

    var overflowing <- rx_range(1,3) |> rx_delay(1,clock,rx_queue(1)) // Default: error.
    var inscope failedSub <- rx_subscribe(overflowing,@(n:int) {panic("unexpected value")},@(s:string) {print("{s}\n")},@() {})
    delete overflowing
    verify(rx_is_closed(failedSub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print("ReactiveX bounded queues demo OK\n")
}
