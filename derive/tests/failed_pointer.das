options gen2
require ../lib/derive.das
[derive(debug=true,equality=false,hash=false)]
struct Bad {pointer:int?}
[export]
def main() {print(derive_debug(Bad()))}
