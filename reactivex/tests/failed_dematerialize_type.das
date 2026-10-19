options gen2
require ../lib/reactivex.das
[export]
def main() {
    var inscope source <- rx_range(1,3) |> rx_dematerialize()
}
