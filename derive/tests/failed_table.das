options gen2
require ../lib/derive.das
[derive(debug=true,equality=false,hash=false)]
struct Bad {values:table<string;int>}
[export]
def main() {var inscope value:Bad;print(derive_debug(value))}
