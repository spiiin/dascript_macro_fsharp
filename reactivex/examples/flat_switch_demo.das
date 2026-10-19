options gen2
options max_infer_passes=1024
require ../lib/reactivex.das

def select_responses(first,second:auto) {
    var a <- rx_clone(first)
    var b <- rx_clone(second)
    return <- @ capture(<-a,<-b) (request:int) {
        if(request==1) {return <- rx_clone(a)}
        return <- rx_clone(b)
    } finally {delete a;delete b}
}
[export]
def main() {
    var inscope requests <- rx_subject(type<int>)
    var inscope first <- rx_subject(type<string>)
    var inscope second <- rx_subject(type<string>)
    var inscope latest <- rx_clone(requests) |> rx_switch_map(select_responses(first,second))
    var inscope all <- rx_clone(requests) |> rx_flat_map(select_responses(first,second))
    var inscope a <- rx_subscribe(latest,@(text:string) {print("switch: {text}\n")},@(message:string) {panic(message)},@(){print("switch done\n")})
    var inscope b <- rx_subscribe(all,@(text:string) {print("flat: {text}\n")},@(message:string) {panic(message)},@(){print("flat done\n")})
    rx_subject_next(requests,1)
    rx_subject_next(first,"first response")
    rx_subject_next(requests,2) // switch cancels first; flat keeps both.
    rx_subject_next(first,"late first response")
    rx_subject_next(second,"second response")
    rx_subject_complete(requests) // wait for active inner subscriptions.
    rx_subject_complete(second)
    rx_subject_complete(first)
    print("ReactiveX switch_map/flat_map demo OK\n")
}
