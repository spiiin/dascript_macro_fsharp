options gen2
options max_infer_passes=512
require ../lib/reactivex.das
require math

[export]
def main() {
    var inscope damage <- rx_subject(type<int>)
    var inscope health <- rx_clone(damage) |> rx_tap(@(delta:int) {print("action: {delta}\n")}) |> rx_scan(100,@(hp:int;delta:int) {return max(0,hp+delta)}) |> rx_start_with(100) |> rx_distinct_until_changed()
    var inscope sub <- rx_subscribe(health,
        @(hp:int) {print("health: {hp}\n")},
        @(message:string) {print("error: {message}\n")},
        @() {print("complete\n")})
    rx_subject_next(damage,-25)
    rx_subject_next(damage,0) // tap sees it; unchanged health is suppressed.
    rx_subject_next(damage,10)
    rx_subject_complete(damage)
    verify(rx_is_closed(sub) && rx_subscriber_count(damage)==0)
    print("ReactiveX stateful demo OK\n")
}
