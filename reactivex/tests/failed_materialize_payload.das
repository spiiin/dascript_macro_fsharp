options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
[export]
def main() {
    var inscope source <- rx_range(1,3) |> rx_window(2) |> rx_materialize()
}
