options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var trace=""
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope source <- rx_defer(@() {
        trace+="connect;"
        return <- rx_range(1,3) |> rx_tap(@(n:int) {trace+="produce{n};"})
    }) |> rx_subscribe_on(clock) |> rx_observe_on(clock,rx_queue(3))
    var inscope sub <- rx_subscribe(source,@(n:int) {trace+="receive{n};"},@(s:string) {panic(s)},@(){trace+="done;"})
    verify(trace=="")
    // One action connects and produces all values, without delivering them.
    rx_advance_to(clock,0,1)
    verify(trace=="connect;produce1;produce2;produce3;")
    rx_advance_to(clock,0)
    verify(trace=="connect;produce1;produce2;produce3;receive1;receive2;receive3;done;")
    verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print("{trace}\nReactiveX scheduling demo OK\n")
}
