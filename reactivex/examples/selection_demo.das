options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
var trace=""
[export]
def main() {
    var inscope source <- rx_range(1,8) |> rx_skip(1) |> rx_skip_while(@(n:int) {return n<4}) |> rx_take_while(@(n:int) {return n<7}) |> rx_pairwise() |> rx_finally(@() {trace+="finally;";print("released\n")})
    var inscope sub <- rx_subscribe(source,
        @(pair:tuple<previous:int;current:int>) {
            trace+="{pair.previous}->{pair.current};"
            print("{pair.previous} -> {pair.current}\n")
        },@(s:string) {panic(s)},@() {trace+="done;"})
    verify(trace=="4->5;5->6;done;finally;" && rx_is_closed(sub))
    print("ReactiveX selection demo OK\n")
}
