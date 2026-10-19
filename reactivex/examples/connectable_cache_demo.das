options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var trace=""
[export]
def main() {
    var inscope input <- rx_subject(type<int>)
    var inscope published <- rx_clone(input) |> rx_publish()
    var inscope a <- rx_subscribe(published,@(n:int){trace+="a{n};"},@(s:string){panic(s)},@(){})
    var inscope b <- rx_subscribe(published,@(n:int){trace+="b{n};"},@(s:string){panic(s)},@(){})
    rx_subject_next(input,0) // not connected yet.
    var connection <- rx_connect(published)
    rx_subject_next(input,1);verify(trace=="a1;b1;")
    rx_unsubscribe(connection);delete connection
    verify(rx_subscriber_count(input)==0)
    var inscope reconnect <- rx_connect(published)
    rx_subject_next(input,2);rx_subject_complete(input)
    verify(trace=="a1;b1;a2;b2;")

    var inscope automatic <- rx_range(1,3) |> rx_publish() |> rx_ref_count() |> rx_last()
    var inscope sub <- rx_subscribe(automatic,@(n:int){verify(n==3)},@(s:string){panic(s)},@(){})
    var inscope clock <- rx_virtual_scheduler()
    var inscope history <- rx_replay_subject(type<int>,4,5,clock)
    rx_subject_next(history,1);rx_advance_to(clock,3);rx_subject_next(history,2)
    rx_advance_to(clock,5);trace=""
    var inscope late <- rx_subscribe(history,@(n:int){trace+="{n};"},@(s:string){panic(s)},@(){})
    verify(trace=="2;")

    var inscope events <- rx_subject(type<int>)
    var inscope cached <- rx_clone(events) |> rx_share_replay(2,10,clock,RxShareOptions(reset_on_complete=false,reset_on_refcount_zero=false))
    var first <- rx_subscribe(cached,@(n:int){},@(s:string){panic(s)},@(){})
    rx_subject_next(events,7);delete first
    rx_subject_next(events,8) // keep-alive caches while there are no listeners.
    trace=""
    var inscope second <- rx_subscribe(cached,@(n:int){trace+="{n};"},@(s:string){panic(s)},@(){})
    verify(trace=="7;8;")
    rx_share_close(cached) // explicit lifetime boundary for keep-alive.
    verify(rx_is_closed(second) && rx_subscriber_count(events)==0)
    print("ReactiveX connectable/cache demo OK\n")
}
