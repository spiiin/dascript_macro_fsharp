options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min=1
@validate_min=2
value:int
}
[export]
def main() {}
