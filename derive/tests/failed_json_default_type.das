options gen2
require ../lib/derive.das
[derive(json=true)]
struct Invalid {
@json_default="bad"
value:int
}
[export]
def main() {}
