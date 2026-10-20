options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min=1.5
value:int
}
[export]
def main() {}
