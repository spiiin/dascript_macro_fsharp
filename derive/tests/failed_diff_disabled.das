options gen2
require ../lib/derive.das
[derive]
struct Invalid {value:int}
[export]
def main() {
    var value:Invalid
    var inscope changes <- derive_diff(value,value)
}
