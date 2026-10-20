options gen2
require ../lib/derive.das
[derive(debug=false,equality=false,hash=false,clone=true)]
struct Invalid {value:table<string;int>}
[export]
def main() {
    var inscope value:Invalid
    var inscope copy <- derive_clone(value)
}
