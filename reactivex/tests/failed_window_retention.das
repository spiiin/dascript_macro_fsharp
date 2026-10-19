options gen2
require ../lib/reactivex.das
[export]
def main() {
    var source <- rx_range(1,4) |> rx_window(3,1) |> rx_share_replay(2)
    delete source
}
