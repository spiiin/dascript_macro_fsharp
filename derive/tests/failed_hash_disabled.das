options gen2
require ../lib/derive.das
[derive(hash=false)]
struct Bad {value:int}
[export]
def main() {print("{derive_hash(Bad())}")}
