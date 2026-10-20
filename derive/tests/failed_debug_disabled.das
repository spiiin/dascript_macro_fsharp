options gen2
require ../lib/derive.das
[derive(debug=false)]
struct Bad {value:int}
[export]
def main() {print(derive_debug(Bad()))}
