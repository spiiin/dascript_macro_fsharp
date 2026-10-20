options gen2
require ../lib/derive.das
struct Unmarked {value:int}
[derive(debug=true,equality=false,hash=false)]
struct Bad {inner:Unmarked}
[export]
def main() {print(derive_debug(Bad()))}
