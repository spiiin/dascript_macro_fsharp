options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope once <- rx_timer(10,clock)
    var inscope repeating <- rx_interval(5,clock) |> rx_take(3)
    var inscope a <- rx_subscribe(once,@(n:int64) {print("timer: {n}\n")},@(s:string) {panic(s)},@(){})
    var inscope b <- rx_subscribe(repeating,@(n:int64) {print("interval: {n}\n")},@(s:string) {panic(s)},@(){})
    var inscope input <- rx_subject(type<int>)
    var inscope settled <- rx_clone(input) |> rx_debounce(5,clock) |> rx_delay(2,clock)
    var inscope c <- rx_subscribe(settled,@(n:int) {verify(n==2);print("settled: {n}\n")},@(s:string) {panic(s)},@(){})
    rx_subject_next(input,1)
    rx_advance_to(clock,3)
    rx_subject_next(input,2)
    rx_advance_to(clock,8)
    rx_subject_complete(input)
    rx_advance_to(clock,15)
    verify(rx_is_closed(a) && rx_is_closed(b) && rx_is_closed(c) && rx_pending_count(clock)==0)

    var inscope silent <- rx_subject(type<int>)
    var inscope guarded <- rx_clone(silent) |> rx_timeout(4,clock)
    var inscope d <- rx_subscribe(guarded,@(n:int) {},@(s:string) {verify(s=="rx timeout");print("{s}\n")},@(){})
    rx_advance_to(clock,19)
    verify(rx_is_closed(d) && rx_subscriber_count(silent)==0)

    // In an application, pass its monotonic frame clock instead of advancing
    // virtual time. No worker thread or sleep is introduced by the library.
    var inscope frames <- rx_scheduler()
    var inscope frameTicks <- rx_interval(10,frames) |> rx_take(2)
    var inscope e <- rx_subscribe(frameTicks,@(n:int64) {print("frame tick: {n}\n")},@(s:string) {panic(s)},@(){})
    for(now in [0,16,32]) {rx_tick(frames,now)}
    verify(rx_is_closed(e) && rx_pending_count(frames)==0)
    print("ReactiveX time demo OK\n")
}
