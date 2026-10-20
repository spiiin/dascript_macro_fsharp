options gen2
require ../lib/derive.das
[derive(debug=false,equality=false,hash=false)]
struct Bad {value:int}
[export]
def main() {}
