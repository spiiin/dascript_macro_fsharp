options gen2
require ../lib/derive.das
struct Nested {value:int}
[derive(debug=false,equality=false,hash=false,validate=true)]
struct Invalid {value:Nested}
[export]
def main() {}
