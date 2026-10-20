options gen2
require ../lib/derive.das
[derive]
struct Child {value:int}
[derive(clone=true)]
struct Invalid {value:Child}
[export]
def main() {
    var value:Invalid
    let copy=derive_clone(value)
}
