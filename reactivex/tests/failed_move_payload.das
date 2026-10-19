options gen2
require ../lib/reactivex.das
[export]
def main() {
    var inscope source <- rx_subject(type<array<int>>)
}
