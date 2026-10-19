options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var trace=""

def jobs(var source,selector:auto;sequential:bool) {
    if(sequential) {return <- source |> rx_concat_map(selector)}
    return <- source |> rx_flat_map(selector,2)
}
def demo(sequential:bool) {
    trace=""
    print(sequential ? "concat_map: one job at a time\n" : "flat_map: at most two jobs\n")
    var inscope clock <- rx_virtual_scheduler()
    var view <- rx_scheduler_clone(clock)
    var inscope source <- jobs(rx_range(1,3),@ capture(<-view) (id:int) {
        print("start job {id}\n")
        return <- rx_timer((4-id)*10,view) |> rx_map(@ capture(copy(id)) (tick:int64) {return id})
    } finally {delete view},sequential)
    var inscope sub <- rx_subscribe(source,
        @(id:int) {trace+="{id};";print("finished job {id}\n")},
        @(message:string) {panic(message)},
        @() {print("all jobs finished\n")})
    rx_advance_by(clock,100)
    verify(trace==(sequential ? "1;2;3;" : "2;1;3;"))
    verify(rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
}
[export]
def main() {
    demo(true)
    demo(false)
    print("ReactiveX concat_map/bounded flat_map demo OK\n")
}
