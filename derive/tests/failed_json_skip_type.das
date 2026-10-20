options gen2
require ../lib/derive.das
[derive(json=true)]
struct Invalid {
@json_skip=1
value:int
}
[export]
def main() {}
