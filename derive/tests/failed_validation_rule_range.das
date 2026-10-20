options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min=5
@validate_max=2
value:int
}
[export]
def main() {}
