options gen2
require ../lib/derive.das
[derive(json=true)]
struct Invalid {
@json_required
@json_required
value:int
}
[export]
def main() {}
