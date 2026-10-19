options gen2
require ../lib/reactivex.das
struct Borrowed {address:int?}
[export]
def main() {
    var inscope source <- rx_subject(type<tuple<item:Borrowed>>)
}
