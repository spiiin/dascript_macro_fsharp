options gen2
require ../lib/derive.das
[derive]
struct Invalid {
@validate_min=1
value:int
}
[export]
def main() {}
