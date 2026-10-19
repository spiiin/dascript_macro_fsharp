options gen2
options max_infer_passes=512
require ../lib/reactivex.das
var sum=0
var done=0
var errors=0
[export]
def main() {
    var inscope subject <- rx_subject(type<int>)
    var inscope pipeline <- rx_clone(subject) |> rx_filter(@(n:int) {return n%2==0}) |> rx_map(@(n:int) {return n*10}) |> rx_take(2)
    var inscope sub <- rx_subscribe(pipeline,@(n:int) {sum+=n},@(message:string) {errors++},@(){done++})
    verify(rx_subscriber_count(subject)==1 && !rx_is_closed(sub))
    for(n in range(1,8)) {rx_subject_next(subject,n)}
    verify(sum==60 && done==1 && errors==0 && rx_is_closed(sub) && rx_subscriber_count(subject)==0)
    var inscope other <- rx_subscribe(subject,@(n:int) {sum+=n},@(message:string) {errors++},@(){done++})
    rx_subject_error(subject,"network disconnected")
    rx_subject_next(subject,100)
    rx_subject_complete(subject)
    verify(errors==1 && done==1 && rx_subscriber_count(subject)==0)
    var inscope late <- rx_subscribe(subject,@(n:int) {sum+=n},@(message:string) {errors++},@(){done++})
    verify(errors==2 && rx_is_closed(late) && sum==60)
    print("ReactiveX Subject checks OK\n")
}
