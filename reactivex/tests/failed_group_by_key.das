options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
struct BorrowedKey {address:int?}
[export]
def main() {
    var inscope source <- rx_range(1,3) |> rx_group_by(@(n:int){return BorrowedKey()})
}
