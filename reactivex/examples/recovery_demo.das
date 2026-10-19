options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var attempts=0
var trace=""
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope request <- rx_defer(@(){
        attempts++
        return <- rx_just(attempts) |> rx_map(@(n:int) {if(n<3) {panic("temporary failure")};return "response from attempt {n}"})
    }) |> rx_retry(3,10,clock) |> rx_catch_error(@(message:string) {return <- rx_just("cached response")})
    var inscope sub <- rx_subscribe(request,@(value:string) {trace+=value;print("{value}\n")},@(message:string) {panic(message)},@(){trace+=";done"})
    verify(attempts==1 && trace=="")
    rx_advance_to(clock,20)
    verify(attempts==3 && trace=="response from attempt 3;done" && rx_is_closed(sub))
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    var inscope fallback <- rx_throw("offline",type<int>) |> rx_catch_error(@(message:string) {verify(message=="offline");return <- rx_just(42)})
    var inscope second <- rx_subscribe(fallback,@(n:int) {verify(n==42)},@(message:string) {panic(message)},@(){})
    verify(rx_is_closed(second))
    print("ReactiveX recovery demo OK\n")
}
