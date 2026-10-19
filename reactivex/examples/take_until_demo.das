options gen2
options max_infer_passes=512
require ../lib/reactivex.das

[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope closeWindow <- rx_subject(type<string>)
    var inscope updates <- rx_interval(10,clock) |> rx_take_until(rx_clone(closeWindow))
    var inscope sub <- rx_subscribe(updates,
        @(frame:int64) {print("background update: {frame}\n")},
        @(message:string) {print("error: {message}\n")},
        @() {print("window closed: updates finished\n")})
    rx_advance_by(clock,25) // updates 0, 1
    rx_subject_next(closeWindow,"close")
    rx_advance_by(clock,100) // no more updates
    verify(rx_is_closed(sub) && rx_subscriber_count(closeWindow)==0)
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print("ReactiveX take_until demo OK\n")
}
