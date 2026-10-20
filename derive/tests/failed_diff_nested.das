options gen2
require ../lib/derive.das
[derive]
struct Child {value:int}
[derive(diff=true)]
struct Invalid {value:Child}
[export]
def main() {
    var value:Invalid
    var inscope changes <- derive_diff(value,value)
}
