options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var listeners:array<RxSubscription>
var trace=""
[export]
def main() {
    var inscope source <- rx_range(1,6) |> rx_group_by(@(n:int) {return n%2==0 ? "even" : "odd"})
    var inscope sub <- rx_subscribe(source,@(group:typedecl(rx_group_marker(type<string>,type<int>))) {
        let key=rx_group_key(group)
        trace+="group:{key};"
        listeners |> emplace(rx_subscribe(group,
            @ capture(copy(key)) (n:int) {trace+="{key}:{n};"},
            @(message:string) {panic(message)},
            @ capture(copy(key)) () {trace+="end:{key};"}))
    },@(message:string) {panic(message)},@(){trace+="done;"})
    verify(trace=="group:odd;odd:1;group:even;even:2;odd:3;even:4;odd:5;even:6;end:odd;end:even;done;")
    for(listener in listeners) {verify(rx_is_closed(listener))}
    delete listeners
    print("{trace}\nReactiveX group_by demo OK\n")
}
