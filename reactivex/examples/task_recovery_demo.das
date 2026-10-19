options gen2
options max_infer_passes=1024
require ../lib/reactivex_task.das
require ../../computation_expressions/lib/computation_macro.das
var attempts=0
var cancelledAttempts=0
var trace=""
def request() {
    return <- computation(TaskResultBuilder(type<string>)) {
        task_delay_ms(5) |> bind
        attempts++
        let response=task_after_polls(0,attempts<3 ? result_error("temporary failure",type<string>) : result_ok("fresh response")) |> bind
        return response
    }
}
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope source <- rx_from_task_result(@(){return <- request()},clock) |> rx_retry(2,10,clock) |> rx_catch_error(@(message:string) {
        return <- rx_just("cached response")
    })
    var inscope sub <- rx_subscribe(source,@(text:string) {trace+=text;print("{text}\n")},@(s:string) {panic(s)},@(){trace+=";done"})
    rx_advance_to(clock,35) // attempts finish at 5, 20, 35 ms.
    verify(attempts==3 && trace=="fresh response;done" && rx_is_closed(sub))
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    trace=""
    var inscope offline <- rx_from_task_result(@(){return <- task_after_polls(0,result_error("offline",type<string>))},clock) |> rx_retry(1,10,clock) |> rx_catch_error(@(message:string) {return <- rx_just("cached response")})
    var inscope cached <- rx_subscribe(offline,@(text:string) {trace+=text;print("{text}\n")},@(s:string) {panic(s)},@(){trace+=";done"})
    rx_advance_by(clock,10)
    verify(trace=="cached response;done" && rx_is_closed(cached))
    var inscope abandoned <- rx_from_task_result(@(){
        cancelledAttempts++;return <- task_after_polls(0,result_error("offline",type<int>))
    },clock) |> rx_retry(3,10,clock)
    var inscope cancelled <- rx_subscribe(abandoned,@(n:int) {panic("unexpected value")},@(s:string) {panic("unexpected error")},@(){panic("unexpected complete")})
    rx_advance_by(clock,0) // first Task failed; retry is waiting for its deadline.
    verify(cancelledAttempts==1 && rx_pending_count(clock)==1)
    rx_unsubscribe(cancelled)
    rx_advance_by(clock,100)
    verify(cancelledAttempts==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    print("ReactiveX Task recovery demo OK\n")
}
