options gen2
require ../lib/derive.das
[derive(debug=false,equality=false,hash=false,clone=true)]
struct Invalid {value:int?}
[export]
def main() {
    var value:Invalid
    let copy=derive_clone(value)
}
