options gen2
require ../lib/reactivex.das
[export]
def main() {
    var inscope left <- rx_range(1,2)
    var inscope right <- rx_range(1,2) |> rx_map(@(n:int) {return "{n}"})
    var inscope source <- left |> rx_concat(right)
}
