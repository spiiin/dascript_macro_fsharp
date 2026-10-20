options gen2
require ../lib/derive.das
variant Unsupported {empty;pointer:int?}
[derive(debug=false,equality=false,hash=false,json=true)]
struct Invalid {action:Unsupported}
[export]
def main() {}
