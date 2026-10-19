options gen2
require ../lib/reactivex.das
[export]
def main() {
    var source <- rx_range(1,4) |> rx_buffer(2) |> rx_share_replay(1)
    delete source
}
