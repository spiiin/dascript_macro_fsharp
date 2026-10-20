options gen2
require ../lib/derive.das
[derive]
struct Invalid {value:int}
[export]
def main() {
    var value:Invalid
    let copy=derive_clone(value)
}
