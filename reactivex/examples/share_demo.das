options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var starts=0
var effects=0
var trace=""

def publish(var source:auto;replay:bool) {
    if(replay) {return <- source |> rx_share_replay(1)}
    return <- source |> rx_share()
}
def demo(replay:bool) {
    starts=0;effects=0;trace=""
    print(replay ? "share_replay: keep the completed result\n" : "share: reconnect after completion\n")
    var inscope clock <- rx_virtual_scheduler()
    var view <- rx_scheduler_clone(clock)
    var inscope hub <- publish(rx_defer(@ capture(<-view) () {
        starts++;print("connect source #{starts}\n")
        return <- rx_interval(10,view) |> rx_take(2) |> rx_tap(@(n:int64) {effects++;print("compute: {n}\n")})
    } finally {delete view}),replay)
    var inscope a <- rx_subscribe(hub,@(n:int64) {trace+="a{n};";print("A: {n}\n")},@(s:string) {panic(s)},@() {})
    rx_advance_by(clock,10)
    var inscope b <- rx_subscribe(hub,@(n:int64) {trace+="b{n};";print("B: {n}\n")},@(s:string) {panic(s)},@() {})
    rx_advance_by(clock,10)
    verify(starts==1 && effects==2 && rx_is_closed(a) && rx_is_closed(b))
    verify(trace==(replay ? "a0;b0;a1;b1;" : "a0;a1;b1;"))
    var inscope c <- rx_subscribe(hub,@(n:int64) {print("late C: {n}\n")},@(s:string) {panic(s)},@() {})
    rx_advance_by(clock,20)
    verify(starts==(replay ? 1 : 2) && effects==(replay ? 2 : 4) && rx_is_closed(c))
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
}
[export]
def main() {
    demo(false)
    demo(true)
    print("ReactiveX share/share_replay demo OK\n")
}
