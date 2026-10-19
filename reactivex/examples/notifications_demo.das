options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var trace=""
[export]
def main() {
    var inscope events <- rx_range(1,2) |> rx_concat(rx_throw("offline",type<int>)) |> rx_materialize()
    var inscope log <- rx_subscribe(events,@(event:typedecl(rx_notification(type<int>))) {
        if(event is next) {trace+="next:{event as next};"}
        elif(event is error) {trace+="error:{event as error};"}
        else {trace+="complete;"}
    },@(message:string){panic("materialize should turn on_error into data")},@(){trace+="done;"})
    verify(trace=="next:1;next:2;error:offline;done;" && rx_is_closed(log))
    print("materialized: {trace}\n")
    trace=""
    var inscope restored <- rx_clone(events) |> rx_dematerialize()
    var inscope sub <- rx_subscribe(restored,@(n:int){trace+="{n};"},@(message:string){trace+="error:{message};"},@(){trace+="done;"})
    verify(trace=="1;2;error:offline;" && rx_is_closed(sub))
    print("restored: {trace}\nReactiveX notifications demo OK\n")
}
