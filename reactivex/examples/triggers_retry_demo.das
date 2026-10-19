options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
var attempts=0
var result=0
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope clicks <- rx_subject(type<int>)
    var inscope settings <- rx_behavior_subject(10)
    var clockView <- rx_scheduler_clone(clock)
    var inscope requests <- rx_clone(clicks) |> rx_with_latest_from(rx_clone(settings)) |> rx_exhaust_map(@ capture(<-clockView) (p:tuple<first:int;second:int>) {
        let answer=p.first*p.second
        return <- rx_timer(3,clockView) |> rx_map(@ capture(copy(answer)) (tick:int64){return answer})
    } finally {delete clockView}) |> rx_reduce(0,@(sum:int;n:int){return sum+n})
    var inscope sub <- rx_subscribe(requests,@(n:int){result=n;print("total: {n}\n")},@(s:string){panic(s)},@(){})
    rx_subject_next(clicks,1);rx_subject_next(clicks,2) // second request is ignored.
    rx_advance_to(clock,3)
    rx_subject_next(settings,20);rx_subject_next(clicks,3);rx_subject_complete(clicks)
    rx_advance_to(clock,6);verify(result==70)

    var inscope download <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
        attempts++
        if(attempts<3){rx_sink_error(sink,"temporary")}
        else {rx_sink_next(sink,42);rx_sink_complete(sink)}
    }) |> rx_retry_backoff(3,2,8,clock,@(message:string;retry:int){print("retry {retry}\n");return message=="temporary"}) |> rx_first()
    result=0
    var inscope pending <- rx_subscribe(download,@(n:int){result=n},@(s:string){panic(s)},@(){})
    rx_advance_to(clock,12)
    verify(result==42 && attempts==3 && rx_pending_count(clock)==0)
    var inscope fallback <- rx_empty(type<int>) |> rx_default_if_empty(7) |> rx_last()
    var inscope last <- rx_subscribe(fallback,@(n:int){verify(n==7)},@(s:string){panic(s)},@(){})
    print("ReactiveX triggers/retry/terminal demo OK\n")
}
