options gen2
require ../lib/derive.das
[derive(json=true,check="hook")]
struct Invalid {value:int}
[export]
def main() {}
